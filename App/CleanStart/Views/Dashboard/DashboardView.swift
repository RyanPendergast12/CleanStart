import CleanStartCore
import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let assessment = model.assessment
        ScrollView {
            VStack(spacing: 16) {
                statusCard(assessment)
                if !assessment.issues.isEmpty { issuesCard(assessment) }
                todayCard
                detailsCard
            }
            .padding()
        }
        .navigationTitle("Today")
        .refreshable { await model.verifyFiltering() }
    }

    private func statusCard(_ assessment: ProtectionAssessment) -> some View {
        let color = Theme.color(for: assessment.level, highContrast: model.preferences.highContrastStatus)
        return Card {
            HStack(spacing: 16) {
                Image(systemName: Theme.symbol(for: assessment.level))
                    .font(.system(size: 44))
                    .foregroundStyle(color)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(assessment.headline).font(.title3.bold())
                    if let success = model.history.lastSuccessful {
                        Text("Last verified \(Format.relative(success.date)) on \(success.networkDescription)")
                            .font(.footnote).foregroundStyle(.secondary)
                    } else {
                        Text("Not verified yet").font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            Button {
                Task { await model.verifyFiltering() }
            } label: {
                if model.isVerifying {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    Label("Check filtering now", systemImage: "arrow.clockwise").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.bordered)
            .disabled(model.isVerifying)
        }
        .accessibilityElement(children: .contain)
    }

    private func issuesCard(_ assessment: ProtectionAssessment) -> some View {
        Card {
            Text("Attention").font(.headline)
            ForEach(assessment.issues) { issue in
                IssueRow(issue: issue)
            }
        }
    }

    private var todayCard: some View {
        let today = model.today
        let streak = model.habitLog.currentStreak(today: today)
        let entry = model.habitLog.checkIn(for: today)
        return Card {
            HStack {
                Text("Today").font(.headline)
                Spacer()
                if model.habitLog.streakTrackingEnabled {
                    Label("\(streak) day\(streak == 1 ? "" : "s")", systemImage: "flame")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }
            }
            Text(Encouragement.message(for: model.habitLog, today: today))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if entry == nil {
                HStack {
                    Button {
                        model.checkIn(.clean)
                    } label: {
                        Label("Porn-free today", systemImage: "checkmark").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    Button {
                        model.checkIn(.slipped)
                    } label: {
                        Text("I slipped").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                Label(entry?.status == .clean ? "Checked in: porn-free" : "Checked in: honest slip",
                      systemImage: entry?.status == .clean ? "checkmark.seal.fill" : "arrow.uturn.backward.circle")
                    .font(.subheadline)
            }
            WeekStrip(days: model.habitLog.recentSummary(today: today))
        }
    }

    private var detailsCard: some View {
        Card {
            Text("Status").font(.headline)
            StatusRow(title: "DNS configuration", value: model.dns.state.title, systemImage: "network")
            StatusRow(title: "Last check", value: model.history.latest?.verdict.title ?? "Never",
                      systemImage: "checklist", color: model.history.latest.map { Theme.color(for: $0.verdict) } ?? .secondary)
            StatusRow(title: "Screen Time", value: screenTimeText, systemImage: "hourglass")
            StatusRow(title: "Connection", value: model.network.description, systemImage: connectionSymbol)
            if model.network.vpnLikelyActive {
                StatusRow(title: "VPN", value: "Appears active", systemImage: "lock.shield", color: .orange)
            }
        }
    }

    private var screenTimeText: String {
        switch model.screenTime.state {
        case .approved: return model.restrictions.shieldsActive ? "Shields active" : "Authorized"
        case .denied: return "Declined"
        case .notDetermined: return "Not set up"
        case .unavailable: return "Unavailable"
        }
    }

    private var connectionSymbol: String {
        switch model.network.kind {
        case .wifi: return "wifi"
        case .cellular: return "antenna.radiowaves.left.and.right"
        case .offline: return "wifi.slash"
        default: return "network"
        }
    }
}

struct WeekStrip: View {
    let days: [(day: DayStamp, status: CheckInStatus?)]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(days, id: \.day) { item in
                VStack(spacing: 4) {
                    Circle()
                        .fill(fill(item.status))
                        .overlay(Circle().strokeBorder(.secondary.opacity(0.3)))
                        .frame(width: 22, height: 22)
                    Text(weekday(item.day)).font(.caption2).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(weekday(item.day)): \(label(item.status))")
            }
        }
    }

    private func fill(_ status: CheckInStatus?) -> Color {
        switch status {
        case .clean?: return Theme.accent
        case .slipped?: return .orange.opacity(0.6)
        case nil: return .clear
        }
    }

    private func label(_ status: CheckInStatus?) -> String {
        switch status {
        case .clean?: return "porn-free"
        case .slipped?: return "slipped"
        case nil: return "no check-in"
        }
    }

    private func weekday(_ day: DayStamp) -> String {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEEE")
        return formatter.string(from: day.date())
    }
}
