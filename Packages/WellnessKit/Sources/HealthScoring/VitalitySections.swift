//
//  VitalitySections.swift
//  HealthScoring (ported from the previous app, behaviour unchanged)
//
//  The isolated, pure, individually testable pieces of the vitality
//  model. Each function does one thing, takes plain numbers, and cites
//  the source of its constants. Nothing here imports SwiftUI/HealthKit.
//
//  References:
//   - Borbely (1982), reappraisal 2016: two-process sleep regulation
//     (Process S homeostatic, Process C circadian).
//   - Garmin / Firstbeat Body Battery: charge/drain magnitudes
//     (good night +40..60; workout drain on a ~45-point scale).
//   - EPOC literature: post-exercise oxygen-debt decays to ~13% by 3 h.
//

import Foundation

enum VitalitySections {

    // MARK: - Scale anchors

    // The whole model is pinned to ONE set of measured numbers, so that
    // "is this constant right" is a question with an answer instead of a
    // taste call. Garmin Connect 2024 population data, the largest public
    // sample of a Body-Battery-shaped metric: the average morning reads
    // 71, the average evening low reads 22, the average day therefore
    // drains 49 points, and the displayed value never goes below 5. A
    // typical night lifts the bank 40-60 points; the very best nights
    // lift it 60-70. Every constant below is chosen to land on those
    // numbers for a typical day, and the tests assert exactly that.

    /// The battery never reads 0. Garmin floors Body Battery at 5, and the
    /// reason is not cosmetic: 0 is an absorbing state that destroys
    /// information. Once a `max(0, .)` clamp bites, "spent" and
    /// "catastrophically spent" display identically, every evening looks
    /// the same, and the next night charges from a level the body was
    /// never actually at. The floor keeps the bottom of the scale
    /// readable and keeps the carry-over honest.
    static let batteryFloor = 5.0

    /// Clamp to the displayable battery range, floor included.
    static func clampBattery(_ value: Double) -> Double {
        min(100, max(batteryFloor, value))
    }

    // MARK: - Backbone constants (Borbely two-process)

    /// Asymptotic homeostatic drain for unbounded wakefulness. Over a
    /// real ~16 h day this yields ~29 points.
    static let homeostaticMaxDrain = 50.0
    /// Process-S build-up time constant during wake, hours.
    static let wakeTau = 18.2
    /// Process-C amplitude on the battery, points.
    static let circadianAmplitude = 7.0

    /// Process-S build-up while awake: a saturating exponential, so most
    /// of the drain lands in the first ~12 h then levels off.
    static func homeostaticDrain(awakeHours: Double) -> Double {
        let h = max(0, awakeHours)
        return homeostaticMaxDrain * (1 - exp(-h / wakeTau))
    }

    /// Classic alertness rhythm in [-1, 1]: late-morning peak (~10 h),
    /// post-lunch dip (~15 h), early-evening bump (~19 h), overnight
    /// nadir (~04 h). Mean ~0, so it shapes the curve without biasing
    /// the level. Anchor points are linearly interpolated.
    static func circadianModulation(clockHour: Double) -> Double {
        let points: [(Double, Double)] = [
            (0, -0.7), (3, -1.0), (6, -0.6), (8, -0.1),
            (10, 0.8), (12, 0.7), (14, 0.25), (15, 0.1),
            (17, 0.45), (19, 0.55), (21, 0.15), (22, -0.2), (24, -0.7)
        ]
        let hour = (clockHour.truncatingRemainder(dividingBy: 24) + 24)
            .truncatingRemainder(dividingBy: 24)
        for index in 1..<points.count where hour <= points[index].0 {
            let (h0, v0) = points[index - 1]
            let (h1, v1) = points[index]
            let t = (hour - h0) / max(0.001, h1 - h0)
            return v0 + (v1 - v0) * t
        }
        return points.last?.1 ?? 0
    }

    // MARK: - Sleep charge

    /// LEGACY flat refill efficiency, now only the FALLBACK when the
    /// night's duration is unknown. Calibrated so a perfect night from a
    /// typical low reserve (~30) gains ~+50 (Garmin 40-60 band). When the
    /// duration IS known, `sleepClosureFraction` replaces this with the
    /// real Process-S dissipation curve.
    static let sleepChargeEfficiency = 0.72

    /// Process-S dissipation time constant during sleep, hours (Borbely
    /// 1982, reappraisal 2016: sleep pressure decays exponentially with
    /// tau ~4.2 h).
    static let sleepPressureTauHours = 4.2

