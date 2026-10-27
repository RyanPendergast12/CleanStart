import CleanStartCore
import UIKit
import SwiftUI

struct ProtectionView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        List {
            Section {
                NavigationLink { DNSSetupView() } label: {
                    row("DNS filtering", detail: model.dns.state.title, symbol: "network")
                }
                NavigationLink { ScreenTimeView() } label: {
                    row("Screen Time & app shields", detail: model.restrictions.shieldsActive ? "Active" : "Off", symbol: "hourglass")
                }
            } header: {
                Text("Layers")
            } footer: {
                Text("DNS filtering protects every app on Wi-Fi and cellular. Screen Time shields add friction for specific apps.")
            }

            Section("Verify") {
                NavigationLink { DiagnosticsView() } label: {
                    row("Run filtering check", detail: model.history.latest?.verdict.title ?? "Never", symbol: "checklist")
                }
            }

            Section("Guides") {
                NavigationLink { DuckDuckGoGuideView() } label: { Label("DuckDuckGo setup", systemImage: "magnifyingglass") }
                NavigationLink { WorkChecklistView() } label: { Label("Teams & work apps checklist", systemImage: "briefcase") }
                NavigationLink { TroubleshootingView() } label: { Label("Troubleshooting", systemImage: "wrench.and.screwdriver") }
            }

            Section {
                NavigationLink { AccountabilityView() } label: {
                    row("Accountability delay", detail: model.ledger.delay.title, symbol: "timer")
                }
            } footer: {
                Text("Turning protection off waits for this delay inside CleanStart. It's a voluntary cooling-off period: iOS Settings can always remove it directly.")
            }
        }
        .navigationTitle("Protection")
    }

    private func row(_ title: String, detail: String, symbol: String) -> some View {
        HStack {
            Label(title, systemImage: symbol)
            Spacer()
            Text(detail).foregroundStyle(.secondary)
        }
    }
}

struct DNSSetupView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var dns: DNSConfigurationService
    @State private var confirmInstall = false
    @State private var confirmRemove = false

    var body: some View {
        List {
            Section("Status") {
                LabeledContent("Configuration", value: dns.state.title)
                LabeledContent("Provider", value: dns.provider.displayName)
                LabeledContent("Endpoint", value: dns.provider.dohURL.absoluteString)
                    .font(.footnote)
                if let error = dns.lastError {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red).font(.footnote)
                }
            }

            Section {
                Button {
                    confirmInstall = true
                } label: {
                    Label(dns.state == .notInstalled ? "Install DNS filtering" : "Reinstall configuration", systemImage: "arrow.down.circle")
                }
                .disabled(dns.isWorking)
            } header: {
                Text("Step 1 · Install")
            } footer: {
                Text("Saves an encrypted DNS (DNS-over-HTTPS) setting. This is not a VPN: there's no tunnel, no VPN icon, and your normal connection is untouched.")
            }

            Section {
                Text("Open **Settings › General › VPN & Device Management › DNS** and select **CleanStart**. iOS requires you to do this yourself.")
                    .font(.subheadline)
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
            } header: {
                Text("Step 2 · Enable")
            } footer: {
                Text("iOS can't deep-link to that screen, so this opens CleanStart's page in Settings — go back to the top level from there. Only one DNS setting can be active, so selecting CleanStart replaces any other DNS profile or app.")
            }

            Section {
                NavigationLink("Run a filtering check") { DiagnosticsView() }
            } header: {
                Text("Step 3 · Verify")
            } footer: {
                Text("“Enabled” only means the setting is saved and selected. The check confirms that adult domains are actually blocked on your current network.")
            }

            Section {
                AccountabilityGate(change: .removeDNSConfiguration)
                Button("Remove DNS filtering", role: .destructive) { confirmRemove = true }
                    .disabled(dns.state == .notInstalled || !model.isAllowed(.removeDNSConfiguration) || dns.isWorking)
            } header: {
                Text("Remove")
            } footer: {
                Text("After removal iOS immediately returns to your network's normal DNS. You can also remove it in Settings › General › VPN & Device Management › DNS.")
            }
        }
        .navigationTitle("DNS Filtering")
        .task { await dns.refresh() }
        .confirmationDialog("Install CleanBrowsing Family DNS?", isPresented: $confirmInstall, titleVisibility: .visible) {
            Button("Install") { Task { await model.installDNS() } }
        } message: {
            Text("All DNS lookups on this iPhone, on every network, will go to CleanBrowsing over HTTPS. Work apps normally keep working; please run the Teams checklist afterwards.")
        }
        .confirmationDialog("Remove DNS filtering?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove", role: .destructive) { Task { _ = await model.removeDNS() } }
        } message: {
            Text("Websites will no longer be filtered by DNS.")
        }
    }
}

struct AccountabilityView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        List {
            Section {
                ForEach(AccountabilityDelay.allCases, id: \.self) { delay in
                    Button {
                        Task { await model.setDelay(delay) }
                    } label: {
                        HStack {
                            Text(delay.title).foregroundStyle(.primary)
                            Spacer()
                            if model.ledger.delay == delay { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
                        }
                    }
                }
            } footer: {
                Text("A longer delay applies immediately. A shorter one must itself wait out the current delay.")
            }

            if let pending = model.ledger.pendingRequest(for: .reduceAccountabilityDelay), let newDelay = pending.newDelay {
                Section("Pending") {
                    Text("Change delay to \(newDelay.title)")
                    AccountabilityGate(change: .reduceAccountabilityDelay)
                    if model.status(of: .reduceAccountabilityDelay) == .ready {
                        Button("Apply new delay") { model.applyDelayReduction() }
                    }
                }
            }

            Section("What this can and can't do") {
                Text("Enforced inside CleanStart: removing DNS filtering, removing shields, turning off the web filter, changing or stopping schedules, and shortening this delay.")
                Text("Not enforceable: as the device owner you can always remove the DNS setting in iOS Settings or turn off CleanStart's Screen Time access. For stronger friction, ask a trusted person to set a Screen Time passcode you don't know.")
            }
            .font(.footnote)
        }
        .navigationTitle("Accountability")
    }
}
