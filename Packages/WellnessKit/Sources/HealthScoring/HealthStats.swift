//
//  HealthStats.swift
//  HealthScoring (ported from the previous app, behaviour unchanged)
//
//  The ONE statistical base every health engine builds on.
//
//  Why this file exists. The 2026-07-25 audit found the same statistics
//  reimplemented across 35 engines with incompatible answers: four standard
//  deviation estimators (only one floored), twelve different "minimum data"
//  thresholds, three definitions of sleep debt disagreeing by a factor of ten,
//  a z threshold of 1.5 applied to baselines of 7 nights as if the standard
//  deviation were known exactly, and score neutrals assumed to be 50 when the
//  real neutral of daily stress is 35. Two engines carried byte-identical
//  copies of the same `baselineStats`. Each divergence on its own is small;
//  together they let two screens of the same app answer the same question
//  differently, which is the one thing a health app must never do.
//
//  Rules for engines, in order:
//    1. Never compute a mean, a standard deviation, a z score, a data gate or
//       a 0...100 score inline. Call this file.
//    2. Declare the spread floor of your metric in `SpreadFloor`, never inline
//       a magic number.
//    3. Return Optional for a genuine gap. A fabricated 0 that renders like a
//       measurement is the most damaging defect this file exists to prevent.
//
//  Everything here is pure, Foundation-only and `nonisolated`, matching the
//  engine template under Core/GodPowers/Engines. That also lets the whole file
//  be compiled and exercised standalone, which is how its numbers were checked
//  (see HealthScoringTests/HealthStatsTests.swift for the locked anchor cases).
//

import Foundation

enum HealthStats {

    // MARK: - Direction

    /// Which way a metric moves when the thing we watch for gets worse.
    /// Canonical for the whole app: `IllnessSignalModel.Direction` is a
    /// typealias onto this so there is one type, not two.
    enum Direction: Sendable, Hashable {
        case higherIsWorse
        case lowerIsWorse

        /// Orients a raw deviation so positive always means "worse".
        func oriented(_ rawDeviation: Double) -> Double {
            self == .higherIsWorse ? rawDeviation : -rawDeviation
        }
    }

    // MARK: - Data gates

    /// The only three "enough data" tiers in the app. Engines pick a tier by
    /// name; none invents its own integer. Chosen to line up with what the
    /// codebase already agreed on twice: `CircadianAlignment
    /// .mediumConfidenceNights` = 14 and `RealHealthMath.confidence(n)` =
    /// min(1, n/14).
    enum DataGate: Int, Sendable, CaseIterable, Comparable {
        /// Enough to say something with an explicit low-confidence marker.
        /// Never enough to state a threshold verdict or alert.
        case minimum = 3
        /// Enough for a personal baseline and a drift verdict.
        case reliable = 7
        /// Enough for a full-confidence reading; shrinkage reaches 1.0 here.
        case confident = 14

        var nights: Int { rawValue }

        static func < (a: DataGate, b: DataGate) -> Bool { a.rawValue < b.rawValue }

        /// The highest tier `count` satisfies, or nil when it clears none.
        /// A nil result is the engine's cue to return no data rather than a
        /// low-confidence number.
        static func tier(for count: Int) -> DataGate? {
            allCases.reversed().first { count >= $0.nights }
        }

        func isMet(by count: Int) -> Bool { count >= nights }
    }

    /// Shrinkage toward the neutral for a thin history: 0 at no data, 1.0 at
    /// `DataGate.confident`. Generalises `RealHealthMath.confidence(n)`, which
    /// already had the right idea and was the only place applying it.
    ///
    /// Use this instead of a hardcoded points cap. A capped penalty says "this
    /// signal can move the score by at most N"; shrinkage says "with little
    /// history, pull the whole score toward its neutral", which is what thin
    /// evidence actually justifies.
    static func confidence(count: Int, full: Int = DataGate.confident.nights) -> Double {
        guard count > 0, full > 0 else { return 0 }
        return min(1, Double(count) / Double(full))
    }

    /// Applies shrinkage: pulls `value` toward `neutral` in proportion to how
    /// far the history falls short of `full`.
    static func shrunk(_ value: Double, toward neutral: Double,
                       count: Int, full: Int = DataGate.confident.nights) -> Double {
        let c = confidence(count: count, full: full)
        return neutral + (value - neutral) * c
    }

    // MARK: - Spread floors

