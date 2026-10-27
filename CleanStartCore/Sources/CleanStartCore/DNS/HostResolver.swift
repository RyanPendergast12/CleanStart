import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// What happened when a host name was looked up through the system resolver.
public enum ResolutionOutcome: Equatable, Sendable {
    /// The name resolved. `canonicalName` is the end of any CNAME chain when the
    /// system reports it (for example `safe.duckduckgo.com`).
    case resolved(addresses: [String], canonicalName: String?)
    /// The resolver answered that the name does not exist (NXDOMAIN) or has no
    /// address records. This is how CleanBrowsing answers for blocked domains.
    case nonexistentDomain
    /// The lookup could not complete (offline, timeout, resolver unreachable).
    case failed(reason: String)

    public var summary: String {
        switch self {
        case .resolved(let addresses, let canonicalName):
            let canonical = canonicalName.map { " via \($0)" } ?? ""
            return "Resolved (\(addresses.count) address\(addresses.count == 1 ? "" : "es"))\(canonical)"
        case .nonexistentDomain:
            return "Blocked / does not exist"
        case .failed(let reason):
            return "Lookup failed: \(reason)"
        }
    }
}

/// Abstraction over name resolution so verification logic can be tested
/// without a network.
public protocol HostResolver: Sendable {
    func resolve(_ host: String) async -> ResolutionOutcome
}

/// Resolves names with `getaddrinfo`, i.e. through the same system resolver that
/// DuckDuckGo, Safari and every other app use. On iOS this honours the active
/// NEDNSSettingsManager / configuration-profile DNS settings, so the result
/// reflects what browsers on this device actually see.
///
/// No web content is ever requested: only DNS lookups are performed.
public struct SystemHostResolver: HostResolver {
    public var timeout: TimeInterval

    public init(timeout: TimeInterval = 8) {
        self.timeout = timeout
    }

    public func resolve(_ host: String) async -> ResolutionOutcome {
        let timeout = self.timeout
        return await withTaskGroup(of: ResolutionOutcome?.self) { group in
            group.addTask {
                await withCheckedContinuation { continuation in
                    // getaddrinfo blocks, so keep it off the cooperative thread pool.
                    DispatchQueue.global(qos: .userInitiated).async {
                        continuation.resume(returning: Self.blockingResolve(host))
                    }
                }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first ?? .failed(reason: "timed out after \(Int(timeout))s")
        }
    }

    static func blockingResolve(_ host: String) -> ResolutionOutcome {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_flags = AI_CANONNAME
        #if canImport(Glibc)
        hints.ai_socktype = Int32(SOCK_STREAM.rawValue)
        #else
        hints.ai_socktype = SOCK_STREAM
        #endif

        var list: UnsafeMutablePointer<addrinfo>?
        let status = getaddrinfo(host, nil, &hints, &list)
        defer { if let list { freeaddrinfo(list) } }

        guard status == 0 else {
            if isNoSuchName(status) { return .nonexistentDomain }
            let message = String(cString: gai_strerror(status))
            return .failed(reason: message)
        }

        var addresses: [String] = []
        var canonicalName: String?
        var cursor = list
        while let entry = cursor?.pointee {
            if canonicalName == nil, let name = entry.ai_canonname {
                canonicalName = String(cString: name)
            }
            if let text = numericHost(entry), !addresses.contains(text) {
                addresses.append(text)
            }
            cursor = entry.ai_next
        }
        if addresses.isEmpty { return .nonexistentDomain }
        if let name = canonicalName, name.lowercased() == host.lowercased() { canonicalName = nil }
        return .resolved(addresses: addresses, canonicalName: canonicalName?.lowercased())
    }

    private static func isNoSuchName(_ status: Int32) -> Bool {
        if status == EAI_NONAME { return true }
        #if os(Linux)
        return status == -5 // EAI_NODATA (GNU extension, not exported to Swift)
        #else
        return status == EAI_NODATA
        #endif
    }

    private static func numericHost(_ entry: addrinfo) -> String? {
        guard let address = entry.ai_addr else { return nil }
        var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let result = getnameinfo(address, entry.ai_addrlen, &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST)
        return result == 0 ? String(cString: buffer) : nil
    }
}
