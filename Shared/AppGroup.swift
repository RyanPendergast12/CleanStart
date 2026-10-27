import Foundation

/// The App Group shared by CleanStart and its Screen Time extensions.
/// The identifier comes from Info.plist (set from the CLEANSTART_APP_GROUP build
/// setting in project.yml) so it only needs to be changed in one place.
enum AppGroup {
    static let identifier: String =
        Bundle.main.object(forInfoDictionaryKey: "CleanStartAppGroup") as? String ?? "group.com.example.cleanstart"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
    }
}