    /// Fraction of the headroom a night of `sleepHours` can close:
    /// 1 - e^(-h / 4.2), the two-process Process-S dissipation. A full
    /// 8 h night closes ~85%, 6 h ~76%, 4 h ~61%. Replaces the flat 0.72,
    /// which ignored duration and silently capped every morning at
    /// reserve + 72% of the gap: waking at 90-100 after a genuinely good
    /// long night (routine on Garmin/Firstbeat) was mathematically
    /// unreachable and a good night from a low evening read ~66. With no
    /// duration the legacy 0.72 anchor stands, so score-only callers are
    /// unchanged.
    static func sleepClosureFraction(sleepHours: Double?) -> Double {
        guard let hours = sleepHours, hours > 0 else { return sleepChargeEfficiency }
        return 1 - exp(-hours / sleepPressureTauHours)
    }

    /// Restoration fraction of a night as a function of its sleep score:
    /// CONCAVE (square root), not linear. Process S dissipates
    /// exponentially and front-loaded during sleep (Borbely; Achermann
    /// 1993), so a mediocre night still clears most of the pressure a
    /// perfect one would. The previous linear map double-counted quality
    /// (the score already folds duration and stages) and pinned the daily
    /// ledger near zero: a typical score of 75 refilled only 54% of the
    /// headroom against a ~47-point typical daily drain, so the battery
    /// ended most evenings at 0 and stayed stuck there. sqrt keeps the
    /// perfect-night anchor (score 100 -> 1.0) and lifts score 75 to
    /// ~0.87, which places the steady state in the Garmin-like band
    /// (evenings ~15-35, mornings ~65-80).
    static func chargeQuality(sleepScore: Double) -> Double {
        (min(100, max(0, sleepScore)) / 100).squareRoot()
    }

    /// A night closes at most this share of the headroom, however good it
    /// was. This is a measured anchor, not a taste call. Garmin's average
    /// night lifts the bank from 22 to 71: it closes 49 of the 78
    /// available points, 63%. The very best nights lift it ~70 points from
    /// a floored evening, closing ~74% of 95. But `chargeQuality *
    /// sleepClosureFraction` alone lets a perfect 8 h night close 85% and a
    /// merely typical one 72%, which overshoots BOTH anchors. That
    /// overshoot is what previously forced the drain constants to be
    /// inflated to compensate, and an inflated drain is what drove the
    /// evening through the floor on any day that was not easy.
    ///
    /// With this factor a typical night (score 75, 7.5 h) closes 62.7% and
    /// a great 8 h night closes 74.1%: both anchors at once, from one
    /// constant. Physiologically it says a night restores TOWARD a
    /// theoretical ceiling it never quite reaches, which is also why
    /// "100" is asymptotic rather than a nightly destination.
    static let nightClosureMax = 0.87

    // MARK: - Night alignment (WHEN the night happened)

    // Duration and quality alone say a night is a night. They are not: the
    // homeostatic pressure this model tracks is discharged mostly in slow-wave
    // sleep, slow-wave sleep is front-loaded, and how much of it a night
    // produces depends on sleeping in phase with the body clock. Polar's ANS
    // Charge reads only the first three to four hours for exactly this reason.
    //
    // The reference is the person's OWN habitual mid-sleep, never a clock
    // time. A consistent night owl asleep from 03:00 to 11:00 is perfectly in
    // phase and pays nothing; the penalty is for a night that departs from
    // your own rhythm, which is the social-jetlag finding rather than a
    // morality about early rising.

    /// Within this much of your habitual mid-sleep, a night is on phase.
    static let nightAlignmentGraceHours = 1.0
    /// Past this, the penalty stops growing: a 6 h shift is not twice as bad
    /// as a 3 h one, both are simply the wrong night.
    static let nightAlignmentFullHours = 3.0
    /// Most a badly-timed night can lose. Deliberately SMALL. The sleep score
    /// already folds duration and stages, and an off-phase night has already
    /// lost deep and REM inside that score, so a large factor here would
    /// charge the same physiological fact twice.
    static let nightAlignmentFloor = 0.88

    /// Charge multiplier for how far a night sat from the person's own
    /// habitual mid-sleep. 1.0 when on phase or unknown.
    static func nightAlignmentMultiplier(misalignmentHours: Double?) -> Double {
        guard let hours = misalignmentHours, hours > nightAlignmentGraceHours else { return 1 }
        let span = max(0.001, nightAlignmentFullHours - nightAlignmentGraceHours)
        let ramp = min(1, (hours - nightAlignmentGraceHours) / span)
        return 1 - (1 - nightAlignmentFloor) * ramp
    }

