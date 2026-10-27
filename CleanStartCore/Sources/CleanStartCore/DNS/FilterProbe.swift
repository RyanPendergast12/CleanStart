import Foundation

/// A single DNS lookup used to judge whether filtering is really in effect.
///
/// Probes only perform DNS lookups. They never open a connection to, or load
/// content from, the probed host.
public struct FilterProbe: Codable, Equatable, Sendable, Identifiable {
    public enum Kind: Codable, Equatable, Sendable {
        /// A harmless, always-available domain. If it fails, the network (not
        /// the filter) is the problem and the run is inconclusive.
        case control
        /// A well-known adult domain that a working family filter must block.
        case mustBeBlocked
        /// A search engine that a family filter rewrites to its SafeSearch
        /// endpoint. Matching either a canonical-name suffix or an address
        /// counts as evidence of filtering.
        case safeSearch(canonicalSuffixes: [String], addresses: [String])
    }

    public let id: String
    public let host: String
    public let purpose: String
    public let kind: Kind

    public init(id: String, host: String, purpose: String, kind: Kind) {
        self.id = id
        self.host = host
        self.purpose = purpose
        self.kind = kind
    }

    /// Returns `true` when the outcome is what an active family filter would
    /// produce, `false` when it shows filtering is absent, and `nil` when the
    /// outcome says nothing either way (lookup failure).
    public func evaluate(_ outcome: ResolutionOutcome) -> Bool? {
        switch (kind, outcome) {
        case (_, .failed):
            return nil
        case (.control, .resolved):
            return true
        case (.control, .nonexistentDomain):
            return false
        case (.mustBeBlocked, .nonexistentDomain):
            return true
        case (.mustBeBlocked, .resolved(let addresses, _)):
            // Some filters answer with a sinkhole address instead of NXDOMAIN.
            return addresses.allSatisfy(Self.isSinkhole)
        case (.safeSearch(let suffixes, let expected), .resolved(let addresses, let canonical)):
            if let canonical, suffixes.contains(where: { canonical.hasSuffix($0.lowercased()) }) { return true }
            let normalizedExpected = Set(expected.map { $0.lowercased() })
            return addresses.contains { normalizedExpected.contains($0.lowercased()) }
        case (.safeSearch, .nonexistentDomain):
            return false
        }
    }

    static func isSinkhole(_ address: String) -> Bool {
        ["0.0.0.0", "::", "127.0.0.1", "::1"].contains(address)
    }
}

public extension FilterProbe {
    /// The default probe set. Adult domains are tested by name resolution only;
    /// the app never displays or loads them.
    static let defaultSet: [FilterProbe] = [
        FilterProbe(
            id: "control-apple",
            host: "www.apple.com",
            purpose: "Confirms the network and DNS are working at all.",
            kind: .control
        ),
        FilterProbe(
            id: "control-microsoft-login",
            host: "login.microsoftonline.com",
            purpose: "Confirms Microsoft Entra sign-in still resolves (work compatibility).",
            kind: .control
        ),
        FilterProbe(
            id: "adult-1",
            host: "pornhub.com",
            purpose: "A well-known adult domain that must be blocked.",
            kind: .mustBeBlocked
        ),
        FilterProbe(
            id: "adult-2",
            host: "xvideos.com",
            purpose: "A second well-known adult domain that must be blocked.",
            kind: .mustBeBlocked
        ),
        FilterProbe(
            id: "safesearch-duckduckgo",
            host: "duckduckgo.com",
            purpose: "CleanBrowsing Family answers with safe.duckduckgo.com (strict Safe Search).",
            kind: .safeSearch(canonicalSuffixes: ["safe.duckduckgo.com"], addresses: [])
        ),
        FilterProbe(
            id: "safesearch-google",
            host: "www.google.com",
            purpose: "CleanBrowsing Family answers with Google's forcesafesearch address.",
            // forcesafesearch.google.com, as documented by Google for network SafeSearch.
            kind: .safeSearch(canonicalSuffixes: ["forcesafesearch.google.com"], addresses: ["216.239.38.120", "2001:4860:4802:32::78"])
        ),
    ]
}
