import CleanStartCore
import SwiftUI

enum Theme {
    static let accent = Color.teal

    static func color(for level: ProtectionLevel, highContrast: Bool = false) -> Color {
        switch level {
        case .protected: return highContrast ? Color(red: 0, green: 0.45, blue: 0.2) : .green
        case .attention: return highContrast ? Color(red: 0.6, green: 0.35, blue: 0) : .orange
        case .unprotected: return highContrast ? Color(red: 0.7, green: 0, blue: 0) : .red
        }
    }

    static func symbol(for level: ProtectionLevel) -> String {
        switch level {
        case .protected: return "checkmark.shield.fill"
        case .attention: return "exclamationmark.shield.fill"
        case .unprotected: return "xmark.shield.fill"
        }
    }

    static func color(for severity: ProtectionIssue.Severity) -> Color {
        switch severity {
        case .info: return .blue
        case .warning: return .orange
        case .critical: return .red
        }
    }

    static func symbol(for severity: ProtectionIssue.Severity) -> String {
        switch severity {
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .critical: return "xmark.octagon.fill"
        }
    }

    static func color(for verdict: FilterVerdict) -> Color {
        switch verdict {
        case .verified: return .green
        case .blockingObserved, .inconclusive: return .orange
        case .notFiltering: return .red
        }
    }
}

/// A rounded content card used across screens.
struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct StatusRow: View {
    let title: String
    let value: String
    let systemImage: String
    var color: Color = .secondary

    var body: some View {
        HStack {
            Label(title, systemImage: systemImage)
            Spacer()
            Text(value).foregroundStyle(color).multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }
}

struct IssueRow: View {
    let issue: ProtectionIssue

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: Theme.symbol(for: issue.severity))
                .foregroundStyle(Theme.color(for: issue.severity))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(issue.title).font(.subheadline.weight(.semibold))
                Text(issue.detail).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Explains a pending accountability request and lets the user act on it.
struct AccountabilityGate: View {
    @EnvironmentObject private var model: AppModel
    let change: ProtectedChange

    var body: some View {
        if model.ledger.delay == .off {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 8) {
                switch model.status(of: change) {
                case .none, .expired?:
                    Text("This weakens protection, so it waits \(model.ledger.delay.title) after you request it.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("Request: \(change.title)") { Task { await model.requestChange(change) } }
                        .buttonStyle(.bordered)
                case .waiting(let remaining)?:
                    TimelineView(.periodic(from: .now, by: 30)) { _ in
                        let live = model.status(of: change)
                        if case .waiting(let left)? = live {
                            Label("Available in \(Format.duration(left))", systemImage: "hourglass")
                        } else {
                            Label("Available in \(Format.duration(remaining))", systemImage: "hourglass")
                        }
                    }
                    .font(.footnote)
                    Button("Cancel request", role: .cancel) { model.cancelChange(change) }
                        .font(.footnote)
                case .ready?:
                    Label("Approved — available for 12 hours", systemImage: "checkmark.circle")
                        .font(.footnote).foregroundStyle(.green)
                }
            }
        }
    }
}