    // MARK: - Daily stress (how much the day cost, not where)

    // The drain gate decides WHERE a day's burn lands; it is mean-preserving
    // and deliberately cannot change how big the day was. This term is the
    // other half: a genuinely tense day costs more in total than a serene one
    // at equal sleep and equal training.
    //
    // It is CENTERED on what an ordinary day reads, because the population
    // anchor (49 points) was measured on ordinary days and therefore already
    // contains ordinary stress. An uncentered term would silently move the
    // anchor and make every day cost more than the data says it does.

    /// What an ordinary day reads on the centered daily stress scale.
    /// `StressEngine.dailyValue` is built so a typical day lands ~35, a rested
    /// day under 22 and a tense day over 70.
    static let dailyStressNeutral = 35.0
    /// Cost of a maximally tense day, above the ordinary one.
    static let dailyStressDrainMax = 12.0
    /// Credit of a maximally serene day. Smaller than the penalty: calm helps
    /// less than tension hurts.
    static let dailyStressCreditMax = 6.0

    /// Signed daily cost of psychological load, in battery points. Positive
    /// drains, negative gives back, 0 when unmeasured (an honest gap, never a
    /// free bonus).
    static func dailyStressDrain(stress: Double?) -> Double {
        guard let stress else { return 0 }
        let value = min(100, max(0, stress))
        if value >= dailyStressNeutral {
            return dailyStressDrainMax
                * (value - dailyStressNeutral) / max(1, 100 - dailyStressNeutral)
        }
        return -dailyStressCreditMax * (dailyStressNeutral - value) / max(1, dailyStressNeutral)
    }

    // MARK: - Illness

    /// Composite deviation, in standard deviations over the tracked vitals
    /// (`IllnessEpisodeEngine.deviationSeries`), under which the body is just
    /// having a normal day. One sigma of daily wobble is normal.
    static let illnessDeviationThreshold = 1.0
    /// Where the cost saturates. Beyond three sigma you are ill, and more
    /// sigma does not make the battery more informative.
    static let illnessDeviationFull = 3.0
    /// Cost of a fully flagged day.
    static let illnessDrainMax = 15.0

    /// Battery cost of being unwell. ONE-DIRECTIONAL: illness drains, and its
    /// absence never credits, because "no detectable drift" is the normal
    /// state the rest of the model is already calibrated on.
    static func illnessDrain(deviation: Double?) -> Double {
        guard let deviation, deviation > illnessDeviationThreshold else { return 0 }
        let span = max(0.001, illnessDeviationFull - illnessDeviationThreshold)
        return illnessDrainMax * min(1, (deviation - illnessDeviationThreshold) / span)
    }

    /// New reserve after a night's sleep. Charges the HEADROOM (not a
    /// flat amount): the duration sets how much of the gap the night can
    /// close (`sleepClosureFraction`, Process S), the score's concave
    /// restoration map scales it for quality, then a late-intense-workout
    /// penalty is subtracted (suppressed overnight recovery, Firstbeat).
    /// `sleepScore` is 0..100; `lateWorkoutPenalty` is in battery points;
    /// `sleepHours` nil falls back to the legacy flat 0.72 closure.
    static func sleepCharge(previousReserve: Double,
                            sleepScore: Double,
                            lateWorkoutPenalty: Double,
                            sleepHours: Double? = nil) -> Double {
        let reserve = clampBattery(previousReserve)
        let quality = chargeQuality(sleepScore: sleepScore)
        let headroom = max(0, 100 - reserve)
        let closure = sleepClosureFraction(sleepHours: sleepHours)
        let gross = reserve + headroom * quality * closure * nightClosureMax
        return clampBattery(gross - max(0, lateWorkoutPenalty))
    }

    // MARK: - Exercise drain (EPOC)

    /// Maximum battery cost a single hard session can impose (Garmin
    /// workout-drain magnitude). The daily ledger's per-strain-point
    /// factor is this ceiling / 100.
    static let exerciseDrainMax = 45.0

    /// Peak battery cost of a workout, saturating in TRIMP and scaled by
    /// fitness: a fitter athlete (higher VO2max) drains less for the same
    /// load. Capped at `exerciseDrainMax`.
    static func exerciseDrainPoints(trimp: Double, vo2max: Double?) -> Double {
        guard trimp > 0 else { return 0 }
        let fitness = min(1.5, max(0.7, (vo2max ?? 40) / 40))
        let tau = 150 * fitness
        return exerciseDrainMax * (1 - exp(-trimp / tau))
    }

