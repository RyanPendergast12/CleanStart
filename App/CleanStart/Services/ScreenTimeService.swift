import CleanStartCore
import Combine
import FamilyControls
import Foundation

/// Individual (self) Screen Time authorization via Family Controls.
@MainActor
final class ScreenTimeService: ObservableObject {
    @Published private(set) var state: ScreenTimeAuthorizationState = .notDetermined
    @Published private(set) var lastError: String?

    private var cancellable: AnyCancellable?

    init() {
        state = Self.map(AuthorizationCenter.shared.authorizationStatus)
        cancellable = AuthorizationCenter.shared.$authorizationStatus
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in self?.state = Self.map(status) }
    }

    /// Shows Apple's consent alert followed by Face ID / Touch ID / passcode.
    func requestAuthorization() async {
        lastError = nil
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
        } catch {
            lastError = Self.describe(error)
        }
        state = Self.map(AuthorizationCenter.shared.authorizationStatus)
    }

    /// Revoking removes every restriction CleanStart applied through Screen Time.
    func revokeAuthorization() {
        AuthorizationCenter.shared.revokeAuthorization { [weak self] result in
            Task { @MainActor in
                if case .failure(let error) = result { self?.lastError = Self.describe(error) }
                self?.state = Self.map(AuthorizationCenter.shared.authorizationStatus)
            }
        }
    }

    private static func map(_ status: AuthorizationStatus) -> ScreenTimeAuthorizationState {
        switch status {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .approved: return .approved
        default:
            // Newer SDKs add approval variants (e.g. `.approvedWithDataAccess`)
            // that aren't available on every OS this app supports; any of them
            // still grants the Managed Settings access CleanStart needs.
            return String(describing: status).hasPrefix("approved") ? .approved : .unavailable
        }
    }

    private static func describe(_ error: Error) -> String {
        if let familyError = error as? FamilyControlsError {
            switch familyError {
            case .restricted: return "Screen Time is restricted on this device (for example by a parent or your organisation)."
            case .unavailable: return "Screen Time isn't available. Make sure Screen Time is turned on in Settings."
            case .invalidAccountType: return "This Apple Account type can't authorize Screen Time apps."
            case .invalidArgument: return "Screen Time rejected the request."
            case .authorizationConflict: return "Another app already manages Screen Time for this device."
            case .authorizationCanceled: return "Authorization was cancelled. You can try again any time."
            case .networkError: return "Screen Time authorization needs an internet connection. Try again when connected."
            case .authenticationMethodUnavailable: return "Set a device passcode to authorize Screen Time."
            default: return familyError.localizedDescription
            }
        }
        let text = (error as NSError).localizedDescription
        if text.localizedCaseInsensitiveContains("entitlement") {
            return "This build lacks the Family Controls entitlement. Sign with a paid Apple Developer Program team. (\(text))"
        }
        return text
    }
}
