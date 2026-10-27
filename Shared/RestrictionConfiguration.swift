import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings

/// Screen Time restrictions chosen by the user. Shared with the Device Activity
/// monitor extension through the App Group so scheduled shields can be applied
/// while CleanStart is not running.
///
/// Apps, categories and websites are opaque Apple tokens: CleanStart cannot see
/// which apps they are, and they cannot be read by anyone else.
struct RestrictionConfiguration: Codable, Equatable {
    enum Mode: String, Codable, CaseIterable, Identifiable {
        case always
        case scheduled
        var id: String { rawValue }
        var title: String { self == .always ? "Always" : "On a schedule" }
    }

    var selection = FamilyActivitySelection()
    var mode: Mode = .always
    var scheduleStart = DateComponents(hour: 21, minute: 0)
    var scheduleEnd = DateComponents(hour: 7, minute: 0)
    /// Apple's built-in adult-website filter (Screen Time "Limit Adult Websites").
    var webContentFilterEnabled = false
    /// Prevents deleting *any* app while enabled (Screen Time "Deleting Apps").
    var denyAppRemoval = false

    var hasSelection: Bool {
        !selection.applicationTokens.isEmpty || !selection.categoryTokens.isEmpty || !selection.webDomainTokens.isEmpty
    }

    var selectionSummary: String {
        let apps = selection.applicationTokens.count
        let categories = selection.categoryTokens.count
        let sites = selection.webDomainTokens.count
        return "\(apps) app\(apps == 1 ? "" : "s"), \(categories) categor\(categories == 1 ? "y" : "ies"), \(sites) website\(sites == 1 ? "" : "s")"
    }

    /// True when `other` shields everything this configuration shields.
    func isCovered(by other: RestrictionConfiguration) -> Bool {
        selection.applicationTokens.isSubset(of: other.selection.applicationTokens)
            && selection.categoryTokens.isSubset(of: other.selection.categoryTokens)
            && selection.webDomainTokens.isSubset(of: other.selection.webDomainTokens)
    }
}

enum RestrictionStorage {
    private static let key = "restriction-configuration"

    static func load() -> RestrictionConfiguration? {
        guard let data = AppGroup.defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(RestrictionConfiguration.self, from: data)
    }

    static func save(_ configuration: RestrictionConfiguration) {
        if let data = try? JSONEncoder().encode(configuration) {
            AppGroup.defaults.set(data, forKey: key)
        }
    }

    static func clear() {
        AppGroup.defaults.removeObject(forKey: key)
    }
}

extension ManagedSettingsStore.Name {
    /// Always-on shields, the web content filter and app-removal protection.
    static let cleanStartAlways = Self("cleanstart.always")
    /// Shields applied only during the schedule by the monitor extension.
    static let cleanStartScheduled = Self("cleanstart.scheduled")
}

extension DeviceActivityName {
    static let cleanStartSchedule = Self("cleanstart.schedule")
}

enum ShieldApplier {
    static func applyShields(_ selection: FamilyActivitySelection, to store: ManagedSettingsStore) {
        store.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        store.shield.applicationCategories = selection.categoryTokens.isEmpty
            ? nil
            : ShieldSettings.ActivityCategoryPolicy.specific(selection.categoryTokens)
        store.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens
        store.shield.webDomainCategories = selection.categoryTokens.isEmpty
            ? nil
            : ShieldSettings.ActivityCategoryPolicy.specific(selection.categoryTokens)
    }

    static func clearShields(in store: ManagedSettingsStore) {
        store.shield.applications = nil
        store.shield.applicationCategories = nil
        store.shield.webDomains = nil
        store.shield.webDomainCategories = nil
    }
}
