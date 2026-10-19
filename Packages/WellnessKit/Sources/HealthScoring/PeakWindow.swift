//
//  PeakWindow.swift
//  HealthScoring (ported from the previous app)
//
//  The predicted alertness curve and the day planned on it. The curve is the
//  SAFTE model (Hursh et al. 2004): a homeostatic sleep reservoir, a two
//  harmonic circadian process and post wake sleep inertia, integrated over
//  the person's own recorded nights. The circadian phase comes from their
//  sleep timing (mid sleep on free days, corrected for sleep debt), and the
//  plan reads its windows off the curve with the original thresholds.
//
//  Simplified from the original in one place: nights are replayed as plain
//  sleep and wake, with no logged caffeine, naps or day load, because Soma
//  records none of those yet. A modelled curve, never a measurement.
//

import Foundation

// MARK: - SAFTE

enum SAFTEEngine {
    static let reservoirCapacity = 2880.0
    static let depletionPerMin = 0.5
    static let feedback = 0.0026564
    static let sleepPropensityAmp = 0.55
    static let maxSleepIntensity = 4.4
    static let inertiaMax = 5.0
    static let inertiaDecayPerMin = 0.04
    static let inertiaWindowMin = 120.0
    static let circ24Acrophase = 18.0
    static let circ12Phase = 21.0
    static let circ12Amplitude = 0.5
    static let baselineCircAmplitude = 7.0
    static let debtCircAmplitude = 5.0

    struct Segment: Sendable, Equatable {
        var minutes: Double
        var asleep: Bool
        var startClockHour: Double
    }

    struct Sample: Sendable, Equatable {
        var clockHour: Double
        /// -1 while asleep, else minutes since the last wake.
        var minutesSinceWake: Double
        var effectiveness: Double
        /// Minutes since the start of the whole timeline.
        var minuteOffset: Double
    }

    static func circadianTerm(clockHour: Double) -> Double {
        cos(2 * Double.pi * (clockHour - circ24Acrophase) / 24)
            + circ12Amplitude * cos(4 * Double.pi * (clockHour - circ12Phase) / 24)
    }

    static func inertia(minutesSinceWake: Double, sleepIntensityAtWake: Double) -> Double {
        guard minutesSinceWake >= 0, minutesSinceWake < inertiaWindowMin else { return 0 }
        let si = max(0.0001, sleepIntensityAtWake)
        return -inertiaMax * exp(-(inertiaDecayPerMin * minutesSinceWake) / si)
    }

    static func effectiveness(reservoir: Double, clockHour: Double,
                              minutesSinceWake: Double, sleepIntensityAtWake: Double) -> Double {
        let amplitude = baselineCircAmplitude
            + debtCircAmplitude * (reservoirCapacity - reservoir) / reservoirCapacity
        let e = 100 * (reservoir / reservoirCapacity)
            + amplitude * circadianTerm(clockHour: clockHour)
            + inertia(minutesSinceWake: minutesSinceWake, sleepIntensityAtWake: sleepIntensityAtWake)
        return min(100, max(0, e))
    }

    /// Walks the timeline and emits a sample every `stepMin` minutes.
    static func curve(over segments: [Segment], from start: Double,
                      stepMin: Double = 10, cbtMinHour: Double = 4.0) -> [Sample] {
        var r = min(reservoirCapacity, max(0, start))
        let step = max(1, stepMin)
        let phaseShift = 4.0 - cbtMinHour
        var minutesSinceWake = -1.0
        var siAtWake = maxSleepIntensity
        var out: [Sample] = []
        var timelineMinutes = 0.0
        for (index, segment) in segments.enumerated() {
            if !segment.asleep, index > 0, segments[index - 1].asleep {
                minutesSinceWake = 0
            }
            var elapsed = 0.0
            while elapsed < segment.minutes {
                let dt = min(step, segment.minutes - elapsed)
                let clock = (segment.startClockHour + elapsed / 60).truncatingRemainder(dividingBy: 24)
                let phased = clock + phaseShift
                if segment.asleep {
                    let si = min(maxSleepIntensity,
                                 sleepPropensityAmp * circadianTerm(clockHour: phased)
                                    + feedback * (reservoirCapacity - r))
                    r += max(0, si) * dt
                    siAtWake = max(0.0001, si)
                    minutesSinceWake = -1
                } else {
                    r -= depletionPerMin * dt
                    if minutesSinceWake >= 0 { minutesSinceWake += dt }
                }
                r = min(reservoirCapacity, max(0, r))
                let msw = minutesSinceWake < 0 ? inertiaWindowMin : minutesSinceWake
                timelineMinutes += dt
                out.append(Sample(clockHour: clock, minutesSinceWake: minutesSinceWake,
                                  effectiveness: effectiveness(reservoir: r, clockHour: phased,
                                                               minutesSinceWake: msw,
                                                               sleepIntensityAtWake: siAtWake),
                                  minuteOffset: timelineMinutes))
                elapsed += dt
            }
        }
        return out
    }
}

