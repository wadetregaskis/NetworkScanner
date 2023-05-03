import NetworkScanner

@main
public struct NetworkScannerDemo {
    static func main() async throws {
        print("Scanning!")

        var resultCount = 0

        for try await result in NetworkScanner(oneFullScanOnly: false,
                                               concurrencyLimit: 3,
                                               probe: { _ in try await Task.sleep(for: .seconds(1)); return Bool.random() }) {
            resultCount += 1
            print("#\(resultCount): \(result)")

            if resultCount > 10 {
                break
            }
        }

        print("\(resultCount) result(s) in total.")

        while true {
            try await Task.sleep(for: .seconds(1))
        }
    }
}
