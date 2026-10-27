import XCTest
@testable import CleanStartCore

final class ProtectionAssessmentTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func report(_ verdict: FilterVerdict, ageHours: Double = 0) -> FilterVerificationReport {
        FilterVerificationReport(date: now.addingTimeInterval(-ageHours * 3600), verdict: verdict, results: [], networkDescription: "Wi-Fi")
    }

    func snapshot(dns: DNSConfigurationState = .enabled(matchesExpected: true), verification: FilterVerificationReport?, previous: FilterVerdict? = nil, screenTime: ScreenTimeAuthorizationState = .approved, shields: Bool = true, vpn: Bool = false) -> ProtectionSnapshot {
        ProtectionSnapshot(dnsConfiguration: dns, latestVerification: verification, previousVerdict: previous, screenTime: screenTime, shieldsActive: shields, vpnLikelyActive: vpn, now: now)
    }

    func testEnabledAndVerifiedIsProtected() {
        let a = ProtectionAssessment.assess(snapshot(verification: report(.verified)))
        XCTAssertEqual(a.level, .protected)
        XCTAssertTrue(a.issues.isEmpty)
    }

    /// Configuration status alone must never be reported as protection.
    func testEnabledButNeverVerifiedIsNotProtected() {
        let a = ProtectionAssessment.assess(snapshot(verification: nil))
        XCTAssertEqual(a.level, .attention)
        XCTAssertTrue(a.issues.contains { $0.id == "verify-never" })
    }

    func testStaleVerification() {
        let a = ProtectionAssessment.assess(snapshot(verification: report(.verified, ageHours: 30)))
        XCTAssertEqual(a.level, .attention)
        XCTAssertTrue(a.issues.contains { $0.id == "verify-stale" })
    }

    func testNotFilteringIsUnprotectedEvenIfConfigured() {
        let a = ProtectionAssessment.assess(snapshot(verification: report(.notFiltering)))
        XCTAssertEqual(a.level, .unprotected)
    }

    func testRegressionIsCalledOut() {
        let a = ProtectionAssessment.assess(snapshot(verification: report(.notFiltering), previous: .verified))
        XCTAssertEqual(a.issues.first?.title, "Protection changed since the last check")
    }

    func testNotInstalledButVerifiedViaProfile() {
        let a = ProtectionAssessment.assess(snapshot(dns: .notInstalled, verification: report(.verified)))
        XCTAssertEqual(a.level, .protected)
        XCTAssertTrue(a.issues.contains { $0.id == "dns-other" && $0.severity == .info })
    }

    func testInstalledNotEnabledIsCritical() {
        let a = ProtectionAssessment.assess(snapshot(dns: .installedNotEnabled, verification: nil))
        XCTAssertEqual(a.level, .unprotected)
        XCTAssertEqual(a.issues.first?.id, "dns-disabled")
    }

    func testVPNWarning() {
        let a = ProtectionAssessment.assess(snapshot(verification: report(.verified), vpn: true))
        XCTAssertEqual(a.level, .attention)
        XCTAssertTrue(a.issues.contains { $0.id == "vpn-active" })
    }

    func testIssuesSortedBySeverity() {
        let a = ProtectionAssessment.assess(snapshot(dns: .notInstalled, verification: nil, screenTime: .notDetermined))
        let severities = a.issues.map(\.severity)
        XCTAssertEqual(severities, severities.sorted(by: >))
    }
}
