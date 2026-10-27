import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings

/// Applies and removes scheduled shields. iOS launches this extension at the
/// start and end of the schedule even when CleanStart itself isn't running.
final class CleanStartActivityMonitor: DeviceActivityMonitor {
    private let scheduledStore = ManagedSettingsStore(named: .cleanStartScheduled)

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        guard activity == .cleanStartSchedule,
              let configuration = RestrictionStorage.load(),
              configuration.mode == .scheduled else { return }
        ShieldApplier.applyShields(configuration.selection, to: scheduledStore)
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        guard activity == .cleanStartSchedule else { return }
        ShieldApplier.clearShields(in: scheduledStore)
    }
}