    /// Minimum plausible spread per metric, so a flat or coarsely quantised
    /// window cannot divide by ~0 and turn sensor rounding into a 2.5 sigma
    /// alert. Values that already existed in the app are reused verbatim
    /// rather than re-picked, so this table introduces no new divergence.
    enum SpreadFloor {
        /// Verbatim from `StressEngine.logHRVSpreadFloor`.
        static let logHRV = 0.05
        /// Verbatim from `StressEngine.rhrSpreadFloor`, in bpm.
        static let restingHR = 2.0
        /// Percentage points. Overnight SpO2 spread is typically 0.4...0.8 pt,
        /// so a 1 pt dip must not read as 2.5 sigma.
        static let bloodOxygen = 0.6
        /// Degrees Celsius of wrist temperature deviation.
        static let wristTemperature = 0.15
        /// Breaths per minute.
        static let respiratoryRate = 0.5
        /// Hours of sleep.
        static let sleepHours = 0.25
        /// Milliseconds of RMSSD, for engines comparing raw (not log) HRV.
        static let hrvMilliseconds = 3.0
        /// Points, for a 0...100 score used as its own baseline.
        static let scorePoints = 3.0
    }

    // MARK: - Robust baseline

    /// A personal baseline: robust center, floored spread, and the sample size
    /// that produced them.
    ///
    /// Center is the MEDIAN and spread is a floored 1.4826 * MAD, not mean and
    /// sample standard deviation. That matters for exactly the case these
    /// engines hit: one aberrant night would otherwise shift the mean AND
    /// inflate the standard deviation, masking the nights that follow it.
    struct Baseline: Sendable, Equatable {
        let center: Double
        let spread: Double
        /// Number of observations behind `center` / `spread`.
        let count: Int

        /// Deviation of `value` in personal standard deviations, oriented so
        /// positive means worse.
        func z(_ value: Double, direction: Direction = .higherIsWorse) -> Double {
            guard spread > 0 else { return 0 }
            return direction.oriented((value - center) / spread)
        }

        var gate: DataGate? { DataGate.tier(for: count) }
        var confidence: Double { HealthStats.confidence(count: count) }
    }

    /// Robust center and floored spread of `values`.
    ///
    /// Returns nil below `DataGate.minimum` observations: with one or two
    /// points there is no personal distribution to speak of, and a spread that
    /// falls back to the floor alone would present the floor as a measurement.
    static func baseline(_ values: [Double],
                         spreadFloor: Double,
                         gate: DataGate = .minimum) -> Baseline? {
        let clean = values.filter { $0.isFinite }
        guard gate.isMet(by: clean.count) else { return nil }
        let center = median(clean)
        let deviations = clean.map { abs($0 - center) }
        let spread = max(spreadFloor, 1.4826 * median(deviations))
        return Baseline(center: center, spread: spread, count: clean.count)
    }

    /// Causal baseline over a daily series: uses only the days STRICTLY BEFORE
    /// `endingBefore`, optionally skipping indices the caller knows are not
    /// representative.
    ///
    /// Causality is the point. The two engines this replaces built their
    /// baseline from the whole window, future included, and admitted it in a
    /// comment. `excluding` is what makes a "sea level" baseline actually mean
    /// sea level: an Altitude Shield trek passes its altitude nights here, and
    /// the same parameter serves travel nights (First Night Fix), illness days,
    /// and luteal days (True Baseline).
    ///
    /// - Parameters:
    ///   - series: daily values, oldest first, nil for a day with no data.
    ///   - endingBefore: index of the day being judged. Excluded from its own
    ///     baseline, which is what makes the resulting z honest.
    ///   - window: how many days back to consider. nil means all history.
    ///   - excluding: indices to leave out entirely.
    static func causalBaseline(_ series: [Double?],
                              endingBefore index: Int,
                              window: Int? = nil,
                              excluding: Set<Int> = [],
                              spreadFloor: Double,
                              gate: DataGate = .minimum) -> Baseline? {
        guard index > 0, index <= series.count else { return nil }
        let lower = window.map { max(0, index - $0) } ?? 0
        var values: [Double] = []
        for i in lower..<min(index, series.count) where !excluding.contains(i) {
            if let v = series[i], v.isFinite { values.append(v) }
        }
        return baseline(values, spreadFloor: spreadFloor, gate: gate)
    }

