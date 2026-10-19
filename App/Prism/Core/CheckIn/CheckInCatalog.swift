//
//  CheckInCatalog.swift
//  Prism
//

import Foundation
import SomaUI

/// Every question Soma asks, each phrased as a question and short enough to
/// read in one glance, in the order it is worth asking.
///
/// The question is the whole card: no title sits over a row ("Alcohol") and
/// leaves the person to guess what is being asked.
nonisolated enum CheckInCatalog {
    static let all: [CheckInQuestion] = morning + evening

    static let morning: [CheckInQuestion] = [
        CheckInQuestion(
            id: "wake", text: "How did you wake up?", windows: [.morning],
            kind: .scale(low: "Groggy", high: "Refreshed", tone: .rising), destination: .wakeRating, aspect: .sleep
        ),
        CheckInQuestion(
            id: "rested", text: "How rested do you feel?", windows: [.morning],
            kind: .scale(low: "Exhausted", high: "Fully rested", tone: .rising), destination: .mindEnergy, aspect: .sleep
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
            id: "day", text: "How was your day?", windows: [.evening],
            kind: .scale(low: "Rough", high: "Great", tone: .rising), destination: .journalFeeling, aspect: .mind
        ),
        CheckInQuestion(
            id: "energy", text: "How much energy is left?", windows: [.evening],
            kind: .scale(low: "Drained", high: "Plenty", tone: .rising), destination: .homeEnergy, aspect: .activity
        ),
        CheckInQuestion(
            id: "stress", text: "How stressed was today?", windows: [.evening],
            kind: .scale(low: "Calm", high: "Very", tone: .falling), destination: .homeStress, aspect: .mind
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
            id: "focus", text: "How focused were you today?", windows: [.evening],
            kind: .scale(low: "Foggy", high: "Sharp", tone: .rising), destination: .mindFocus, aspect: .mind
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
                    text: "Resting HR up \(Int(rise)) bpm. Coming down with something?",
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
