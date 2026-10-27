import CleanStartCore
import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings

/// Applies Screen Time restrictions with Managed Settings and schedules them
/// with Device Activity.
@MainActor
final class RestrictionService: ObservableObject {
    @Published private(set) var configuration: RestrictionConfiguration
    @Published private(set) var lastError: String?

    private let alwaysStore = ManagedSettingsStore(named: .cleanStartAlways)
    private let scheduledStore = ManagedSettingsStore(named: .cleanStartScheduled)
    private let center = DeviceActivityCenter()

    init() {
        configuration = RestrictionStorage.load() ?? RestrictionConfiguration()
    }

    var shieldsActive: Bool {
        configuration.hasSelection && (configuration.mode == .always || isMonitoringSchedule)
    }

    var isMonitoringSchedule: Bool {
        center.activities.contains(.cleanStartSchedule)
    }

    /// Changes in `proposed` that weaken protection and therefore go through the
    /// accountability delay. Anything not listed is a strengthening change.
    func weakeningChanges(to proposed: RestrictionConfiguration) -> [ProtectedChange] {
        let current = configuration
        var changes: [ProtectedChange] = []
        if !current.isCovered(by: proposed) || (current.mode == .always && proposed.mode == .scheduled && current.hasSelection) {
            changes.append(.clearAppShields)
        }
        if current.mode == .scheduled, proposed.mode == .scheduled,
           current.scheduleStart != proposed.scheduleStart || current.scheduleEnd != proposed.scheduleEnd {
            changes.append(.stopSchedule)
        }
        if current.webContentFilterEnabled && !proposed.webContentFilterEnabled {
            changes.append(.disableWebContentFilter)
        }
        if current.denyAppRemoval && !proposed.denyAppRemoval {
            changes.append(.disableAppRemovalProtection)
        }
        return changes
    }

    /// Applies a configuration. Callers must have cleared accountability first.
    func apply(_ proposed: RestrictionConfiguration) {
        lastError = nil
        switch proposed.mode {
        case .always:
            center.stopMonitoring([.cleanStartSchedule])
            ShieldApplier.clearShields(in: scheduledStore)
            ShieldApplier.applyShields(proposed.selection, to: alwaysStore)
        case .scheduled:
            ShieldApplier.clearShields(in: alwaysStore)
            do {
                try startSchedule(for: proposed)
            } catch {
                lastError = Self.describe(error)
                return
            }
        }

        alwaysStore.webContent.blockedByFilter = proposed.webContentFilterEnabled ? .auto() : nil
        alwaysStore.application.denyAppRemoval = proposed.denyAppRemoval ? true : nil

        configuration = proposed
        RestrictionStorage.save(proposed)
    }

    /// Removes every restriction CleanStart set. Used for rollback.
    func removeAll() {
        center.stopMonitoring()
        alwaysStore.clearAllSettings()
        scheduledStore.clearAllSettings()
        configuration = RestrictionConfiguration()
        RestrictionStorage.clear()
    }

    private func startSchedule(for proposed: RestrictionConfiguration) throws {
        center.stopMonitoring([.cleanStartSchedule])
        let schedule = DeviceActivitySchedule(
            intervalStart: proposed.scheduleStart,
            intervalEnd: proposed.scheduleEnd,
            repeats: true
        )
        // Save first so the extension reads the new selection when it starts.
        RestrictionStorage.save(proposed)
        try center.startMonitoring(.cleanStartSchedule, during: schedule)
        // If we're already inside the window, shield immediately rather than
        // relying on the extension's start callback.
        if Self.isWithin(start: proposed.scheduleStart, end: proposed.scheduleEnd, at: Date()) {
            ShieldApplier.applyShields(proposed.selection, to: scheduledStore)
        } else {
            ShieldApplier.clearShields(in: scheduledStore)
        }
    }

    static func isWithin(start: DateComponents, end: DateComponents, at date: Date, calendar: Calendar = .current) -> Bool {
        let now = calendar.dateComponents([.hour, .minute], from: date)
        let minutes = (now.hour ?? 0) * 60 + (now.minute ?? 0)
        let s = (start.hour ?? 0) * 60 + (start.minute ?? 0)
        let e = (end.hour ?? 0) * 60 + (end.minute ?? 0)
        return s <= e ? (minutes >= s && minutes < e) : (minutes >= s || minutes < e)
    }

    private static func describe(_ error: Error) -> String {
        if let monitoringError = error as? DeviceActivityCenter.MonitoringError {
            switch monitoringError {
            case .intervalTooShort: return "The schedule must be at least 15 minutes long."
            case .intervalTooLong: return "The schedule is longer than iOS allows."
            case .invalidDateComponents: return "The schedule times are invalid."
            case .excessiveActivities: return "Too many Screen Time schedules are active."
            case .unauthorized: return "Screen Time access isn't authorized."
            @unknown default: return monitoringError.localizedDescription
            }
        }
        return error.localizedDescription
    }
}