    /// Convenience for the dominant shape: judge the most recent value of a
    /// daily series against every earlier day in the window.
    ///
    /// Replaces the byte-identical `baselineStats` in `BreathingRadarEngine`
    /// and `AltitudeShieldEngine`. Unlike those, it does not compact the series
    /// before taking "latest": a compacted `last` silently returns a value that
    /// may be days old and presents it as tonight's. Here the latest day must
    /// actually hold a value.
    static func latestVersusBaseline(_ series: [Double?],
                                     window: Int? = nil,
                                     excluding: Set<Int> = [],
                                     spreadFloor: Double,
                                     gate: DataGate = .reliable)
        -> (latest: Double, baseline: Baseline)? {
        guard let lastIndex = series.indices.last,
              let latest = series[lastIndex], latest.isFinite,
              let base = causalBaseline(series, endingBefore: lastIndex,
                                        window: window, excluding: excluding,
                                        spreadFloor: spreadFloor, gate: gate)
        else { return nil }
        return (latest, base)
    }

    // MARK: - Drift threshold

    /// One-sided false positive rate per signal per night that the drift
    /// threshold targets. 0.0668 is the tail the legacy constant 1.5 implied
    /// under a known standard deviation, so `driftThreshold` converges to 1.5
    /// as the baseline grows: behaviour tuned at large n is preserved, and only
    /// the small-n case (the actual source of false alerts) tightens.
    static let defaultDriftAlpha = 0.0668

    /// Deviation, in personal standard deviations, past which a signal counts
    /// as drifted, given how many nights the baseline rests on.
    ///
    /// The legacy constant 1.5 treated the baseline standard deviation as if it
    /// were known exactly. It is not: estimated from n nights it carries a
    /// relative error of 1/sqrt(2(n-1)), which is 29% at n = 7. The correct
    /// statistic for "is today an outlier against a baseline of n" is
    ///
    ///     t = (x - center) / (s * sqrt(1 + 1/n))     ~ t(n - 1)
    ///
    /// so the bar in units of s is `t(1-alpha, n-1) * sqrt(1 + 1/n)`. The
    /// sqrt term is the part every engine omitted: today's value is itself a
    /// draw, not the population mean.
    ///
    /// At alpha = 0.0668 this returns 2.833 at n = 3, 1.854 at n = 7, 1.656 at
    /// n = 14, 1.571 at n = 29 and 1.500 in the limit, so a thin baseline now
    /// demands a bigger excursion instead of alerting more often. These are the
    /// values the implementation actually produces, checked in
    /// `HealthStatsTests.testDriftThresholdAnchors`, not estimates.
    static func driftThreshold(baselineCount n: Int,
                               alpha: Double = defaultDriftAlpha) -> Double {
        guard n >= 2 else { return .infinity }   // no spread, never alert
        let t = studentTQuantile(upperTail: alpha, degreesOfFreedom: n - 1)
        return t * (1 + 1.0 / Double(n)).squareRoot()
    }

    /// Probability that at least `minDeviating` of `signals` independent
    /// signals cross their threshold on a quiet night.
    ///
    /// Read it as an OPTIMISTIC bound, not a rate. The overnight signals these
    /// engines watch (SpO2, respiratory rate, resting HR, HRV) move together
    /// under one mechanism, so treating "two of them drifted" as independent
    /// corroboration overstates the evidence. Exposed so an engine can at
    /// least see the number it is implicitly choosing.
    static func alertRateUnderNull(signals k: Int, minDeviating m: Int,
                                   perSignalAlpha alpha: Double = defaultDriftAlpha) -> Double {
        guard k > 0, m > 0, m <= k, alpha > 0, alpha < 1 else { return 0 }
        var tail = 0.0
        for i in m...k {
            tail += binomialCoefficient(k, i) * pow(alpha, Double(i)) * pow(1 - alpha, Double(k - i))
        }
        return min(1, max(0, tail))
    }

    /// Per-signal alpha that makes "at least `m` of `k` drifted" fire about
    /// once every `everyNights` quiet nights. Lets an engine declare the alert
    /// rate it wants instead of inheriting whatever a shared 1.5 produced for
    /// its particular signal count.
    static func perSignalAlpha(forOneAlertEvery everyNights: Double,
                               signals k: Int, minDeviating m: Int) -> Double {
        guard everyNights > 1, k > 0, m > 0, m <= k else { return defaultDriftAlpha }
        let target = 1 / everyNights
        var lo = 1e-6, hi = 0.5
        for _ in 0..<80 {
            let mid = (lo + hi) / 2
            if alertRateUnderNull(signals: k, minDeviating: m, perSignalAlpha: mid) < target {
                lo = mid
            } else {
                hi = mid
            }
        }
        return (lo + hi) / 2
    }

