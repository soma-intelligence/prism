//
//  TrackRitualSummary.swift
//  Prism
//

import Foundation
import HealthExportCore

/// What the Rituals part shows for one ritual: how far today is, the last
/// two weeks, the run of days kept, and what keeping it does for the person.
///
/// A day is kept when every step was ticked. The effect is ``EffectMath``'s,
/// on the days kept against the others: a morning ritual on that evening's
/// HRV, an evening ritual on the deep sleep of the night after it.
struct TrackRitualSummary: Equatable, Sendable {
    var moment: TrackRitualMoment
    /// Steps ticked today, of how many.
    var doneToday: Int
    var steps: Int
    /// The share of steps done on each of the last ``days`` days, oldest
    /// first, today last. Nil for a ritual with no steps.
    var shares: [Double?]
    /// Days kept in a row, counted back from today, or from yesterday while
    /// today is still open.
    var streak: Int
    /// Days kept in the last seven.
    var keptThisWeek: Int
    var effect: EffectMath.Effect

    /// How many days the strip shows.
    static let days = 14
    /// How far back the effect looks.
    static let effectDays = 60

    var isKeptToday: Bool { steps > 0 && doneToday == steps }

    /// "2 of 3", or nil with no steps, which a view draws as the missing mark.
    var progressText: String? { steps == 0 ? nil : "\(doneToday) of \(steps)" }

    /// "5 days running", "Kept yesterday", or nil with no run.
    var streakText: String? {
        switch streak {
        case 0: nil
        case 1: "1 day running"
        default: "\(streak) days running"
        }
    }

    /// The run of days kept, or the days kept this week, or nil when there
    /// is neither: a row of empty days says it already.
    var keptText: String? {
        streakText ?? (keptThisWeek > 0 ? "\(keptThisWeek) of 7 this week" : nil)
    }

    /// What keeping it does, in a few words: "+12 min deep sleep", "+4 ms
    /// HRV". Nil until there is a clear effect: no sentence asks the person
    /// to wait for one.
    var effectText: String? {
        guard let delta = effect.delta else { return nil }
        let signed = MindMath.signed(delta)
        guard signed != "0" else { return nil }
        return moment == .morning ? "\(signed) ms HRV" : "\(signed) min deep sleep"
    }

    @MainActor
    static func make(_ moment: TrackRitualMoment, store: TrackRitualStore, inputs: MindInputs?,
                     today: Date, calendar: Calendar) -> TrackRitualSummary {
        let start = calendar.startOfDay(for: today)
        let steps = store.ritual(moment).steps
        func day(_ back: Int) -> Date { calendar.date(byAdding: .day, value: -back, to: start) ?? start }

        let shares = (0..<days).reversed().map { store.share(moment, on: day($0)) }
        let kept = Set((0..<effectDays).map(day).filter { store.share(moment, on: $0) == 1 })
        let doneToday = steps.filter { store.isDone($0, on: start) }.count

        return TrackRitualSummary(
            moment: moment,
            doneToday: doneToday,
            steps: steps.count,
            shares: shares,
            streak: steps.isEmpty ? 0 : MindMath.streak(kept, today: start, calendar: calendar),
            keptThisWeek: (0..<7).filter { kept.contains(day($0)) }.count,
            effect: effect(moment, kept: kept, inputs: inputs, today: start, calendar: calendar)
        )
    }

    /// The ritual's effect on its reading, today left out: its outcome is
    /// not in yet.
    static func effect(_ moment: TrackRitualMoment, kept: Set<Date>, inputs: MindInputs?,
                       today: Date, calendar: Calendar) -> EffectMath.Effect {
        guard let inputs else { return EffectMath.Effect(delta: nil, held: 0, tries: 0) }
        let outcome: [Date: Double]
        switch moment {
        case .morning:
            outcome = MindDaily.eveningVariability(inputs.heartRateVariability, calendar: calendar).filter { $0.key < today }
        case .evening:
            var deep: [Date: Double] = [:]
            for night in PulseNights.nights(from: inputs.sleep, calendar: calendar) {
                guard let minutes = night.deep.map({ $0 / 60 }),
                      let before = calendar.date(byAdding: .day, value: -1, to: night.day) else { continue }
                deep[calendar.startOfDay(for: before)] = minutes
            }
            outcome = deep
        }
        return EffectMath.effect(causeDays: kept.filter { $0 < today }, outcome: outcome, better: .higher)
    }
}
