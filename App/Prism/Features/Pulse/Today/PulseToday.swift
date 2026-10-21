//
//  PulseToday.swift
//  Prism
//

import Foundation
import HealthExportCore
import SomaUI

/// Everything the Today page shows, worked out from what Apple Health holds.
///
/// Every value is optional, and nil renders as a dash: not measured is not
/// zero. The row under the orb carries Soma's three 0 to 100 scores (sleep,
/// Mind and activity) and the energy card the energy bank, all from
/// ``SomaScores``; the aspect cards below keep the raw values they are built
/// from.
struct PulseToday: Equatable {
    /// One value in the row under the orb.
    struct Reading: Equatable {
        var value: String?
        var trend: SomaTrend?
    }

    /// One thing to do next, and the numbers that ask for it.
    struct Move: Equatable, Identifiable {
        var id: SomaAspect { aspect }
        var aspect: SomaAspect
        var title: String
        var reason: String
        /// The engine's id for the move, which the history keys on.
        var moveID: String = ""
        /// The two words the orb wears.
        var orb: String = ""
        /// One line from the evidence: what asked for the move.
        var why: String = ""

        init(aspect: SomaAspect, title: String, reason: String, moveID: String = "", orb: String = "", why: String = "") {
            self.aspect = aspect
            self.title = title
            self.reason = reason
            self.moveID = moveID
            self.orb = orb
            self.why = why
        }

        init(_ candidate: NextMoveCandidate) {
            self.init(
                aspect: candidate.aspect, title: candidate.title, reason: candidate.message,
                moveID: candidate.id, orb: candidate.orbWord, why: candidate.why
            )
        }
    }

    /// The words of one aspect card.
    struct Card: Equatable {
        var value: String?
        var summary: String
    }

    /// The aspect the day turns on, which the orb opens on. Nil when nothing
    /// stands out, or nothing was measured.
    var carrying: SomaAspect?
    var headline: String
    var reason: String

    var movesTitle: String
    var moves: [Move]
    /// What the orb says now: the engine's winner, or the calm default. Nil
    /// when nothing was read, so the orb claims nothing.
    var cue: Move?
    /// The calm default for this part of the day, for when every move has
    /// been ticked off.
    var steady: Move?

    var sleep: Reading
    var mind: Reading
    var activity: Reading

    /// The energy bank's level in 0...1: nil until the bank has seen a night.
    var energyLevel: Double?
    var energyNote: String

    var events: [SomaTimelineEvent]

    var sleepCard: Card
    /// Hours asleep on each of the last seven nights, oldest first.
    var nights: [Double?]
    var heartCard: Card
    /// Resting heart rate on each of the last fourteen days, oldest first.
    var restingDays: [Double?]
    /// The middle half of the last month's resting rates.
    var restingBand: ClosedRange<Double>?
    var bodyCard: Card
    var age: Int?

    /// Whether the store held anything at all for today.
    var hasData: Bool
}

extension PulseToday {
    /// The page for `inputs`.
    ///
    /// The moves and the orb's cue come from the Next move engine. `context`
    /// carries what the person logged when the caller read it; without it the
    /// engine reads Health alone.
    static func make(
        from inputs: PulseInputs,
        scores: SomaScores? = nil,
        context: NextMoveContext? = nil,
        history: NextMoveHistory = .empty,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> PulseToday {
        PulseTodayBuilder(
            inputs: inputs,
            scores: scores,
            context: context ?? NextMoveContext.make(inputs: inputs, scores: scores, calendar: calendar),
            history: history,
            calendar: calendar,
            words: PulseWording(calendar: calendar, locale: locale)
        ).build()
    }
}

/// The arithmetic behind the page, in the order the page reads.
private struct PulseTodayBuilder {
    let inputs: PulseInputs
    let scores: SomaScores?
    let context: NextMoveContext
    let history: NextMoveHistory
    let calendar: Calendar
    let words: PulseWording

    var now: Date { inputs.now }
    var today: Date { calendar.startOfDay(for: now) }