    // MARK: - Score scales

    /// The REAL neutral of each 0...100 score in the app.
    ///
    /// Assuming 50 is the neutral of every score is a live defect: the daily
    /// stress model is calibrated so a typical day reads 35, so an engine that
    /// compares stress against 50 concludes "below neutral" on an ordinary day
    /// and its adverse verdict becomes unreachable. Any engine that centers,
    /// inverts or offsets a score reads its neutral from here.
    enum ScoreScale: String, Sendable, CaseIterable {
        case recovery
        case stressDaily
        case sleep
        case genericCentered

        /// Value a typical day produces on this scale.
        var neutral: Double {
            switch self {
            case .recovery:        return 50   // RealHealthMath.recoveryBreakdown base
            case .stressDaily:     return 35   // StressEngine centered logistic at z = 0
            case .sleep:           return 50
            case .genericCentered: return 50
            }
        }

        /// True when a HIGHER value is the better outcome. Drives whether a
        /// readout inverts before being painted by the shared zone colours.
        var higherIsBetter: Bool {
            switch self {
            case .recovery, .sleep, .genericCentered: return true
            case .stressDaily: return false
            }
        }

        /// Signed deviation from this scale's real neutral, positive meaning
        /// better than typical.
        func deviation(_ value: Double) -> Double {
            let raw = value - neutral
            return higherIsBetter ? raw : -raw
        }
    }

    // MARK: - Canonical composite

    /// One input to a composite score: a 0...100 sub-score and its weight.
    /// A nil value means the signal is absent, which is different from zero.
    struct Component: Sendable {
        let value: Double?
        let weight: Double
        let label: String

        init(_ label: String, value: Double?, weight: Double) {
            self.label = label
            self.value = value
            self.weight = weight
        }
    }

    struct Composite: Sendable {
        let score: Double
        /// Signals that were actually present.
        let presentCount: Int
        /// Sum of the weights that were present, before renormalisation.
        /// Well under 1.0 means most of the model was missing, which a caller
        /// should surface rather than hide behind a confident number.
        let weightCovered: Double
        /// Present component with the worst (lowest) value, for a "what is
        /// holding this back" line.
        let limiter: String?
    }

    /// Weighted mean over the components actually present, renormalised on
    /// their weights.
    ///
    /// This is the app's canonical score shape, chosen because it was already
    /// implemented twice identically (`SkinForecastEngine`, `GreenLightEngine`)
    /// and because it handles a missing input natively instead of counting it
    /// as a zero. Returns nil when nothing is present: an honest gap, never a
    /// fabricated midpoint.
    ///
    /// Note on double counting: this assumes the components are distinct
    /// signals. Passing two inputs that are both driven by HRV weights HRV
    /// twice and quietly shrinks the composite's variance.
    static func composite(_ components: [Component]) -> Composite? {
        let present = components.filter { $0.value != nil && $0.weight > 0 }
        guard !present.isEmpty else { return nil }
        var weighted = 0.0, weightSum = 0.0
        for c in present {
            guard let v = c.value else { continue }
            weighted += c.weight * min(100, max(0, v))
            weightSum += c.weight
        }
        guard weightSum > 0 else { return nil }
        let limiter = present.min { ($0.value ?? 100) < ($1.value ?? 100) }?.label
        return Composite(score: min(100, max(0, weighted / weightSum)),
                         presentCount: present.count,
                         weightCovered: weightSum,
                         limiter: limiter)
    }

    /// Maps a mean positive z onto 0...100 for a "screening index" readout.
    ///
    /// Callers previously wrote `mean(max(0, z)) / 3 * 100` inline in four
    /// places, which has two problems this function makes explicit. Clipping
    /// negatives means a night BETTER than baseline cannot improve the index,
    /// and the mean of clipped normals is positive even when nothing is wrong
    /// (0.399 per signal), so the zero of the scale is unreachable and every
    /// band threshold is read against a floor of about 13 rather than 0.
    /// `subtractNullFloor` removes that bias so 0 means "as expected".
    static let zIndexFullScale = 3.0
    /// E[max(0, Z)] for a standard normal: 1/sqrt(2*pi).
    static let clippedNormalMean = 0.3989422804014327

