//
//  CheckInCatalog.swift
//  Prism
//

import Foundation
import SomaUI

/// Every question Soma asks, each phrased as a question and short enough to
/// read in one glance, in the order it is worth asking. Every one is a yes
/// or no, as Whoop's journal asks (owner, 2026-10-24): the questions that
/// were scales are phrased so a yes is the scale's high end, which is where
/// ``CheckInAnswer/step`` puts it.
///
/// The question is the whole card: no title sits over a row ("Alcohol") and
/// leaves the person to guess what is being asked.
nonisolated enum CheckInCatalog {
    static let all: [CheckInQuestion] = morning + evening

    static let morning: [CheckInQuestion] = [
        CheckInQuestion(
            id: "wake", text: "Woke up refreshed?", windows: [.morning],
            kind: .yesNo, destination: .wakeRating, aspect: .sleep
        ),
        CheckInQuestion(
            id: "rested", text: "Feeling rested?", windows: [.morning],
            kind: .yesNo, destination: .mindEnergy, aspect: .sleep
        ),
        CheckInQuestion(
            id: "alcohol", text: "Did you drink alcohol yesterday?", windows: [.morning],
            kind: .yesNo, destination: .journalTag("alcohol", day: .yesterday), aspect: .heart
        ),
        CheckInQuestion(
            id: "screens-in-bed", text: "Screens in bed last night?", windows: [.morning],
            kind: .yesNo, destination: .journalTag("screens-in-bed", day: .yesterday), aspect: .sleep
        ),
        CheckInQuestion(
            id: "late-meal", text: "Did you eat late last night?", windows: [.morning],
            kind: .yesNo, destination: .journalTag("late-meal", day: .yesterday), aspect: .gut
        ),
    ]

    static let evening: [CheckInQuestion] = [
        CheckInQuestion(
            id: "day", text: "Good day overall?", windows: [.evening],
            kind: .yesNo, destination: .journalFeeling, aspect: .mind
        ),
        // Bleeding gums when brushing are the first sign of gingivitis (ADA).
        // Once a week is enough to see it last, and second in the evening so
        // the session limit never pushes it out on the day it is due.
        CheckInQuestion(
            id: "gums", text: "Gums bleed when brushing?", windows: [.evening],
            kind: .yesNo, destination: .journalTag(OralTag.gumsBleed, day: .today), aspect: .body,
            everyDays: 7
        ),
        CheckInQuestion(
            id: "energy", text: "Energy left tonight?", windows: [.evening],
            kind: .yesNo, destination: .homeEnergy, aspect: .activity
        ),
        CheckInQuestion(
            id: "stress", text: "Stressful day?", windows: [.evening],
            kind: .yesNo, destination: .homeStress, aspect: .mind
        ),
        // Strong social ties go with a longer life (Holt-Lunstad, Smith and
        // Layton, PLoS Med 2010). Asked every evening, right after stress,
        // so the session limit keeps it in the run; a yes writes the Journal
        // tag Mind's connection page counts.
        CheckInQuestion(
            id: "people", text: "Time with people you care about today?", windows: [.evening],
            kind: .yesNo, destination: .journalTag(SocialTag.timeWithPeople, day: .today), aspect: .mind
        ),
        CheckInQuestion(
            id: "coffee-late", text: "Coffee after 14:00?", windows: [.evening],
            kind: .yesNo, destination: .journalTag("coffee-late", day: .today), aspect: .sleep
        ),
        CheckInQuestion(
            id: "sore", text: "Any aches or soreness?", windows: [.evening],
            kind: .yesNo, destination: .homeBody, aspect: .body
        ),
        CheckInQuestion(
            id: "hard-training", text: "Hard training today?", windows: [.evening],
            kind: .yesNo, destination: .journalTag("hard-training", day: .today), aspect: .activity
        ),
        CheckInQuestion(
            id: "meditation", text: "Did you meditate today?", windows: [.evening],
            kind: .yesNo, destination: .journalTag("meditation", day: .today), aspect: .mind
        ),
        CheckInQuestion(
            id: "sauna", text: "Sauna today?", windows: [.evening],
            kind: .yesNo, destination: .journalTag("sauna", day: .today), aspect: .heart
        ),
        CheckInQuestion(
            id: "focus", text: "Focused today?", windows: [.evening],
            kind: .yesNo, destination: .mindFocus, aspect: .mind
        ),
    ]

    // MARK: Data driven

    /// Last night this much under the usual is worth asking about.
    static let shortNightMinutes = 30.0
    /// And this much over it.
    static let longNightMinutes = 60.0
    /// A resting heart rate this many beats over the usual.
    static let restingRiseBeats = 3.0

    /// The questions today's readings ask, strongest first. Each needs both
    /// of its numbers: a question about "usual" with no usual is not asked.
    static func dataDriven(_ signals: CheckInSignals) -> [CheckInQuestion] {
        var asked: [(strength: Double, question: CheckInQuestion)] = []

        if let slept = signals.lastNightSleepMinutes, let usual = signals.usualSleepMinutes {
            let short = usual - slept
            if short >= shortNightMinutes {
                asked.append((short / shortNightMinutes, CheckInQuestion(
                    id: "data.sleep-short",
                    text: "Slept \(span(short)) less than usual. Feeling it?",
                    windows: [.morning], kind: .yesNo, destination: .bodyQuestion, aspect: .sleep, isDataDriven: true
                )))
            } else if -short >= longNightMinutes {
                asked.append((-short / longNightMinutes, CheckInQuestion(
                    id: "data.sleep-long",
                    text: "Slept \(span(-short)) more than usual. Catching up?",
                    windows: [.morning], kind: .yesNo, destination: .bodyQuestion, aspect: .sleep, isDataDriven: true
                )))
            }
        }

        if let resting = signals.restingHeartRate, let usual = signals.usualRestingHeartRate {
            let rise = (resting - usual).rounded()
            if rise >= restingRiseBeats {
                asked.append((rise / restingRiseBeats, CheckInQuestion(
                    id: "data.resting-up",
                    text: "Resting heart rate is \(Int(rise)) bpm above your usual. How do you feel?",
                    windows: [.morning, .evening], kind: .yesNo, destination: .bodyQuestion, aspect: .heart, isDataDriven: true
                )))
            }
        }

        return asked.sorted { $0.strength > $1.strength }.map(\.question)
    }

    /// Minutes as the question says them, to the nearest five: "50 min",
    /// "1 h 10".
    static func span(_ minutes: Double) -> String {
        let rounded = max(5, Int((minutes / 5).rounded()) * 5)
        if rounded < 60 { return "\(rounded) min" }
        let rest = rounded % 60
        return rest == 0 ? "\(rounded / 60) h" : String(format: "%d h %02d", rounded / 60, rest)
    }
}
