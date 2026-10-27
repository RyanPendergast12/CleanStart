import XCTest
@testable import CleanStartCore

/// Deterministic resolver for tests.
struct StubResolver: HostResolver {
    var answers: [String: ResolutionOutcome]
    func resolve(_ host: String) async -> ResolutionOutcome {
        answers[host] ?? .failed(reason: "no stub")
    }
}

extension StubResolver {
    /// Answers modelled on real CleanBrowsing Family responses captured on 2026-10-27.
    static let cleanBrowsing = StubResolver(answers: [
        "www.apple.com": .resolved(addresses: ["23.1.2.3"], canonicalName: "e6858.dsce9.akamaiedge.net"),
        "login.microsoftonline.com": .resolved(addresses: ["40.126.24.81"], canonicalName: "bno-lb.current.a.prd.aadg.akadns.net"),
        "pornhub.com": .nonexistentDomain,
        "xvideos.com": .nonexistentDomain,
        "duckduckgo.com": .resolved(addresses: ["52.149.247.1"], canonicalName: "safe.duckduckgo.com"),
        "www.google.com": .resolved(addresses: ["216.239.38.120"], canonicalName: nil),
    ])

    static let unfiltered = StubResolver(answers: [
        "www.apple.com": .resolved(addresses: ["23.1.2.3"], canonicalName: nil),
        "login.microsoftonline.com": .resolved(addresses: ["40.126.24.81"], canonicalName: nil),
        "pornhub.com": .resolved(addresses: ["66.254.114.41"], canonicalName: nil),
        "xvideos.com": .resolved(addresses: ["185.88.181.2"], canonicalName: nil),
        "duckduckgo.com": .resolved(addresses: ["52.149.246.39"], canonicalName: nil),
        "www.google.com": .resolved(addresses: ["142.250.1.1"], canonicalName: nil),
    ])
}

final class FilterVerifierTests: XCTestCase {
    func testCleanBrowsingAnswersAreVerified() async {
        let report = await FilterVerifier(resolver: StubResolver.cleanBrowsing).run(networkDescription: "Wi-Fi")
        XCTAssertEqual(report.verdict, .verified)
        XCTAssertTrue(report.results.allSatisfy { $0.passed == true })
    }

    func testUnfilteredResolverIsNotFiltering() async {
        let report = await FilterVerifier(resolver: StubResolver.unfiltered).run(networkDescription: "Cellular")
        XCTAssertEqual(report.verdict, .notFiltering)
        XCTAssertTrue(report.explanation.contains("NOT"))
    }

    func testOfflineIsInconclusiveNotFailure() async {
        let offline = StubResolver(answers: [:])
        let report = await FilterVerifier(resolver: offline).run(networkDescription: "No connection")
        XCTAssertEqual(report.verdict, .inconclusive)
    }

    /// iOS can report NXDOMAIN for *everything* when offline; the control probe
    /// must stop that being mistaken for "adult domains blocked".
    func testAllNXDOMAINIsNotTreatedAsBlocking() async {
        var answers: [String: ResolutionOutcome] = [:]
        for probe in FilterProbe.defaultSet { answers[probe.host] = .nonexistentDomain }
        let report = await FilterVerifier(resolver: StubResolver(answers: answers)).run(networkDescription: "Wi-Fi")
        XCTAssertEqual(report.verdict, .inconclusive)
    }

    func testBlockingWithoutSafeSearchIsPartial() async {
        var resolver = StubResolver.cleanBrowsing
        resolver.answers["duckduckgo.com"] = .resolved(addresses: ["52.149.246.39"], canonicalName: nil)
        resolver.answers["www.google.com"] = .resolved(addresses: ["142.250.1.1"], canonicalName: nil)
        let report = await FilterVerifier(resolver: resolver).run(networkDescription: "Wi-Fi")
        XCTAssertEqual(report.verdict, .blockingObserved)
    }

    func testOneAdultDomainResolvingIsDecisive() async {
        var resolver = StubResolver.cleanBrowsing
        resolver.answers["xvideos.com"] = .resolved(addresses: ["185.88.181.2"], canonicalName: nil)
        let report = await FilterVerifier(resolver: resolver).run(networkDescription: "Wi-Fi")
        XCTAssertEqual(report.verdict, .notFiltering)
    }