    static func screeningIndex(zs: [Double],
                               fullScale: Double = zIndexFullScale,
                               subtractNullFloor: Bool = true) -> Double? {
        guard !zs.isEmpty, fullScale > 0 else { return nil }
        let clipped = zs.map { max(0, $0) }
        let mean = clipped.reduce(0, +) / Double(clipped.count)
        let adjusted = subtractNullFloor ? mean - clippedNormalMean : mean
        return min(100, max(0, adjusted / fullScale * 100))
    }

    // MARK: - Sleep debt

    /// Sleep debt, with the two meanings named apart.
    ///
    /// They were conflated: one screen showed 2.0 h and another 21 h for the
    /// same nights, both labelled "sleep debt in hours", because one meant last
    /// night's shortfall and the other a two-week cumulative sum. Naming them
    /// separately is the fix; a caller now has to say which one it means.
    enum SleepDebt {

        /// How far a single night fell short of the need. Never negative: a
        /// long night does not pre-pay a future one.
        ///
        /// See `NightSleepDebtScale` for how far one night's shortfall has to
        /// go before an engine calls it maximal. That scale is deliberately a
        /// separate, shared type: the number is a judgement about severity,
        /// not a property of the subtraction above.
        static func nightShortfallHours(asleepHours: Double?, needHours: Double?) -> Double? {
            guard let asleepHours, let needHours, needHours > 0 else { return nil }
            return max(0, needHours - asleepHours)
        }

        /// Cumulative debt over a window, and the surplus that offsets it.
        ///
        /// `net` is what a screen promising "paid back" must display: summing
        /// shortfalls alone means sleeping longer changes nothing and the debt
        /// only ever falls by nights ageing out of the window, which is not
        /// what "paying it down" means to a reader.
        ///
        /// A night with no data contributes nothing: a missing night is
        /// unknown, not a full deficit.
        struct Window: Sendable, Equatable {
            let shortfallHours: Double
            let surplusHours: Double
            let nightsCounted: Int
            /// The accumulator's final state. Stored, not derived: it is the
            /// LAST value of `series` over the same nights, so a caller can
            /// never read a net that disagrees with the curve it plots.
            let netHours: Double
        }

        /// Fraction of a long night's excess that counts against the debt.
        /// Recovery sleep is real but not one-for-one (Van Dongen 2003,
        /// Kitamura 2016), so this is a declared product judgment, not a
        /// measurement. One constant, so no surface can quietly pick another.
        static let surplusCredit: Double = 0.5

        /// Where the accumulator stops counting.
        ///
        /// It never returns to zero on its own: someone sleeping 30 min short
        /// every night gains 0.5 h a night and would reach 45 h in three
        /// months, which makes the chart unreadable and the number useless.
        /// Past this point the message is "chronic debt", and the exact count
        /// no longer changes any decision.
        static let ceilingHours: Double = 20

        /// Nights the displayed debt is accumulated over.
        ///
        /// A LIFETIME accumulator was the first design and it does not
        /// survive real data: it never returns to zero on its own, so anyone
        /// chronically short saturates at `ceilingHours` within months and
        /// every chart of it draws a flat line at the cap forever. A trailing
        /// window keeps the number responsive and keeps a card titled "last
        /// 14 nights" honest about its own window.
        ///
        /// One constant, because the modal, the metric page, the smart alarm
        /// and the challenge hero must all accumulate over the same nights.
        static let windowNights: Int = 14

        /// How far the balance may go NEGATIVE, i.e. the largest credit a run
        /// of long nights can build. One full night.
        ///
        /// Sleep banking is real: extending sleep before a period of
        /// restriction measurably protects performance (Rupp, Wesensten &
        /// Balkin 2009). It is not unlimited, hence a cap, and it does not
        /// keep for weeks, hence `creditHalfLifeNights` below. Both are
        /// declared product judgments, not measurements.
        static let creditFloorHours: Double = 8

        /// How fast an unused credit fades, in nights.
        ///
        /// The benefit of sleep extension is short-lived, so a credit earned a
        /// fortnight ago must not still be protecting anything: at three
        /// nights, a full 8 h credit is under 1 h after nine nights. Debt does
        /// NOT decay. Nothing repays it but sleep.
        static let creditHalfLifeNights: Double = 3

        /// Per-night multiplier derived from the half-life. Applied only while
        /// the balance is negative.
        static var creditDecayPerNight: Double {
            pow(0.5, 1 / creditHalfLifeNights)
        }

