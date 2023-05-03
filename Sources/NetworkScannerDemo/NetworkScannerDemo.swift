import NetworkScanner

@main
public struct NetworkScannerDemo {
    static func main() async throws {
        print("Scanning!")

        for try await result in NetworkScanner(oneFullScanOnly: false, probe: { _ in true }) {
            print(result)
        }
    }
}
