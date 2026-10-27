import CleanStartCore
import FamilyControls
import SwiftUI

struct ScreenTimeView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var screenTime: ScreenTimeService
    @EnvironmentObject private var restrictions: RestrictionService

    @State private var draft = RestrictionConfiguration()
    @State private var showingPicker = false
    @State private var pendingApprovals: [ProtectedChange] = []
    @State private var confirmRemoveAll = false
    @State private var savedMessage: String?

    var body: some View {
        List {
            authorizationSection
            if screenTime.state == .approved {
                selectionSection
                scheduleSection
                extrasSection
                saveSection
                removeSection
            }
            limitsSection
        }
        .navigationTitle("Screen Time")
        .onAppear { draft = restrictions.configuration }
        .familyActivityPicker(isPresented: $showingPicker, selection: $draft.selection)
        .confirmationDialog("Remove all Screen Time restrictions?", isPresented: $confirmRemoveAll, titleVisibility: .visible) {
            Button("Remove all", role: .destructive) {
                if model.removeAllRestrictions() { draft = restrictions.configuration }
            }
        }
    }

    private var authorizationSection: some View {
        Section {
            LabeledContent("Authorization", value: screenTime.state.rawValue.capitalized)
            if screenTime.state != .approved {
                Button("Connect Screen Time") { Task { await screenTime.requestAuthorization() } }
            }
            if let error = screenTime.lastError {
                Text(error).font(.footnote).foregroundStyle(.red)
            }
        } header: {
            Text("Authorization")
        } footer: {
            Text("iOS asks you to confirm with Face ID, Touch ID or your passcode. CleanStart only receives opaque tokens for what you pick — never your usage history.")
        }
    }

    private var selectionSection: some View {
        Section {
            Button {
                showingPicker = true
            } label: {
                Label("Choose apps, categories & websites", systemImage: "square.grid.2x2")
            }
            Text(draft.selectionSummary).font(.footnote).foregroundStyle(.secondary)
            ForEach(Array(draft.selection.applicationTokens), id: \.self) { token in
                Label(token)
            }
        } header: {
            Text("What to shield")
        } footer: {
            Text("Good candidates: other browsers you don't need, apps where explicit content tends to appear, and the App Store's browser category. Don't shield Microsoft Teams, Authenticator, Company Portal or Phone.")
        }
    }

    private var scheduleSection: some View {
        Section {
            Picker("When", selection: $draft.mode) {
                ForEach(RestrictionConfiguration.Mode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            if draft.mode == .scheduled {
                DatePicker("From", selection: timeBinding(\.scheduleStart), displayedComponents: .hourAndMinute)
                DatePicker("Until", selection: timeBinding(\.scheduleEnd), displayedComponents: .hourAndMinute)
            }
        } header: {
            Text("Schedule")
        } footer: {
            Text("Schedules repeat daily and may cross midnight (e.g. 9 PM to 7 AM). iOS requires at least 15 minutes.")
        }
    }

    private var extrasSection: some View {
        Section {
            Toggle("Apple adult-website filter", isOn: $draft.webContentFilterEnabled)
            Toggle("Prevent deleting apps", isOn: $draft.denyAppRemoval)
        } header: {
            Text("Extra protection")
        } footer: {
            Text("The adult-website filter is Screen Time's “Limit Adult Websites”, applied by iOS to Safari and to apps built on WebKit; check DuckDuckGo afterwards. “Prevent deleting apps” blocks deleting *any* app, CleanStart included, until you turn it off here.")
        }
    }

    private var saveSection: some View {
        Section {
            Button("Save restrictions") { save() }
                .disabled(draft == restrictions.configuration)
            if let savedMessage {
                Label(savedMessage, systemImage: "checkmark.circle").foregroundStyle(.green).font(.footnote)
            }
            if let error = restrictions.lastError {
                Text(error).font(.footnote).foregroundStyle(.red)
            }
            if !pendingApprovals.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("These changes weaken protection and need to wait:").font(.footnote.weight(.semibold))
                    ForEach(pendingApprovals, id: \.self) { change in
                        Text("• \(change.title)").font(.footnote)
                        AccountabilityGate(change: change)
                    }
                    Button("Revert my edits") { draft = restrictions.configuration; pendingApprovals = [] }
                        .font(.footnote)
                }
            }
        }
    }

    private var removeSection: some View {
        Section {
            Button("Remove all restrictions", role: .destructive) { confirmRemoveAll = true }
        } footer: {
            Text("Clears every shield, schedule and filter CleanStart set. Subject to the accountability delay.")
        }
    }

    private var limitsSection: some View {
        Section("Limits") {
            Text("You authorized CleanStart for yourself, so you can revoke its access at any time in Settings › Screen Time. Doing so removes all of these restrictions. CleanStart can't prevent that, and doesn't pretend to.")
                .font(.footnote)
        }
    }

    private func save() {
        savedMessage = nil
        switch model.applyRestrictions(draft) {
        case .applied:
            pendingApprovals = []
            savedMessage = "Restrictions saved"
            draft = restrictions.configuration
        case .needsApproval(let changes):
            pendingApprovals = changes
        case .failed:
            break
        }
    }

    private func timeBinding(_ keyPath: WritableKeyPath<RestrictionConfiguration, DateComponents>) -> Binding<Date> {
        Binding(
            get: { Calendar.current.date(from: draft[keyPath: keyPath]) ?? Date() },
            set: { draft[keyPath: keyPath] = Calendar.current.dateComponents([.hour, .minute], from: $0) }
        )
    }
}
