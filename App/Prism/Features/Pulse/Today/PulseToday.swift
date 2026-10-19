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
    static func make(
        from inputs: PulseInputs,
        scores: SomaScores? = nil,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> PulseToday {
        PulseTodayBuilder(
            inputs: inputs,
            scores: scores,
            calendar: calendar,
            words: PulseWording(calendar: calendar, locale: locale)
        ).build()
    }
}

/// The arithmetic behind the page, in the order the page reads.
private struct PulseTodayBuilder {
    let inputs: PulseInputs
    let scores: SomaScores?
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
        let before = nights.filter { $0.day < today && $0.day >= day(-30) }
        let usualSleep = before.count >= 3 ? PulseSignals.median(before.suffix(14).map(\.asleep)) : nil
        let shortBy: TimeInterval? = {
            guard let lastNight, let usualSleep, usualSleep - lastNight.asleep >= 45 * 60 else { return nil }
            return usualSleep - lastNight.asleep
        }()

        let variability = heartRateVariability(since: lastNight?.fellAsleep ?? today)
        let resting = restingHeart()
        let usualExercise = inputs.exerciseByNowBefore.count >= 5 ? PulseSignals.median(inputs.exerciseByNowBefore) : nil

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

        let moves = self.moves(
            lastNight: lastNight, shortBy: shortBy, month: before + [lastNight].compactMap { $0 },
            variability: variability, resting: resting, peaks: peaks, usualExercise: usualExercise
        )
        let (headline, reason) = self.headline(
            top: moves.first, lastNight: lastNight, shortBy: shortBy,
            variability: variability, resting: resting, peaks: peaks, usualExercise: usualExercise
        )

        let week = (-6...0).map { offset in nights.first { $0.day == day(offset) } }
        let lowest = lowestOvernight(lastNight)

