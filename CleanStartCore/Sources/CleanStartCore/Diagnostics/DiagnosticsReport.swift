import Foundation

/// Builds a plain-text diagnostics summary the user can read or copy.
/// It is never sent anywhere by CleanStart, and contains no browsing data,
/// IP addresses, network names or identifiers.
public struct DiagnosticsReport: Sendable {
    public var appVersion: String
    public var osVersion: String
    public var dnsConfiguration: DNSConfigurationState
    public var screenTime: ScreenTimeAuthorizationState
    public var networkDescription: String
    public var vpnLikelyActive: Bool
    public var latestVerification: FilterVerificationReport?
    public var lastError: String?

    public init(appVersion: String, osVersion: String, dnsConfiguration: DNSConfigurationState, screenTime: ScreenTimeAuthorizationState, networkDescription: String, vpnLikelyActive: Bool, latestVerification: FilterVerificationReport?, lastError: String?) {
        self.appVersion = appVersion
        self.osVersion = osVersion
        self.dnsConfiguration = dnsConfiguration
        self.screenTime = screenTime
        self.networkDescription = networkDescription
        self.vpnLikelyActive = vpnLikelyActive
        self.latestVerification = latestVerification
        self.lastError = lastError
    }

    public func text(dateFormatter: (Date) -> String = { ISO8601DateFormatter().string(from: $0) }) -> String {
        var lines = [
            "CleanStart diagnostics",
            "App: \(appVersion)  OS: \(osVersion)",
            "DNS configuration: \(dnsConfiguration.title)",
            "Screen Time: \(screenTime.rawValue)",
            "Network: \(networkDescription)",
            "VPN detected: \(vpnLikelyActive ? "yes" : "no")",
        ]
        if case .unavailable(let reason) = dnsConfiguration { lines.append("DNS API detail: \(reason)") }
        if let report = latestVerification {
            lines.append("Last check: \(dateFormatter(report.date)) on \(report.networkDescription) → \(report.verdict.title)")
            for result in report.results {
                let mark = result.passed.map { $0 ? "PASS" : "FAIL" } ?? "N/A "
                lines.append("  [\(mark)] \(result.probeID): \(result.outcomeSummary) (\(result.durationMilliseconds) ms)")
            }
        } else {
            lines.append("Last check: never")
        }
        if let lastError { lines.append("Last error: \(lastError)") }
        return lines.joined(separator: "\n")
    }
}
