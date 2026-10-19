//
//  CheckInQuestion.swift
//  Prism
//
//  The words of "Soma asks": what a question is, when it may be asked, how it
//  is answered and where the answer goes. Pure values, so the engine that picks
//  them is tested without a store.
//

import Foundation
import SomaUI

/// When in the day a question may be asked. Outside both, nothing is asked.
nonisolated enum CheckInWindow: String, Codable, CaseIterable, Sendable {
    /// 05:00 to 12:00: last night and how the day starts.
    case morning
    /// 18:00 to midnight: how the day went.
    case evening

    /// The hours the window covers, start inclusive, end exclusive.
    var hours: Range<Int> {
        switch self {
        case .morning: 5..<12
        case .evening: 18..<24
        }
    }

    /// The window `date` falls in, or nil between them.
    static func at(_ date: Date, calendar: Calendar) -> CheckInWindow? {
        let hour = calendar.component(.hour, from: date)
        return allCases.first { $0.hours.contains(hour) }
    }

    /// When the window closes on the day of `date`.
    func end(on date: Date, calendar: Calendar) -> Date {
        let day = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .hour, value: hours.upperBound, to: day) ?? day
    }
}

/// How a question is answered.
nonisolated enum CheckInAnswerKind: Equatable, Sendable {
    /// Two big pills.
    case yesNo
    /// Five steps, 1 to 5, a word under each end, coloured the way the
    /// scale runs.
    case scale(low: String, high: String, tone: SomaScaleTone)
    /// A whole number set with a stepper.
    case number(range: ClosedRange<Int>, start: Int, unit: String?)
}

/// What a person said.
nonisolated enum CheckInAnswer: Codable, Equatable, Sendable {
    case yes
    case no
    /// 1...5.
    case scale(Int)
    case number(Int)
}

/// The day a Journal tag lands on. A morning question about last night belongs
/// to yesterday, the day the drink or the screen happened on.
nonisolated enum CheckInDay: String, Codable, Sendable {
    case today
    case yesterday
}

/// Where an answer is written.
nonisolated enum CheckInDestination: Equatable, Sendable {
    /// A Journal tag, on for yes and off for no.
    case journalTag(String, day: CheckInDay)
    /// The Journal's feeling for today, from the five steps.
    case journalFeeling
    /// The evening check-in's energy, 1...5.
    case homeEnergy
    /// The evening check-in's stress, 1...5.
    case homeStress
    /// The evening check-in's body: yes is sore, no is normal.
    case homeBody
    /// Mind's check-in energy, 0...4. Asked only once Mind is on.
    case mindEnergy
    /// Mind's check-in focus, 0...4. Asked only once Mind is on.
    case mindFocus
    /// A question the body asked, kept with its answer: in Mind's check-in when
    /// Mind is on, and in the check-in record always.
    case bodyQuestion
    /// How the person woke, Track's wake rating for today: five steps land on
    /// its ten as Pulse's five words do, a count on it as it is.
    case wakeRating
}

/// One question.
nonisolated struct CheckInQuestion: Identifiable, Equatable, Sendable {
    /// Stable across days: the record of what was answered keys on it.
    var id: String
    var text: String
    var windows: Set<CheckInWindow>
    var kind: CheckInAnswerKind
    var destination: CheckInDestination
    /// The aspect the question is about: its hue fills the Yes pill.
    var aspect: SomaAspect
    /// Written from today's readings rather than taken from the catalog.
    var isDataDriven = false
}

/// The readings a data driven question is written from. Nil is "not
/// measured", and a question that needs it is not asked.
nonisolated struct CheckInSignals: Equatable, Sendable {
    /// Minutes asleep last night.
    var lastNightSleepMinutes: Double?
    /// The median of the nights before it.
    var usualSleepMinutes: Double?
    /// Today's resting heart rate, or yesterday's when today has none yet.
    var restingHeartRate: Double?
    /// The median of the fortnight before.
    var usualRestingHeartRate: Double?

    static let none = CheckInSignals()
}

/// What the person has already logged elsewhere today, and what the app may
/// write to. A question whose answer is already known is not asked.
nonisolated struct CheckInContext: Equatable, Sendable {
    /// The Journal tags on offer: a tag switched off in Customize is not asked
    /// about.
    var offeredTags: Set<String> = []
    var tagsToday: Set<String> = []
    var tagsYesterday: Set<String> = []
    /// Today's Journal feeling is already set.
    var hasFeeling = false
    /// This morning's wake rating is already set.
    var hasWakeRating = false
    /// The evening check-in was filled in from its own sheet.
    var homeCheckInElsewhere = false
    /// Mind is on (its consent was given), so its check-in may be written.
    var mindAvailable = false
}
