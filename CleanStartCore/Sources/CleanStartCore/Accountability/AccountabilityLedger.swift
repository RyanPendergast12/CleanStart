import Foundation

/// A change that weakens protection. Strengthening changes never wait.
///
/// The delay is enforced only inside CleanStart. It is a voluntary
/// "cooling-off" measure: the device owner can always remove the DNS setting in
/// iOS Settings or revoke Screen Time access without waiting.
public enum ProtectedChange: String, Codable, CaseIterable, Sendable {
    case removeDNSConfiguration
    case clearAppShields
    case disableWebContentFilter
    case disableAppRemovalProtection
    case stopSchedule
    case reduceAccountabilityDelay

    public var title: String {
        switch self {
        case .removeDNSConfiguration: return "Remove DNS filtering"
        case .clearAppShields: return "Remove app shields"
        case .disableWebContentFilter: return "Turn off Apple's adult-website filter"
        case .disableAppRemovalProtection: return "Allow app deletion again"
        case .stopSchedule: return "Stop the restriction schedule"
        case .reduceAccountabilityDelay: return "Shorten the accountability delay"
        }
    }
}

public enum AccountabilityDelay: Int, Codable, CaseIterable, Sendable, Comparable {
    case off = 0
    case fifteenMinutes = 900
    case oneHour = 3600
    case oneDay = 86400
    case threeDays = 259200

    public var interval: TimeInterval { TimeInterval(rawValue) }

    public var title: String {
        switch self {
        case .off: return "No delay"
        case .fifteenMinutes: return "15 minutes"
        case .oneHour: return "1 hour"
        case .oneDay: return "24 hours"
        case .threeDays: return "3 days"
        }
    }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

public struct PendingChange: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let change: ProtectedChange
    public let requestedAt: Date
    public let availableAt: Date
    /// For `.reduceAccountabilityDelay`, the delay to switch to.
    public let newDelay: AccountabilityDelay?
}

public enum PendingChangeStatus: Equatable, Sendable {
    case waiting(remaining: TimeInterval)
    case ready
    case expired
}

/// Records requests to weaken protection and when they become allowed.
public struct AccountabilityLedger: Codable, Equatable, Sendable {
    public private(set) var delay: AccountabilityDelay
    public private(set) var pending: [PendingChange]

    /// Once ready, an approval must be used within this window, so an old
    /// request cannot be quietly kept "in the pocket" for later.
    public static let readyWindow: TimeInterval = 12 * 60 * 60

    public init(delay: AccountabilityDelay = .oneHour, pending: [PendingChange] = []) {
        self.delay = delay
        self.pending = pending
    }

    public enum LedgerError: Error, Equatable {
        case notRequested
        case stillWaiting(remaining: TimeInterval)
        case expired
        case notAReduction
    }

    /// Increasing the delay is a strengthening change and applies immediately.
    /// Returns `false` if the new value is shorter (use `request` instead).
    @discardableResult
    public mutating func increaseDelay(to newDelay: AccountabilityDelay) -> Bool {
        guard newDelay >= delay else { return false }
        delay = newDelay
        return true
    }

    @discardableResult
    public mutating func request(_ change: ProtectedChange, newDelay: AccountabilityDelay? = nil, now: Date) throws -> PendingChange {
        if change == .reduceAccountabilityDelay {
            guard let newDelay, newDelay < delay else { throw LedgerError.notAReduction }
        }
        // One outstanding request per change type; a repeat request keeps the
        // original clock rather than restarting it.
        if let existing = pending.first(where: { $0.change == change && status(of: $0, now: now) != .expired }) {
            return existing
        }
        pending.removeAll { $0.change == change }
        let item = PendingChange(id: UUID(), change: change, requestedAt: now,
                                 availableAt: now.addingTimeInterval(delay.interval), newDelay: newDelay)
        pending.append(item)
        return item
    }

    public func status(of item: PendingChange, now: Date) -> PendingChangeStatus {
        if now < item.availableAt { return .waiting(remaining: item.availableAt.timeIntervalSince(now)) }
        if now.timeIntervalSince(item.availableAt) > Self.readyWindow { return .expired }
        return .ready
    }

    public func pendingRequest(for change: ProtectedChange) -> PendingChange? {
        pending.first { $0.change == change }
    }

    public mutating func cancel(_ change: ProtectedChange) {
        pending.removeAll { $0.change == change }
    }

    /// Marks an approved request as used. Throws unless it is ready.
    /// For `.reduceAccountabilityDelay` the delay is updated here.
    public mutating func consume(_ change: ProtectedChange, now: Date) throws {
        guard let item = pendingRequest(for: change) else {
            // With no delay configured, weakening changes are allowed directly.
            if delay == .off, change != .reduceAccountabilityDelay { return }
            throw LedgerError.notRequested
        }
        switch status(of: item, now: now) {
        case .waiting(let remaining): throw LedgerError.stillWaiting(remaining: remaining)
        case .expired:
            pending.removeAll { $0.id == item.id }
            throw LedgerError.expired
        case .ready:
            pending.removeAll { $0.id == item.id }
            if change == .reduceAccountabilityDelay, let newDelay = item.newDelay { delay = newDelay }
        }
    }

    public mutating func pruneExpired(now: Date) {
        let window = Self.readyWindow
        pending.removeAll { now.timeIntervalSince($0.availableAt) > window }
    }
}
