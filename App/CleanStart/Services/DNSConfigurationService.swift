import CleanStartCore
import Foundation
import NetworkExtension

/// Installs, inspects and removes CleanStart's system-wide encrypted DNS
/// configuration via NEDNSSettingsManager.
///
/// This is *not* a VPN: no tunnel, no virtual interface and no packet
/// processing. iOS itself sends DNS queries to the configured DoH server over
/// the device's normal Wi-Fi or cellular connection.
@MainActor
final class DNSConfigurationService: ObservableObject {
    @Published private(set) var state: DNSConfigurationState = .unknown
    @Published private(set) var lastError: String?
    @Published private(set) var isWorking = false

    let provider = EncryptedDNSProvider.cleanBrowsingFamily
    private var observer: NSObjectProtocol?

    init() {
        // Fires when the user selects or deselects the configuration in Settings.
        observer = NotificationCenter.default.addObserver(
            forName: .NEDNSSettingsConfigurationDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            Task { await self?.refresh() }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    func refresh() async {
        let manager = NEDNSSettingsManager.shared()
        do {
            try await manager.loadFromPreferences()
            state = Self.state(of: manager, provider: provider)
        } catch {
            state = .unavailable(reason: Self.describe(error))
        }
    }

    /// Saves the CleanBrowsing Family configuration. The user must then select
    /// it in Settings › General › VPN & Device Management › DNS — iOS requires
    /// that explicit step and no app can skip it.
    func install() async {
        isWorking = true
        defer { isWorking = false }
        lastError = nil
        do {
            try provider.validate()
            let manager = NEDNSSettingsManager.shared()
            try await manager.loadFromPreferences()

            let settings = NEDNSOverHTTPSSettings(servers: provider.serverAddresses)
            settings.serverURL = provider.dohURL
            // matchDomains stays nil: the filter applies to every domain.
            manager.dnsSettings = settings
            manager.localizedDescription = "CleanStart · \(provider.displayName)"

            // A single catch-all rule: apply on every network — Wi-Fi, cellular,
            // anything — with no exceptions.
            let everywhere = NEOnDemandRuleConnect()
            everywhere.interfaceTypeMatch = .any
            manager.onDemandRules = [everywhere]

            try await manager.saveToPreferences()
            try await manager.loadFromPreferences()
            state = Self.state(of: manager, provider: provider)
        } catch {
            lastError = Self.describe(error)
            await refresh()
        }
    }

    /// Removes the configuration. iOS immediately falls back to the network's
    /// normal DNS (no filtering).
    func remove() async {
        isWorking = true
        defer { isWorking = false }
        lastError = nil
        do {
            let manager = NEDNSSettingsManager.shared()
            try await manager.loadFromPreferences()
            try await manager.removeFromPreferences()
            try await manager.loadFromPreferences()
            state = Self.state(of: manager, provider: provider)
        } catch {
            lastError = Self.describe(error)
            await refresh()
        }
    }

    private static func state(of manager: NEDNSSettingsManager, provider: EncryptedDNSProvider) -> DNSConfigurationState {
        guard let settings = manager.dnsSettings else { return .notInstalled }
        guard manager.isEnabled else { return .installedNotEnabled }
        let url = (settings as? NEDNSOverHTTPSSettings)?.serverURL
        return .enabled(matchesExpected: provider.matches(serverURL: url))
    }

    static func describe(_ error: Error) -> String {
        if let validation = error as? EncryptedDNSProvider.ValidationError { return validation.description }
        let nsError = error as NSError
        if nsError.domain == "NEDNSSettingsErrorDomain" {
            switch nsError.code {
            case 1: return "iOS rejected the DNS configuration as invalid."
            case 2: return "The DNS configuration is disabled. Select CleanStart in Settings › General › VPN & Device Management › DNS."
            case 3: return "The configuration changed elsewhere. Close and reopen CleanStart, then try again."
            case 4: return "This DNS configuration can't be removed — it may be managed by a configuration profile or your organisation."
            default: break
            }
        }
        let text = nsError.localizedDescription
        if text.localizedCaseInsensitiveContains("permission") || text.localizedCaseInsensitiveContains("entitle") {
            return "This build lacks the Network Extension “DNS Settings” entitlement. Sign it with a paid Apple Developer Program team that has the capability enabled. (\(text))"
        }
        return text
    }
}
