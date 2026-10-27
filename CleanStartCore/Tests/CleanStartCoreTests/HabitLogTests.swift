import XCTest
@testable import CleanStartCore

final class HabitLogTests: XCTestCase {
    var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }()
    let today = DayStamp(year: 2026, month: 11, day: 3)

    func day(_ offset: Int) -> DayStamp { today.adding(days: offset, calendar: calendar) }

    func log(_ entries: [(Int, CheckInStatus)]) throws -> HabitLog {
        var log = HabitLog()
        for (offset, status) in entries {
            try log.record(status, for: day(offset), today: day(offset), calendar: calendar)
        }
        return log
    }

    func testStreakCountsThroughYesterdayBeforeTodayCheckIn() throws {
        let l = try log([(-3, .clean), (-2, .clean), (-1, .clean)])
        XCTAssertEqual(l.currentStreak(today: today, calendar: calendar), 3)
    }

    func testSlipResetsStreakButKeepsTotals() throws {
        let l = try log([(-4, .clean), (-3, .clean), (-2, .slipped), (-1, .clean), (0, .clean)])
        XCTAssertEqual(l.currentStreak(today: today, calendar: calendar), 2)
        XCTAssertEqual(l.bestStreak(calendar: calendar), 2)
        XCTAssertEqual(l.totalCleanDays, 4)
    }

    func testGapBreaksStreak() throws {
        let l = try log([(-5, .clean), (-4, .clean), (-3, .clean), (-1, .clean)])
        XCTAssertEqual(l.currentStreak(today: today, calendar: calendar), 1)
        XCTAssertEqual(l.bestStreak(calendar: calendar), 3)
    }

    func testRecordingAgainReplacesEntry() throws {
        var l = try log([(0, .clean)])
        try l.record(.slipped, for: today, today: today, note: "  rough evening  ", calendar: calendar)
        XCTAssertEqual(l.checkIns.count, 1)
        XCTAssertEqual(l.checkIn(for: today)?.status, .slipped)
        XCTAssertEqual(l.checkIn(for: today)?.note, "rough evening")
    }

    func testBackfillLimits() {
        var l = HabitLog()
        XCTAssertNoThrow(try l.record(.clean, for: day(-2), today: today, calendar: calendar))
        XCTAssertThrowsError(try l.record(.clean, for: day(-3), today: today, calendar: calendar))
        XCTAssertThrowsError(try l.record(.clean, for: day(1), today: today, calendar: calendar))
    }

    func testMonthBoundary() throws {
        // Oct 31 -> Nov 1 -> Nov 2 -> Nov 3, across the US DST change (Nov 1, 2026).
        let l = try log([(-3, .clean), (-2, .clean), (-1, .clean), (0, .clean)])
        XCTAssertEqual(day(-3), DayStamp(year: 2026, month: 10, day: 31))
        XCTAssertEqual(l.currentStreak(today: today, calendar: calendar), 4)
    }

    func testGoalProgress() throws {
        let l = try log([(-2, .clean), (-1, .clean), (0, .clean)])
        let goal = HabitGoal(title: "Week", targetDays: 7)
        XCTAssertEqual(l.progress(toward: goal, today: today, calendar: calendar), 3.0 / 7.0, accuracy: 0.0001)
        XCTAssertEqual(HabitGoal(title: "bad", targetDays: 0).targetDays, 1)
    }

    func testRecentSummary() throws {
        let l = try log([(-1, .clean), (0, .slipped)])
        let summary = l.recentSummary(today: today, days: 3, calendar: calendar)
        XCTAssertEqual(summary.map(\.day), [day(-2), day(-1), day(0)])
        XCTAssertEqual(summary.map(\.status), [nil, .clean, .slipped])
    }

    func testEncouragementIsNonPunitiveAfterSlip() throws {
        let l = try log([(0, .slipped)])
        let message = Encouragement.message(for: l, today: today, calendar: calendar)
        for harsh in ["fail", "shame", "ruined", "lost everything"] {
            XCTAssertFalse(message.lowercased().contains(harsh), message)
        }
    }

    func testMilestoneMessage() throws {
        let l = try log((-6...0).map { ($0, .clean) })
        XCTAssertTrue(Encouragement.message(for: l, today: today, calendar: calendar).contains("week"))
    }

    func testDeleteAll() throws {
        var l = try log([(0, .clean)])
        l.deleteAll()
        XCTAssertTrue(l.checkIns.isEmpty)
    }
}

final class StorageTests: XCTestCase {
    func testSaveLoadAndDeleteAll() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cleanstart-tests-\(UUID().uuidString)")
        let store = LocalStore(directory: dir)
        var log = HabitLog()
        try log.record(.clean, for: DayStamp(year: 2026, month: 1, day: 1), today: DayStamp(year: 2026, month: 1, day: 1))
        try store.save(log, key: StoreKey.habitLog)
        XCTAssertEqual(store.load(HabitLog.self, key: StoreKey.habitLog), log)
        XCTAssertEqual(store.storedKeys(), [StoreKey.habitLog])
        try store.removeAll()
        XCTAssertNil(store.load(HabitLog.self, key: StoreKey.habitLog))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path))
    }

    func testVerificationHistoryCapAndRegression() {
        var history = VerificationHistory()
        for i in 0..<(VerificationHistory.limit + 5) {
            history.append(FilterVerificationReport(date: Date(timeIntervalSince1970: Double(i)), verdict: .verified, results: [], networkDescription: "Wi-Fi"))
        }
        history.append(FilterVerificationReport(date: Date(), verdict: .notFiltering, results: [], networkDescription: "Wi-Fi"))
        XCTAssertEqual(history.reports.count, VerificationHistory.limit)
        XCTAssertEqual(history.previousVerdict, .verified)
        XCTAssertEqual(history.latest?.verdict, .notFiltering)
        XCTAssertEqual(history.lastSuccessful?.verdict, .verified)
    }

    func testWorkChecklist() {
        var list = WorkChecklist()
        for item in WorkChecklist.items { list.set(item.id, done: true) }
        XCTAssertTrue(list.allDone)
        list.set("teams-signin", done: false)
        XCTAssertFalse(list.allDone)
    }

    func testDiagnosticsReportHasNoAddresses() {
        let report = FilterVerificationReport(date: Date(), verdict: .verified, results: [
            ProbeResult(probeID: "adult-1", host: "pornhub.com", purpose: "", outcomeSummary: ResolutionOutcome.nonexistentDomain.summary, passed: true, durationMilliseconds: 12),
        ], networkDescription: "Cellular")
        let text = DiagnosticsReport(appVersion: "1.0", osVersion: "26.0", dnsConfiguration: .enabled(matchesExpected: true), screenTime: .approved, networkDescription: "Cellular", vpnLikelyActive: false, latestVerification: report, lastError: nil).text()
        XCTAssertTrue(text.contains("[PASS] adult-1"))
        XCTAssertTrue(text.contains("Enabled"))
    }
}