// MARK: - The plan

enum PeakWindowPlanner {
    static let deepWorkRelative = 0.85
    static let trainingRelative = 0.90
    static let deepWorkFloor = 77.5
    static let trainingFloor = 65.0
    static let minWindowMinutes = 60.0
    static let maxWindowMinutes = 120.0
    static let deepWorkCeilingAfterCBTMin = 16.0
    static let trainingStartAfterCBTMin = 11.0
    static let trainingEndAfterCBTMin = 17.0
    static let inertiaMinutes = 120.0

    struct Window: Sendable, Equatable {
        var startHour: Double
        var endHour: Double
        var meanEffectiveness: Double
    }

    /// The best window of the day: the highest mean one to two hour run at or
    /// above the relative cutoff, or nil when the day never clears the floor.
    static func window(_ samples: [SAFTEEngine.Sample], relative: Double, floor: Double) -> Window? {
        let sorted = samples.filter { $0.minutesSinceWake >= 0 }.sorted { $0.minutesSinceWake < $1.minutesSinceWake }
        guard let peak = sorted.map(\.effectiveness).max(), peak >= floor else { return nil }
        let cutoff = max(peak * relative, floor)
        let tolerance = sampleStep(sorted) * 1.5
        var runs: [[SAFTEEngine.Sample]] = []
        var current: [SAFTEEngine.Sample] = []
        for sample in sorted {
            guard sample.effectiveness >= cutoff else {
                if !current.isEmpty { runs.append(current); current = [] }
                continue
            }
            if let last = current.last, sample.minutesSinceWake - last.minutesSinceWake > tolerance {
                runs.append(current)
                current = []
            }
            current.append(sample)
        }
        if !current.isEmpty { runs.append(current) }
        return runs.compactMap(bestPlacement).max { $0.meanEffectiveness < $1.meanEffectiveness }
    }

    private static func bestPlacement(in run: [SAFTEEngine.Sample]) -> Window? {
        guard let first = run.first, let last = run.last else { return nil }
        let span = last.minutesSinceWake - first.minutesSinceWake
        guard span >= minWindowMinutes else { return nil }
        let length = min(span, maxWindowMinutes)
        return placement(in: run, length: length, slack: 1e-6)
            ?? placement(in: run, length: length, slack: sampleStep(run))
    }

    private static func placement(in run: [SAFTEEngine.Sample], length: Double, slack: Double) -> Window? {
        var best: Window?
        for (i, start) in run.enumerated() {
            var j = i
            while j + 1 < run.count, run[j + 1].minutesSinceWake - start.minutesSinceWake <= length {
                j += 1
            }
            let duration = run[j].minutesSinceWake - start.minutesSinceWake
            guard duration >= minWindowMinutes, duration >= length - slack else { continue }
            let slice = run[i...j]
            let mean = slice.reduce(0) { $0 + $1.effectiveness } / Double(slice.count)
            if best == nil || mean > best!.meanEffectiveness {
                best = Window(startHour: start.clockHour, endHour: run[j].clockHour, meanEffectiveness: mean)
            }
        }
        return best
    }

    private static func sampleStep(_ sorted: [SAFTEEngine.Sample]) -> Double {
        var step = Double.greatestFiniteMagnitude
        for (a, b) in zip(sorted, sorted.dropFirst()) {
            let d = b.minutesSinceWake - a.minutesSinceWake
            if d > 0 { step = min(step, d) }
        }
        return step == .greatestFiniteMagnitude ? 10 : step
    }

    static func minutesAfterWake(_ hour: Double, wakeHour: Double) -> Double {
        HealthStats.Clock.forward(from: wakeHour, to: hour) * 60
    }

    /// The caffeine cutoff: the hours a standard 100 mg serving needs to fall
    /// to 25 mg by bedtime, at a five hour half life.
    static func caffeineCutoffHour(bedtimeHour: Double, doseMg: Double = 100) -> Double {
        guard doseMg > 25 else { return HealthStats.Clock.wrap24(bedtimeHour) }
        return HealthStats.Clock.wrap24(bedtimeHour - 5 * log2(doseMg / 25))
    }
}

// MARK: - Chronotype