    func testPartialAdultTimeoutIsInconclusive() async {
        var resolver = StubResolver.cleanBrowsing
        resolver.answers["xvideos.com"] = .failed(reason: "timed out")
        let report = await FilterVerifier(resolver: resolver).run(networkDescription: "Wi-Fi")
        XCTAssertEqual(report.verdict, .inconclusive)
    }

    func testSinkholeAddressCountsAsBlocked() {
        let probe = FilterProbe(id: "x", host: "x", purpose: "", kind: .mustBeBlocked)
        XCTAssertEqual(probe.evaluate(.resolved(addresses: ["0.0.0.0"], canonicalName: nil)), true)
        XCTAssertEqual(probe.evaluate(.resolved(addresses: ["0.0.0.0", "1.2.3.4"], canonicalName: nil)), false)
    }

    func testSafeSearchMatchesIPv6Address() {
        let google = FilterProbe.defaultSet.first { $0.id == "safesearch-google" }!
        XCTAssertEqual(google.evaluate(.resolved(addresses: ["2001:4860:4802:32::78"], canonicalName: nil)), true)
    }

    func testReportDoesNotStoreAddresses() async throws {
        let report = await FilterVerifier(resolver: StubResolver.unfiltered).run(networkDescription: "Wi-Fi")
        let json = String(decoding: try JSONEncoder().encode(report), as: UTF8.self)
        XCTAssertFalse(json.contains("66.254.114.41"))
    }
}

final class EncryptedDNSProviderTests: XCTestCase {
    func testCleanBrowsingFamilyIsValid() throws {
        try EncryptedDNSProvider.cleanBrowsingFamily.validate()
        XCTAssertEqual(EncryptedDNSProvider.cleanBrowsingFamily.dohURL.absoluteString, "https://doh.cleanbrowsing.org/doh/family-filter/")
    }

    func testRejectsInsecureAndBadAddresses() {
        let p = EncryptedDNSProvider.cleanBrowsingFamily
        let http = EncryptedDNSProvider(id: "x", displayName: "x", dohURL: URL(string: "http://example.com/dns")!, serverAddresses: p.serverAddresses, dotHostname: "", documentationURL: p.documentationURL)
        XCTAssertThrowsError(try http.validate())
        let bad = EncryptedDNSProvider(id: "x", displayName: "x", dohURL: p.dohURL, serverAddresses: ["999.1.1.1"], dotHostname: "", documentationURL: p.documentationURL)
        XCTAssertThrowsError(try bad.validate()) { XCTAssertEqual($0 as? EncryptedDNSProvider.ValidationError, .invalidServerAddress("999.1.1.1")) }
        let none = EncryptedDNSProvider(id: "x", displayName: "x", dohURL: p.dohURL, serverAddresses: [], dotHostname: "", documentationURL: p.documentationURL)
        XCTAssertThrowsError(try none.validate())
    }

    func testURLMatchingIgnoresTrailingSlashAndCase() {
        let p = EncryptedDNSProvider.cleanBrowsingFamily
        XCTAssertTrue(p.matches(serverURL: URL(string: "https://DOH.cleanbrowsing.org/doh/family-filter")))
        XCTAssertFalse(p.matches(serverURL: URL(string: "https://doh.cleanbrowsing.org/doh/adult-filter/")))
        XCTAssertFalse(p.matches(serverURL: nil))
    }
}

/// Exercises the real getaddrinfo path. This container's resolver is not
/// filtered, so these only check mechanics, not filtering.
final class SystemHostResolverTests: XCTestCase {
    func testInvalidTLDReportsNonexistent() async {
        let outcome = await SystemHostResolver(timeout: 10).resolve("does-not-exist.invalid")
        switch outcome {
        case .nonexistentDomain, .failed: break // .failed if the sandbox has no DNS at all
        case .resolved: XCTFail("RFC 6761 .invalid must never resolve")
        }
    }

    func testLocalhostResolves() async {
        let outcome = await SystemHostResolver(timeout: 10).resolve("localhost")
        guard case .resolved(let addresses, _) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertFalse(addresses.isEmpty)
    }
}
