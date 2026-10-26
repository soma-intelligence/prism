//
//  CheckInEngine.swift
//  Prism
//

import Foundation

/// What one day of "Soma asks" holds: what was answered, what was skipped,
/// and where each window stands.
///
/// "Later" is never counted as done, so a morning put off is not a morning
/// lost. It only snoozes; a window is done when its last question is
/// behind the person, and only then.
nonisolated struct CheckInDayRecord: Codable, Equatable, Sendable {
    /// Answers by question id. An answered question is never asked again that
    /// day.
    var answers: [String: CheckInAnswer] = [:]
    /// The question text each answer was given to, for the data driven ones,
    /// whose words change with the numbers.
    var asked: [String: String] = [:]
    /// Questions passed over with Skip: not asked again that day.
    var skipped: Set<String> = []
    /// Windows put off with Later, and until when.
    var snoozedUntil: [CheckInWindow.RawValue: Date] = [:]
    /// Windows whose run reached its end: "Done for today".
    var finished: Set<CheckInWindow> = []
    /// Windows the app already opened on its own.
    var presented: Set<CheckInWindow> = []

    func isSettled(_ id: String) -> Bool {
        answers[id] != nil || skipped.contains(id)
    }

    func isSnoozed(_ window: CheckInWindow, at now: Date) -> Bool {
        guard let until = snoozedUntil[window.rawValue] else { return false }
        return until > now
    }

    mutating func answer(_ question: CheckInQuestion, with answer: CheckInAnswer) {
        answers[question.id] = answer
        skipped.remove(question.id)
        if question.isDataDriven { asked[question.id] = question.text }
    }

    mutating func skip(_ question: CheckInQuestion) {
        guard answers[question.id] == nil else { return }
        skipped.insert(question.id)
    }

    /// Later: the window comes back once the snooze runs out, and it is not
    /// done.
    mutating func snooze(_ window: CheckInWindow, at now: Date) {
        snoozedUntil[window.rawValue] = now.addingTimeInterval(CheckInEngine.snooze)
        presented.remove(window)
        finished.remove(window)
    }

    mutating func finish(_ window: CheckInWindow) {
        finished.insert(window)
        snoozedUntil[window.rawValue] = nil
    }

    mutating func markPresented(_ window: CheckInWindow) {
        presented.insert(window)
    }
}

/// Picks what to ask now. Pure: the clock, the day's record, the readings and
/// what is already logged go in, an ordered run of questions comes out.
nonisolated enum CheckInEngine {
    /// No run is longer than this.
    static let sessionLimit = 5
    /// How long Later puts a window off.
    static let snooze: TimeInterval = 2 * 60 * 60

    /// The run for `now`: empty outside the windows, once the window is done,
    /// and when nothing is left to ask. Data driven questions lead, strongest
    /// first, then the catalog in its own order.
    static func questions(
        now: Date,
        calendar: Calendar,
        record: CheckInDayRecord,
        signals: CheckInSignals,
        context: CheckInContext,
        catalog: [CheckInQuestion] = CheckInCatalog.all
    ) -> [CheckInQuestion] {
        guard let window = CheckInWindow.at(now, calendar: calendar),
              !record.finished.contains(window) else { return [] }
        let candidates = CheckInCatalog.dataDriven(signals) + catalog
        var seen: Set<String> = []
        let run = candidates.filter { question in
            question.windows.contains(window)
                && !record.isSettled(question.id)
                && isOpen(question, context: context)
                && isDue(question, now: now, calendar: calendar, context: context)
                && seen.insert(question.id).inserted
        }
        return Array(run.prefix(sessionLimit))
    }

    /// Whether the app may open the run by itself when it becomes active:
    /// inside a window, once per window, not while snoozed and not once done.
    /// A run put off with Later comes back on the first activation after the
    /// snooze.
    static func shouldPresentAutomatically(now: Date, calendar: Calendar, record: CheckInDayRecord) -> Bool {
        guard let window = CheckInWindow.at(now, calendar: calendar) else { return false }
        return !record.finished.contains(window)
            && !record.isSnoozed(window, at: now)
            && !record.presented.contains(window)
    }

    /// When a Later reminder should come: two hours on, as long as the window
    /// is still open then. Nil when the snooze would run past it.
    static func reminderDate(after now: Date, calendar: Calendar) -> Date? {
        guard let window = CheckInWindow.at(now, calendar: calendar) else { return nil }
        let when = now.addingTimeInterval(snooze)
        return when < window.end(on: now, calendar: calendar) ? when : nil
    }

    /// Whether a question asked less than daily has waited its days: a
    /// weekly one settled on Saturday comes back the next Saturday.
    static func isDue(_ question: CheckInQuestion, now: Date, calendar: Calendar, context: CheckInContext) -> Bool {
        guard question.everyDays > 1, let last = context.lastSettled[question.id] else { return true }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: last), to: calendar.startOfDay(for: now)).day ?? 0
        return days >= question.everyDays
    }

    /// Whether `question` still has something to learn, given what is already
    /// logged and what the app may write to.
    static func isOpen(_ question: CheckInQuestion, context: CheckInContext) -> Bool {
        switch question.destination {
        case .journalTag(let tag, let day):
            let tagged = day == .today ? context.tagsToday : context.tagsYesterday
            return context.offeredTags.contains(tag) && !tagged.contains(tag)
        case .journalFeeling:
            return !context.hasFeeling
        case .homeEnergy, .homeStress, .homeBody:
            return !context.homeCheckInElsewhere
        case .mindEnergy, .mindFocus:
            return context.mindAvailable
        case .bodyQuestion:
            return true
        case .wakeRating:
            return !context.hasWakeRating
        }
    }

    // MARK: Answers into the stores' scales

    /// The Journal's seven stops from the five steps, the ends kept at the
    /// ends.
    static func feelingStop(fromStep step: Int) -> Int {
        [0, 2, 3, 4, 6][min(max(step, 1), 5) - 1]
    }

    /// Mind's 0...4 from the five steps.
    static func mindStep(fromStep step: Int) -> Int {
        min(max(step, 1), 5) - 1
    }

    /// The evening check-in written from the day's answers, laid over the one
    /// already kept. What was never answered keeps the existing value, or the
    /// middle of the scale the check-in sheet itself starts on.
    @MainActor
    static func homeCheckIn(
        from answers: [String: CheckInAnswer],
        over existing: HomeCheckIn?,
        on date: Date,
        catalog: [CheckInQuestion] = CheckInCatalog.all
    ) -> HomeCheckIn? {
        var energy: Int?
        var stress: Int?
        var body: HomeBodyFeel?
        for question in catalog {
            guard let answer = answers[question.id] else { continue }
            switch (question.destination, answer) {
            case (.homeEnergy, _): if let step = answer.step { energy = min(max(step, 1), 5) }
            case (.homeStress, _): if let step = answer.step { stress = min(max(step, 1), 5) }
            case (.homeBody, .yes): body = .sore
            case (.homeBody, .no): body = existing?.body == .fresh ? .fresh : .normal
            default: continue
            }
        }
        guard energy != nil || stress != nil || body != nil else { return nil }
        var checkIn = existing ?? HomeCheckIn(date: date, energy: 3, stress: 3, body: .normal, tags: [])
        checkIn.date = date
        if let energy { checkIn.energy = energy }
        if let stress { checkIn.stress = stress }
        if let body { checkIn.body = body }
        return checkIn
    }
}
