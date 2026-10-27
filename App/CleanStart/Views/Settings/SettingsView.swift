import CleanStartCore
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var confirmDelete = false

    var body: some View {
        List {
            Section("Notifications") {
                Toggle("Daily check-in reminder", isOn: $model.preferences.dailyReminderEnabled)
                if model.preferences.dailyReminderEnabled {
                    DatePicker("Time", selection: reminderTime, displayedComponents: .hourAndMinute)
                }
                Toggle("Alert if protection stops working", isOn: $model.preferences.protectionAlertsEnabled)
            }
            .onChange(of: model.preferences.dailyReminderEnabled) { _, _ in Task { await model.updateReminder() } }
            .onChange(of: model.preferences.dailyReminderHour) { _, _ in Task { await model.updateReminder() } }
            .onChange(of: model.preferences.dailyReminderMinute) { _, _ in Task { await model.updateReminder() } }

            Section {
                Toggle("Check filtering when opened", isOn: $model.preferences.verifyOnOpen)
            } header: {
                Text("Verification")
            } footer: {
                Text("Background re-checks are also requested, but iOS decides if and when they run.")
            }

            Section {
                Toggle("High-contrast status colours", isOn: $model.preferences.highContrastStatus)
            } header: {
                Text("Accessibility")
            } footer: {
                Text("CleanStart follows your system Dynamic Type, Bold Text, Reduce Motion and VoiceOver settings. Status is always shown with text and icons, not just colour.")
            }

            Section("Privacy") {
                NavigationLink("What CleanStart stores") { PrivacyView() }
                Button("Delete all local data", role: .destructive) { confirmDelete = true }
            }

            Section("Removing CleanStart") {
                NavigationLink("Disable or uninstall safely") { UninstallGuideView() }
            }

            Section("About") {
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–")
                Link("CleanBrowsing Family Filter", destination: EncryptedDNSProvider.cleanBrowsingFamily.documentationURL)
            }
        }
        .navigationTitle("Settings")
        .confirmationDialog("Delete all local data?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { model.deleteAllLocalData() }
        } message: {
            Text("Deletes check-ins, goals, notes, check history and preferences. DNS and Screen Time settings stay as they are; remove those from Protection.")
        }
    }

    private var reminderTime: Binding<Date> {
        Binding(
            get: { Calendar.current.date(from: DateComponents(hour: model.preferences.dailyReminderHour, minute: model.preferences.dailyReminderMinute)) ?? Date() },
            set: {
                let c = Calendar.current.dateComponents([.hour, .minute], from: $0)
                model.preferences.dailyReminderHour = c.hour ?? 21
                model.preferences.dailyReminderMinute = c.minute ?? 0
            }
        )
    }
}

struct PrivacyView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        List {
            Section("Never collected") {
                bullet("Browsing history, visited sites or search terms")
                bullet("Analytics, crash reporting, advertising IDs or tracking SDKs")
                bullet("Accounts, email addresses or contacts")
                bullet("Work traffic, credentials or authentication tokens")
            }
            Section("Stored only on this iPhone") {
                ForEach(model.storedDataKeys, id: \.self) { Text($0).font(.body.monospaced()) }
                Text("Files live in CleanStart's private app storage, are encrypted by iOS data protection and excluded from backups. Screen Time selections are opaque Apple tokens stored in the app group so the schedule extension can read them.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Network use") {
                bullet("CleanStart itself makes no web requests. Filtering checks are plain DNS lookups of a fixed test list.")
                bullet("With DNS filtering on, iOS sends every DNS lookup from this iPhone to CleanBrowsing over HTTPS. Read CleanBrowsing's privacy policy to decide if you're comfortable with that.")
            }
        }
        .navigationTitle("Privacy")
    }
}

struct UninstallGuideView: View {
    var body: some View {
        List {
            Section("Quick restore (internet or work trouble)") {
                step(1, "Settings › General › VPN & Device Management › DNS → choose **Automatic** or deselect CleanStart.")
                step(2, "Your iPhone now uses the network's normal DNS. Nothing else needs to change.")
            }
            Section("Full rollback inside CleanStart") {
                step(1, "Protection › Screen Time › **Remove all restrictions** (after any accountability delay).")
                step(2, "Protection › DNS Filtering › **Remove DNS filtering**.")
                step(3, "Settings › Delete all local data (optional).")
            }
            Section("Without CleanStart (always possible)") {
                step(1, "Remove DNS: Settings › General › VPN & Device Management › DNS.")
                step(2, "Remove Screen Time access: Settings › Screen Time › scroll to apps with Screen Time access › CleanStart › turn off. All shields, the web filter and app-deletion protection are removed.")
                step(3, "If “Prevent deleting apps” is on, turn it off in CleanStart (or revoke Screen Time access) before deleting the app.")
                step(4, "Delete the app. iOS removes network configurations that belong to a deleted app, together with its data. Check Settings › General › VPN & Device Management afterwards to confirm nothing is left.")
            }
            Section("If you used the CleanBrowsing profile") {
                step(1, "Settings › General › VPN & Device Management › select the CleanBrowsing profile › **Remove Profile**.")
            }
            Section("Verify") {
                Text("Before deleting the app, run Diagnostics › Run filtering check. After a complete rollback it should report “Not filtering”, which confirms the network is back to normal DNS.")
                    .font(.footnote)
            }
        }
        .navigationTitle("Remove safely")
    }
}