    func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: today) ?? today
    }

    func build() -> PulseToday {
        let nights = PulseNights.nights(from: inputs.sleep, calendar: calendar)
        let lastNight = nights.last { $0.day == today && $0.woke <= now }
        let resting = restingHeart()

        let workouts = PulseSignals.workouts(
            inputs.workouts.filter { $0.start >= today },
            steps: inputs.workoutSteps,
            heartRate: inputs.heartRate,
            age: inputs.age
        )
        let peaks = PulseSignals.peaks(
            heartRate: inputs.heartRate,
            since: lastNight?.woke ?? today,
            resting: resting.latest ?? resting.usual,
            steps: inputs.steps,
            stepsToday: inputs.stepsToday,
            workouts: workouts
        )

        // The engine ranks the moves for this part of the person's day. The
        // card lists what was ticked off too; the orb moves past it.
        let arbiter = NextMoveArbiter()
        let ranked = arbiter.rank(context, history: history.listing)
        var seen: Set<SomaAspect> = []
        let moves = ranked.filter { seen.insert($0.aspect).inserted }.prefix(3).map { PulseToday.Move($0) }
        let hasData = !inputs.isEmpty
        let cue = hasData ? PulseToday.Move(arbiter.cue(context, history: history)) : nil
        let (headline, reason) = hasData
            ? (cue?.title ?? "", cue?.reason ?? "")
            : ("Nothing to read yet.",
               "Apple Health holds no sleep, heart or activity for today. The page fills in as your watch and phone record them.")

        let week = (-6...0).map { offset in nights.first { $0.day == day(offset) } }
        let lowest = lowestOvernight(lastNight)

        return PulseToday(
            carrying: moves.first?.aspect,
            headline: headline,
            reason: reason,
            movesTitle: words.movesTitle(context.part),
            moves: Array(moves),
            cue: cue,
            steady: hasData ? PulseToday.Move(NextMoveSteady.cue(context)) : nil,
            // The three scores. Mind is recovery, or 100 minus stress on a day
            // without recovery: see `SomaScores.mind`.
            sleep: PulseToday.Reading(value: scores?.sleep.map(words.score), trend: scores?.sleepTrend),
            mind: PulseToday.Reading(value: scores?.mind.map(words.score), trend: scores?.mindTrend),
            activity: PulseToday.Reading(value: scores?.strain.map(words.score), trend: scores?.strainTrend),
            energyLevel: scores?.energy.map { Double($0) / 100 },
            energyNote: words.energyNote(scores),
            events: events(lastNight: lastNight, workouts: workouts, peaks: peaks),
            sleepCard: PulseToday.Card(
                value: lastNight.map { words.clock($0.asleep) },
                summary: words.sleepSummary(lastNight, week: week.compactMap { $0 })
            ),
            nights: week.map { $0.map { $0.asleep / 3600 } },
            heartCard: PulseToday.Card(
                value: resting.latest.map { words.whole($0) },
                summary: resting.latest.map { words.heartSummary(resting: $0, usual: resting.usual, lowest: lowest) }
                    ?? "No resting heart rate recorded yet."
            ),
            restingDays: (-13...0).map { resting.daily[day($0)] },
            restingBand: resting.band,
            bodyCard: {
                let fitness = BodyFitnessAge.stat(vo2Max: inputs.vo2Max, age: inputs.age, sex: inputs.sex)
                return PulseToday.Card(value: fitness.value, summary: words.bodySummary(fitness))
            }(),
            age: inputs.age,
            hasData: hasData
        )
    }

    // MARK: - Signals

    struct Resting {
        var latest: Double?
        var latestDay: Date?
        var usual: Double?
        var band: ClosedRange<Double>?
        var daily: [Date: Double]
    }

    /// The latest resting rate, if it is from the last day and a half, against
    /// the median and the middle half of the month before it.
    func restingHeart() -> Resting {
        let daily = PulseSignals.daily(inputs.restingHeartRate.filter { $0.start >= day(-30) }, calendar: calendar) {
            PulseSignals.median($0)
        }
        let latestReading = inputs.restingHeartRate
            .filter { $0.start <= now && now.timeIntervalSince($0.end) < 36 * 60 * 60 }
            .max { $0.end < $1.end }
        let latestDay = latestReading.map { calendar.startOfDay(for: $0.start) }
        let earlier = daily.filter { day, _ in latestDay.map { day < $0 } ?? (day < today) }.map(\.value)
        let usual = earlier.count >= 5 ? PulseSignals.median(earlier) : nil
        var band: ClosedRange<Double>?
        if earlier.count >= 5, let low = PulseSignals.percentile(earlier, 0.25), let high = PulseSignals.percentile(earlier, 0.75) {
            band = low...max(high, low)
        }
        return Resting(
            latest: latestDay.flatMap { daily[$0] } ?? latestReading?.value,
            latestDay: latestDay,
            usual: usual,
            band: band,
            daily: daily
        )
    }

    /// The lowest heart rate while asleep last night, and when.
    func lowestOvernight(_ night: PulseNight?) -> (value: Double, at: Date)? {
        guard let night else { return nil }
        return inputs.heartRate
            .filter { $0.start >= night.fellAsleep && $0.start <= night.woke }
            .min { $0.value < $1.value }
            .map { ($0.value, $0.start) }
    }

    // MARK: - The timeline

    /// The day as events, each with its numbers as glyph and value stats
    /// (the card draws those rather than the sentence, which stays as the
    /// fallback and the spoken detail), its span, hue and symbol.
    func events(lastNight: PulseNight?, workouts: [PulseWorkout], peaks: [PulsePeak]) -> [SomaTimelineEvent] {
        var dated: [(Date, SomaTimelineEvent)] = []

        if let lastNight {
            var stats = [SomaTimelineStat(symbol: "bed.double.fill", text: words.clock(lastNight.asleep))]
            if let deep = lastNight.deep { stats.append(SomaTimelineStat(symbol: "moon.zzz.fill", text: words.minutes(deep))) }
            dated.append((lastNight.woke, SomaTimelineEvent(
                id: "wake", time: words.time(lastNight.woke), title: "Woke up",
                detail: words.wokeUp(lastNight), aspect: .sleep,
                hue: .sleep, symbol: "sun.horizon.fill", stats: stats,
                start: lastNight.fellAsleep, end: lastNight.woke
            )))
        }
        for workout in workouts {
            var stats = [SomaTimelineStat(symbol: "timer", text: "\(words.whole(workout.minutes)) min")]
            if let steps = workout.steps { stats.append(SomaTimelineStat(symbol: "figure.walk", text: words.whole(steps))) }
            if let zone = workout.zoneThreeMinutes { stats.append(SomaTimelineStat(symbol: "flame.fill", text: "\(Int(zone.rounded())) min z3+")) }
            if let average = workout.averageHeartRate { stats.append(SomaTimelineStat(symbol: "heart.fill", text: "\(words.whole(average)) bpm")) }
            dated.append((workout.start, SomaTimelineEvent(
                id: "workout-\(workout.start.timeIntervalSinceReferenceDate)", time: words.time(workout.start),
                title: workout.name, detail: words.workout(workout), aspect: .activity,
                hue: .activity, symbol: workout.kind == .onFoot ? "figure.walk" : "figure.strengthtraining.traditional",
                stats: stats, start: workout.start, end: workout.end
            )))
        }
        for session in inputs.mindful where session.start >= today {
            let length = session.end.timeIntervalSince(session.start)
            dated.append((session.start, SomaTimelineEvent(
                id: "mindful-\(session.start.timeIntervalSinceReferenceDate)", time: words.time(session.start),
                title: "Mindful session", detail: "\(words.minutes(length)).", aspect: .mind,
                hue: .mind, symbol: "brain.head.profile",
                stats: [SomaTimelineStat(symbol: "timer", text: words.minutes(length))],
                start: session.start, end: session.end
            )))
        }
        for peak in peaks {
            dated.append((peak.start, SomaTimelineEvent(
                id: "peak-\(peak.start.timeIntervalSinceReferenceDate)", time: words.time(peak.start),
                title: "Stress peak", detail: words.peak(peak), aspect: .mind,
                hue: .heart, symbol: "waveform.path.ecg",
                stats: [
                    SomaTimelineStat(symbol: "heart.fill", text: "\(words.whole(peak.peak)) bpm"),
                    SomaTimelineStat(symbol: "arrow.up", text: "+\(words.whole(peak.above))"),
                ],
                start: peak.start, end: peak.end
            )))
        }

        var nowStats: [SomaTimelineStat] = []
        if let steps = inputs.stepsToday { nowStats.append(SomaTimelineStat(symbol: "figure.walk", text: words.whole(steps))) }
        if let exercise = inputs.exerciseToday { nowStats.append(SomaTimelineStat(symbol: "flame.fill", text: "\(words.whole(exercise)) min")) }
        let now = SomaTimelineEvent(
            id: "now", time: words.time(self.now), title: "Now",
            detail: words.now(steps: inputs.stepsToday, exercise: inputs.exerciseToday), isNow: true,
            stats: nowStats, start: self.now
        )
        return dated.sorted { $0.0 < $1.0 }.map(\.1) + [now]
    }
}
