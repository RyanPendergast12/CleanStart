import Foundation

/// Overall judgement from one verification run. This describes filtering
/// *effectiveness*, which is separate from whether a configuration is installed.
public enum FilterVerdict: String, Codable, Sendable, CaseIterable {
    /// Adult domains are blocked and SafeSearch rewriting is observed: the
    /// system resolver behaves like CleanBrowsing Family.
    case verified
    /// Adult domains are blocked, but SafeSearch rewriting was not observed.
    /// Some filter is active; it may not be CleanBrowsing Family.
    case blockingObserved
    /// At least one adult domain resolved normally: filtering is NOT in effect
    /// for this network right now.
    case notFiltering
    /// The network or resolver was unavailable, so nothing can be concluded.
    case inconclusive

    public var title: String {
        switch self {
        case .verified: return "Filtering verified"
        case .blockingObserved: return "Blocking observed"
        case .notFiltering: return "Not filtering"
        case .inconclusive: return "Inconclusive"
        }
    }
}

public struct ProbeResult: Codable, Equatable, Sendable, Identifiable {
    public var id: String { probeID }
    public let probeID: String
    public let host: String
    public let purpose: String
    public let outcomeSummary: String
    /// `true` = as expected for an active filter, `false` = contrary, `nil` = unknown.
    public let passed: Bool?
    public let durationMilliseconds: Int

    public init(probeID: String, host: String, purpose: String, outcomeSummary: String, passed: Bool?, durationMilliseconds: Int) {
        self.probeID = probeID
        self.host = host
        self.purpose = purpose
        self.outcomeSummary = outcomeSummary
        self.passed = passed
        self.durationMilliseconds = durationMilliseconds
    }
}

public struct FilterVerificationReport: Codable, Equatable, Sendable {
    public let date: Date
    public let verdict: FilterVerdict
    public let results: [ProbeResult]
    /// e.g. "Wi-Fi" or "Cellular" — never an SSID or IP address.
    public let networkDescription: String

    public init(date: Date, verdict: FilterVerdict, results: [ProbeResult], networkDescription: String) {
        self.date = date
        self.verdict = verdict
        self.results = results
        self.networkDescription = networkDescription
    }

    public var explanation: String {
        switch verdict {
        case .verified:
            return "Adult test domains were blocked and search engines were redirected to SafeSearch on \(networkDescription). This matches CleanBrowsing Family."
        case .blockingObserved:
            return "Adult test domains were blocked on \(networkDescription), but SafeSearch redirection was not observed. A filter is active, but it may not be CleanBrowsing Family."
        case .notFiltering:
            return "An adult test domain resolved normally on \(networkDescription). Websites are NOT being filtered by DNS right now."
        case .inconclusive:
            return "The network or DNS resolver did not respond on \(networkDescription), so filtering could not be checked. Try again when you have a connection."
        }
    }
}

/// Runs the probe set through a resolver and derives a verdict.
public struct FilterVerifier: Sendable {
    public let resolver: HostResolver
    public let probes: [FilterProbe]

    public init(resolver: HostResolver = SystemHostResolver(), probes: [FilterProbe] = FilterProbe.defaultSet) {
        self.resolver = resolver
        self.probes = probes
    }

    public func run(networkDescription: String, now: @Sendable () -> Date = { Date() }) async -> FilterVerificationReport {
        var results: [ProbeResult] = []
        for probe in probes {
            let start = Date()
            let outcome = await resolver.resolve(probe.host)
            let elapsed = Int(Date().timeIntervalSince(start) * 1000)
            // Addresses are deliberately not stored: only the summary.
            results.append(ProbeResult(
                probeID: probe.id,
                host: probe.host,
                purpose: probe.purpose,
                outcomeSummary: outcome.summary,
                passed: probe.evaluate(outcome),
                durationMilliseconds: elapsed
            ))
        }
        return FilterVerificationReport(
            date: now(),
            verdict: Self.verdict(probes: probes, results: results),
            results: results,
            networkDescription: networkDescription
        )
    }

    public static func verdict(probes: [FilterProbe], results: [ProbeResult]) -> FilterVerdict {
        let byID = Dictionary(uniqueKeysWithValues: results.map { ($0.probeID, $0) })
        func passes(where predicate: (FilterProbe.Kind) -> Bool) -> [Bool?] {
            probes.filter { predicate($0.kind) }.map { byID[$0.id]?.passed ?? nil }
        }

        let control = passes { $0 == .control }
        let blocked = passes { $0 == .mustBeBlocked }
        let safeSearch = passes { if case .safeSearch = $0 { return true } else { return false } }

        // Without at least one working control lookup the network itself is down.
        guard control.contains(true) else { return .inconclusive }
        // Any adult domain resolving is decisive, regardless of other probes.
        if blocked.contains(false) { return .notFiltering }
        // Require every adult probe to have an answer before claiming success.
        guard !blocked.isEmpty, blocked.allSatisfy({ $0 == true }) else { return .inconclusive }
        return safeSearch.contains(true) ? .verified : .blockingObserved
    }
}
