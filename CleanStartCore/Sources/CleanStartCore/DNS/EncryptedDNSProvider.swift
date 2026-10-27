import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// An encrypted DNS (DNS-over-HTTPS) resolver that CleanStart can configure.
public struct EncryptedDNSProvider: Codable, Equatable, Sendable {
    public let id: String
    public let displayName: String
    /// RFC 8484 DNS-over-HTTPS endpoint.
    public let dohURL: URL
    /// Plain IP addresses of the DoH server. iOS uses them to reach the server
    /// without first resolving its hostname through another (unfiltered) resolver.
    public let serverAddresses: [String]
    /// DNS-over-TLS hostname, documented for users who prefer a profile.
    public let dotHostname: String
    /// Official page documenting these values.
    public let documentationURL: URL

    public init(id: String, displayName: String, dohURL: URL, serverAddresses: [String], dotHostname: String, documentationURL: URL) {
        self.id = id
        self.displayName = displayName
        self.dohURL = dohURL
        self.serverAddresses = serverAddresses
        self.dotHostname = dotHostname
        self.documentationURL = documentationURL
    }

    /// CleanBrowsing Family Filter, as published at https://cleanbrowsing.org/filters/
    /// (verified 2026-10-27). Blocks adult content, proxy/VPN bypass domains and
    /// mixed-content sites, and enforces SafeSearch on Google, Bing, YouTube and
    /// DuckDuckGo (duckduckgo.com is answered with a CNAME to safe.duckduckgo.com).
    public static let cleanBrowsingFamily = EncryptedDNSProvider(
        id: "cleanbrowsing-family",
        displayName: "CleanBrowsing Family Filter",
        dohURL: URL(string: "https://doh.cleanbrowsing.org/doh/family-filter/")!,
        serverAddresses: [
            "185.228.168.168",
            "185.228.169.168",
            "2a0d:2a00:1::",
            "2a0d:2a00:2::",
        ],
        dotHostname: "family-filter-dns.cleanbrowsing.org",
        documentationURL: URL(string: "https://cleanbrowsing.org/filters/")!
    )

    public enum ValidationError: Error, Equatable, CustomStringConvertible {
        case insecureScheme(String)
        case missingHost
        case noServerAddresses
        case invalidServerAddress(String)

        public var description: String {
            switch self {
            case .insecureScheme(let scheme): return "The DNS server URL must use https (found \"\(scheme)\")."
            case .missingHost: return "The DNS server URL has no host name."
            case .noServerAddresses: return "At least one DNS server IP address is required."
            case .invalidServerAddress(let address): return "\"\(address)\" is not a valid IPv4 or IPv6 address."
            }
        }
    }

    /// Checks the configuration before it is handed to the system, so a typo
    /// can never silently produce a broken (and therefore unfiltered) setup.
    public func validate() throws {
        guard dohURL.scheme?.lowercased() == "https" else {
            throw ValidationError.insecureScheme(dohURL.scheme ?? "none")
        }
        guard let host = dohURL.host, !host.isEmpty else { throw ValidationError.missingHost }
        guard !serverAddresses.isEmpty else { throw ValidationError.noServerAddresses }
        for address in serverAddresses where !IPAddress.isValid(address) {
            throw ValidationError.invalidServerAddress(address)
        }
    }

    /// Compares a URL reported by the system with this provider's endpoint,
    /// ignoring case and a trailing slash.
    public func matches(serverURL: URL?) -> Bool {
        guard let serverURL else { return false }
        return Self.normalize(serverURL) == Self.normalize(dohURL)
    }

    private static func normalize(_ url: URL) -> String {
        var text = url.absoluteString.lowercased()
        while text.hasSuffix("/") { text.removeLast() }
        return text
    }
}

public enum IPAddress {
    public static func isValid(_ text: String) -> Bool {
        var v4 = in_addr()
        var v6 = in6_addr()
        return text.withCString { pointer in
            inet_pton(AF_INET, pointer, &v4) == 1 || inet_pton(AF_INET6, pointer, &v6) == 1
        }
    }
}
