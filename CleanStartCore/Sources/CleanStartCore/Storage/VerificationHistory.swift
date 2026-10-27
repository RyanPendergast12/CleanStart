import Foundation

/// The most recent verification reports, capped so storage stays tiny.
/// Only the fixed probe list is recorded — never the user's own browsing.
public struct VerificationHistory: Codable, Equatable, Sendable {
    public private(set) var reports: [FilterVerificationReport]
    public static let limit = 30

    public init(reports: [FilterVerificationReport] = []) {
        self.reports = Array(reports.suffix(Self.limit))
    }

    public var latest: FilterVerificationReport? { reports.last }

    public var lastSuccessful: FilterVerificationReport? {
        reports.last { $0.verdict == .verified || $0.verdict == .blockingObserved }
    }

    /// The verdict before the latest one, used to detect regressions.
    public var previousVerdict: FilterVerdict? {
        reports.count >= 2 ? reports[reports.count - 2].verdict : nil
    }

    public mutating func append(_ report: FilterVerificationReport) {
        reports.append(report)
        if reports.count > Self.limit { reports.removeFirst(reports.count - Self.limit) }
    }

    public mutating func clear() { reports.removeAll() }
}

/// User preferences. All local.
public struct Preferences: Codable, Equatable, Sendable {
    public var dailyReminderEnabled: Bool
    public var dailyReminderHour: Int
    public var dailyReminderMinute: Int
    public var protectionAlertsEnabled: Bool
    public var verifyOnOpen: Bool
    public var highContrastStatus: Bool
    public var hasCompletedOnboarding: Bool

    public init(dailyReminderEnabled: Bool = false, dailyReminderHour: Int = 21, dailyReminderMinute: Int = 0, protectionAlertsEnabled: Bool = true, verifyOnOpen: Bool = true, highContrastStatus: Bool = false, hasCompletedOnboarding: Bool = false) {
        self.dailyReminderEnabled = dailyReminderEnabled
        self.dailyReminderHour = dailyReminderHour
        self.dailyReminderMinute = dailyReminderMinute
        self.protectionAlertsEnabled = protectionAlertsEnabled
        self.verifyOnOpen = verifyOnOpen
        self.highContrastStatus = highContrastStatus
        self.hasCompletedOnboarding = hasCompletedOnboarding
    }
}
