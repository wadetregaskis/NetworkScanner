import AsyncAlgorithms
import os
import NetworkInterfaceInfo
import NetworkInterfaceChangeMonitoring


public struct NetworkScanner: AsyncSequence {
    private let interfaceFilter: (NetworkInterface) -> Bool
    private let oneFullScanOnly: Bool
    private let reportTimeouts: Bool
    private let probe: (String) async throws -> Bool

    public init(interfaceFilter: @escaping (NetworkInterface) -> Bool = { !$0.loopback },
                oneFullScanOnly: Bool = false,
                reportTimeouts: Bool = false,
                probe: @escaping (String) async throws -> Bool) {
        self.interfaceFilter = interfaceFilter
        self.oneFullScanOnly = oneFullScanOnly
        self.reportTimeouts = reportTimeouts
        self.probe = probe
    }

    public struct Result: Sendable {
        public let address: String

        public enum Conclusion: Sendable {
            case hit
            case timeout
            case error
        }

        public let conclusion: Conclusion
    }

    public typealias Element = Result

    public func makeAsyncIterator() -> Iterator {
        return Iterator(interfaceFilter: interfaceFilter,
                        oneFullScanOnly: oneFullScanOnly,
                        reportTimeouts: reportTimeouts,
                        probe: probe)
    }

    public final class Iterator: AsyncIteratorProtocol {
        private let interfaceFilter: (NetworkInterface) -> Bool
        private let reportTimeouts: Bool
        private let probe: (String) async throws -> Bool

        private var overarchingTask: Task<Void, Error>? = nil
        private let channel = AsyncThrowingChannel<Result, Error>()

        private enum TaskGroupResult: Sendable {
            case networkChange(NetworkInterface.Change)
            case probeResult(Result?)
        }

        fileprivate init(interfaceFilter: @escaping (NetworkInterface) -> Bool,
                         oneFullScanOnly: Bool,
                         reportTimeouts: Bool,
                         probe: @escaping (String) async throws -> Bool) {
            self.interfaceFilter = interfaceFilter
            self.reportTimeouts = reportTimeouts
            self.probe = probe

            self.overarchingTask = Task { [oneFullScanOnly, channel] in
                do {
                    try await withThrowingTaskGroup(of: Result?.self) { taskGroup in
                        if oneFullScanOnly {
                            for interface in try NetworkInterface.all {
                                guard !Task.isCancelled else { break }

                                scan(interface: interface, taskGroup: &taskGroup)
                            }

                            for try await result in taskGroup {
                                guard !Task.isCancelled else {
                                    print("Cancelled.")
                                    taskGroup.cancelAll()
                                    break
                                }

                                print("Got result: \(result)")

                                if let result {
                                    await channel.send(result)
                                }
                            }
                        } else {
                            for try await result in merge(taskGroup.map { TaskGroupResult.probeResult($0) },
                                                          NetworkInterface.changes().map { TaskGroupResult.networkChange($0) }) {
                                guard !Task.isCancelled else {
                                    print("Cancelled.")
                                    taskGroup.cancelAll()
                                    break
                                }

                                switch result {
                                case .networkChange(let change):
                                    print("Network change: \(change)")

                                    switch change.nature {
                                    case .added:
                                        scan(interface: change.interface, taskGroup: &taskGroup)
                                    case .modified(let nature):
                                        if nature.contains(.address) || nature.contains(.netmask) {
                                            scan(interface: change.interface, taskGroup: &taskGroup)
                                        }
                                    default:
                                        break
                                    }
                                case .probeResult(let result):
                                    print("Got result: \(result)")

                                    if let result {
                                        await channel.send(result)
                                    }
                                }
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

        private func scan(interface: NetworkInterface, taskGroup: inout ThrowingTaskGroup<Result?, Error>) {
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
                    return
                }

                if candidate != networkAddress && candidate != v4Address.address {
                    let addressString = NetworkAddress.IPv4View(addressInHostOrder: candidate).description

                    print("\tScanning \(addressString)…")

                    _ = taskGroup.addTaskUnlessCancelled { [probe] in
                        if try await probe(addressString) {
                            print("\t\tReturning hit for \(addressString).")
                            return Result(address: addressString, conclusion: .hit)
                        } else {
                            print("\t\tReturning miss for \(addressString).")
                            return nil
                        }
                    }
                }
            }
        }

        public func next() async throws -> Result? {
            for try await result in channel {
                return result
            }

            return nil
        }
    }
}