        return PulseToday(
            carrying: moves.first?.aspect,
            headline: headline,
            reason: reason,
            movesTitle: words.movesTitle(at: now),
            moves: moves,
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
            bodyCard: PulseToday.Card(value: nil, summary: words.bodySummary(age: inputs.age)),
            age: inputs.age,
            hasData: !inputs.isEmpty
        )
    }

    // MARK: - Signals

    struct Variability {
        var today: Double?
        var usual: Double?
    }

    /// Today's heart rate variability, from the readings since falling asleep,
    /// against the median of the daily means over the month before.
    func heartRateVariability(since start: Date) -> Variability {
        let recent = inputs.heartRateVariability.filter { $0.start >= start && $0.start <= now }.map(\.value)
        // A night with no reading falls back on the latest one, if it is
        // recent enough to still describe today.
        let current = recent.isEmpty
            ? inputs.heartRateVariability
                .filter { $0.start <= now && now.timeIntervalSince($0.end) < 36 * 60 * 60 }
                .max { $0.end < $1.end }?
                .value
            : recent.reduce(0, +) / Double(recent.count)
        let earlier = inputs.heartRateVariability.filter { $0.start < start && $0.start >= day(-30) }
        let daily = PulseSignals.daily(earlier, calendar: calendar) { values in
            values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
        }
        let usual = daily.count >= 5 ? PulseSignals.median(Array(daily.values)) : nil
        return Variability(today: current, usual: usual)
    }

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

    // MARK: - Moves

    /// Up to three moves, the most pressing first. Each one is asked for by a
    /// number: nothing here fires on a hunch.
    func moves(
        lastNight: PulseNight?,
        shortBy: TimeInterval?,
        month: [PulseNight],
        variability: Variability,
        resting: Resting,
        peaks: [PulsePeak],
        usualExercise: Double?
    ) -> [PulseToday.Move] {
        var found: [(priority: Int, move: PulseToday.Move)] = []

        let variabilityLow = variability.today.flatMap { today in
            variability.usual.map { today <= $0 * 0.9 }
        } ?? false
        if !peaks.isEmpty || variabilityLow {
            let reason = variability.usual.map {
                "Slow breathing can bring your HRV back toward your usual \(words.whole($0)) ms."
            } ?? "Slow breathing helps a raised heart settle."
            found.append((peaks.count >= 2 ? 100 : (peaks.isEmpty ? 60 : 80),
                          PulseToday.Move(aspect: .mind, title: "Breathe for 10 minutes", reason: reason)))
        }

        if let bedtime = bedtime(month) {
            var reason = "Your longest nights this month started before \(words.time(bedtime.before))."
            if let shortBy, let lastNight {
                reason = "You slept \(words.clock(lastNight.asleep)), \(words.span(shortBy)) under your usual."
            }
            found.append((shortBy == nil ? 30 : 90,
                          PulseToday.Move(aspect: .sleep, title: "In bed by \(words.time(bedtime.target))", reason: reason)))
        }

        // Compared as the card prints them, in whole beats, so a card that
        // reads "5 above your usual" and the move it asks for agree.
        if let latest = resting.latest, let usual = resting.usual, (latest - usual).rounded() >= 5 {
            found.append((70, PulseToday.Move(
                aspect: .heart,
                title: "Keep tonight easy",
                reason: "Resting heart rate is \(words.whole(latest)), \(words.whole(latest - usual)) above your usual."
            )))
        }

        let hour = calendar.component(.hour, from: now)
        if let exercise = inputs.exerciseToday, let usual = usualExercise, (10..<20).contains(hour),
           exercise < usual - max(10, usual * 0.3) {
            found.append((50, PulseToday.Move(
                aspect: .activity,
                title: "Walk for 15 minutes",
                reason: "\(words.whole(exercise)) min of exercise so far. By now you usually have \(words.whole(usual))."
            )))
        }

        return Array(found.sorted { $0.priority > $1.priority }.prefix(3).map(\.move))
    }

    /// When to be in bed tonight: the middle of the bedtimes of the month's
    /// longest nights, rounded down to the quarter hour, and the latest of
    /// them, rounded up, to say why.
    func bedtime(_ month: [PulseNight]) -> (target: Date, before: Date)? {
        guard month.count >= 7 else { return nil }
        let longest = month.sorted { $0.asleep > $1.asleep }.prefix(max(3, month.count / 3))
        // Minutes since six in the evening, so a bedtime after midnight sorts
        // after one before it.
        let clocks = longest.map { night -> Double in
            let parts = calendar.dateComponents([.hour, .minute], from: night.bedtime)
            let minutes = Double((parts.hour ?? 0) * 60 + (parts.minute ?? 0))
            return (minutes - 18 * 60 + 24 * 60).truncatingRemainder(dividingBy: 24 * 60)
        }
        guard let middle = PulseSignals.median(clocks), let latest = clocks.max() else { return nil }
        let evening = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: today) ?? today
        let target = evening.addingTimeInterval((middle / 15).rounded(.down) * 15 * 60)
        let before = evening.addingTimeInterval((latest / 15).rounded(.up) * 15 * 60)
        return (target, max(before, target))
    }

    // MARK: - The headline

    func headline(
        top: PulseToday.Move?,
        lastNight: PulseNight?,
        shortBy: TimeInterval?,
        variability: Variability,
        resting: Resting,
        peaks: [PulsePeak],
        usualExercise: Double?
    ) -> (String, String) {
        guard !inputs.isEmpty else {
            return ("Nothing to read yet.",
                    "Apple Health holds no sleep, heart or activity for today. The page fills in as your watch and phone record them.")
        }
        let partName: String = switch words.part(of: now) {
        case .morning: "morning"
        case .afternoon: "afternoon"
        case .evening: "evening"
        }

        switch top?.aspect {
        case .mind where !peaks.isEmpty:
            let when = peaks.map { words.time($0.start) }
            let above = peaks.map(\.above).max() ?? 0
            let count = words.count(peaks.count, "stress peak", "stress peaks").capitalizedFirst
            return ("Slow the \(partName) down.",
                    "\(count) today, at \(words.list(when)), your heart up to \(words.whole(above)) above resting while you were still. Ten minutes of slow breathing and an early night help it settle.")
        case .mind:
            guard let current = variability.today, let usual = variability.usual else { break }
            return ("Go gently today.",
                    "Your HRV is \(words.whole(current)) ms, under your usual \(words.whole(usual)). Slow breathing and an early night help it recover.")
        case .sleep:
            guard let lastNight, let shortBy else { break }
            return (words.part(of: now) == .evening ? "Tonight decides tomorrow." : "A short night to make up.",
                    "You slept \(words.clock(lastNight.asleep)), \(words.span(shortBy)) under your usual. An earlier night gives most of it back.")
        case .heart:
            guard let latest = resting.latest, let usual = resting.usual else { break }
            return ("Keep today light.",
                    "Your resting heart rate is \(words.whole(latest)), \(words.whole(latest - usual)) above your usual. An easy day and a full night usually bring it down.")
        case .activity:
            guard let exercise = inputs.exerciseToday, let usualExercise else { break }
            return ("A walk would help.",
                    "\(words.whole(exercise)) min of exercise so far. By this time you usually have \(words.whole(usualExercise)).")
        default:
            break
        }
        return ("A steady day.", "Sleep, heart and movement sit close to your usual.")
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

private extension String {
    /// The string with its first letter capitalised: "two" reads "Two".
    var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}
