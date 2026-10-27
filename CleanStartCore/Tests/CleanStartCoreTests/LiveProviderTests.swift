import XCTest
@testable import CleanStartCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Minimal RFC 8484 client used only by these tests, so the default probe set
/// can be checked against the real CleanBrowsing service from any machine.
/// Only DNS messages are exchanged; no website content is fetched.
struct DoHTestResolver: HostResolver {
    let endpoint: URL

    func resolve(_ host: String) async -> ResolutionOutcome {
        var request = URLRequest(url: endpoint, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/dns-message", forHTTPHeaderField: "Content-Type")
        request.setValue("application/dns-message", forHTTPHeaderField: "Accept")
        request.httpBody = Self.query(host)
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            return Self.parse([UInt8](data))
        } catch {
            return .failed(reason: error.localizedDescription)
        }
    }

    static func query(_ host: String) -> Data {
        var bytes: [UInt8] = [0, 0, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0]
        for label in host.split(separator: ".") {
            bytes.append(UInt8(label.utf8.count))
            bytes.append(contentsOf: label.utf8)
        }
        bytes += [0, 0, 1, 0, 1] // QTYPE A, QCLASS IN
        return Data(bytes)
    }

    static func parse(_ m: [UInt8]) -> ResolutionOutcome {
        guard m.count >= 12 else { return .failed(reason: "short response") }
        let rcode = m[3] & 0x0F
        if rcode == 3 { return .nonexistentDomain }
        guard rcode == 0 else { return .failed(reason: "rcode \(rcode)") }
        let qd = Int(m[4]) << 8 | Int(m[5])
        let an = Int(m[6]) << 8 | Int(m[7])
        var offset = 12
        for _ in 0..<qd { offset = skipName(m, offset) + 4 }
        var addresses: [String] = []
        var canonical: String?
        for _ in 0..<an {
            offset = skipName(m, offset)
            let type = Int(m[offset]) << 8 | Int(m[offset + 1])
            let length = Int(m[offset + 8]) << 8 | Int(m[offset + 9])
            let rdata = offset + 10
            if type == 1, length == 4 { addresses.append(m[rdata..<rdata + 4].map(String.init).joined(separator: ".")) }
            if type == 5 { canonical = readName(m, rdata) }
            offset = rdata + length
        }
        return addresses.isEmpty ? .nonexistentDomain : .resolved(addresses: addresses, canonicalName: canonical)
    }

    static func skipName(_ m: [UInt8], _ start: Int) -> Int {
        var o = start
        while m[o] != 0 {
            if m[o] & 0xC0 == 0xC0 { return o + 2 }
            o += Int(m[o]) + 1
        }
        return o + 1
    }

    static func readName(_ m: [UInt8], _ start: Int) -> String {
        var labels: [String] = []
        var o = start
        var hops = 0
        while m[o] != 0, hops < 20 {
            if m[o] & 0xC0 == 0xC0 {
                o = Int(m[o] & 0x3F) << 8 | Int(m[o + 1]); hops += 1; continue
            }
            let length = Int(m[o])
            labels.append(String(decoding: m[(o + 1)...(o + length)], as: UTF8.self))
            o += length + 1
        }
        return labels.joined(separator: ".")
    }
}

/// Set CLEANSTART_LIVE_TESTS=1 to run. Requires internet access.
final class LiveProviderTests: XCTestCase {
    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["CLEANSTART_LIVE_TESTS"] == "1", "Live network tests disabled")
    }

    func testCleanBrowsingFamilyPassesDefaultProbes() async {
        let resolver = DoHTestResolver(endpoint: EncryptedDNSProvider.cleanBrowsingFamily.dohURL)
        let report = await FilterVerifier(resolver: resolver).run(networkDescription: "Live DoH")
        for result in report.results { print("  \(result.probeID): \(result.outcomeSummary) passed=\(String(describing: result.passed))") }
        XCTAssertEqual(report.verdict, .verified)
    }

    func testUnfilteredResolverIsDetected() async {
        let resolver = DoHTestResolver(endpoint: URL(string: "https://cloudflare-dns.com/dns-query")!)
        let report = await FilterVerifier(resolver: resolver).run(networkDescription: "Live DoH (unfiltered)")
        XCTAssertEqual(report.verdict, .notFiltering)
    }
}