    /// Ceiling of a WHOLE DAY's training cost, points. Lower than
    /// `exerciseDrainMax` on purpose: that one is the momentary peak of a
    /// single session including its EPOC spike, this one is what the day
    /// still carries at bedtime once the tail has decayed.
    static let dailyStrainDrainMax = 40.0
    /// Strain-scale constant of the daily training cost.
    static let dailyStrainDrainTau = 60.0

    /// The day's training cost, SATURATING in the 0..100 strain score.
    ///
    /// Replaces a linear `0.45 * strain`, which charged a strain-80 day 36
    /// points on top of a ~30-point homeostatic burn. That put the daily
    /// budget at 66 against a night that could only return ~50, so the
    /// ledger's fixed point sat BELOW zero and the clamp pinned it there:
    /// the battery read 0 every evening and no amount of sleep could lift
    /// it back. Saturation also matches what the per-workout model already
    /// does (`exerciseDrainPoints`), so the daily and per-session views
    /// stop contradicting each other.
    ///
    /// Anchors: strain 40 (the population's typical day) costs 19.5, which
    /// with the ~29.8-point homeostatic burn of a 16.5 h waking day totals
    /// 49.3, Garmin's measured average of 49. Strain 60 costs 25.3, strain
    /// 100 costs 32.4: a maximal day hurts, without erasing the scale.
    static func dailyStrainDrain(strain: Double) -> Double {
        let value = max(0, strain)
        return dailyStrainDrainMax * (1 - exp(-value / dailyStrainDrainTau))
    }

    /// EPOC decay multiplier after a workout ends: 1.0 at the end,
    /// ~0.13 at 3 h (exp(-0.68 h)), negligible thereafter.
    static func epocFactor(hoursSinceEnd: Double) -> Double {
        guard hoursSinceEnd > 0 else { return 1.0 }
        return exp(-0.68 * hoursSinceEnd)
    }

    /// Total exercise drain in effect at `time`, summed across today's
    /// workouts. During a workout the full peak applies; after it ends,
    /// the EPOC tail decays. Workouts wholly in the future contribute 0.
    static func exerciseDrain(at time: Date,
                              workouts: [VitalityWorkout],
                              vo2max: Double?) -> Double {
        workouts.reduce(0.0) { total, w in
            guard time >= w.start else { return total }
            let peak = exerciseDrainPoints(trimp: w.trimp, vo2max: vo2max)
            if time <= w.end { return total + peak } // mid-workout: full
            let hours = time.timeIntervalSince(w.end) / 3600
            return total + peak * epocFactor(hoursSinceEnd: hours)
        }
    }

    // MARK: - Stress drain (non-exercise sympathetic load)

    /// Battery points/hour drained at the maximum (stress = 100, fully
    /// above threshold). Keeps a day of sustained high stress from
    /// emptying the bank by itself.
    static let stressDrainPerHourMax = 3.0

    /// Non-exercise stress drain: time-integral of stress ABOVE a neutral
    /// threshold, EXCLUDING samples that fall inside a workout window
    /// (those are credited to `exerciseDrain`, so there is no double
    /// counting). `stressSamples` must be ascending in time.
    static func stressDrain(stressSamples: [VitalitySample],
                            workouts: [VitalityWorkout],
                            neutralThreshold: Double) -> Double {
        guard stressSamples.count >= 2 else { return 0 }
        func inWorkout(_ d: Date) -> Bool {
            workouts.contains { d >= $0.start && d <= $0.end }
        }
        var drain = 0.0
        for i in 1..<stressSamples.count {
            let prev = stressSamples[i - 1]
            let cur = stressSamples[i]
            let midDate = Date(timeIntervalSince1970:
                (prev.date.timeIntervalSince1970 + cur.date.timeIntervalSince1970) / 2)
            if inWorkout(midDate) { continue }
            let hours = cur.date.timeIntervalSince(prev.date) / 3600
            guard hours > 0 else { continue }
            let avg = (prev.value + cur.value) / 2
            let over = max(0, avg - neutralThreshold) / max(1, 100 - neutralThreshold)
            drain += over * stressDrainPerHourMax * hours
        }
        return drain
    }

    // MARK: - Recovery-aware energy (v3)

