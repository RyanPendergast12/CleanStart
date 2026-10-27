import BackgroundTasks
import CleanStartCore
import Combine
import Foundation
import UIKit

/// Owns app state and coordinates the services. All persistence is local.
@MainActor
final class AppModel: ObservableObject {
    nonisolated static let backgroundTaskID = "app.cleanstart.verify"

    let dns = DNSConfigurationService()
    let network = NetworkStatusService()
    let screenTime = ScreenTimeService()
    let restrictions = RestrictionService()

    @Published var habitLog: HabitLog { didSet { persist(habitLog, StoreKey.habitLog) } }
    @Published private(set) var ledger: AccountabilityLedger { didSet { persist(ledger, StoreKey.accountability) } }
    @Published private(set) var history: VerificationHistory { didSet { persist(history, StoreKey.verificationHistory) } }
    @Published var checklist: WorkChecklist { didSet { persist(checklist, StoreKey.workChecklist) } }
    @Published var preferences: Preferences { didSet { persist(preferences, StoreKey.preferences) } }
    @Published private(set) var isVerifying = false
    @Published var lastError: String?

    private let store: LocalStore
    private var cancellables: Set<AnyCancellable> = []

    init(store: LocalStore = LocalStore(directory: LocalStore.defaultDirectory())) {
        self.store = store
        habitLog = store.load(HabitLog.self, key: StoreKey.habitLog) ?? HabitLog()
        ledger = store.load(AccountabilityLedger.self, key: StoreKey.accountability) ?? AccountabilityLedger()
        history = store.load(VerificationHistory.self, key: StoreKey.verificationHistory) ?? VerificationHistory()
        checklist = store.load(WorkChecklist.self, key: StoreKey.workChecklist) ?? WorkChecklist()
        preferences = store.load(Preferences.self, key: StoreKey.preferences) ?? Preferences()

        // Re-publish service changes so views observing the model refresh.
        for publisher in [dns.objectWillChange, network.objectWillChange, screenTime.objectWillChange, restrictions.objectWillChange] {
            publisher.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        }
    }

    // MARK: Status

    var today: DayStamp { DayStamp(Date()) }

    var assessment: ProtectionAssessment {
        ProtectionAssessment.assess(ProtectionSnapshot(
            dnsConfiguration: dns.state,
            latestVerification: history.latest,
            previousVerdict: history.previousVerdict,
            screenTime: screenTime.state,
            shieldsActive: restrictions.shieldsActive,
            vpnLikelyActive: network.vpnLikelyActive,
            now: Date()
        ))
    }

    var diagnosticsText: String {
        DiagnosticsReport(
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?",
            osVersion: UIDevice.current.systemVersion,
            dnsConfiguration: dns.state,
            screenTime: screenTime.state,
            networkDescription: network.description,
            vpnLikelyActive: network.vpnLikelyActive,
            latestVerification: history.latest,
            lastError: lastError ?? dns.lastError ?? screenTime.lastError ?? restrictions.lastError
        ).text()
    }

    /// Called when the app becomes active.
    func refreshOnOpen() async {
        ledger.pruneExpired(now: Date())
        await dns.refresh()
        if preferences.verifyOnOpen { await verifyFiltering() }
        Self.scheduleBackgroundVerification()
    }

    // MARK: Verification

    func verifyFiltering() async {
        guard !isVerifying else { return }
        isVerifying = true
        defer { isVerifying = false }
        let report = await FilterVerifier().run(networkDescription: network.description)
        history.append(report)
    }

    func clearVerificationHistory() { history.clear() }

    /// Runs from a background app refresh task. iOS decides if and when this
    /// happens, so it is a best-effort extra, never a guarantee.
    nonisolated static func performBackgroundVerification() async {
        let store = LocalStore(directory: LocalStore.defaultDirectory())
        var history = store.load(VerificationHistory.self, key: StoreKey.verificationHistory) ?? VerificationHistory()
        let preferences = store.load(Preferences.self, key: StoreKey.preferences) ?? Preferences()
        let report = await FilterVerifier().run(networkDescription: "Background check")
        let previous = history.latest?.verdict
        history.append(report)
        try? store.save(history, key: StoreKey.verificationHistory)
        if preferences.protectionAlertsEnabled, report.verdict == .notFiltering,
           previous == .verified || previous == .blockingObserved {
            await NotificationService.postProtectionAlert("Adult-site filtering stopped working since the last check. Open CleanStart to see why.")
        }
        scheduleBackgroundVerification()
    }

