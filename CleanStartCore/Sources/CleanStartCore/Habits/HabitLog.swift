import Foundation

/// A calendar day independent of time zone shifts after it was recorded.
public struct DayStamp: Codable, Hashable, Comparable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public init(_ date: Date, calendar: Calendar = .current) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year!, month: c.month!, day: c.day!)
    }

    public func date(in calendar: Calendar = .current) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    public func adding(days: Int, calendar: Calendar = .current) -> DayStamp {
        DayStamp(calendar.date(byAdding: .day, value: days, to: date(in: calendar))!, calendar: calendar)
    }

    public static func < (lhs: DayStamp, rhs: DayStamp) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    public var description: String { String(format: "%04d-%02d-%02d", year, month, day) }
}

public enum CheckInStatus: String, Codable, Sendable, CaseIterable {
    /// "I stayed porn-free today."
    case clean
    /// "I slipped today." Recorded honestly, without judgement.
    case slipped
}

public struct CheckIn: Codable, Equatable, Sendable {
    public let day: DayStamp
    public var status: CheckInStatus
    /// Optional private reflection; never leaves the device.
    public var note: String?
    public var recordedAt: Date
}

public struct HabitGoal: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var title: String
    public var targetDays: Int

    public init(id: UUID = UUID(), title: String, targetDays: Int) {
        self.id = id
        self.title = title
        self.targetDays = max(1, targetDays)
    }

    public static let suggestions: [HabitGoal] = [
        HabitGoal(title: "First week", targetDays: 7),
        HabitGoal(title: "One month", targetDays: 30),
        HabitGoal(title: "90-day reset", targetDays: 90),
        HabitGoal(title: "A clean year at 25", targetDays: 365),
    ]
}

/// Local-only habit history and the derived statistics.
public struct HabitLog: Codable, Equatable, Sendable {
    public private(set) var checkIns: [CheckIn]
    public var goals: [HabitGoal]
    public var streakTrackingEnabled: Bool

    /// Check-ins may be recorded for today and this many previous days, so a
    /// forgotten evening can be filled in honestly the next morning.
    public static let backfillDays = 2

    public init(checkIns: [CheckIn] = [], goals: [HabitGoal] = [HabitGoal.suggestions[0]], streakTrackingEnabled: Bool = true) {
        self.checkIns = checkIns.sorted { $0.day < $1.day }
        self.goals = goals
        self.streakTrackingEnabled = streakTrackingEnabled
    }

    public enum RecordError: Error, Equatable {
        case futureDay
        case tooFarInPast
    }

    public mutating func record(_ status: CheckInStatus, for day: DayStamp, today: DayStamp, note: String? = nil, now: Date = Date(), calendar: Calendar = .current) throws {
        guard day <= today else { throw RecordError.futureDay }
        guard day >= today.adding(days: -Self.backfillDays, calendar: calendar) else { throw RecordError.tooFarInPast }
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        let entry = CheckIn(day: day, status: status, note: (trimmed?.isEmpty ?? true) ? nil : trimmed, recordedAt: now)
        if let index = checkIns.firstIndex(where: { $0.day == day }) {
            checkIns[index] = entry
        } else {
            checkIns.append(entry)
            checkIns.sort { $0.day < $1.day }
        }
    }

    public func checkIn(for day: DayStamp) -> CheckIn? {
        checkIns.first { $0.day == day }
    }

    public mutating func removeCheckIn(for day: DayStamp) {
        checkIns.removeAll { $0.day == day }
    }

    public mutating func deleteAll() {
        checkIns.removeAll()
    }

    /// Consecutive clean days ending today, or ending yesterday if today has
    /// not been checked in yet (so the streak doesn't "break" every morning).
    public func currentStreak(today: DayStamp, calendar: Calendar = .current) -> Int {
        let byDay = Dictionary(checkIns.map { ($0.day, $0.status) }, uniquingKeysWith: { _, last in last })
        var cursor = today
        if byDay[today] == nil { cursor = today.adding(days: -1, calendar: calendar) }
        var count = 0
        while byDay[cursor] == .clean {
            count += 1
            cursor = cursor.adding(days: -1, calendar: calendar)
        }
        return count
    }

    public func bestStreak(calendar: Calendar = .current) -> Int {
        var best = 0
        var run = 0
        var previous: DayStamp?
        for entry in checkIns {
            if entry.status == .clean {
                if let previous, previous.adding(days: 1, calendar: calendar) == entry.day {
                    run += 1
                } else {
                    run = 1
                }
                best = max(best, run)
            } else {
                run = 0
            }
            previous = entry.day
        }
        return best
    }

    public var totalCleanDays: Int { checkIns.filter { $0.status == .clean }.count }

    /// Days in the last `days` (inclusive of today) and how many were clean.
    public func recentSummary(today: DayStamp, days: Int = 7, calendar: Calendar = .current) -> [(day: DayStamp, status: CheckInStatus?)] {
        (0..<days).reversed().map { offset in
            let day = today.adding(days: -offset, calendar: calendar)
            return (day, checkIn(for: day)?.status)
        }
    }

    public func progress(toward goal: HabitGoal, today: DayStamp, calendar: Calendar = .current) -> Double {
        min(1, Double(currentStreak(today: today, calendar: calendar)) / Double(goal.targetDays))
    }
}