        /// Running sleep balance, night after night. One value per input,
        /// index aligned; nil until the first measured night is reached.
        ///
        /// SIGN CONVENTION: positive is debt, negative is credit. Every caller
        /// reading this as "hours of debt" must clamp at zero first, or it
        /// will report a credit as a negative debt.
        ///
        /// The two bounds are deliberately asymmetric, and so is the decay.
        /// Debt runs to `ceilingHours` and never fades; credit stops at
        /// `creditFloorHours` and halves every `creditHalfLifeNights`. That
        /// asymmetry is the whole safeguard: an uncapped, non-decaying credit
        /// would let one long weekend silently swallow the following weeks'
        /// deficits, which is exactly the defect the previous zero floor
        /// existed to prevent.
        ///
        /// A night with no data carries the balance forward, undecayed. A
        /// missing night is unknown, not a full deficit and not a night of
        /// ageing.
        static func series(_ nights: [(asleep: Double?, need: Double?)],
                           surplusCredit: Double = Self.surplusCredit,
                           ceilingHours: Double = Self.ceilingHours,
                           creditFloorHours: Double = Self.creditFloorHours) -> [Double?] {
            let decay = creditDecayPerNight
            var balance = 0.0
            var seen = false
            var out: [Double?] = []
            out.reserveCapacity(nights.count)
            for n in nights {
                if let asleep = n.asleep, let need = n.need, need > 0 {
                    seen = true
                    // The credit ages BEFORE tonight lands, so a credit earned
                    // tonight is not discounted on the very night it is earned.
                    if balance < 0 { balance *= decay }
                    let delta = need - asleep
                    balance += delta > 0 ? delta : delta * surplusCredit
                    balance = min(ceilingHours, max(-creditFloorHours, balance))
                }
                out.append(seen ? balance : nil)
            }
            return out
        }

        /// - Parameters:
        ///   - nights: (asleepHours, needHours) per night; nil entries skipped.
        ///   - surplusCredit: see the constant of the same name.
        ///   - ceilingHours: see the constant of the same name.
        /// No ceiling by default: a window is bounded by construction, so it
        /// has no runaway to guard against, and capping it would silently
        /// truncate a caller's own arithmetic. `series` keeps the cap because
        /// it runs over a lifetime.
        /// The credit floor is NOT lifted the way the ceiling is: it is a
        /// product rule about how much a good stretch may buy you, not a
        /// runaway guard, so it applies to a bounded window too.
        static func window(_ nights: [(asleep: Double?, need: Double?)],
                           surplusCredit: Double = Self.surplusCredit,
                           ceilingHours: Double = .infinity) -> Window {
            var short = 0.0, surplus = 0.0, counted = 0
            for n in nights {
                guard let asleep = n.asleep, let need = n.need, need > 0 else { continue }
                counted += 1
                let delta = need - asleep
                if delta > 0 { short += delta } else { surplus += -delta * surplusCredit }
            }
            let net = series(nights, surplusCredit: surplusCredit,
                             ceilingHours: ceilingHours).compactMap { $0 }.last ?? 0
            return Window(shortfallHours: short, surplusHours: surplus,
                          nightsCounted: counted, netHours: net)
        }
    }

    // MARK: - Circular hours

    /// Hour-of-day arithmetic on the 24 h circle.
    ///
    /// Duplicated geometry was a live source of bugs: a cutoff computed as
    /// `bedtime - 6` without a wrap goes negative for anyone asleep after
    /// midnight and silently disables a whole module. `CircadianMath` owns the
    /// richer circadian helpers; these are the three operations engines kept
    /// rewriting privately.
    enum Clock {
        /// Folds any hour onto [0, 24).
        static func wrap24(_ hour: Double) -> Double {
            let h = hour.truncatingRemainder(dividingBy: 24)
            return h < 0 ? h + 24 : h
        }

        /// Hours forward from `from` to `to` on the circle, always [0, 24).
        static func forward(from: Double, to: Double) -> Double {
            wrap24(to - from)
        }

        /// Shortest distance between two hours, [0, 12].
        static func distance(_ a: Double, _ b: Double) -> Double {
            let d = forward(from: a, to: b)
            return min(d, 24 - d)
        }