enum ChronotypeEstimator {
    struct Night: Sendable, Equatable {
        var bedHour: Double
        var wakeHour: Double
        var isFreeDay: Bool
    }

    static let minFreeNights = 2

    /// Mid sleep on free days, corrected for sleep debt (MSFsc), or nil with
    /// fewer than two free nights.
    static func msfSc(_ nights: [Night]) -> Double? {
        let valid = nights.filter {
            let d = SomaScoringEngine.sleepDuration(bedHour: $0.bedHour, wakeHour: $0.wakeHour)
            return d >= 2 && d <= 16
        }
        let free = valid.filter(\.isFreeDay)
        guard free.count >= minFreeNights else { return nil }
        let mids = free.map { SomaScoringEngine.midSleepHour(bedHour: $0.bedHour, wakeHour: $0.wakeHour) }
        guard let msf = CircadianMath.circularMeanHours(mids) else { return nil }
        let freeMean = free.map { SomaScoringEngine.sleepDuration(bedHour: $0.bedHour, wakeHour: $0.wakeHour) }
            .reduce(0, +) / Double(free.count)
        let weekMean = valid.map { SomaScoringEngine.sleepDuration(bedHour: $0.bedHour, wakeHour: $0.wakeHour) }
            .reduce(0, +) / Double(valid.count)
        return freeMean <= weekMean ? msf : CircadianMath.wrap24(msf - (freeMean - weekMean) / 2)
    }

    /// Morning, intermediate or evening, an hour either side of 04:30.
    static func category(msfSc: Double) -> ScoringPeakDay.Chronotype {
        let delta = CircadianMath.signedDeltaHours(from: 4.5, to: msfSc)
        if delta < -1 { return .morning }
        if delta > 1 { return .evening }
        return .intermediate
    }
}

// MARK: - The public face

/// Today's predicted alertness and the plan read off it.
public struct ScoringPeakDay: Sendable, Equatable {
    public enum Chronotype: String, Sendable, Hashable {
        case morning, intermediate, evening
    }

    /// Today's curve from midnight to tonight's bedtime, one point every ten
    /// minutes: clock hour and 0 to 100.
    public let curve: [(hour: Double, level: Double)]
    /// Alertness now, when now is inside the curve.
    public let now: Double?
    public let nowHour: Double
    /// When today's curve peaks while awake.
    public let peakHour: Double?
    public let deepWork: (start: Double, end: Double)?
    public let training: (start: Double, end: Double)?
    public let caffeineCutoffHour: Double
    public let windDownHour: Double
    /// The habitual bed and wake hours the plan is laid on.
    public let bedHour: Double
    public let wakeHour: Double
    public let cbtMinHour: Double
    /// Nil until two free day nights are recorded; the phase then falls back
    /// to the model default.
    public let chronotype: Chronotype?
    public let nights: Int

    public static func == (lhs: ScoringPeakDay, rhs: ScoringPeakDay) -> Bool {
        lhs.curve.map(\.level) == rhs.curve.map(\.level) && lhs.nowHour == rhs.nowHour
            && lhs.peakHour == rhs.peakHour && lhs.bedHour == rhs.bedHour && lhs.nights == rhs.nights
    }

    /// Nights before a day is modelled.
    public static let minimumNights = 3
    /// Nights replayed into the reservoir at most.
    public static let historyNights = 14

