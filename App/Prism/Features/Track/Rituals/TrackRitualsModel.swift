//
//  TrackRitualsModel.swift
//  Prism
//

import Foundation
import HealthExportCore
import SomaUI

struct MindRitual: Equatable, Sendable, Identifiable {
    enum Kind: Equatable, Sendable {
        case breathe
        case walk
        case tag(String)
    }

    /// The reading a ritual is measured on.
    enum Reading: Equatable, Sendable {
        /// Evening and overnight HRV, the same day.
        case variability
        /// Deep sleep the night after: for rituals done at bedtime.
        case deepSleep
    }

    var kind: Kind
    var reading: Reading
    /// What the row reads: Breathe, 10 minutes.
    var title: String
    /// What a sentence calls it: Breathing.
    var name: String
    /// Typical length in minutes, when Health timed it.
    var minutes: Double?
    var days: Set<Date>
    var effect: EffectMath.Effect

    var id: String {
        switch kind {
        case .breathe: "breathe"
        case .walk: "walk"
        case .tag(let tag): "tag-\(tag)"
        }
    }

    var unit: String { reading == .variability ? "ms" : "min" }

    /// Signed with its unit, or nil when there is no clear effect yet.
    var value: String? {
        effect.delta.map { "\(MindMath.signed($0)) \(unit)" }
    }

    var detail: String {
        if effect.delta != nil {
            return reading == .variability
                ? "HRV, \(effect.held) of \(effect.tries) times"
                : "Deep sleep, \(effect.held) of \(effect.tries) nights"
        }
        switch effect.tries {
        case 0: return "No readings to compare yet"
        case 1: return "No clear effect yet, 1 try"
        default: return "No clear effect yet, \(effect.tries) tries"
        }
    }

    /// The move as a share of the bar's half width: ten milliseconds of HRV,
    /// or thirty minutes of deep sleep, fill it.
    var fraction: Double? {
        effect.delta.map { $0 / (reading == .variability ? 10 : 30) }
    }

    var isCost: Bool { effect.isCost(.higher) }

    /// The title of the card that offers it tonight.
    var offer: String {
        switch kind {
        case .breathe: "Breathe for \(Int((minutes ?? 10).rounded())) minutes"
        case .walk: "Walk outside for \(Int((minutes ?? 20).rounded())) minutes"
        case .tag: name
        }
    }
}

struct MindRituals: Equatable, Sendable {
    var rituals: [MindRitual]
    var thisWeek: Int?
    var bestEffect: String?
    var streak: Int?
    var reason: String
    /// The ritual the card offers tonight, or nil for the default breath.
    var tonight: MindRitual?
    var tonightDetail: String

    /// Whether any ritual has enough days on both sides to show an effect.
    var hasEffects: Bool { rituals.contains { $0.effect.delta != nil } }

    /// A session shorter than this is not counted as the ritual.
    static let breatheMinimumMinutes: Double = 3
    /// `HKWorkoutActivityType.walking`.
    static let walkingActivity = 52

    /// Which tags behave like rituals, and what each is measured on. A tag of
    /// the person's own joins when its title names one.
    static func reading(forTag id: String, title: String) -> MindRitual.Reading? {
        let text = (id + " " + title).lowercased()
        let evening = ["meditat", "breath", "yoga", "cold", "walk", "stretch"]
        let bedtime = ["sauna", "journal", "read", "bath", "no screens"]
        if bedtime.contains(where: text.contains) { return .deepSleep }
        if evening.contains(where: text.contains) { return .variability }
        return nil
    }

