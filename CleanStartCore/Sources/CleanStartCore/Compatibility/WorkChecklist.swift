import Foundation

/// Manual checks to confirm work apps still function after enabling filtering.
/// CleanStart never inspects work traffic; the user performs and ticks these.
public struct WorkChecklistItem: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let howTo: String
}

public struct WorkChecklist: Codable, Equatable, Sendable {
    public static let items: [WorkChecklistItem] = [
        .init(id: "teams-signin", title: "Teams signs in",
              howTo: "Fully close Teams, reopen it, and confirm you reach your chats without a sign-in error."),
        .init(id: "teams-messages", title: "Teams messages and calls work",
              howTo: "Send yourself a message, open a channel, and (optionally) join a test meeting."),
        .init(id: "authenticator-push", title: "Authenticator approvals arrive",
              howTo: "Trigger a sign-in that needs MFA (e.g. sign in to office.com in DuckDuckGo) and approve it in Microsoft Authenticator."),
        .init(id: "authenticator-codes", title: "Authenticator codes are accepted",
              howTo: "Use a one-time code from Authenticator for a sign-in and confirm it's accepted."),
        .init(id: "entra-browser", title: "Entra web sign-in works",
              howTo: "In DuckDuckGo, open myaccount.microsoft.com or office.com and sign in with your work account."),
        .init(id: "compliance", title: "Company Portal / compliance is unchanged",
              howTo: "If your employer uses Intune Company Portal, open it and confirm the device still shows as compliant (or that nothing changed)."),
        .init(id: "cellular", title: "Teams works on cellular",
              howTo: "Turn Wi-Fi off, then repeat the Teams sign-in and message checks on LTE/5G."),
        .init(id: "other-wifi", title: "Teams works on another Wi-Fi",
              howTo: "On a different network (office, café), open Teams and confirm it connects."),
    ]

    public private(set) var completed: [String: Date]

    public init(completed: [String: Date] = [:]) {
        self.completed = completed
    }

    public mutating func set(_ id: String, done: Bool, now: Date = Date()) {
        completed[id] = done ? now : nil
    }

    public func isDone(_ id: String) -> Bool { completed[id] != nil }

    public var allDone: Bool { Self.items.allSatisfy { isDone($0.id) } }

    public mutating func reset() { completed.removeAll() }
}