    /// How much of a night's restorative power a nap carries, minute for minute
    /// at the same sleep pressure.
    ///
    /// PROVISIONAL. A nap lacks a night's architecture (little REM, slow wave
    /// sleep only if it runs long enough), it costs sleep inertia on waking, and
    /// it BORROWS from the pressure the coming night would have discharged. No
    /// single published figure covers that, so this says "most of a night
    /// minute, not all of it" and is written as the assumption it is.
    ///
    /// It replaced a constant named `napChargeEfficiency` that meant something
    /// else: the fraction of the headroom a FULL sleep need of napping would
    /// close, applied on a LINEAR ramp. See `napCharge` for why the ramp was the
    /// real defect.
    static let napRestorationFactor = 0.75

    /// Maximum total nap charge in a day, points.
    ///
    /// A nap borrows from tonight: pressure it discharges now is pressure the
    /// night cannot discharge later, so unbounded napping cannot keep refilling
    /// the bank. 25 admits one full cycle nap plus a short second one, which is
    /// where the borrowing starts to dominate. It was 15, which a single 90 min
    /// nap now reaches on its own.
    static let napChargeCap = 25.0

    /// Battery points a stretch of napping adds, as the INCREMENT between two
    /// cumulative nap durations.
    ///
    /// THE CURVE IS THE FIX HERE, NOT THE CONSTANT. The night closes its
    /// headroom on `sleepClosureFraction`, the two process Process S
    /// dissipation `1 - e^(-h/4.2)`, which this file already documents as
    /// exponential and FRONT LOADED (Borbely; Achermann 1993). The nap charge
    /// closed it on a straight line, `napSeconds / sleepNeed`. A nap is by
    /// definition entirely front loaded sleep, so the straight line
    /// systematically under credited it exactly where the model says sleep is
    /// most effective: an hour's nap returned about a third of what an hour of
    /// night returns, for no stated reason. It now rides the same curve the
    /// night does, discounted by `napRestorationFactor`.
    ///
    /// INCREMENTAL ON PURPOSE. Under an exponential law, charging thirty minutes
    /// and then another thirty is NOT charging sixty: the second half is worth
    /// less than the first. The caller walks the day in buckets, so it passes
    /// the cumulative nap hours before and after this bucket and gets the
    /// difference, which is the same `before` / `after` shape the homeostatic
    /// drain in the same loop already uses.
    ///
    /// `alreadyCharged` is the day's nap credit so far, so the cap is enforced
    /// here rather than by every caller remembering to.
    static func napCharge(level: Double,
                          hoursBefore: Double,
                          hoursAfter: Double,
                          alreadyCharged: Double) -> Double {
        guard hoursAfter > hoursBefore else { return 0 }
        let headroom = max(0, 100 - clampBattery(level))
        guard headroom > 0 else { return 0 }
        // NOT `sleepClosureFraction` directly. That function answers a NIGHT's
        // question, so it treats a missing or zero duration as "no duration
        // recorded" and falls back to the legacy flat 0.72. Here zero hours
        // means zero hours: napping for no time closes nothing. Reading the
        // fallback as a starting point made the first stretch of every nap come
        // out NEGATIVE, clamped to zero, so the opening minutes of a nap were
        // silently free. Caught by
        // `testTheSecondHalfHourOfANapIsWorthLessThanTheFirst`, which saw the
        // first half hour score 0 and the second score 3.25.
        func closure(_ hours: Double) -> Double {
            hours > 0 ? sleepClosureFraction(sleepHours: hours) : 0
        }
        let closed = closure(hoursAfter) - closure(hoursBefore)
        let gross = headroom * closed * nightClosureMax * napRestorationFactor
        return min(max(0, napChargeCap - alreadyCharged), max(0, gross))
    }

    /// How much last night's recovery (HRV vs baseline, REM share) scales the
    /// night's charge efficiency. ~0.80..1.15; 1.0 when inputs are absent.
    static func recoveryChargeMultiplier(hrv: Double?, hrvBaseline: Double?,
                                         remFraction01: Double?) -> Double {
        var mult = 1.0
        if let hrv, let base = hrvBaseline, base > 0 {
            mult += min(1, max(-1, (hrv - base) / base)) * 0.10
        }
        if let rem = remFraction01 {
            mult += min(0.10, max(-0.10, rem - 0.20)) * 0.5
        }
        return min(1.15, max(0.80, mult))
    }

    // MARK: - Drain gate (stress SHAPES the burn, it does not resize it)

