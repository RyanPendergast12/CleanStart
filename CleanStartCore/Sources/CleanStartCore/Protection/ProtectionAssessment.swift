import Foundation

/// What the system reports about CleanStart's own DNS settings configuration
/// (NEDNSSettingsManager). This is configuration *status*, not effectiveness.
public enum DNSConfigurationState: Codable, Equatable, Sendable {
    case unknown
    /// CleanStart has never saved a DNS configuration (or it was removed).
    case notInstalled
    /// Saved, but the user has not selected it in Settings, or another DNS
    /// configuration (e.g. a profile) is currently selected instead.
    case installedNotEnabled
    /// Selected and applied system-wide. `matchesExpected` is false if the stored
    /// server differs from CleanBrowsing Family.
    case enabled(matchesExpected: Bool)
    /// The API is unavailable (missing entitlement, unsupported device, error).
    case unavailable(reason: String)

    public var title: String {
        switch self {
        case .unknown: return "Checking…"
        case .notInstalled: return "Not installed"
        case .installedNotEnabled: return "Installed, not enabled"
        case .enabled(let matches): return matches ? "Enabled" : "Enabled (unexpected server)"
        case .unavailable: return "Unavailable"
        }
    }
}

public enum ScreenTimeAuthorizationState: String, Codable, Sendable {
    case notDetermined, denied, approved, unavailable
}

public struct ProtectionIssue: Equatable, Sendable, Identifiable {
    public enum Severity: Int, Comparable, Sendable {
        case info = 0, warning = 1, critical = 2
        public static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.rawValue < rhs.rawValue }
    }
    public let id: String
    public let severity: Severity
    public let title: String
    public let detail: String
}

public enum ProtectionLevel: String, Sendable {
    /// Configuration in place AND filtering recently verified.
    case protected
    /// Something needs attention (unverified, stale, warning).
    case attention
    /// Filtering is known not to be working.
    case unprotected
}

/// Inputs gathered by the app; kept as plain values so the rules are testable.
public struct ProtectionSnapshot: Sendable {
    public var dnsConfiguration: DNSConfigurationState
    public var latestVerification: FilterVerificationReport?
    public var previousVerdict: FilterVerdict?
    public var screenTime: ScreenTimeAuthorizationState
    public var shieldsActive: Bool
    public var vpnLikelyActive: Bool
    public var now: Date

    public init(dnsConfiguration: DNSConfigurationState, latestVerification: FilterVerificationReport?, previousVerdict: FilterVerdict? = nil, screenTime: ScreenTimeAuthorizationState, shieldsActive: Bool, vpnLikelyActive: Bool, now: Date) {
        self.dnsConfiguration = dnsConfiguration
        self.latestVerification = latestVerification
        self.previousVerdict = previousVerdict
        self.screenTime = screenTime
        self.shieldsActive = shieldsActive
        self.vpnLikelyActive = vpnLikelyActive
        self.now = now
    }
}

public struct ProtectionAssessment: Sendable {
    public let level: ProtectionLevel
    public let headline: String
    public let issues: [ProtectionIssue]

    /// A verification older than this is treated as stale.
    public static let verificationMaxAge: TimeInterval = 24 * 60 * 60

    public static func assess(_ s: ProtectionSnapshot) -> ProtectionAssessment {
        var issues: [ProtectionIssue] = []
        let verdict = s.latestVerification?.verdict

        switch s.dnsConfiguration {
        case .notInstalled where verdict == .verified || verdict == .blockingObserved:
            issues.append(.init(id: "dns-other", severity: .info, title: "Filtering comes from another configuration",
                                detail: "CleanStart's DNS setting isn't installed, but filtering was verified. You're probably using a DNS profile. That's fine; CleanStart just can't manage it."))
        case .notInstalled:
            issues.append(.init(id: "dns-missing", severity: .critical, title: "DNS filtering not set up",
                                detail: "Open Protection › DNS Filtering to install the CleanBrowsing Family configuration."))
        case .installedNotEnabled:
            issues.append(.init(id: "dns-disabled", severity: verdict == .verified ? .info : .critical, title: "DNS setting not selected",
                                detail: "Open Settings › General › VPN & Device Management › DNS and choose CleanStart. iOS uses only one DNS configuration at a time."))
        case .enabled(let matches) where !matches:
            issues.append(.init(id: "dns-mismatch", severity: .warning, title: "Unexpected DNS server",
                                detail: "The saved configuration does not point at CleanBrowsing Family. Reinstall it from Protection › DNS Filtering."))
        case .unavailable(let reason):
            issues.append(.init(id: "dns-unavailable", severity: .warning, title: "DNS settings API unavailable",
                                detail: "\(reason) You can use the CleanBrowsing configuration profile instead (see Protection › Troubleshooting)."))
        case .enabled, .unknown:
            break
        }

        if let report = s.latestVerification {
            if s.now.timeIntervalSince(report.date) > verificationMaxAge {
                issues.append(.init(id: "verify-stale", severity: .warning, title: "Verification is out of date",
                                    detail: "The last successful check was more than a day ago. Run a check to confirm filtering on your current network."))
            }
            switch report.verdict {
            case .notFiltering:
                let regressed = s.previousVerdict == .verified || s.previousVerdict == .blockingObserved
                issues.append(.init(id: "verify-failed", severity: .critical,
                                    title: regressed ? "Protection changed since the last check" : "Filtering is not working",
                                    detail: report.explanation))
            case .inconclusive:
                issues.append(.init(id: "verify-inconclusive", severity: .warning, title: "Couldn't verify filtering", detail: report.explanation))
            case .blockingObserved:
                issues.append(.init(id: "verify-partial", severity: .warning, title: "Filter not confirmed as CleanBrowsing", detail: report.explanation))
            case .verified:
                break
            }
        } else {
            issues.append(.init(id: "verify-never", severity: .warning, title: "Protection is unverified",
                                detail: "Run a filtering check. A configuration being installed does not by itself prove websites are filtered."))
        }

        if s.vpnLikelyActive {
            issues.append(.init(id: "vpn-active", severity: .warning, title: "A VPN appears to be active",
                                detail: "While a VPN is connected, iOS uses the VPN's DNS for traffic inside the tunnel, which can bypass CleanBrowsing. Work VPNs are expected; personal or browser VPNs defeat the filter."))
        }

        switch s.screenTime {
        case .notDetermined:
            issues.append(.init(id: "st-undetermined", severity: .info, title: "Screen Time not connected",
                                detail: "Optional: authorize Screen Time to shield chosen apps and turn on Apple's adult-website filter."))
        case .denied:
            issues.append(.init(id: "st-denied", severity: .info, title: "Screen Time access declined",
                                detail: "App shields are off. You can grant access later from Protection › Screen Time."))
        case .approved where !s.shieldsActive:
            issues.append(.init(id: "st-noshields", severity: .info, title: "No app restrictions active",
                                detail: "Screen Time is authorized but nothing is shielded yet."))
        case .approved, .unavailable:
            break
        }

        issues.sort { $0.severity > $1.severity }

        let level: ProtectionLevel
        let headline: String
        if verdict == .notFiltering {
            level = .unprotected
            headline = "Not protected on this network"
        } else if verdict == .verified, !issues.contains(where: { $0.severity >= .warning }) {
            level = .protected
            headline = "Protected and verified"
        } else if issues.contains(where: { $0.severity == .critical }) {
            level = .unprotected
            headline = "Protection needs setup"
        } else {
            level = .attention
            headline = "Protection unverified"
        }
        return ProtectionAssessment(level: level, headline: headline, issues: issues)
    }
}
