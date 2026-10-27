import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        TabView {
            NavigationStack { DashboardView() }
                .tabItem { Label("Today", systemImage: "sun.horizon") }
            NavigationStack { ProtectionView() }
                .tabItem { Label("Protection", systemImage: "shield.lefthalf.filled") }
            NavigationStack { HabitsView() }
                .tabItem { Label("Habits", systemImage: "leaf") }
            NavigationStack { DiagnosticsView() }
                .tabItem { Label("Diagnostics", systemImage: "stethoscope") }
            NavigationStack { SettingsView() }
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .sheet(isPresented: Binding(
            get: { !model.preferences.hasCompletedOnboarding },
            set: { if !$0 { model.preferences.hasCompletedOnboarding = true } }
        )) {
            OnboardingView()
                .interactiveDismissDisabled()
        }
        .alert("Something needs attention", isPresented: Binding(
            get: { model.lastError != nil },
            set: { if !$0 { model.lastError = nil } }
        )) {
            Button("OK", role: .cancel) { model.lastError = nil }
        } message: {
            Text(model.lastError ?? "")
        }
    }
}

struct OnboardingView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Image(systemName: "leaf.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(Theme.accent)
                    .accessibilityHidden(true)
                Text("Welcome to CleanStart")
                    .font(.largeTitle.bold())
                Text("Three layers, all on your iPhone, all under your control:")
                    .foregroundStyle(.secondary)

                feature("network", "DNS filtering", "CleanBrowsing Family blocks adult sites on Wi-Fi and cellular, in DuckDuckGo and every other app. It's an iOS DNS setting, not a VPN.")
                feature("hourglass", "Screen Time shields", "Optionally pause chosen apps and turn on Apple's adult-website filter.")
                feature("leaf", "Daily check-ins", "A private, judgement-free streak. It works alongside Finch; it doesn't connect to it.")

                Card {
                    Label("Private by design", systemImage: "lock.fill").font(.headline)
                    Text("No account, no analytics, no ads, no tracking. CleanStart never records your browsing. Everything stays on this device.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Card {
                    Label("Honest about limits", systemImage: "hand.raised.fill").font(.headline)
                    Text("You're the owner of this iPhone, so you can always undo these settings in iOS Settings. CleanStart adds friction and keeps you aware; it can't make change impossible, and it never claims to.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }

                Button {
                    model.preferences.hasCompletedOnboarding = true
                } label: {
                    Text("Get started").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(24)
        }
    }

    private func feature(_ symbol: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(Theme.accent)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(text).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
