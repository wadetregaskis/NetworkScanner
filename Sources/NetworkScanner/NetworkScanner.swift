import AsyncAlgorithms
import Logging
import NetworkInterfaceInfo
import NetworkInterfaceChangeMonitoring


/// Scans networks for hosts that pass a given probe.
///
/// Currently only IPv4 networks are supported.
public struct NetworkScanner<HitData: Sendable, MissData: Sendable>: AsyncSequence {
    fileprivate enum Mode {
        case localNetworks(interfaceFilter: (NetworkInterface) -> Bool,
                           oneFullScanOnly: Bool)
        case arbitraryNetwork(address: IPv4Address,
                              netmask: IPv4Address)
    }

    private let mode: Mode
    private let reportMisses: Bool
    private let concurrencyLimit: Int?
    private let log: Logger?
    private let probe: (String) async throws -> Result.Conclusion

    /// Scans local networks.
    ///
    /// - Parameters:
    ///   - interfaceFilter: An optional filter to determine which network interfaces are scanned.
    ///
    ///     Note that some interfaces will be ignored irrespective of what this filter is (and this filter won't even be asked about them), because they intrinsically cannot be scanned or ``NetworkScanner`` doesn't currently support them.  This includes those that don't have addresses & netmasks, or aren't a supported interface type (e.g. non-IP interfaces).
    ///
    ///     If unspecified, all non-loopback interfaces are scanned (within the constraints noted above).
    ///   - oneFullScanOnly: Scan just once or scan perpetually.
    ///
    ///     Irrespective of the value of this parameter, the scan starts with all currently active interfaces.  Once that is complete, this parameter determines if scanning ends (`true`) or perpetually monitors for network changes and performs additional scans where appropriate.
    ///
    ///     If this argument is `false` - which is the default - then iterations over the scanner's results will never naturally end.  Iteration can only be ended by cancelling scanning (e.g. simply breaking out of the `for try await result in NetworkScanner(…) {` loop) or by an error occurring.
    ///   - reportMisses: Whether to report misses or just silently omit them.
    ///
    ///     This is mostly for the convenience of the user - by pre-filtering out misses, which many use-cases don't care about - but also potentially a performance booster - scanner tasks will conclude faster and not be subject to any consumption back-ups by the user.
    ///
    ///     It is always better to set this to `false` (or leave it at that default) if you don't care about misses, than filter them out manually.
    ///   - concurrencyLimit: How many hosts to probe at a time.
    ///
    ///     This can & should be used to limit concurrency to reasonable levels when your probes might take a non-trivial amount of time.  This is almost always the case, and the real question is just what specific limit is appropriate for each use-case.  That often depends on the maximum time required for a probe (usually a timeout your probe closure enforces).  e.g. if your probe closure ensures a ten second timeout, then a concurrency limit of 100 means at least 10 hosts probed per second.  Thus you should tune both your timeout and this concurrency limit in concert, to achieve an acceptable average probe rate.
    ///
    ///     A too-low value will cause scanning to take longer than necessary.
    ///
    ///     A too-high value can cause scanning to fail for any of various reasons, such as application or OS resource exhaustion (e.g. memory, or file descriptors), or even defensive reactions from networking equipment (e.g. treating this host as abusive and throttling or blocking its traffic).  It can also cause false negatives due to network congestion.  Ironically, it can even reduce scanning speed by causing too much overhead in handling many concurrent probes (although on most systems this requires extraordinarily high concurrency).
    ///
    ///     By default there is _no concurrency limit_, which is usually fine if the available networks are small (e.g. class C networks, such as the typical 192.168.0.0) but can very easily become problematic if the available networks happen to be larger.
    ///   - logger: The logger to use for [mostly] debugging output.  If `nil` (the default) a unique logger is created internally for each iterator.
    ///   - probe: The test to run against each host, to determine if it is a "hit" or "miss".
    ///
    ///     The test can be practically anything you wish - e.g. a simple TCP connection attempt, a HTTPS attempt, a HTTPS POST and interrogation of the response, etc.
    public init(interfaceFilter: @escaping (NetworkInterface) -> Bool = { !$0.loopback },
                oneFullScanOnly: Bool = false,
                reportMisses: Bool = false,
                concurrencyLimit: Int? = nil,
                logger: Logger? = nil,
                probe: @escaping (String) async throws -> Result.Conclusion) {
        self.mode = .localNetworks(interfaceFilter: interfaceFilter, oneFullScanOnly: oneFullScanOnly)
        self.reportMisses = reportMisses
        self.concurrencyLimit = concurrencyLimit
        self.log = logger
        self.probe = probe
    }