    nonisolated static func scheduleBackgroundVerification() {
        let request = BGAppRefreshTaskRequest(identifier: backgroundTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 6 * 60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    // MARK: DNS

    func installDNS() async {
        await dns.install()
        lastError = dns.lastError
    }

    func removeDNS() async -> Bool {
        do {
            try ledger.consume(.removeDNSConfiguration, now: Date())
        } catch {
            lastError = describe(error, for: .removeDNSConfiguration)
            return false
        }
        await dns.remove()
        lastError = dns.lastError
        return dns.lastError == nil
    }

    // MARK: Accountability

    func status(of change: ProtectedChange) -> PendingChangeStatus? {
        ledger.pendingRequest(for: change).map { ledger.status(of: $0, now: Date()) }
    }

    /// True if the change may be performed right now.
    func isAllowed(_ change: ProtectedChange) -> Bool {
        if ledger.delay == .off, change != .reduceAccountabilityDelay { return true }
        return status(of: change) == .ready
    }

    func requestChange(_ change: ProtectedChange, newDelay: AccountabilityDelay? = nil) async {
        do {
            let item = try ledger.request(change, newDelay: newDelay, now: Date())
            if item.availableAt > Date() {
                await NotificationService.scheduleChangeReady(id: item.id, title: change.title, at: item.availableAt)
            }
        } catch {
            lastError = describe(error, for: change)
        }
    }

    func cancelChange(_ change: ProtectedChange) {
        if let item = ledger.pendingRequest(for: change) { NotificationService.cancelChangeReady(id: item.id) }
        ledger.cancel(change)
    }

    func setDelay(_ delay: AccountabilityDelay) async {
        if !ledger.increaseDelay(to: delay) {
            await requestChange(.reduceAccountabilityDelay, newDelay: delay)
        }
    }

    func applyDelayReduction() {
        do {
            try ledger.consume(.reduceAccountabilityDelay, now: Date())
        } catch {
            lastError = describe(error, for: .reduceAccountabilityDelay)
        }
    }

    // MARK: Restrictions

    enum ApplyResult: Equatable {
        case applied
        case needsApproval([ProtectedChange])
        case failed(String)
    }

    func applyRestrictions(_ proposed: RestrictionConfiguration) -> ApplyResult {
        let weakening = restrictions.weakeningChanges(to: proposed)
        let blocked = weakening.filter { !isAllowed($0) }
        guard blocked.isEmpty else { return .needsApproval(blocked) }
        for change in weakening { try? ledger.consume(change, now: Date()) }
        restrictions.apply(proposed)
        if let error = restrictions.lastError { return .failed(error) }
        return .applied
    }

    func removeAllRestrictions() -> Bool {
        let needed: [ProtectedChange] = [.clearAppShields, .disableWebContentFilter, .disableAppRemovalProtection, .stopSchedule]
            .filter { change in
                switch change {
                case .clearAppShields: return restrictions.configuration.hasSelection
                case .disableWebContentFilter: return restrictions.configuration.webContentFilterEnabled
                case .disableAppRemovalProtection: return restrictions.configuration.denyAppRemoval
                case .stopSchedule: return restrictions.configuration.mode == .scheduled
                default: return false
                }
            }
        guard needed.allSatisfy(isAllowed) else {
            lastError = "Request the pending changes first: " + needed.filter { !isAllowed($0) }.map(\.title).joined(separator: ", ")
            return false
        }
        for change in needed { try? ledger.consume(change, now: Date()) }
        restrictions.removeAll()
        return true
    }

    // MARK: Habits

    func checkIn(_ status: CheckInStatus, for day: DayStamp? = nil, note: String? = nil) {
        do {
            try habitLog.record(status, for: day ?? today, today: today, note: note)
        } catch {
            lastError = "That day can't be changed any more."
        }
    }

    // MARK: Preferences & data

    func updateReminder() async {
        if preferences.dailyReminderEnabled {
            if await NotificationService.requestPermission() {
                await NotificationService.scheduleDailyReminder(hour: preferences.dailyReminderHour, minute: preferences.dailyReminderMinute)
            } else {
                preferences.dailyReminderEnabled = false
                lastError = "Notifications are turned off for CleanStart in iOS Settings."
            }
        } else {
            NotificationService.cancelDailyReminder()
        }
    }

    /// Deletes habits, history, checklist and preferences. DNS and Screen Time
    /// settings are left untouched; they have their own rollback steps.
    func deleteAllLocalData() {
        do {
            try store.removeAll()
        } catch {
            lastError = error.localizedDescription
        }
        cancellables.removeAll()
        habitLog = HabitLog()
        history = VerificationHistory()
        checklist = WorkChecklist()
        preferences = Preferences(hasCompletedOnboarding: true)
        NotificationService.cancelDailyReminder()
        // Keep the accountability ledger so data deletion isn't a shortcut
        // around a pending delay.
        persist(ledger, StoreKey.accountability)
        for publisher in [dns.objectWillChange, network.objectWillChange, screenTime.objectWillChange, restrictions.objectWillChange] {
            publisher.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        }
    }

    var storedDataKeys: [String] { store.storedKeys() }

    // MARK: Helpers

    private func persist<T: Encodable>(_ value: T, _ key: String) {
        do {
            try store.save(value, key: key)
        } catch {
            lastError = "Couldn't save \(key): \(error.localizedDescription)"
        }
    }

    private func describe(_ error: Error, for change: ProtectedChange) -> String {
        switch error as? AccountabilityLedger.LedgerError {
        case .notRequested: return "“\(change.title)” needs to be requested first (accountability delay: \(ledger.delay.title))."
        case .stillWaiting(let remaining): return "“\(change.title)” will be available in \(Format.duration(remaining))."
        case .expired: return "The approval for “\(change.title)” expired. Request it again if you still want it."
        case .notAReduction: return "Choose a shorter delay than the current one."
        case nil: return error.localizedDescription
        }
    }
}

enum Format {
    static func duration(_ interval: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = interval >= 3600 ? [.day, .hour, .minute] : [.minute, .second]
        formatter.unitsStyle = .short
        formatter.maximumUnitCount = 2
        return formatter.string(from: max(0, interval)) ?? "\(Int(interval))s"
    }

    static func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
