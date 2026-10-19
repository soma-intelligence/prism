//
//  CheckInWriter.swift
//  Prism
//

import Foundation

/// Writes each answer where it belongs, so "Soma asks" keeps no second copy
/// of anything another surface already records: tags and the feeling in the
/// Journal, energy, stress and the body in the Pulse home's evening check-in,
/// the wake rating in Track, and energy, focus and the body's questions in
/// Mind once Mind is on.
@MainActor
struct CheckInWriter {
    var journal: JournalStore?
    var home: HomeLog = .shared
    var mind: MindStore = .shared
    var track: TrackLogStore = .shared
    var calendar: Calendar = .current

    /// Writes one answer at once. Mind's answers wait for ``writeMind(_:now:)``
    /// at the end of the run, so a run makes one Mind check-in rather than one
    /// per question.
    func write(_ question: CheckInQuestion, _ answer: CheckInAnswer, answers: [String: CheckInAnswer], now: Date) {
        switch (question.destination, answer) {
        case (.journalTag(let tag, let day), .yes):
            setTag(tag, on: date(day, now: now), to: true)
        case (.journalTag(let tag, let day), .no):
            setTag(tag, on: date(day, now: now), to: false)
        case (.journalFeeling, .scale(let step)):
            journal?.setFeeling(CheckInEngine.feelingStop(fromStep: step), on: now)
        case (.homeEnergy, _), (.homeStress, _), (.homeBody, _):
            if let checkIn = CheckInEngine.homeCheckIn(from: answers, over: home.checkIn(on: now), on: now) {
                home.addCheckIn(checkIn)
            }
        case (.wakeRating, .scale(let step)):
            track.setWakeFeel(step, on: now)
        case (.wakeRating, .number(let rating)):
            track.setWakeRating(rating, on: now)
        default:
            break
        }
    }

    /// The run's Mind check-in, when Mind is on and the run answered anything
    /// of Mind's. The first question the body asked rides in it; any further
    /// one gets a check-in of its own, since a check-in holds one.
    func writeMind(_ answered: [(question: CheckInQuestion, answer: CheckInAnswer)], now: Date) {
        guard mind.consent.isGiven else { return }
        var energy: Int?
        var focus: Int?
        var asked: [(String, MindCheckIn.Answer)] = []
        for (question, answer) in answered {
            switch (question.destination, answer) {
            case (.mindEnergy, .scale(let step)): energy = CheckInEngine.mindStep(fromStep: step)
            case (.mindFocus, .scale(let step)): focus = CheckInEngine.mindStep(fromStep: step)
            case (.bodyQuestion, .yes): asked.append((question.text, .yes))
            case (.bodyQuestion, .no): asked.append((question.text, .no))
            default: continue
            }
        }
        guard energy != nil || focus != nil || !asked.isEmpty else { return }
        mind.add(MindCheckIn(date: now, energy: energy, focus: focus, question: asked.first?.0, answer: asked.first?.1))
        for (question, answer) in asked.dropFirst() {
            mind.add(MindCheckIn(date: now, question: question, answer: answer))
        }
    }

    private func date(_ day: CheckInDay, now: Date) -> Date {
        switch day {
        case .today: now
        case .yesterday: calendar.date(byAdding: .day, value: -1, to: now) ?? now
        }
    }

    private func setTag(_ tag: String, on date: Date, to isOn: Bool) {
        guard let journal, journal.day(date).tags.contains(tag) != isOn else { return }
        journal.toggle(tag, on: date)
    }
}