    /// Scans the given network / address range.
    ///
    /// - Parameters:
    ///   - networkAddress: The address of the network to scan, e.g. 192.168.0.0.
    ///   - netmask: The netmask for the network, e.g. 255.255.0.0.
    ///   - reportMisses: Whether to report misses or just silently omit them.
    ///
    ///     This is mostly for the convenience of the user - by pre-filtering out misses, which many use-cases don't care about - but also potentially a performance booster - scanner tasks will conclude faster and not be subject to any consumption back-ups by the user.
    ///
    ///     It is always better to set this to `false` (or leave it at that default) if you don't care about misses, than filter them out manually.
    ///   - concurrencyLimit: How many hosts to probe at a time.
    ///
    ///     This can & should be used to limit concurrency to reasonable levels when your probes might take a non-trivial amount of time.  This is almost always the case, and the real question is just what specific limit is appropriate for each use-case.  That often depends on the maximum time required for a probe (usually a timeout your probe closure enforces).  e.g. if your probe closure ensures a ten second timeout, then a concurrency limit of 100 means at least 10 hosts probed per second.  Thus you should tune both your timeout and this concurrency limit in concert, to achieve an acceptable average probe rate.
    ///
    ///     A too-low value will cause scanning to take longer than necessary.
    ///
    ///     A too-high value can cause scanning to fail for any of various reasons, such as application or OS resource exhaustion (e.g. memory, or file descriptors), or even defensive reactions from networking equipment (e.g. treating this host as abusive and throttling or blocking its traffic).  It can also cause false negatives due to network congestion.  Ironically, it can even reduce scanning speed by causing too much overhead in handling many concurrent probes (although on most systems this requires extraordinarily high concurrency).
    ///
    ///     By default there is _no concurrency limit_, which is usually fine if the available networks are small (e.g. class C networks, such as the typical 192.168.0.0) but can very easily become problematic if the available networks happen to be larger.
    ///   - logger: The logger to use for [mostly] debugging output.  If `nil` (the default) a unique logger is created internally for each iterator.
    ///   - probe: The test to run against each host, to determine if it is a "hit" or "miss".
    ///
    ///     The test can be practically anything you wish - e.g. a simple TCP connection attempt, a HTTPS attempt, a HTTPS POST and interrogation of the response, etc.
    public init(networkAddress: IPv4Address,
                netmask: IPv4Address,
                reportMisses: Bool = false,
                concurrencyLimit: Int? = nil,
                logger: Logger? = nil,
                probe: @escaping (String) async throws -> Result.Conclusion) {
        self.mode = .arbitraryNetwork(address: networkAddress, netmask: netmask)
        self.reportMisses = reportMisses
        self.concurrencyLimit = concurrencyLimit
        self.log = logger
        self.probe = probe
    }

    /// The result of a probe attempt.
    public struct Result: Sendable {
        /// The address that was probed, e.g. "192.168.0.123".
        public let address: String

        /// How a probe attempt concluded.
        ///
        /// Note that if the probe closure throws an exception, that is not represented by this enum - it is instead propagated back to the iterator of the ``NetworkScanner`` (as a real, thrown exception).
        public enum Conclusion: Sendable {
            /// The probe succeeded (returned `true`).
            case hit(HitData)

            /// The probe returned `false`.
            case miss(MissData)
        }

        /// The conclusion of the probe attempt.
        public let conclusion: Conclusion
    }

    public typealias Element = Result

    public func makeAsyncIterator() -> Iterator {
        return Iterator(mode: mode,
                        reportMisses: reportMisses,
                        concurrencyLimit: concurrencyLimit,
                        log: log,
                        probe: probe)
    }

