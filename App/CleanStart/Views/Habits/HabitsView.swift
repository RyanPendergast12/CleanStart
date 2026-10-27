import CleanStartCore
import SwiftUI

struct HabitsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var note = ""
    @State private var selectedDayOffset = 0
    @State private var newGoalTitle = ""
    @State private var newGoalDays = 30

    var body: some View {
        let today = model.today
        let log = model.habitLog
        List {
            Section {
                Picker("Day", selection: $selectedDayOffset) {
                    Text("Today").tag(0)
                    Text("Yesterday").tag(-1)
                    Text("2 days ago").tag(-2)
                }
                .pickerStyle(.segmented)
                let day = today.adding(days: selectedDayOffset)
                if let entry = log.checkIn(for: day) {
                    Label(entry.status == .clean ? "Recorded: porn-free" : "Recorded: slipped",
                          systemImage: entry.status == .clean ? "checkmark.seal.fill" : "arrow.uturn.backward.circle")
                }
                TextField("Private note (optional)", text: $note, axis: .vertical)
                HStack {
                    Button {
                        model.checkIn(.clean, for: day, note: note); note = ""
                    } label: {
                        Text("Porn-free").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    Button {
                        model.checkIn(.slipped, for: day, note: note); note = ""
                    } label: {
                        Text("I slipped").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            } header: {
                Text("Check in")
            } footer: {
                Text(Encouragement.message(for: log, today: today))
            }

            Section("Progress") {
                Toggle("Track streaks", isOn: $model.habitLog.streakTrackingEnabled)
                if log.streakTrackingEnabled {
                    LabeledContent("Current streak", value: "\(log.currentStreak(today: today)) days")
                    LabeledContent("Best streak", value: "\(log.bestStreak()) days")
                }
                LabeledContent("Total porn-free days", value: "\(log.totalCleanDays)")
                WeekStrip(days: log.recentSummary(today: today))
                    .padding(.vertical, 4)
            }

            Section {
                ForEach(log.goals) { goal in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(goal.title)
                            Spacer()
                            Text("\(min(log.currentStreak(today: today), goal.targetDays))/\(goal.targetDays)")
                                .monospacedDigit().foregroundStyle(.secondary)
                        }
                        ProgressView(value: log.progress(toward: goal, today: today))
                    }
                    .accessibilityElement(children: .combine)
                }
                .onDelete { model.habitLog.goals.remove(atOffsets: $0) }
                HStack {
                    TextField("New goal", text: $newGoalTitle)
                    Stepper("\(newGoalDays)d", value: $newGoalDays, in: 1...365)
                        .fixedSize()
                }
                Button("Add goal") {
                    let title = newGoalTitle.trimmingCharacters(in: .whitespaces)
                    model.habitLog.goals.append(HabitGoal(title: title.isEmpty ? "\(newGoalDays) days" : title, targetDays: newGoalDays))
                    newGoalTitle = ""
                }
            } header: {
                Text("Goals")
            } footer: {
                Text("Goals track your current streak. A slip resets the streak, but never your total.")
            }

            Section("History") {
                if log.checkIns.isEmpty {
                    Text("No check-ins yet.").foregroundStyle(.secondary)
                }
                ForEach(Array(log.checkIns.reversed().prefix(60)), id: \.day) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(entry.day.date(), style: .date)
                            Spacer()
                            Text(entry.status == .clean ? "Porn-free" : "Slipped")
                                .foregroundStyle(entry.status == .clean ? Theme.accent : .orange)
                        }
                        if let note = entry.note { Text(note).font(.footnote).foregroundStyle(.secondary) }
                    }
                }
            }

            Section {
                Text("CleanStart is designed to sit alongside your Finch routine. It doesn't read or write Finch data — there's no supported integration — so keep your Finch goals there and use this for the porn-free check-in.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Habits")
    }
}