    // The homeostatic burn alone is a function of the clock: it charges an
    // hour of meditation exactly what it charges an hour of a tense
    // meeting. Firstbeat's model does the opposite, driving the drain off
    // the autonomic signal, which is why a Garmin curve flattens during a
    // calm stretch and can tick upward during a genuinely quiet one.
    //
    // The gate is a multiplier on the homeostatic step, centered on the
    // day's OWN mean stress and normalized so its awake-time-weighted mean
    // is exactly 1. Two consequences, both deliberate:
    //
    //   - The day's TOTAL burn is unchanged, so the intraday curve and the
    //     daily ledger still land on the same evening value. The gate
    //     redistributes the budget, it never inflates it. That is what
    //     keeps the number shown tonight equal to the number carried into
    //     tomorrow, which the previous static-stress term broke.
    //   - It is self-centering, so it reads "calm FOR YOU" rather than
    //     calm against a population constant, and it cannot be fooled by
    //     someone whose resting heart rate simply runs high.
    //
    // A bucket far enough below the day's mean gets a NEGATIVE gate: the
    // battery genuinely recovers during a quiet stretch, at up to half the
    // rate it would otherwise have burned.

    /// Most negative gate: a genuinely quiet stretch recovers at half the
    /// rate it would have burned (~0.8 points/hour mid-day).
    static let drainGateMin = -0.50
    /// Most positive gate: a tense stretch burns 1.6x. Capped so that one
    /// bad hour cannot eat the day.
    static let drainGateMax = 1.60
    /// How many stress points below the day's mean buy a full unit of
    /// gate. FIXED, deliberately, and not the day's own spread: a
    /// spread-relative divisor is self-cancelling, because a day with big
    /// swings gets a big divisor and flattens the very gate its swings
    /// should have opened. Measured on a bimodal day (calm morning, tense
    /// afternoon) a MAD-based divisor came out at 34.8 and left the calm
    /// buckets at gate 0.27 instead of recharging. Fixed at 18 points, a
    /// flat day still self-neutralizes (every bucket sits near the mean,
    /// so every gate sits near 1) without needing a floor at all.
    static let drainGateSpread = 18.0
    /// Below this many usable stress buckets there is not enough signal to
    /// shape a day, and every gate stays 1 (an honest "no opinion").
    static let drainGateMinBuckets = 4

    /// Raw, un-normalized gate for one bucket.
    static func drainGate(stress: Double, dayMean: Double) -> Double {
        let raw = 1 + (stress - dayMean) / drainGateSpread
        return min(drainGateMax, max(drainGateMin, raw))
    }

    /// Mean-preserving gates for a whole day, one per input bucket.
    ///
    /// `stress` is 0..100 per bucket, nil where nothing was measured;
    /// `awakeHours` is the awake time of that same bucket. Buckets that
    /// are asleep or unmeasured get a gate of 1 and take no part in the
    /// weighting. Returns an array the same length as `stress`.
    ///
    /// The normalization runs a few times because the clamps leak: scaling
    /// pushes some gates past `drainGateMax`, clipping them loses part of
    /// the correction, and re-scaling recovers most of what was lost. On a
    /// day violent enough to peg gates at BOTH ends it cannot converge all
    /// the way, and settles a few percent under 1. That residue is
    /// deliberate and one-directional: such a day drains slightly less
    /// than the ledger predicted, never more, so the gate can never invent
    /// fatigue the daily budget did not account for.
    static func drainGates(stress: [Double?], awakeHours: [Double]) -> [Double] {
        var gates = [Double](repeating: 1, count: stress.count)
        var usable: [(index: Int, stress: Double, hours: Double)] = []
        for (index, value) in stress.enumerated() {
            let hours = index < awakeHours.count ? awakeHours[index] : 0
            guard let value, hours > 0 else { continue }
            usable.append((index, min(100, max(0, value)), hours))
        }
        let totalHours = usable.reduce(0) { $0 + $1.hours }
        guard usable.count >= drainGateMinBuckets, totalHours > 0 else { return gates }

        let mean = usable.reduce(0) { $0 + $1.stress * $1.hours } / totalHours
        var shaped = usable.map { drainGate(stress: $0.stress, dayMean: mean) }

        for _ in 0..<6 {
            let weighted = zip(shaped, usable).reduce(0) { $0 + $1.0 * $1.1.hours }
            guard weighted > 0.0001 else { break }
            let scale = totalHours / weighted
            shaped = shaped.map { min(drainGateMax, max(drainGateMin, $0 * scale)) }
        }
        for (slot, entry) in usable.enumerated() { gates[entry.index] = shaped[slot] }
        return gates
    }
}