    public final class Iterator: AsyncIteratorProtocol {
        private var overarchingTask: Task<Void, Error>? = nil
        private let channel = AsyncThrowingChannel<Result, Error>()

        fileprivate init(mode: Mode,
                         reportMisses: Bool,
                         concurrencyLimit: Int?,
                         log: Logger?,
                         probe: @escaping (String) async throws -> Result.Conclusion) {
            let labelConstructor = {
                let missVoid = Void.self != MissData.self
                let anyVoid = Void.self != HitData.self || missVoid
                let myAddress = Unmanaged.passUnretained(self).toOpaque()

                return "NetworkScanner\(anyVoid ? "<\(HitData.self)\(missVoid ? ", \(MissData.self)" : "")>" : "").Iterator[\(myAddress)]"
            }

            let log = log ?? Logger(label: labelConstructor())

            self.overarchingTask = Task { [channel] in
                do {
                    try await withThrowingTaskGroup(of: Void.self) { taskGroup in
                        // max(1, …) to ensure that there's always at least one task that can run at a time, so as to make forward progress.
                        var taskTokens = Swift.max(1, concurrencyLimit ?? Int.max)

                        switch mode {
                        case .localNetworks(let interfaceFilter, let oneFullScanOnly):
                            if oneFullScanOnly {
                                for interface in try NetworkInterface.all {
                                    guard !Task.isCancelled else { break }

                                    try await NetworkScanner.Iterator.scan(interface: interface,
                                                                           interfaceFilter: interfaceFilter,
                                                                           reportMisses: reportMisses,
                                                                           probe: probe,
                                                                           channel: channel,
                                                                           taskGroup: &taskGroup,
                                                                           taskTokens: &taskTokens,
                                                                           log: log)
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
                                                                               taskTokens: &taskTokens,
                                                                               log: log)
                                    default:
                                        break
                                    }
                                }
                            }
                        case .arbitraryNetwork(let address, let netmask):
                            try await NetworkScanner.Iterator.scan(networkAddress: address,
                                                                   netmask: netmask,
                                                                   reportMisses: reportMisses,
                                                                   probe: probe,
                                                                   channel: channel,
                                                                   taskGroup: &taskGroup,
                                                                   taskTokens: &taskTokens,
                                                                   log: log)
                        }

                        log.info("Wrapping up results…")

                        for try await _ in taskGroup {
                            guard !Task.isCancelled else {
                                log.info("Cancelled.")
                                taskGroup.cancelAll()
                                break
                            }
                        }

                        log.info("No more results.")
                    }

                    channel.finish()
                } catch {
                    log.info("Scanning failed with error:\n\(error)")
                    channel.fail(error)
                }
            }
        }

        deinit {
            self.overarchingTask?.cancel()
        }

        private static func scan(interface: NetworkInterface,
                                 interfaceFilter: (NetworkInterface) -> Bool,
                                 reportMisses: Bool,
                                 probe: @escaping (String) async throws -> Result.Conclusion,
                                 channel: AsyncThrowingChannel<Result, Error>,
                                 taskGroup: inout ThrowingTaskGroup<Void, Error>,
                                 taskTokens: inout Int,
                                 log: Logger) async throws {
            guard let genericAddress = interface.address,
                  let genericNetmask = interface.netmask,
                  interface.up,
                  let addressFamily = interface.addressFamily,
                  .inet == addressFamily, // TODO: Support IPv6 too.
                  interfaceFilter(interface) else {
                return
            }

            guard let v4Address = genericAddress.IPv4,
                  let v4Netmask = genericNetmask.IPv4 else {
                return
            }

            log.info("Scanning \(interface)…")

            try await scan(networkAddress: v4Address,
                           netmask: v4Netmask,
                           reportMisses: reportMisses,
                           probe: probe,
                           channel: channel,
                           taskGroup: &taskGroup,
                           taskTokens: &taskTokens,
                           log: log)

            log.info("Scanning completed for \(interface).")
        }

        private static func scan(networkAddress: IPv4Address,
                                 netmask: IPv4Address,
                                 reportMisses: Bool,
                                 probe: @escaping (String) async throws -> Result.Conclusion,
                                 channel: AsyncThrowingChannel<Result, Error>,
                                 taskGroup: inout ThrowingTaskGroup<Void, Error>,
                                 taskTokens: inout Int,
                                 log: Logger) async throws {
            let startAddress = netmask.address & networkAddress.address
            let lastAddress = startAddress | ~netmask.address

            log.info("Scanning \(IPv4Address(addressInHostOrder: startAddress)) to \(IPv4Address(addressInHostOrder: lastAddress)) (about \((lastAddress - startAddress).formatted()) addresses)…")

            for candidate in startAddress..<lastAddress {
                guard !Task.isCancelled, !taskGroup.isCancelled else {
                    log.info("Scanning cancelled for \(IPv4Address(addressInHostOrder: startAddress)) to \(IPv4Address(addressInHostOrder: lastAddress)) (at \(candidate)).")
                    return
                }

                if candidate != startAddress && candidate != networkAddress.address {
                    let addressString = IPv4Address(addressInHostOrder: candidate).description

                    log.debug("\tScanning \(addressString)…")

                    if 0 >= taskTokens {
                        try await taskGroup.next()
                    } else {
                        taskTokens -= 1
                    }

                    _ = taskGroup.addTaskUnlessCancelled { [probe, channel] in
                        let conclusion = try await probe(addressString)

                        switch conclusion {
                        case .hit:
                            log.info("\t\tReturning hit for \(addressString).")
                        case .miss:
                            log.debug("\t\tReturning miss for \(addressString).")

                            guard reportMisses else { return }
                        }

                        await channel.send(Result(address: addressString, conclusion: conclusion))
                    }
                }
            }

            log.info("Scanning completed for \(IPv4Address(addressInHostOrder: startAddress)) to \(IPv4Address(addressInHostOrder: lastAddress)).")
        }

        public func next() async throws -> Result? {
            for try await result in channel {
                return result
            }

            return nil
        }
    }
}