    static func make(from inputs: MindInputs, journal: MindJournal, calendar: Calendar, locale: Locale = .current) -> MindRituals {
        let words = PulseWording(calendar: calendar, locale: locale)
        let today = calendar.startOfDay(for: inputs.now)

        // Tonight is not over: today's outcome stays out.
        let evenings = MindDaily.eveningVariability(inputs.heartRateVariability, calendar: calendar).filter { $0.key < today }
        var deep: [Date: Double] = [:]
        for night in PulseNights.nights(from: inputs.sleep, calendar: calendar) {
            guard let minutes = night.deep.map({ $0 / 60 }),
                  let before = calendar.date(byAdding: .day, value: -1, to: night.day) else { continue }
            deep[before] = minutes
        }

        func outcome(_ reading: MindRitual.Reading) -> [Date: Double] {
            reading == .variability ? evenings : deep
        }

        var rituals: [MindRitual] = []

        let sessions = inputs.mindful.filter { $0.end.timeIntervalSince($0.start) / 60 >= breatheMinimumMinutes }
        if !sessions.isEmpty {
            let days = Set(sessions.map { calendar.startOfDay(for: $0.start) })
            let typical = PulseSignals.median(sessions.map { $0.end.timeIntervalSince($0.start) / 60 })
            rituals.append(MindRitual(
                kind: .breathe, reading: .variability,
                title: typical.map { "Breathe, \(words.whole($0)) minutes" } ?? "Breathe",
                name: "Breathing", minutes: typical, days: days,
                effect: EffectMath.effect(causeDays: days, outcome: evenings, better: .higher)
            ))
        }

        let walks = inputs.workouts.filter { Int($0.value) == walkingActivity }
        if !walks.isEmpty {
            let days = Set(walks.map { calendar.startOfDay(for: $0.start) })
            let typical = PulseSignals.median(walks.map { $0.end.timeIntervalSince($0.start) / 60 })
            rituals.append(MindRitual(
                kind: .walk, reading: .variability,
                title: typical.map { "Walk outside, \(words.whole($0)) minutes" } ?? "Walk outside",
                name: "A walk outside", minutes: typical, days: days,
                effect: EffectMath.effect(causeDays: days, outcome: evenings, better: .higher)
            ))
        }

        let tagIDs = Set(journal.tagsByDay.values.flatMap { $0 }).sorted()
        for id in tagIDs {
            let title = journal.titles[id] ?? id
            guard let reading = reading(forTag: id, title: title) else { continue }
            let days = journal.days(tagged: id)
            rituals.append(MindRitual(
                kind: .tag(id), reading: reading, title: title, name: title, minutes: nil, days: days,
                effect: EffectMath.effect(causeDays: days, outcome: outcome(reading), better: .higher)
            ))
        }

        // The clearest good effects first, then the ones still gathering days.
        rituals.sort { lhs, rhs in
            switch (lhs.fraction, rhs.fraction) {
            case let (l?, r?): return l > r
            case (.some, nil): return true
            case (nil, .some): return false
            case (nil, nil): return lhs.effect.tries > rhs.effect.tries
            }
        }

        let allDays = rituals.reduce(into: Set<Date>()) { $0.formUnion($1.days) }
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: inputs.now)?.start ?? today
        let thisWeek = rituals.isEmpty ? nil : rituals.reduce(0) { $0 + $1.days.filter { $0 >= weekStart }.count }
        let streak = rituals.isEmpty ? nil : MindMath.streak(allDays, today: today, calendar: calendar)

        let good = rituals.filter { ($0.effect.delta ?? 0) > 0 }
        let bestHRV = good.filter { $0.reading == .variability }.compactMap(\.effect.delta).max()

        let reason: String
        if let best = good.first, let value = best.value {
            var text = "\(best.name) \(best.reading == .variability ? "lifts your evening HRV" : "adds deep sleep") the most, \(value)."
            if good.count > 1 {
                text += " \(good[1].name) comes second."
            }
            reason = text
        } else if rituals.isEmpty {
            reason = "Nothing measured yet. Breathing sessions and walks from Apple Health, and rituals you tag in the Journal, show here with what they do for you."
        } else {
            reason = "Not enough days yet. Each ritual needs three days with it and three without before Soma states its effect."
        }

        let tonight = good.first
        let tonightDetail: String
        if let tonight, let value = tonight.value {
            let reading = tonight.reading == .variability ? "evening HRV" : "deep sleep"
            tonightDetail = "Your \(reading) runs \(value) after it, \(tonight.effect.held) of \(tonight.effect.tries) times."
        } else {
            tonightDetail = "Ten slow minutes. Soma measures what they do for you."
        }

        return MindRituals(
            rituals: rituals,
            thisWeek: thisWeek,
            bestEffect: bestHRV.map(MindMath.signed),
            streak: streak,
            reason: reason,
            tonight: tonight,
            tonightDetail: tonightDetail
        )
    }
}
