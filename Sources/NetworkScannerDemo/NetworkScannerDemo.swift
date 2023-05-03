import Foundation
import NetworkInterfaceInfo
import NetworkScanner

@main
public struct NetworkScannerDemo {
    static func main() async throws {
        print("Scanning!")

        var resultCount = 0

        // Doesn't do anything.  URLSession bug?
        //URLSession.shared.configuration.timeoutIntervalForRequest = 5
        //URLSession.shared.configuration.timeoutIntervalForResource = 1

        // e.g. Google: 0x8efb2000, 142.251.32.0
        //      Facebook: 0x9df01600, 157.240.22.0
        for try await result in NetworkScanner(networkAddress: NetworkAddress.IPv4View(addressInHostOrder: 0x9df00000),
                                               netmask: NetworkAddress.IPv4View(addressInHostOrder: 0xffff0000),
                                               //oneFullScanOnly: true,
                                               //reportMisses: true,
                                               concurrencyLimit: 250,
                                               probe: probeHTTPS) {
            resultCount += 1
            print("#\(resultCount): \(result)")

            if resultCount >= 10 {
                break
            }
        }

        print("\(resultCount) result(s) in total.")
    }
}

func probeFake(address: String) async throws -> Bool {
    try await Task.sleep(for: .milliseconds(Int.random(in: 250...2500)))
    return Bool.random()
}

class Delegate: NSObject, URLSessionDelegate, URLSessionDataDelegate {
    func urlSession(_ session: URLSession,
                             task: URLSessionTask,
                             willPerformHTTPRedirection response: HTTPURLResponse,
                             newRequest request: URLRequest) async -> URLRequest? {
        nil // Always refuse all redirects; they're unnecessary to confirm that we hit a HTTPS server.
    }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didReceive challenge: URLAuthenticationChallenge) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        // It _should_ work to just return cancelAuthenticationChallenge, but URLSession has a bug whereby that results in a URLError.cancelled, not URLError.userCancelledAuthentication.  We need to distinguish between the two.
        (.rejectProtectionSpace, nil) // No need to push ahead further, it's clearly a HTTPS server.
    }

}

let delegate = Delegate()

let session = {
    var s = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)

    // Doesn't do anything.  URLSession bug?
    //s.configuration.timeoutIntervalForRequest = 5
    //s.configuration.timeoutIntervalForResource = 1
    s.configuration.waitsForConnectivity = false

    return s
}()

func probeHTTPS(address: String) async throws -> Bool {
    guard let URL = URL(string: "https://\(address)") else {
        throw Errors.unableToConstructHTTPSURL(address: address)
    }

    var request = URLRequest(url: URL, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 5)
    request.httpMethod = "HEAD"
    request.allowsCellularAccess = true
    request.allowsExpensiveNetworkAccess = true
    request.allowsConstrainedNetworkAccess = true
    request.attribution = .user

    do {
        let (bytes, _) = try await session.bytes(for: request, delegate: delegate)
        bytes.task.cancel()
        return true
    } catch URLError.clientCertificateRequired,
            URLError.clientCertificateRejected,
            URLError.dataLengthExceedsMaximum,
            URLError.httpTooManyRedirects,
            URLError.redirectToNonExistentLocation,
            URLError.serverCertificateHasBadDate,
            URLError.serverCertificateHasUnknownRoot,
            URLError.serverCertificateNotYetValid,
            URLError.serverCertificateUntrusted,
            URLError.userAuthenticationRequired,
            URLError.zeroByteResource {
        print("Unclean hit against \(address).")
        return true
    } catch URLError.cannotFindHost,
            URLError.cannotConnectToHost,
            URLError.cannotParseResponse,
            URLError.networkConnectionLost,
            URLError.timedOut,
            URLError.secureConnectionFailed {
        print("Couldn't connect to \(address).")
        return false
    }
}

enum Errors: Error {
    case unableToConstructHTTPSURL(address: String)
}