        /// Signed shortest delta from `a` to `b`, (-12, 12]. Positive means
        /// later. Use this instead of subtracting hours: a linear subtraction
        /// on wrapped hours is what turned an ultra-early riser into an
        /// evening chronotype and reversed a night-shift phase direction.
        static func signedDelta(from a: Double, to b: Double) -> Double {
            let d = forward(from: a, to: b)
            return d > 12 ? d - 24 : d
        }

        /// True when `hour` lies inside the window walking forward from
        /// `start` to `end`, handling a window that crosses midnight.
        static func contains(_ hour: Double, start: Double, end: Double) -> Bool {
            let span = forward(from: start, to: end)
            guard span > 0 else { return false }
            return forward(from: start, to: hour) <= span
        }
    }

    // MARK: - Correlation inference

    /// Two-sided p value for a Pearson r, from the Student t distribution.
    ///
    /// The app computed this through the normal CDF, which is optimistic in
    /// exactly the direction that sells a correlation: at n = 6 and r = 0.75
    /// the normal gives p = 0.023 while the correct t with 4 df gives 0.086,
    /// a factor of 3.7. The exact table lived in `TrendPrediction` all along.
    static func pearsonTwoSidedP(r: Double, n: Int) -> Double? {
        guard n >= 3 else { return nil }
        let rc = min(0.999999, max(-0.999999, r))
        let df = n - 2
        let t = abs(rc) * (Double(df) / (1 - rc * rc)).squareRoot()
        return 2 * studentTUpperTail(t, degreesOfFreedom: df)
    }

    /// 95% confidence interval for a Pearson r via the Fisher z transform.
    /// A correlation reported without one invites reading noise as a finding.
    static func pearsonConfidenceInterval(r: Double, n: Int) -> (low: Double, high: Double)? {
        guard n >= 4 else { return nil }
        let rc = min(0.999999, max(-0.999999, r))
        let z = 0.5 * log((1 + rc) / (1 - rc))
        let se = 1 / Double(n - 3).squareRoot()
        let crit = 1.959964
        return (tanh(z - crit * se), tanh(z + crit * se))
    }

    /// Benjamini-Hochberg step-up. Returns each input p value's q value, in
    /// the caller's original order.
    ///
    /// Needed wherever one target is screened against many candidates: sorting
    /// N candidates by |r| and keeping the top few guarantees surfacing noise
    /// (at n = 10 over 40 candidates the largest |r| under the null averages
    /// about 0.62, which the app's own wording calls "strong").
    static func benjaminiHochberg(_ pValues: [Double]) -> [Double] {
        let m = pValues.count
        guard m > 0 else { return [] }
        let order = pValues.enumerated().sorted { $0.element < $1.element }
        var q = [Double](repeating: 1, count: m)
        var running = 1.0
        for rank in stride(from: m, through: 1, by: -1) {
            let (idx, p) = order[rank - 1]
            running = min(running, p * Double(m) / Double(rank))
            q[idx] = min(1, max(0, running))
        }
        return q
    }

    // MARK: - Student t

    /// P(T > t) for t > 0, exact via the regularised incomplete beta function.
    static func studentTUpperTail(_ t: Double, degreesOfFreedom df: Int) -> Double {
        guard df >= 1 else { return .nan }
        guard t.isFinite else { return t > 0 ? 0 : 1 }
        let dfD = Double(df)
        let x = dfD / (dfD + t * t)
        let both = incompleteBeta(a: dfD / 2, b: 0.5, x: x)   // P(|T| > |t|)
        return t >= 0 ? both / 2 : 1 - both / 2
    }

    /// The t value whose upper tail equals `upperTail`. Bisection, which is
    /// slower than Newton and cannot diverge.
    static func studentTQuantile(upperTail p: Double, degreesOfFreedom df: Int) -> Double {
        guard df >= 1, p > 0, p < 1 else { return .nan }
        if p >= 0.5 { return -studentTQuantile(upperTail: 1 - p, degreesOfFreedom: df) }
        var lo = 0.0, hi = 1.0
        while studentTUpperTail(hi, degreesOfFreedom: df) > p, hi < 1e6 { hi *= 2 }
        for _ in 0..<200 {
            let mid = (lo + hi) / 2
            if studentTUpperTail(mid, degreesOfFreedom: df) > p { lo = mid } else { hi = mid }
        }
        return (lo + hi) / 2
    }

