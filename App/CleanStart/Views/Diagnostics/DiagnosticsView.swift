import CleanStartCore
import SwiftUI
import UIKit

struct DiagnosticsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var copied = false

    var body: some View {
        List {
            Section {
                Button {
                    Task { await model.verifyFiltering() }
                } label: {
                    HStack {
                        Label("Run filtering check", systemImage: "play.circle")
                        Spacer()
                        if model.isVerifying { ProgressView() }
                    }
                }
                .disabled(model.isVerifying)
            } footer: {
                Text("Looks up a fixed list of test domains through the system resolver on \(model.network.description). Only DNS lookups — no website is opened and nothing is displayed.")
            }

            if let report = model.history.latest {
                Section {
                    Label(report.verdict.title, systemImage: report.verdict == .verified ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.color(for: report.verdict))
                        .font(.headline)
                    Text(report.explanation).font(.footnote)
                    ForEach(report.results) { result in
                        HStack(alignment: .top) {
                            Image(systemName: symbol(result.passed))
                                .foregroundStyle(color(result.passed))
                                .accessibilityLabel(Text(passLabel(result.passed)))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(result.purpose).font(.subheadline)
                                Text(result.outcomeSummary).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Latest check · \(Format.relative(report.date))")
                }
            }

            Section("Configuration vs. effectiveness") {
                LabeledContent("DNS configuration", value: model.dns.state.title)
                LabeledContent("Filtering check", value: model.history.latest?.verdict.title ?? "Never run")
                Text("The first line is what iOS reports about CleanStart's saved setting. The second is what actually happened when this iPhone looked up test domains. Only the second proves filtering.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section("Permissions") {
                LabeledContent("Screen Time", value: model.screenTime.state.rawValue.capitalized)
                LabeledContent("Shields", value: model.restrictions.shieldsActive ? "Active" : "Off")
                LabeledContent("Connection", value: model.network.description)
                LabeledContent("VPN detected", value: model.network.vpnLikelyActive ? "Yes" : "No")
            }

            if let error = model.dns.lastError ?? model.screenTime.lastError ?? model.restrictions.lastError {
                Section("Errors") {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
            }

            Section("History") {
                ForEach(Array(model.history.reports.reversed()), id: \.date) { report in
                    HStack {
                        Circle().fill(Theme.color(for: report.verdict)).frame(width: 10, height: 10)
                        Text(report.verdict.title)
                        Spacer()
                        Text("\(report.networkDescription) · \(Format.relative(report.date))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if !model.history.reports.isEmpty {
                    Button("Clear check history", role: .destructive) { model.clearVerificationHistory() }
                }
            }

            Section {
                Button(copied ? "Copied" : "Copy diagnostics summary") {
                    UIPasteboard.general.string = model.diagnosticsText
                    copied = true
                }
            } footer: {
                Text("Copies a plain-text summary to the clipboard. It contains no browsing data, IP addresses or network names, and CleanStart never sends it anywhere.")
            }

            Section("Restore & rollback") {
                NavigationLink("Safe removal and rollback steps") { UninstallGuideView() }
            }
        }
        .navigationTitle("Diagnostics")
    }

    private func symbol(_ passed: Bool?) -> String {
        switch passed {
        case true?: return "checkmark.circle.fill"
        case false?: return "xmark.circle.fill"
        case nil: return "questionmark.circle"
        }
    }

    private func passLabel(_ passed: Bool?) -> String {
        switch passed {
        case true?: return "Pass"
        case false?: return "Fail"
        case nil: return "Unknown"
        }
    }

    private func color(_ passed: Bool?) -> Color {
        switch passed {
        case true?: return .green
        case false?: return .red
        case nil: return .secondary
        }
    }
}
