import XCTest
@testable import CleanStartCore

final class AccountabilityLedgerTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func testWeakeningChangeWaitsForDelay() throws {
        var ledger = AccountabilityLedger(delay: .oneHour)
        try ledger.request(.removeDNSConfiguration, now: t0)
        XCTAssertThrowsError(try ledger.consume(.removeDNSConfiguration, now: t0.addingTimeInterval(1800))) {
            guard case .stillWaiting = $0 as? AccountabilityLedger.LedgerError else { return XCTFail("\($0)") }
        }
        XCTAssertNoThrow(try ledger.consume(.removeDNSConfiguration, now: t0.addingTimeInterval(3600)))
        XCTAssertNil(ledger.pendingRequest(for: .removeDNSConfiguration))
    }

    func testCannotConsumeWithoutRequest() {
        var ledger = AccountabilityLedger(delay: .oneHour)
        XCTAssertThrowsError(try ledger.consume(.clearAppShields, now: t0)) {
            XCTAssertEqual($0 as? AccountabilityLedger.LedgerError, .notRequested)
        }
    }

    func testNoDelayAllowsDirectChange() {
        var ledger = AccountabilityLedger(delay: .off)
        XCTAssertNoThrow(try ledger.consume(.clearAppShields, now: t0))
    }

    func testRepeatRequestKeepsOriginalClock() throws {
        var ledger = AccountabilityLedger(delay: .oneHour)
        let first = try ledger.request(.clearAppShields, now: t0)
        let second = try ledger.request(.clearAppShields, now: t0.addingTimeInterval(1000))
        XCTAssertEqual(first.id, second.id)
    }

    func testApprovalExpires() throws {
        var ledger = AccountabilityLedger(delay: .fifteenMinutes)
        try ledger.request(.clearAppShields, now: t0)
        let late = t0.addingTimeInterval(900 + AccountabilityLedger.readyWindow + 1)
        XCTAssertThrowsError(try ledger.consume(.clearAppShields, now: late)) {
            XCTAssertEqual($0 as? AccountabilityLedger.LedgerError, .expired)
        }
    }

    func testIncreasingDelayIsImmediateButReducingWaits() throws {
        var ledger = AccountabilityLedger(delay: .oneHour)
        XCTAssertTrue(ledger.increaseDelay(to: .oneDay))
        XCTAssertEqual(ledger.delay, .oneDay)
        XCTAssertFalse(ledger.increaseDelay(to: .off))
        XCTAssertEqual(ledger.delay, .oneDay)

        try ledger.request(.reduceAccountabilityDelay, newDelay: .off, now: t0)
        XCTAssertThrowsError(try ledger.consume(.reduceAccountabilityDelay, now: t0.addingTimeInterval(3600)))
        try ledger.consume(.reduceAccountabilityDelay, now: t0.addingTimeInterval(86400))
        XCTAssertEqual(ledger.delay, .off)
    }

    func testReductionRequestMustActuallyReduce() {
        var ledger = AccountabilityLedger(delay: .oneHour)
        XCTAssertThrowsError(try ledger.request(.reduceAccountabilityDelay, newDelay: .oneDay, now: t0))
        XCTAssertThrowsError(try ledger.request(.reduceAccountabilityDelay, newDelay: nil, now: t0))
    }

    /// With no delay, reducing is meaningless and must not bypass the request flow.
    func testReduceDelayAlwaysNeedsRequest() {
        var ledger = AccountabilityLedger(delay: .off)
        XCTAssertThrowsError(try ledger.consume(.reduceAccountabilityDelay, now: t0))
    }

    func testCodableRoundTrip() throws {
        var ledger = AccountabilityLedger(delay: .oneDay)
        try ledger.request(.disableWebContentFilter, now: t0)
        let data = try JSONEncoder().encode(ledger)
        XCTAssertEqual(try JSONDecoder().decode(AccountabilityLedger.self, from: data), ledger)
    }
}
