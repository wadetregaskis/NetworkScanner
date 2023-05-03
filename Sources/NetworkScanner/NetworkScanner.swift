import AsyncAlgorithms
import Darwin // For usleep().
import NetworkInterfaceInfo
import NetworkInterfaceChangeMonitoring


public struct NetworkScanner: AsyncSequence {
    private let interfaceFilter: (NetworkInterface) -> Bool
    private let oneFullScanOnly: Bool
    private let reportMisses: Bool
    private let concurrencyLimit: Int?
    private let probe: (String) async throws -> Bool

    public init(interfaceFilter: @escaping (NetworkInterface) -> Bool = { !$0.loopback },
                oneFullScanOnly: Bool = false,
                reportMisses: Bool = false,
                concurrencyLimit: Int? = nil,
                probe: @escaping (String) async throws -> Bool) {
        self.interfaceFilter = interfaceFilter
        self.oneFullScanOnly = oneFullScanOnly
        self.reportMisses = reportMisses
        self.concurrencyLimit = concurrencyLimit
        self.probe = probe
    }

    public struct Result: Sendable {
        public let address: String

        public enum Conclusion: Sendable {
            case hit
            case miss
        }

        public let conclusion: Conclusion
    }

    public typealias Element = Result

    public func makeAsyncIterator() -> Iterator {
        return Iterator(interfaceFilter: interfaceFilter,
                        oneFullScanOnly: oneFullScanOnly,
                        reportMisses: reportMisses,
                        concurrencyLimit: concurrencyLimit,
                        probe: probe)
    }

    public final class Iterator: AsyncIteratorProtocol {
        private var overarchingTask: Task<Void, Error>? = nil
        private let channel = AsyncThrowingChannel<Result, Error>()

        fileprivate init(interfaceFilter: @escaping (NetworkInterface) -> Bool,
                         oneFullScanOnly: Bool,
                         reportMisses: Bool,
                         concurrencyLimit: Int?,
                         probe: @escaping (String) async throws -> Bool) {
            self.overarchingTask = Task { [channel] in
                do {
                    // max(1, …) to ensure that there's always at least one task that can run at a time, so as to make forward progress.
                    var taskTokens = Swift.max(1, concurrencyLimit ?? Int.max)

                    try await withThrowingTaskGroup(of: Void.self) { taskGroup in
                        if oneFullScanOnly {
                            for interface in try NetworkInterface.all {
                                guard !Task.isCancelled else { break }

                                try await NetworkScanner.Iterator.scan(interface: interface,
                                                                       interfaceFilter: interfaceFilter,
                                                                       reportMisses: reportMisses,
                                                                       probe: probe,
                                                                       channel: channel,
                                                                       taskGroup: &taskGroup,
                                                                       taskTokens: &taskTokens)
                            }
                        } else {
                            for try await change in NetworkInterface.changes() {
                                guard !Task.isCancelled else { break }

                                switch change.nature {
                                case .modified(let nature):
                                    if nature.contains(.address) || nature.contains(.netmask) {
                                        fallthrough
                                    }
                                case .added:
                                    try await NetworkScanner.Iterator.scan(interface: change.interface,
                                                                           interfaceFilter: interfaceFilter,
                                                                           reportMisses: reportMisses,
                                                                           probe: probe,
                                                                           channel: channel,
                                                                           taskGroup: &taskGroup,
                                                                           taskTokens: &taskTokens)
                                default:
                                    break
                                }
                            }
                        }

                        print("Collating results…")

                        for try await _ in taskGroup {
                            guard !Task.isCancelled else {
                                print("Cancelled.")
                                taskGroup.cancelAll()
                                break
                            }
                        }

                        print("No more results.")
                    }

                    channel.finish()
                } catch {
                    channel.fail(error)
                }
            }
        }

        deinit {
            self.overarchingTask?.cancel()
        }

        private static let supportedAddressFamilies = Set<NetworkAddress.AddressFamily>(arrayLiteral: .inet) // TODO: Support IPv6 too.

        private static func scan(interface: NetworkInterface,
                                 interfaceFilter: (NetworkInterface) -> Bool,
                                 reportMisses: Bool,
                                 probe: @escaping (String) async throws -> Bool,
                                 channel: AsyncThrowingChannel<Result, Error>,
                                 taskGroup: inout ThrowingTaskGroup<Void, Error>,
                                 taskTokens: inout Int) async throws {
            guard let genericAddress = interface.address,
                  let genericNetmask = interface.netmask,
                  interface.up,
                  let addressFamily = interface.addressFamily,
                  Iterator.supportedAddressFamilies.contains(addressFamily),
                  interfaceFilter(interface) else {
                return
            }

            print("Scanning \(interface)…")

            guard let v4Address = genericAddress.IPv4,
                  let v4Netmask = genericNetmask.IPv4 else {
                return
            }

            let networkAddress = v4Netmask.address & v4Address.address

            for candidate in networkAddress..<(networkAddress | ~v4Netmask.address) {
                guard !Task.isCancelled else {
                    print("Scanning cancelled.")
                    return
                }

                if candidate != networkAddress && candidate != v4Address.address {
                    let addressString = NetworkAddress.IPv4View(addressInHostOrder: candidate).description

                    print("\tScanning \(addressString)…")

                    if 0 >= taskTokens {
                        try await taskGroup.next()
                    } else {
                        taskTokens -= 1
                    }

                    _ = taskGroup.addTaskUnlessCancelled { [probe, channel] in
                        if try await probe(addressString) {
                            print("\t\tReturning hit for \(addressString).")
                            await channel.send(Result(address: addressString, conclusion: .hit))
                        } else {
                            print("\t\tReturning miss for \(addressString).")

                            if reportMisses {
                                await channel.send(Result(address: addressString, conclusion: .miss))
                            }
                        }
                    }
                }

                usleep(10000)
            }

            print("Scanning completed.")
        }

        public func next() async throws -> Result? {
            for try await result in channel {
                return result
            }

            return nil
        }
    }
}
