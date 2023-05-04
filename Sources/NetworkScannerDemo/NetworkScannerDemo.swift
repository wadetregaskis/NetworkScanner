import Foundation
import NetworkInterfaceInfo
import NetworkScanner

/// A simple demo executable.
///
/// This generates a *lot* of log spam, sadly, because URLSesson et al seem to presume that you won't ever really have any connection issues.  However, this spam is via OSLog, which only shows up in Xcode and the Console app.  If you run this demo executable e.g. via `swift run`, you'll be spared the horror.
@main
public struct NetworkScannerDemo {
    static func main() async throws {
        print("Scanning!")

        var resultCount = 0

        // e.g. Google: 142.251.32.0
        //      Facebook: 157.240.22.0
        for try await result in NetworkScanner(networkAddress: IPv4Address(from: "157.240.0.0")!,
                                               netmask: IPv4Address(from: "255.255.0.0")!,
                                               //oneFullScanOnly: true,
                                               //reportMisses: true,
                                               concurrencyLimit: 250,
                                               probe: probeHTTPS) {
            resultCount += 1
            print("#\(resultCount.formatted()): \(result)")

            // Useful to uncomment if you're running this a lot and don't actually want to "DoS" Facebook all the time. 😝
//            if resultCount >= 10 {
//                break
//            }
        }

        print("\(resultCount.formatted()) result(s) in total.")
    }
}

/// An example probe which just waits a short while and randomly returns true or false.
///
/// This is really just for testing purposes - it's obviously not useful in a real application.
func probeFake(address: String) async throws -> NetworkScanner<Void, Void>.Result.Conclusion {
    try await Task.sleep(nanoseconds: .random(in: 250_000...2_500_000))
    return Bool.random() ? .hit : .miss
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
    s.configuration.urlCache = nil
    s.configuration.urlCredentialStorage = nil
    s.configuration.httpShouldSetCookies = false
    s.configuration.httpCookieStorage = nil
    s.configuration.httpCookieAcceptPolicy = .never
    s.configuration.httpMaximumConnectionsPerHost = 1
    s.configuration.httpShouldUsePipelining = false

    return s
}()

/// An example probe that looks for HTTPS servers.
///
/// It doesn't require them to be fully functional or correctly configured or to even handle HTTP requests successfully.  They just have to be HTTPS servers.
///
/// One grey area is SSL/TLS problems - it's assumed that many kinds of TLS issues, such as invalid server certificates, imply that it is indeed a HTTPS server.  Given the 443 port being used.  But strictly-speaking it's possible that something that's _not_ a HTTPS server could be listening on the HTTPS port and using TLS.  But if so, why?!
func probeHTTPS(address: String) async throws -> NetworkScanner<HitNature, Error>.Result.Conclusion {
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
        return .hit(.clean)
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
        return .hit(.unclean)
    } catch let error as URLError where missErrorCodes.contains(error.errorCode) {
        print("Couldn't connect to \(address).")
        return .miss(error)
    }
}

enum HitNature {
    case clean
    case unclean
}

let missErrorCodes: Set = [NSURLErrorCannotFindHost,
                           NSURLErrorCannotConnectToHost,
                           NSURLErrorCannotParseResponse,
                           NSURLErrorNetworkConnectionLost,
                           NSURLErrorTimedOut,
                           NSURLErrorSecureConnectionFailed]

enum Errors: Error {
    case unableToConstructHTTPSURL(address: String)
}