extension NetworkScanner.Result: Equatable where HitData: Equatable, MissData: Equatable {}
extension NetworkScanner.Result: Hashable where HitData: Hashable, MissData: Hashable {}

extension NetworkScanner.Result: CustomStringConvertible {
    public var description: String {
        "\(address): \(conclusion)"
    }
}

extension NetworkScanner.Result.Conclusion: Equatable where HitData: Equatable, MissData: Equatable {}
extension NetworkScanner.Result.Conclusion: Hashable where HitData: Hashable, MissData: Hashable {}

extension NetworkScanner.Result.Conclusion: CustomStringConvertible {
    public var description: String {
        switch self {
        case .hit(let data):
            if HitData.self == Void.self {
                return "Hit"
            } else {
                return "Hit (\(data))"
            }
        case .miss(let data):
            if MissData.self == Void.self {
                return "Miss"
            } else {
                return "Miss (\(data))"
            }
        }
    }
}

// Unfortunately even if you don't have any additional data to return with hits and/or misses, by default Swift [4 onwards] still makes you provide an associated 'value' explicitly, like `.hit(())`.  These two special-casing extensions are to work around that.  Kudos to Geoff Hackworth (https://stackoverflow.com/users/870671/geoff-hackworth) for figuring this out (https://stackoverflow.com/a/76175910/790079), with help from Martin R (https://stackoverflow.com/users/1187415/martin-r) and Hamish (https://stackoverflow.com/users/2976878/hamish) re. https://stackoverflow.com/a/46863180/790079.
extension NetworkScanner.Result.Conclusion where HitData == Void {
    /// A convenience constructor so you don't have to write `.hit(())`, just `.hit`, when you're not using HitData (i.e. when you set it to Void).
    public static var hit: Self {
        .hit(())
    }
}

extension NetworkScanner.Result.Conclusion where MissData == Void {
    /// A convenience constructor so you don't have to write `.miss(())`, just `.miss`, when you're not using MissData (i.e. when you set it to Void).
    public static var miss: Self {
        .miss(())
    }
}

extension NetworkScanner.Result.Conclusion: CaseIterable where HitData == Void, MissData == Void {
    public static var allCases: [NetworkScanner<(), ()>.Result.Conclusion] {
        [.hit, .miss]
    }
}
