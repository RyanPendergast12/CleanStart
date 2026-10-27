import Foundation
import UserNotifications

/// Local notifications only. Nothing is sent to or through a server.
enum NotificationService {
    private static let dailyReminderID = "cleanstart.daily-checkin"

    @discardableResult
    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func scheduleDailyReminder(hour: Int, minute: Int) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [dailyReminderID])
        let content = UNMutableNotificationContent()
        content.title = "Daily check-in"
        content.body = "How did today go? A quick, honest check-in keeps your streak in view."
        content.sound = .default
        let trigger = UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: hour, minute: minute), repeats: true)
        try? await center.add(UNNotificationRequest(identifier: dailyReminderID, content: content, trigger: trigger))
    }

    static func cancelDailyReminder() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [dailyReminderID])
    }

    static func scheduleChangeReady(id: UUID, title: String, at date: Date) async {
        let content = UNMutableNotificationContent()
        content.title = "Requested change is available"
        content.body = "\(title) can now be applied in CleanStart for the next 12 hours. You can also simply cancel it."
        let interval = max(1, date.timeIntervalSinceNow)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "cleanstart.change.\(id.uuidString)", content: content, trigger: trigger))
    }

    static func cancelChangeReady(id: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["cleanstart.change.\(id.uuidString)"])
    }

    static func postProtectionAlert(_ body: String) async {
        let content = UNMutableNotificationContent()
        content.title = "CleanStart protection check"
        content.body = body
        content.sound = .default
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "cleanstart.protection-alert", content: content, trigger: nil))
    }
}