    /// Regularised incomplete beta I_x(a, b), by continued fraction with the
    /// standard symmetry swap for numerical stability.
    private static func incompleteBeta(a: Double, b: Double, x: Double) -> Double {
        if x <= 0 { return 0 }
        if x >= 1 { return 1 }
        let lbeta = lgamma(a + b) - lgamma(a) - lgamma(b)
        let front = exp(lbeta + a * log(x) + b * log(1 - x))
        if x < (a + 1) / (a + b + 2) {
            return front * betaContinuedFraction(a: a, b: b, x: x) / a
        }
        return 1 - exp(lbeta + b * log(1 - x) + a * log(x))
            * betaContinuedFraction(a: b, b: a, x: 1 - x) / b
    }

    /// Lentz's modified continued fraction for the incomplete beta.
    private static func betaContinuedFraction(a: Double, b: Double, x: Double) -> Double {
        let tiny = 1e-30
        let qab = a + b, qap = a + 1, qam = a - 1
        var c = 1.0
        var d = 1 - qab * x / qap
        if abs(d) < tiny { d = tiny }
        d = 1 / d
        var h = d
        for m in 1...300 {
            let mD = Double(m), m2 = 2 * mD
            var aa = mD * (b - mD) * x / ((qam + m2) * (a + m2))
            d = 1 + aa * d; if abs(d) < tiny { d = tiny }
            c = 1 + aa / c; if abs(c) < tiny { c = tiny }
            d = 1 / d
            h *= d * c
            aa = -(a + mD) * (qab + mD) * x / ((a + m2) * (qap + m2))
            d = 1 + aa * d; if abs(d) < tiny { d = tiny }
            c = 1 + aa / c; if abs(c) < tiny { c = tiny }
            d = 1 / d
            let del = d * c
            h *= del
            if abs(del - 1) < 3e-16 { break }
        }
        return h
    }

    // MARK: - Small helpers

    /// Median of an unsorted array. Zero for empty, which callers must gate
    /// on rather than pass through.
    static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let s = values.sorted()
        let n = s.count
        return n % 2 == 1 ? s[n / 2] : (s[n / 2 - 1] + s[n / 2]) / 2
    }

    /// Sample standard deviation (n - 1). Nil below two values, so a caller
    /// cannot mistake a single point for a spread of zero.
    static func sampleStdDev(_ values: [Double]) -> Double? {
        let clean = values.filter { $0.isFinite }
        guard clean.count >= 2 else { return nil }
        let mean = clean.reduce(0, +) / Double(clean.count)
        let ss = clean.reduce(0) { $0 + ($1 - mean) * ($1 - mean) }
        return (ss / Double(clean.count - 1)).squareRoot()
    }

    static func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
        min(hi, max(lo, v))
    }

    /// 0...100, the app's score range.
    static func clampScore(_ v: Double) -> Double { clamp(v, 0, 100) }

    private static func binomialCoefficient(_ n: Int, _ k: Int) -> Double {
        guard k >= 0, k <= n else { return 0 }
        return exp(lgamma(Double(n + 1)) - lgamma(Double(k + 1)) - lgamma(Double(n - k + 1))).rounded()
    }
}

/// How severe one night's shortfall has to be before an engine treats it as
/// maximal sleep pressure.
///
/// Its own top-level type, and shared, because the audit found the same
/// grandeur saturating at two different values: SleepForecastEngine capped the
/// prior-night shortfall at 2 h while BreakoutRiskEngine used 4 h, so a single
/// short night read twice as severe on one screen as on the other. One number,
/// one place, and the engines take their per-quantity gain from it rather than
/// each choosing where the scale ends.
enum NightSleepDebtScale {
    /// Hours of shortfall in a single night at which pressure is full.
    ///
    /// FOUR, AND THE CHOICE IS LOAD-BEARING. The two engines disagreed (sleep
    /// screens used 2 h, BreakoutRisk 4 h) and unifying them had to pick one.
    /// It picked 4, and `SleepForecastEngineTests` was migrated onto it, so its
    /// published durations and stage fractions now encode 4 h. BreakoutRisk's
    /// audit fixtures still encode 2 h, because that engine's remediation was
    /// never landed until 2026-09-06; two of its incidental expected values
    /// were restated then rather than moving this constant back and breaking
    /// five landed assertions on the sleep side.
    static let saturationHours: Double = 4.0

    /// `hours` expressed on 0...1 against that saturation. Never negative: a
    /// long night does not pre-pay a future one.
    static func pressure01(hours: Double) -> Double {
        guard saturationHours > 0 else { return 0 }
        return min(max(hours, 0) / saturationHours, 1)
    }
}
