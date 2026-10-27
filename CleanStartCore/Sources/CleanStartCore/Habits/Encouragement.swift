import Foundation

/// Supportive, non-punitive feedback. Slips are treated as information, not failure.
public enum Encouragement {
    public static func message(for log: HabitLog, today: DayStamp, calendar: Calendar = .current) -> String {
        let todayEntry = log.checkIn(for: today)
        let streak = log.currentStreak(today: today, calendar: calendar)

        switch todayEntry?.status {
        case .slipped:
            return pick(from: afterSlip, seed: today)
        case .clean:
            if let milestone = milestones.first(where: { $0.days == streak }) {
                return milestone.text
            }
            if streak <= 1 { return pick(from: freshStart, seed: today) }
            return pick(from: keepGoing, seed: today) + " \(streak) days in a row."
        case nil:
            if log.checkIns.isEmpty { return "Welcome. Checking in once a day is enough — small, honest steps add up." }
            return "How did today go? A quick, honest check-in keeps you connected to why you started."
        }
    }

    static let milestones: [(days: Int, text: String)] = [
        (3, "Three days. The first stretch is often the hardest — you're through it."),
        (7, "One full week. That's a real change in rhythm."),
        (14, "Two weeks. Your new default is taking shape."),
        (30, "Thirty days. A month of choosing what you actually want."),
        (90, "Ninety days. This is a genuine reset — be proud of it."),
        (365, "A full year. What a way to start your mid-twenties."),
    ]

    static let freshStart = [
        "Day one counts. Every streak starts exactly here.",
        "A clean start, just like the name. Nice work today.",
    ]

    static let keepGoing = [
        "Steady progress.",
        "You're building something that lasts.",
        "Another day on your terms.",
    ]

    static let afterSlip = [
        "Thanks for being honest. A slip is a data point, not a verdict — tomorrow is a clean start.",
        "Recording this takes courage. Notice what led here, be kind to yourself, and begin again.",
        "One day doesn't erase your progress. Your total clean days still count.",
    ]

    private static func pick(from options: [String], seed: DayStamp) -> String {
        options[abs(seed.year * 372 + seed.month * 31 + seed.day) % options.count]
    }
}