    /// The day, from the recorded nights (oldest first; the last is the night
    /// that ended today). Nil with fewer than ``minimumNights``, or when the
    /// last night did not end today.
    public static func resolve(nights: [ScoringNightWindow], now: Date,
                               calendar: Calendar = .current) -> ScoringPeakDay? {
        let recent = Array(nights.suffix(historyNights))
        guard recent.count >= minimumNights, let last = recent.last,
              calendar.isDate(last.end, inSameDayAs: now) else { return nil }

        func hour(_ date: Date) -> Double {
            Double(calendar.component(.hour, from: date)) + Double(calendar.component(.minute, from: date)) / 60
        }
        let bedHours = recent.map { hour($0.start) }
        let wakeHours = recent.map { hour($0.end) }
        guard let bedHour = CircadianMath.circularMeanHours(bedHours),
              let wakeHour = CircadianMath.circularMeanHours(wakeHours) else { return nil }

        let chronoNights = recent.map { night -> ChronotypeEstimator.Night in
            let bed = hour(night.start)
            let weekday = calendar.component(.weekday, from: night.end)
            return ChronotypeEstimator.Night(bedHour: bed < 12 ? bed + 24 : bed, wakeHour: hour(night.end),
                                             isFreeDay: weekday == 1 || weekday == 7)
        }
        let msf = ChronotypeEstimator.msfSc(chronoNights)
        let cbtMin: Double = msf.map { msf in
            switch ChronotypeEstimator.category(msfSc: msf) {
            case .morning: 3.5
            case .intermediate: 4.5
            case .evening: 5.5
            }
        } ?? 4.0

        // The timeline: every night asleep, every day awake, then today awake
        // until the habitual bedtime.
        let today = calendar.startOfDay(for: now)
        let bedTonight: Date = {
            let base = calendar.date(byAdding: .minute, value: Int(bedHour * 60), to: today) ?? now
            return bedHour < 12 ? base.addingTimeInterval(86_400) : base
        }()
        var segments: [SAFTEEngine.Segment] = []
        for (index, night) in recent.enumerated() {
            segments.append(.init(minutes: night.end.timeIntervalSince(night.start) / 60, asleep: true,
                                  startClockHour: hour(night.start)))
            let nextStart = index + 1 < recent.count ? recent[index + 1].start : max(bedTonight, now)
            let awake = nextStart.timeIntervalSince(night.end) / 60
            if awake > 0 {
                segments.append(.init(minutes: awake, asleep: false, startClockHour: hour(night.end)))
            }
        }
        guard let origin = recent.first?.start else { return nil }
        let samples = SAFTEEngine.curve(over: segments, from: SAFTEEngine.reservoirCapacity * 0.9,
                                        stepMin: 10, cbtMinHour: cbtMin)
        let todayOffset = today.timeIntervalSince(origin) / 60
        let lastWakeOffset = last.end.timeIntervalSince(origin) / 60
        let day = samples.filter { $0.minuteOffset >= todayOffset }
        guard !day.isEmpty else { return nil }
        let awakeToday = day.filter { $0.minuteOffset > lastWakeOffset }

        let nowHour = hour(now)
        let nowOffset = now.timeIntervalSince(origin) / 60
        let nowLevel = day.min { abs($0.minuteOffset - nowOffset) < abs($1.minuteOffset - nowOffset) }
            .flatMap { abs($0.minuteOffset - nowOffset) <= 15 ? $0.effectiveness : nil }

        let windDown = HealthStats.Clock.wrap24(bedHour - 1)
        let wake = hour(last.end)
        let ceiling = min(PeakWindowPlanner.minutesAfterWake(
                              CircadianMath.wrap24(cbtMin + PeakWindowPlanner.deepWorkCeilingAfterCBTMin), wakeHour: wake),
                          PeakWindowPlanner.minutesAfterWake(windDown, wakeHour: wake))
        let daytime = awakeToday.filter {
            $0.minutesSinceWake >= PeakWindowPlanner.inertiaMinutes && $0.minutesSinceWake <= ceiling
        }
        var trainingStart = PeakWindowPlanner.minutesAfterWake(
            CircadianMath.wrap24(cbtMin + PeakWindowPlanner.trainingStartAfterCBTMin), wakeHour: wake)
        let trainingEnd = PeakWindowPlanner.minutesAfterWake(
            CircadianMath.wrap24(cbtMin + PeakWindowPlanner.trainingEndAfterCBTMin), wakeHour: wake)
        if trainingEnd < trainingStart { trainingStart = 0 }
        let evening = awakeToday.filter { $0.minutesSinceWake >= trainingStart && $0.minutesSinceWake <= trainingEnd }
        let deepWork = PeakWindowPlanner.window(daytime, relative: PeakWindowPlanner.deepWorkRelative,
                                                floor: PeakWindowPlanner.deepWorkFloor)
        let training = PeakWindowPlanner.window(evening, relative: PeakWindowPlanner.trainingRelative,
                                                floor: PeakWindowPlanner.trainingFloor)
        let best = awakeToday.map(\.effectiveness).max()
        let peak = best.flatMap { best in awakeToday.first { $0.effectiveness == best }?.clockHour }

        return ScoringPeakDay(
            curve: day.map { ($0.clockHour, $0.effectiveness) },
            now: nowLevel,
            nowHour: nowHour,
            peakHour: peak,
            deepWork: deepWork.map { ($0.startHour, $0.endHour) },
            training: training.map { ($0.startHour, $0.endHour) },
            caffeineCutoffHour: PeakWindowPlanner.caffeineCutoffHour(bedtimeHour: bedHour),
            windDownHour: windDown,
            bedHour: bedHour,
            wakeHour: wakeHour,
            cbtMinHour: cbtMin,
            chronotype: msf.map(ChronotypeEstimator.category(msfSc:)),
            nights: recent.count)
    }
}
