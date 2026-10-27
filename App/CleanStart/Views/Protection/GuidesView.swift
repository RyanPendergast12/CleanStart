import CleanStartCore
import SwiftUI

struct DuckDuckGoGuideView: View {
    var body: some View {
        List {
            Section("What's protected automatically") {
                bullet("DuckDuckGo for iOS looks up websites through the iPhone's system DNS, so CleanBrowsing blocks adult domains in every tab, including after using the Fire Button. Verify this yourself with the device test plan.")
                bullet("CleanBrowsing answers duckduckgo.com with safe.duckduckgo.com, which DuckDuckGo documents as always using strict Safe Search. That's enforced by DNS, not by the in-app setting.")
                bullet("Google, Bing and YouTube are also forced into SafeSearch / Restricted Mode by the filter.")
            }
            Section("Recommended settings in DuckDuckGo") {
                step(1, "Open DuckDuckGo › Settings › Search › Safe Search and choose **Strict**. This is a second layer if the DNS filter is ever off.")
                step(2, "Don't turn on the DuckDuckGo VPN (subscription feature). Like any VPN, it uses its own DNS, which bypasses CleanBrowsing.")
                step(3, "The Fire Button only clears local tabs and data. It does not change DNS, so filtering is unaffected.")
            }
            Section("Honest limits") {
                bullet("DNS filtering works per domain. It can't inspect individual images or videos on sites that are allowed (for example social networks or image search results that slip through).")
                bullet("Image results in Safe Search come from DuckDuckGo's own filtering, which is good but not perfect.")
                bullet("If you install a different browser that uses its own encrypted DNS, it can skip the system DNS. Shield extra browsers with Screen Time if you don't need them.")
            }
            Section("Check it") {
                NavigationLink("Run a filtering check") { DiagnosticsView() }
                Text("The check only performs DNS lookups. It never opens a website, so nothing explicit is ever loaded.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("DuckDuckGo")
    }
}

struct TroubleshootingView: View {
    var body: some View {
        List {
            Section("“Installed, not enabled”") {
                Text("Open Settings › General › VPN & Device Management › DNS and choose CleanStart. If a CleanBrowsing profile or another DNS app is selected, iOS uses that one instead (filtering may still be verified).")
            }
            Section("Check says “Not filtering”") {
                bullet("Is a VPN connected (personal, browser or work)? While connected, its DNS takes over.")
                bullet("Is iCloud Private Relay on? Apple states configured encrypted DNS takes precedence, but turn it off and re-check if results disagree.")
                bullet("Some Wi-Fi networks block encrypted DNS. iOS then shows a privacy warning for that network and lookups fail rather than going unfiltered; switch networks or use cellular.")
                bullet("Reinstall from Protection › DNS Filtering, then re-select it in Settings.")
            }
            Section("Websites or apps won't load") {
                bullet("CleanBrowsing Family also blocks VPN/proxy services and mixed-content sites like Reddit. That's intentional.")
                bullet("If CleanBrowsing is unreachable, Apple's encrypted-DNS design is for lookups to fail rather than silently fall back to unfiltered DNS (confirm with the outage test in the README). To restore internet immediately, deselect CleanStart in Settings › General › VPN & Device Management › DNS.")
                bullet("Work problems: see the Teams checklist. Deselecting CleanStart in Settings restores your network's default DNS straight away.")
            }
            Section("Can't use the in-app DNS setting?") {
                Text("If this build can't save a DNS configuration (for example it was signed without the DNS Settings entitlement), use CleanBrowsing's official profile instead: open cleanbrowsing.org/filters in Safari, choose Family Filter › Apple devices, download the .mobileconfig, then install it in Settings › General › VPN & Device Management. CleanStart's check still verifies it.")
                Link("CleanBrowsing filters page", destination: EncryptedDNSProvider.cleanBrowsingFamily.documentationURL)
            }
            Section("Managed (work) iPhone") {
                Text("If your iPhone is enrolled in your employer's device management and it controls DNS, or policy forbids personal DNS settings, don't install the DNS setting. Use Screen Time shields, Apple's adult-website filter and DuckDuckGo Strict Safe Search instead; none of them change network settings.")
            }
        }
        .font(.subheadline)
        .navigationTitle("Troubleshooting")
    }
}

struct WorkChecklistView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        List {
            Section {
                Text("CleanStart never looks at work traffic, sign-ins or tokens. Changing DNS can still affect work services in rare cases (for example internal company domains only your office DNS knows). Tick each check after enabling filtering.")
                    .font(.footnote)
            }
            Section("Checks") {
                ForEach(WorkChecklist.items) { item in
                    Button {
                        model.checklist.set(item.id, done: !model.checklist.isDone(item.id))
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: model.checklist.isDone(item.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(model.checklist.isDone(item.id) ? Theme.accent : .secondary)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.title).foregroundStyle(.primary)
                                Text(item.howTo).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .accessibilityAddTraits(model.checklist.isDone(item.id) ? .isSelected : [])
                }
            }
            Section("If something fails") {
                step(1, "Go to Settings › General › VPN & Device Management › DNS and choose **Automatic** (or deselect CleanStart). That restores normal DNS instantly.")
                step(2, "Retry the failing work app. If it now works, the issue is DNS-related; contact your IT team before re-enabling.")
                step(3, "Never try to work around your employer's policies. Screen Time shields and DuckDuckGo Strict Safe Search work without touching network settings.")
            }
            Section {
                Button("Reset checklist") { model.checklist.reset() }
            }
        }
        .navigationTitle("Work apps")
    }
}

func bullet(_ text: LocalizedStringKey) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text("•").accessibilityHidden(true)
        Text(text)
    }
    .font(.subheadline)
}

func step(_ number: Int, _ text: LocalizedStringKey) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 10) {
        Text("\(number).").font(.subheadline.weight(.semibold)).monospacedDigit()
        Text(text).font(.subheadline)
    }
}
