//
//  RealHealthMath.swift
//  HealthScoring (ported from the previous app, behaviour unchanged)
//
//  Pure math for the real-data backend: personal baselines, the
//  Edwards TRIMP training-load model, the personalized sleep need,
//  and the per-day score rollups. Formula rationale lives in
//  HEALTH_BACKEND.md at the repo root.
//
//  Everything here is deterministic and side-effect free; it runs on
//  the snapshot right after the HealthKit queries.
//

import Foundation

// MARK: - Recovery breakdown

/// One signed contribution to the recovery score, with the raw
/// numbers behind it so the UI can show exactly why the score is
/// what it is.
struct RecoveryContribution: Identifiable {
    enum Kind: String { case hrv, rhr, sleep, rest }
    var id: String { kind.rawValue }
    let kind: Kind
    /// Signed points after shaping, confidence and the per-term cap.
    let points: Double
    /// Today's reading (ms / bpm / sleep score), nil for the rest credit.
    let value: Double?
    /// Personal baseline (ms / bpm), nil for sleep and rest.
    let baseline: Double?
}

/// The full recovery computation: the 50 baseline plus every signed
/// term, the pre-clamp total (so the UI can flag a score capped at
/// 100 or 0), and the final 0-100 score.
struct RecoveryBreakdown {
    let score: Int
    let baseline: Double
    let rawTotal: Double
    let contributions: [RecoveryContribution]
    /// Signals with no data today (the term was skipped, not faked).
    let missing: [RecoveryContribution.Kind]

    /// The raw total overshot 100: the score is capped, every signal
    /// is strongly in the user's favour.
    var clampedHigh: Bool { rawTotal >= 100.5 }
    var clampedLow: Bool { rawTotal <= -0.5 }
}

enum RealHealthMath {

    // MARK: Trailing windows

    /// The last `limit` MEASURED values strictly before `index`, oldest first.
    /// nil slots are skipped, so the window counts readings and not calendar
    /// days, which is what every rolling baseline in this app means by "the
    /// last 28 nights".
    ///
    /// Replaces the expression this app used to write inline:
    ///
    ///     series[..<index].compactMap { $0 }.suffix(limit)
    ///
    /// Same value, element for element (`TrailingWindowTests`
    /// pins that against the expression itself). Different cost, and that is
    /// the whole point: the expression walks and ALLOCATES the entire prefix
    /// before throwing all but `limit` away, so calling it once per day is
    /// quadratic in the length of the series. This walks backward and stops at
    /// `limit`, which makes it O(limit) per call whatever the history is.
    ///
    /// Measured on device 2026-08-24, before the change:
    /// `nightMisalignmentSeries` 1063 ms per rebuild, and
    /// `IllnessEpisodeEngine.deviationSeries`
    /// most of another 940 ms, on a 3650-day series. Together they were 98% of
    /// every derived-memo cascade, and the cascades were 97% of the Home
    /// column's cost. Nothing about that is visible in the expression, which is
    /// why it survived so long: it reads as a slice, and slices look cheap.
    ///
    /// An `index` past the end clamps rather than trapping, matching
    /// `series[..<min(index, count)]`. A non-positive `limit` returns empty.
    ///
    /// `maxLookback` caps how far back the walk may reach, in SLOTS, which is
    /// what keeps the cost bounded rather than merely smaller. Without it the
    /// walk is O(distance to `limit` values), which is short on a dense history
    /// and unbounded on a sparse one: a series holding a reading every three
    /// weeks makes every day scan most of a year. See `baselineLookbackDays`
    /// for why the callers pass 365 and not less.
    ///
    /// CALLER NOTE. Sites that used to guard on the count of the FULL prefix
    /// (`prior.count >= minimum`) can guard on this window's count instead,
    /// but only while `limit >= minimum`: below that the window saturates and
    /// the two guards stop agreeing. Both current callers satisfy it (28 >= 7)
    /// and the suite pins it.
    static func trailingValues(_ series: [Double?],
                               before index: Int,
                               limit: Int,
                               maxLookback: Int) -> [Double] {
        guard limit > 0, maxLookback > 0 else { return [] }
        let upper = min(index, series.count)
        var cursor = upper - 1
        guard cursor >= 0 else { return [] }
        // Written as a comparison rather than `max(0, upper - maxLookback)`:
        // that subtraction OVERFLOWS and traps for a very large `maxLookback`,
        // which is exactly what a caller passes when it means "no cap".
        let earliest = upper > maxLookback ? upper - maxLookback : 0
        var window: [Double] = []
        window.reserveCapacity(limit)
        while cursor >= earliest, window.count < limit {
            if let value = series[cursor] { window.append(value) }
            cursor -= 1
        }
        // Collected newest first; the callers and the expression this replaces
        // both read oldest first.
        window.reverse()
        return window
    }

    /// How far back a rolling baseline may reach for its window, in days.
    ///
    /// One year, and the number is measured rather than picked. Benchmarked on
    /// a 3650-day series over the four signals `IllnessEpisodeEngine` tracks,
    /// at `-Onone`, against the same walk with no cap:
    ///
    ///     fill rate   uncapped   at 365d   days whose window changes
    ///     90%           85.9ms    41.7ms   0 of 2001
    ///     12%          115.6ms    63.0ms   0 of 1922
    ///      4%          190.1ms    68.4ms   1615 of 1864
    ///
    /// So at 365 the cap is free for any history a person could plausibly
    /// record, and it halves the walk. 180 was rejected on the same bench: it
    /// changed 1419 of 1922 days at 12% fill, which is a behaviour change
    /// wearing an optimisation's clothes.
    ///
    /// The histories that DO move at 365 hold fewer than seven measured nights
    /// in a whole year. There, the uncapped walk was averaging nights years
    /// apart and calling the result "the last 28 nights". Returning nil instead
    /// is the more honest answer, and it is the reason to prefer a cap over a
    /// bigger one: this is a correctness bound that happens to also be faster.
    static let baselineLookbackDays = 365

    // MARK: The open day

    /// Metric keys whose daily value ACCUMULATES through the day: a total that
    /// is only final at midnight. Read at 9 a.m. the current slot holds a few
    /// hundred steps, a few kcal, no training load at all, which is NOT a low
    /// day, only an unfinished one. Every consumer that compares days (trend
    /// direction, status pill, period deltas, chart scale) has to skip that
    /// slot, and every chart that draws it has to mark it as in progress.
    ///
    /// Point-in-time metrics are deliberately absent: HRV, resting HR, SpO2,
    /// wrist temperature, sleep score and the sleep durations all describe a
    /// measurement that is already over by the time the day starts, so their
    /// current slot is a finished reading.
    ///
    /// `strainPct` / `trimp` are here because the strain series is derived
    /// from the day's accumulated training load.
    ///
    /// Keys are the snapshot's own daily-series keys, and only ones that
    /// actually exist are listed, so a lookup here never quietly depends on a
    /// series the reader does not build.
    static let accumulatingKeys: Set<String> = [
        "steps", "activeEnergy", "exerciseMin", "standHours", "trimp", "strainPct"
    ]

    /// True when this metric's current-day slot is still filling up.
    static func isAccumulating(_ key: String) -> Bool {
        accumulatingKeys.contains(key)
    }

    /// How many trailing slots of a window are still accumulating, i.e. how
    /// much of its tail must be excluded from any day-to-day comparison and
    /// drawn as "in progress". One (today) for an accumulating metric on a
    /// window that ends on the current day; zero everywhere else, so a past
    /// selected day and every point-in-time metric are untouched.
    static func openDayTail(key: String, windowEndsToday: Bool) -> Int {
        (windowEndsToday && isAccumulating(key)) ? 1 : 0
    }

    /// `values` without its open tail: what a comparison is allowed to read.
    /// A series whose ONLY day is the open one comes back empty on purpose:
    /// the caller must then report no comparison (no status pill, no
    /// direction) rather than compare against a half-finished total.
    static func completedDays(_ values: [Double?], openDayTail tail: Int) -> [Double?] {
        guard tail > 0 else { return values }
        guard values.count > tail else { return [] }
        return Array(values.dropLast(tail))
    }

    // MARK: Direction of travel

    /// Where a series is HEADING over the days that are actually finished.
    enum TrendDirection: Sendable, Equatable { case rising, falling, flat }

    /// How far a metric has to move, in relative terms, before its direction is
    /// called rather than read as flat. A daily total swings by a fifth of
    /// itself from one day to the next (a rest day, a travel day, a sick day),
    /// so a 1.5 % dead band would hand it a fresh verdict every morning;
    /// point-in-time baselines (HRV, resting HR, weight) drift slowly and 1.5 %
    /// is already a real move for them.
    static func directionDeadBand(key: String?) -> Double {
        guard let key, isAccumulating(key) else { return 0.015 }
        return 0.05
    }

    /// Whether a RISING series is the good news for this metric. Tints a
    /// direction pill and the Trends Analysis rows, and nothing else. One map,
    /// so a tile and the modal it opens cannot paint the same move differently.
    ///
    /// nil is not "unknown", it is a deliberate verdict: the metric has no
    /// universal good way, so BOTH directions read informational blue rather
    /// than green or orange. Three families sit there on purpose:
    ///
    ///  - band metrics, whose target is a range and not a direction (wrist
    ///    temperature, respiratory rate, glucose, blood pressure, strain, the
    ///    sleeping-room temperature);
    ///  - schedule metrics, where earlier is neither better nor worse in
    ///    itself (bed time, wake time);
    ///  - body metrics the user may be moving either way on purpose (weight,
    ///    tape measurements). Losing 2 kg is a win for one person and a
    ///    warning for another, and a health app does not get to guess.
    ///
    /// Body FAT and LEAN mass are the exceptions in that family: they are
    /// composition, not mass, so their good way does not depend on the goal.
    static func risingIsGood(key: String?) -> Bool? {
        switch key {
        // More is better: what the user is trying to grow.
        case "steps", "activeEnergy", "exerciseMin", "standHours",
             "hrv", "camHRV", "spo2", "dipProxy", "vo2", "lean",
             "sleepHours", "sleepScore", "remHours", "deepHours",
             "recovery", "energy":
            return true
        // Less is better: the loads and the deficits.
        case "rhr", "camHR", "dayHR", "bodyFat", "stress", "bank",
             "envSound", "headphoneSound":
            return false
        // Everything else has no universal good way (see above).
        default:
            return nil
        }
    }

    /// Direction of travel over `values`, with the open day dropped first.
    ///
    /// This is what a daily total reports instead of a normal-range verdict:
    /// at 9 a.m. its current slot holds a fraction of a day, so "where is this
    /// heading over my finished days" is the only honest reading left.
    ///
    /// Compares the mean of the window's FIRST `k` known days against the mean
    /// of its LAST `k` (a week at most), not its first point against its last:
    /// on a month of steps, a single rest day at either end decided the verdict
    /// of the whole window.
    ///
    /// nil when there is nothing to compare (fewer than two finished readings,
    /// or an opening mean of zero). The caller must render that as NO pill: an
    /// invented "Stable" over a metric that was never measured reads as a
    /// measurement.
    static func trendDirection(_ values: [Double?], key: String? = nil,
                               openDayTail tail: Int = 0) -> TrendDirection? {
        let known = completedDays(values, openDayTail: tail).compactMap { $0 }
        guard known.count >= 2 else { return nil }
        let span = Swift.max(1, Swift.min(7, known.count / 2))
        let opening = known.prefix(span).reduce(0, +) / Double(span)
        let closing = known.suffix(span).reduce(0, +) / Double(span)
        guard abs(opening) > 0.0001 else { return nil }
        let change = (closing - opening) / abs(opening)
        let dead = directionDeadBand(key: key)
        if change > dead { return .rising }
        if change < -dead { return .falling }
        return .flat
    }

    // MARK: Normal-range standing

    /// Where a reading sits against its normal range. ONE definition, used by
    /// the detail modal hero and by the trend tile pill, so a tile can never
    /// claim "Normal range" while the modal it opens says "Below normal".
    enum BandStanding: Sendable, Equatable { case below, inside, above }

    /// A reading against a band. Edges are inclusive: sitting exactly on the
    /// floor or the ceiling is inside the range, matching the modal's own
    /// `last > bandHigh` / `last < bandLow` test.
    static func bandStanding(value: Double, lower: Double, upper: Double) -> BandStanding {
        // Tolerate an inverted band (a caller that swapped its edges) instead
        // of reporting a reading as both above and below.
        let low = Swift.min(lower, upper)
        let high = Swift.max(lower, upper)
        if value > high { return .above }
        if value < low { return .below }
        return .inside
    }

    // MARK: Series helpers

    /// Mean of the last `days` non-nil values.
    static func tailMean(_ series: [Double?]?, days: Int) -> Double? {
        guard let series else { return nil }
        let tail = series.suffix(days).compactMap { $0 }
        guard !tail.isEmpty else { return nil }
        return tail.reduce(0, +) / Double(tail.count)
    }

    /// Resolves "today's OWN" vital reading (see `HostStore.todayOwnHRV`):
    /// the preferred-method value or the night's average, in that order.
    /// `preferred` is NOT same-day by construction: some measurement-window
    /// sources ("mindful" / "sleepMindful") can resolve entirely from a
    /// session logged yesterday, so the caller must pass `nil` here unless
    /// it has already confirmed the window covers today (see
    /// `RealHealthSnapshot.hrvPreferredCoversToday` / `rhrPreferredCoversToday`
    /// and `RealHealthMath.windowsCoverToday`). `tailMean` is accepted only
    /// to make the contract explicit and testable: it is deliberately NEVER
    /// consulted, because (unlike the first two candidates) it can be
    /// several days old, and admitting it here would let a stale reading
    /// pass as today's own again. Extracted out of the host store so this
    /// regression guard is unit-testable without a live snapshot.
    static func todayOwnVital(preferred: Double?, nightAverage: Double?, tailMean: Double?) -> Double? {
        _ = tailMean
        return preferred ?? nightAverage
    }

    /// True when at least one measurement window actually reaches into
    /// today, i.e. its END falls after `startOfToday`. Windows are built
    /// ending at or before "now" (see `RealHealthReader.measurementWindows`),
    /// so checking the end alone is enough: a window that ends before
    /// today started was computed entirely from an earlier day (the
    /// "mindful" / "sleepMindful" sources can build a window purely from an
    /// evening session logged yesterday when nothing was logged today).
    /// Backs `RealHealthSnapshot.hrvPreferredCoversToday` /
    /// `rhrPreferredCoversToday`, which gate whether the preferred-method
    /// reading may count as "today's own" (`HostStore.todayOwnHRV` /
    /// `todayOwnRHR`). An empty window list never covers today.
    static func windowsCoverToday(_ windows: [(Date, Date)], startOfToday: Date) -> Bool {
        windows.contains { $0.1 > startOfToday }
    }

    /// Right-aligns a daily series onto a frame of `count` days.
    ///
    /// Every daily series in a snapshot shares one index frame: oldest-first,
    /// ending on the snapshot's generation day (`HostStore.seriesIndex(for:)`
    /// sizes every lookup off one of them). So a series read over a different
    /// window cannot be installed as-is; it has to be re-framed, and because
    /// both end on the same day the alignment is at the END: trim the extra
    /// history off the front, or pad the missing history with nils there.
    /// Padding with nil is honest, nil meaning "no data for that day", which
    /// is exactly what a shorter read knows about the days before its window.
    static func alignedSeries(_ series: [Double?], toCount count: Int) -> [Double?] {
        guard count >= 0 else { return series }
        if series.count == count { return series }
        if series.count > count { return Array(series.suffix(count)) }
        return Array(repeating: nil, count: count - series.count) + series
    }

    /// The slice of a daily series a trend sparkline should draw: the last
    /// `length` days when they hold enough real points, otherwise the most
    /// recent `length`-day span that DOES (a metric not recorded lately still
    /// shows its real history instead of a blank).
    ///
    /// Returns nil when the series cannot draw a trend at all (empty, or a
    /// single known day anywhere). Callers MUST treat that nil as "no data"
    /// and render a gap: the previous behaviour was to hand back a window of
    /// zeros, which the sparkline drew as a perfectly flat line pinned to the
    /// bottom of the frame, i.e. a measurement that never happened. Two points
    /// is the same threshold `realMasterSeries` and `cumulativeComplete` use,
    /// so a series either draws everywhere or reads as empty everywhere.
    ///
    /// Pure and so the window rule is unit-testable without a
    /// live snapshot.
    static func trendWindowBounds(_ raw: [Double?], length: Int = 31) -> Range<Int>? {
        guard !raw.isEmpty, length > 0 else { return nil }
        let tailStart = max(0, raw.count - length)
        if raw[tailStart...].compactMap({ $0 }).count >= 2 {
            return tailStart..<raw.count
        }
        guard let last = raw.lastIndex(where: { $0 != nil }) else { return nil }
        let end = last + 1
        let start = max(0, end - length)
        guard raw[start..<end].compactMap({ $0 }).count >= 2 else { return nil }
        return start..<end
    }

    /// True when a discrete vital's daily SERIES has to be re-read on its own,
    /// after a snapshot build left it empty while the metric's current reading
    /// resolved (`HostStore.backfillDiscreteVitals`).
    ///
    /// `hasReading` is the proof the device actually records the metric: it
    /// comes from the same accessor that decides whether the tile is shown at
    /// all, so a user who simply never measures SpO2 is never re-queried. The
    /// two-day floor is the chart's own threshold (`trendWindowBounds`): below
    /// it the tile can draw nothing, which is exactly the state worth curing,
    /// and at or above it the series is already usable and must be left alone.
    static func needsVitalSeriesBackfill(hasReading: Bool, knownDays: Int) -> Bool {
        hasReading && knownDays < 2
    }

    /// True while a night is recent enough to speak for CURRENT readiness: it
    /// is already over and its wake is no older than `maxAgeHours`. Backs
    /// `RealHealthSnapshot.readinessNight`, which lets recovery fall back to
    /// the last night actually measured when the current day recorded none,
    /// rather than reporting no data at all. The bound is what keeps that
    /// honest: one missed night still yields a readiness score, a watch left
    /// off for days does not.
    static func nightIsFreshForReadiness(wake: Date, now: Date,
                                         maxAgeHours: Double = 36) -> Bool {
        let ageHours = now.timeIntervalSince(wake) / 3600
        return ageHours >= 0 && ageHours <= maxAgeHours
    }

    /// Standard deviation of the last `days` non-nil values.
    static func tailStdDev(_ series: [Double?]?, days: Int) -> Double? {
        guard let series else { return nil }
        let tail = series.suffix(days).compactMap { $0 }
        guard tail.count > 3 else { return nil }
        let mean = tail.reduce(0, +) / Double(tail.count)
        var variance = 0.0
        for value in tail {
            variance += (value - mean) * (value - mean)
        }
        return (variance / Double(tail.count - 1)).squareRoot()
    }

    /// Per-day CAUSAL trailing mean: element i is the mean of the non-nil
    /// values in the last `days` calendar positions ENDING at i (window
    /// `[i-days+1 ... i]`). The defining property is prefix-independence:
    /// `trailingMeanSeries(s)[i]` depends only on `s[0...i]`, so a finished
    /// day's baseline never moves when newer data lands (the fix for
    /// history shifting day to day). At the final index it equals the old
    /// global `tailMean`, so "today" is unchanged. nil where the window
    /// holds no value.
    static func trailingMeanSeries(_ series: [Double?]?, days: Int) -> [Double?] {
        guard let series, days > 0 else { return [] }
        let n = series.count
        var result = [Double?](repeating: nil, count: n)
        for i in 0..<n {
            let start = max(0, i - days + 1)
            var sum = 0.0
            var count = 0
            var j = start
            while j <= i {
                if let value = series[j] { sum += value; count += 1 }
                j += 1
            }
            if count > 0 { result[i] = sum / Double(count) }
        }
        return result
    }

    /// Per-day CAUSAL trailing maximum over the non-nil values in the last
    /// `days` calendar positions ending at i. The causal twin of the global
    /// `series.suffix(days).max()` used for the strain normalizer
    /// (`trimp90Max`): a future high-load day can no longer change an
    /// earlier day's normalizer. Equals the global tail at the final index.
    static func trailingMaxSeries(_ series: [Double?]?, days: Int) -> [Double?] {
        guard let series, days > 0 else { return [] }
        let n = series.count
        var result = [Double?](repeating: nil, count: n)
        for i in 0..<n {
            let start = max(0, i - days + 1)
            var maxValue: Double? = nil
            var j = start
            while j <= i {
                if let value = series[j] {
                    maxValue = maxValue.map { Swift.max($0, value) } ?? value
                }
                j += 1
            }
            result[i] = maxValue
        }
        return result
    }

    /// Per-day CAUSAL robust spread (1.4826 x MAD, floored): the trailing
    /// twin of the stress engine's global spread, over the non-nil values
    /// in the last `days` positions ending at i, after `transform` (used in
    /// LOG space for HRV). Keeps a past day's stress z-score stable.
    static func trailingRobustSpreadSeries(_ series: [Double?]?, days: Int,
                                           floor: Double,
                                           transform: (Double) -> Double = { $0 })
        -> [Double?] {
        guard let series, days > 0 else { return [] }
        let n = series.count
        var result = [Double?](repeating: nil, count: n)
        for i in 0..<n {
            let start = max(0, i - days + 1)
            var window: [Double] = []
            var j = start
            while j <= i {
                if let value = series[j] { window.append(transform(value)) }
                j += 1
            }
            result[i] = StressEngine.robustSpread(window, floor: floor)
        }
        return result
    }

    /// Fills nil gaps by linear interpolation between neighbours so
    /// chart series stay continuous (leading/trailing gaps take the
    /// nearest known value).
    static func interpolated(_ series: [Double?]) -> [Double] {
        let count = series.count
        guard count > 0 else { return [] }
        guard let firstKnown = series.compactMap({ $0 }).first else {
            return Array(repeating: 0, count: count)
        }

        var result = Array(repeating: firstKnown, count: count)
        var lastKnownIndex = -1
        var lastKnownValue = firstKnown

        for index in 0..<count {
            guard let value = series[index] else { continue }
            if lastKnownIndex < 0 {
                for fill in 0...index { result[fill] = value }
            } else if index - lastKnownIndex > 1 {
                let span = Double(index - lastKnownIndex)
                for fill in (lastKnownIndex + 1)..<index {
                    let t = Double(fill - lastKnownIndex) / span
                    result[fill] = lastKnownValue + (value - lastKnownValue) * t
                }
                result[index] = value
            } else {
                result[index] = value
            }
            lastKnownIndex = index
            lastKnownValue = value
        }
        if lastKnownIndex >= 0, lastKnownIndex < count - 1 {
            for fill in (lastKnownIndex + 1)..<count { result[fill] = lastKnownValue }
        }
        return result
    }

    /// Rolling 14-day mean +/- 1 SD band around an interpolated
    /// series (the personal range painted behind the charts).
    static func rollingBand(_ values: [Double]) -> (lower: [Double], upper: [Double]) {
        let window = 14
        var lower: [Double] = []
        var upper: [Double] = []
        lower.reserveCapacity(values.count)
        upper.reserveCapacity(values.count)

        for index in 0..<values.count {
            let start = max(0, index - window + 1)
            let slice = values[start...index]
            let mean = slice.reduce(0, +) / Double(slice.count)
            var variance = 0.0
            for value in slice {
                variance += (value - mean) * (value - mean)
            }
            let sd = slice.count > 2
                ? (variance / Double(slice.count - 1)).squareRoot()
                : abs(mean) * 0.06
            let spread = max(sd, abs(mean) * 0.03)
            lower.append(mean - spread)
            upper.append(mean + spread)
        }

        // Warm-up flatten. The first `window - 1` slots are computed from a
        // partial, still-EXPANDING window, so their SPREAD is unstable and,
        // for the first one or two slots, deliberately inflated (the count<=2
        // fallback above seeds mean*0.06, e.g. +/-2.1 C on a 35.7 C wrist
        // temperature). When a chart recomputes the band over a single
        // truncated window (the modal's on-demand read, a custom calendar
        // range), that inflated edge painted a wide funnel at the LEFT of
        // every window that matched no real data and jumped on each paging
        // swipe. Hold the WIDTH at the first full-window value so the band
        // enters as a steady ribbon. The per-day mean (the band CENTER) is
        // untouched, so the level still tracks the data: only the width is
        // stabilized. Mid-series (full window) slots are unchanged.
        let firstFull = min(window - 1, values.count - 1)
        if firstFull > 0 {
            let stableSpread = (upper[firstFull] - lower[firstFull]) / 2
            for index in 0..<firstFull {
                let center = (upper[index] + lower[index]) / 2
                lower[index] = center - stableSpread
                upper[index] = center + stableSpread
            }
        }
        return (lower, upper)
    }

    // MARK: Training load (Edwards TRIMP)

    /// Edwards (1993) summated heart-rate-zone TRIMP: minutes in each
    /// of the five zones, weighted by the zone index.
    static func edwardsTRIMP(zoneSeconds: [Int]) -> Double {
        var trimp = 0.0
        for (index, seconds) in zoneSeconds.enumerated() where index < 5 {
            trimp += Double(seconds) / 60.0 * Double(index + 1)
        }
        return trimp
    }

    /// The ONE active-kilocalories-per-Edwards-TRIMP-point constant used by
    /// EVERY kcal->TRIMP conversion in the app (history `estimatedTRIMP`,
    /// the workout-kcal fallback, AND today's `todayTRIMP`). TRIMP is an
    /// intensity x duration construct, not an energy metric, so kcal are
    /// only a FALLBACK proxy for days/sessions that lack real HR zone
    /// seconds (decision doc D1.c). When a day has real zone seconds the
    /// kcal term only acts as a floor, never the headline.
    ///
    /// JUDGMENT CALL: 2.2 active kcal per TRIMP point. Derivation is the
    /// house "1 MET ~ 1 kcal/kg/h; TRIMP = minutes x HR-zone weight"
    /// heuristic, not a literature constant. The EXACT value matters less
    /// than the fact that history and today now share ONE scale: the
    /// previous `todayTRIMP` divisors (1/10 and 1/12) sat ~5x below this,
    /// so the same 500 kcal produced ~227 TRIMP in history but only ~42-50
    /// today, a hard scale break at the today/history boundary that crushed
    /// historical strain toward 0 against a today-dominated tau.
    static let activeKcalPerTrimp = 2.2

    /// JUDGMENT CALL: strain saturation tau as a multiple of chronic daily
    /// load (CTL/EWMA). tau = clamp(k x CTL, 200...1500) with k = 4.5, so a
    /// day at the chronic load reads ~20% and a day at 4.5x chronic ~63%,
    /// self-normalizing whatever the TRIMP currency. Replaces the prior
    /// `0.85 x trimp90Max` (90-day rolling MAX): a single marathon used to
    /// lift tau for ~90 days and depress every other day's strain%, a
    /// non-stationary normalizer the evidence rejects in favour of a stable
    /// central tendency (decision doc D2.b; Murray 2016 EWMA, ref [2]).
    /// The 420 ceiling that CTL tau initially inherited from the fallback
    /// clamp broke the self-normalization for every regular watch wearer
    /// (see `strainPercent`); the fallback path keeps its own 200...420.
    static let strainTauChronicMultiplier = 4.5

    /// Daily TRIMP estimate for history days where only daily aggregates
    /// survive (today uses the real zone seconds). Active energy already
    /// folds in workouts AND daily movement, so the strongest single
    /// signal is taken rather than summed (which would double-count).
    /// Exercise minutes / steps carry the day when active energy is
    /// missing, and the heart-rate reserve is the FLOOR so a day the
    /// heart was clearly beating (a wearable logged HR / RHR, hence a
    /// recovery score exists) never collapses to 0% strain just because
    /// the motion aggregates are absent (e.g. sleep/HRV trackers that do
    /// not write steps or active energy to Health).
    static func estimatedTRIMP(exerciseMinutes: Double?, steps: Double?,
                               activeKcal: Double? = nil,
                               dayHR: Double? = nil, restHR: Double? = nil,
                               maxHR: Double = 190, awakeHours: Double = 16,
                               male: Bool = true) -> Double? {
        let hasAggregate = exerciseMinutes != nil || steps != nil || activeKcal != nil
        let hrTrimp = heartRateReserveTRIMP(dayHR: dayHR, restHR: restHR,
                                            maxHR: maxHR, awakeHours: awakeHours,
                                            male: male)
        guard hasAggregate || hrTrimp != nil else { return nil }
        let kcalTrimp = (activeKcal ?? 0) / activeKcalPerTrimp
        // Apple exercise minutes accrue at brisk-walk intensity (>= ~3
        // METs), which is Edwards ZONE 2, so each minute earns weight 2.
        // The previous weight 4 treated every ring minute as a zone-4
        // minute and inflated no-workout days; genuinely hard sessions
        // are covered by the real zone-seconds TRIMP or kcal anyway.
        let exerciseTrimp = (exerciseMinutes ?? 0) * 2.0
        let stepTrimp = (steps ?? 0) / 120.0
        return max(max(kcalTrimp, exerciseTrimp), max(stepTrimp, hrTrimp ?? 0))
    }

    /// Banister / Morton exponential-weighted TRIMP from the day's mean
    /// heart rate over the awake window:
    ///   TRIMP = minutes x HRr x 0.64 x e^(1.92 x HRr),
    ///   HRr   = (HRmean - HRrest) / (HRmax - HRrest)
    /// The exponential weighting makes elevated-HR days count
    /// progressively more (Banister 1991; Morton, Fitz-Clarke & Banister
    /// 1990). It lands on the same TRIMP scale as the zone-seconds and
    /// active-kcal estimates, so the per-person tau keeps the displayed
    /// strain continuous across days that fall back to it. nil when no
    /// usable heart-rate pair exists.
    static func heartRateReserveTRIMP(dayHR: Double?, restHR: Double?,
                                      maxHR: Double, awakeHours: Double,
                                      male: Bool = true) -> Double? {
        guard let dayHR, let restHR, maxHR > restHR + 10 else { return nil }
        let reserve = max(0, min(0.9, (dayHR - restHR) / (maxHR - restHR)))
        // Quiet wakefulness alone holds the mean day HR ~10% of the
        // reserve above rest (posture, digestion, arousal), so only the
        // reserve ABOVE that baseline counts as training load. Banister's
        // formula is a per-SESSION construct; applying it raw to the
        // whole 16 h awake window scored a plain desk day 100-150 TRIMP
        // (25-30% strain) before any actual movement. The exponential
        // intensity weight stays on the full reserve.
        let loadReserve = max(0, reserve - 0.10)
        guard loadReserve > 0.01 else { return nil }
        let minutes = max(60, min(20, awakeHours) * 60)
        // Banister 1991 sex-specific HR-reserve weighting: men
        // 0.64*e^(1.92*HRr), women 0.86*e^(1.67*HRr) (Strain.md A.2).
        // Previously the male form was applied to everyone.
        let (a, b) = male ? (0.64, 1.92) : (0.86, 1.67)
        return minutes * loadReserve * a * exp(b * reserve)
    }

    /// Strain on a SATURATING curve (Whoop-style): equal TRIMP gets
    /// harder to convert as the day fills, so an easy walk reads ~10,
    /// a solid hour ~45 and only monster days approach 90+.
    ///   strain% = 100 x (1 - exp(-TRIMP / tau))
    ///
    /// tau is personalized by training history (heavier histories need
    /// more load for the same strain). PREFERRED source is the chronic
    /// DAILY load (CTL/EWMA): `tau = clamp(strainTauChronicMultiplier x
    /// chronicDailyTrimp, 200...420)`. This is STATIONARY: a single hard
    /// day no longer moves tau, so an earlier day's strain% stays put
    /// (decision doc D2.b). When `chronicDailyTrimp` is nil (thin history
    /// or cache built before CTL existed) we FALL BACK to the legacy
    /// `0.85 x trimp90Max` so the causal-stability contract and existing
    /// callers are byte-for-byte unchanged.
    ///
    /// Any real movement floors at 1%: a day you burned calories is
    /// never shown as a 0% day.
    static func strainPercent(trimp: Double, trimp90Max: Double,
                              chronicDailyTrimp: Double? = nil) -> Int {
        guard trimp > 0.5 else { return 0 }
        let tau: Double
        if let chronic = chronicDailyTrimp {
            // The CTL tau is SELF-NORMALIZING: a day at the chronic load
            // reads ~20% whatever the TRIMP currency, because the currency
            // cancels between the numerator and tau. The old shared 420
            // ceiling defeated exactly that: any regular watch wearer
            // carries a CTL above ~93 (700 active kcal/day alone is ~318
            // TRIMP), so tau pinned at 420 and an ordinary no-workout day
            // read 45-60% instead of ~20%. The ceiling now only guards
            // against absurd data spikes; the 200 floor still protects
            // thin histories from a hypersensitive scale.
            tau = min(1500, max(200, chronic * strainTauChronicMultiplier))
        } else {
            // Legacy trimp90Max fallback, byte-for-byte unchanged (the
            // causal-stability contract for thin histories / old caches).
            tau = min(420, max(200, trimp90Max * 0.85))
        }
        let value = 100 * (1 - exp(-trimp / tau))
        return max(1, Int(min(100, value).rounded()))
    }

    /// Personal strain TARGET for the day. With a training history,
    /// the band is anchored on the CHRONIC load (CTL-style EWMA of
    /// daily TRIMP) so it follows what your body is actually adapted
    /// to, and today's recovery slides the aim across the safe
    /// acute:chronic window. The aim is centred BELOW-to-around the
    /// chronic daily load (0.70x at low recovery, ~1.05x at full) and
    /// the band edges are kept INSIDE the ~0.8 to 1.35x window the
    /// evidence favours, so the daily target asks for a sustainable
    /// load, never a spike: the band top now lands near ~1.25x chronic
    /// at full recovery, where the prior 0.8 + 0.5r / x1.35 multipliers
    /// overshot to ~1.7x (and climbed with recovery, which was
    /// backwards). Without history the legacy recovery-only anchor
    /// stands, also gentled.
    static func strainTarget(recovery: Int, chronicDailyTrimp: Double? = nil,
                             trimp90Max: Double = 0) -> ClosedRange<Int> {
        if let chronic = chronicDailyTrimp, chronic > 8 {
            let readiness = Double(min(100, max(0, recovery))) / 100
            let midTrimp = chronic * (0.7 + readiness * 0.35)
            // The band converts through the SAME CTL tau as the displayed
            // strain (chronic passed through). Dropping it here sent the
            // band through the legacy trimp90Max tau while the actual
            // strain used the CTL tau: two different scales on one gauge.
            var lower = strainPercent(trimp: midTrimp * 0.78, trimp90Max: trimp90Max,
                                      chronicDailyTrimp: chronic)
            var upper = strainPercent(trimp: midTrimp * 1.22, trimp90Max: trimp90Max,
                                      chronicDailyTrimp: chronic)
            lower = max(4, min(lower, 86))
            upper = min(96, max(upper, lower + 12))
            return lower...upper
        }
        let lower = Int((6 + 0.26 * Double(recovery)).rounded())
        return lower...(lower + 20)
    }

    /// Chronic daily training load as a CTL-style EWMA of the daily
    /// TRIMP series (Banister/Coggan tau = 42 d, alpha = 1 - e^(-1/42)
    /// = 0.0235), the acute:chronic input Strain.md prefers over a
    /// rolling mean (more sensitive, Murray 2016) and the same
    /// definition CardioLoadService uses for CTL. Rest/missing days
    /// count as 0 load, because chronic load decays when you do not
    /// train; a nil-skipping mean would overstate it. nil until at
    /// least 5 real load-days exist. Pass the history ENDING the day
    /// before the target day (today's session is acute, not chronic).
    static func chronicDailyTRIMP(_ trimp: [Double?]) -> Double? {
        guard !trimp.isEmpty else { return nil }
        let alpha = 1 - exp(-1.0 / 42.0)
        var ctl = 0.0
        var realDays = 0
        for value in trimp {
            ctl = alpha * (value ?? 0) + (1 - alpha) * ctl
            if value != nil { realDays += 1 }
        }
        return realDays >= 5 ? ctl : nil
    }

    /// Per-day CAUSAL chronic-daily-TRIMP (CTL) series, aligned 1:1 with
    /// `trimp`: element i is the EWMA over `trimp[0...i-1]` (the load known
    /// the day BEFORE day i, since day i's own session is acute, not yet
    /// chronic), nil until >= 5 real load-days precede it. Same tau = 42 d
    /// EWMA as `chronicDailyTRIMP`, just streamed so every day gets its own
    /// stationary normalizer. Feeds `strainPercent(chronicDailyTrimp:)` so a
    /// past day's strain stays put when a later hard day arrives (the
    /// stationary replacement for the 90-day rolling max, decision doc D2.b).
    static func causalChronicDailyTRIMPSeries(_ trimp: [Double?]) -> [Double?] {
        let n = trimp.count
        guard n > 0 else { return [] }
        let alpha = 1 - exp(-1.0 / 42.0)
        var result = [Double?](repeating: nil, count: n)
        var ctl = 0.0
        var realDays = 0
        for i in 0..<n {
            // CTL ENDING the day before i: a day is normalized by the load
            // it was already adapted to, never by its own acute session.
            result[i] = realDays >= 5 ? ctl : nil
            ctl = alpha * (trimp[i] ?? 0) + (1 - alpha) * ctl
            if trimp[i] != nil { realDays += 1 }
        }
        return result
    }

    /// Standing for the daily "Strain Performance" headline: the most
    /// recent COMPLETED training day's strain measured against the
    /// personal target band. The current day is still accumulating, so
    /// reading it makes the card show "-XX% below target" every morning
    /// before you have trained. We skip the open day, then walk back over
    /// `lookback` finished days to the most recent real session (strain at
    /// or above the band floor). Rest days, missing days and the empty
    /// current day are skipped, so a light or not-yet-trained day never
    /// reads as a target miss. Returns nil when no recent session exists,
    /// so the UI shows an honest rest state instead of a fabricated
    /// negative (the prior 7-day mean of daily strain, which folds in rest
    /// days and the empty current day, sat structurally below a single
    /// recovery-elevated band and read negative almost every day).
    ///
    /// - Parameters:
    ///   - series: daily strain percentages (0-100), oldest first, the
    ///     current day last.
    ///   - band: the personal strain target zone (same 0-100 scale).
    ///   - dropCurrentDay: true when `series` ends on the still-open day.
    ///   - lookback: how many finished days back a session still counts.
    /// - Returns: `(delta vs band midpoint, isAbove)`, or nil for a rest
    ///   state.
    static func latestSessionStanding(series: [Double?],
                                      band: ClosedRange<Int>,
                                      dropCurrentDay: Bool,
                                      lookback: Int = 10)
        -> (delta: Int, isAbove: Bool)? {
        var index = series.count - 1
        if dropCurrentDay { index -= 1 }
        var scanned = 0
        while index >= 0, scanned < lookback {
            if let value = series[index], Int(value.rounded()) >= band.lowerBound {
                let mid = Double(band.lowerBound + band.upperBound) / 2
                let delta = Int(((value - mid) / max(1, mid) * 100).rounded())
                return (delta, Int(value.rounded()) > band.upperBound)
            }
            index -= 1
            scanned += 1
        }
        return nil
    }

    // MARK: Recovery

    /// Settings > Calculations > Recovery model. Cautious damps the
    /// positive deviations (one good night moves the score less) and
    /// amplifies the negative ones; Aggressive does the opposite.
    enum RecoveryModel: Sendable {
        case cautious, balanced, aggressive

        var positiveGain: Double {
            switch self {
            case .cautious: return 0.8
            case .balanced: return 1.0
            case .aggressive: return 1.2
            }
        }

        var negativeGain: Double {
            switch self {
            case .cautious: return 1.1
            case .balanced: return 1.0
            case .aggressive: return 0.9
            }
        }

        var restBonusCap: Double {
            switch self {
            case .cautious: return 2
            case .balanced: return 4
            case .aggressive: return 6
            }
        }
    }

    /// Per-term caps: no SINGLE signal can saturate the score, so a
    /// high number means every axis is strongly in the user's
    /// favour, not one inflated reading against a thin baseline.
    /// Deliberately tight (28+20+16+6 over the 50 baseline): even
    /// with everything in your favour the RAW total stays near 120,
    /// and the soft knee then keeps the displayed score in the 90s.
    static let recoveryHRVCap = 28.0
    static let recoveryRHRCap = 20.0
    static let recoverySleepCap = 16.0

    /// Full recovery breakdown (the score plus its signed terms).
    /// HRV and RHR are measured against the personal baselines, last
    /// night's sleep against 50, and a rest credit rewards a calm
    /// previous day. `hrvSamples` / `rhrSamples` are how many real
    /// days the baseline rests on: a thin baseline pulls its term
    /// toward zero (needs ~14 nights to be trusted), so early days no
    /// longer fly to 100. Anchored on Plews et al. 2013.
    static func recoveryBreakdown(hrv: Double?, hrvBaseline: Double?, hrvSamples: Int = 60,
                                  hrv7dMean: Double? = nil,
                                  rhr: Double?, rhrBaseline: Double?, rhrSamples: Int = 60,
                                  sleepScore: Int, yesterdayStrain: Int,
                                  model: RecoveryModel = .balanced,
                                  jetLagResidualH: Double = 0) -> RecoveryBreakdown {
        func shaped(_ term: Double) -> Double {
            term >= 0 ? term * model.positiveGain : term * model.negativeGain
        }
        func confidence(_ n: Int) -> Double { min(1, max(0, Double(n) / 14)) }
        func cap(_ value: Double, _ limit: Double) -> Double {
            min(limit, max(-limit, value))
        }
        // Jet-lag tolerance: while the body clock is still re-entraining,
        // a depressed HRV / elevated RHR is travel, not a real recovery
        // hit, so soften the NEGATIVE autonomic terms in proportion to the
        // residual misalignment (Sleep.md S10.4 "widen the band"). Each
        // residual hour cuts the penalty 8%, floored at 50%. Default 0 = no
        // change; positive contributions are never inflated.
        let jetLagDamp = jetLagResidualH > 0 ? max(0.5, 1 - jetLagResidualH * 0.08) : 1.0
        func jetLagAdjust(_ pts: Double) -> Double { pts < 0 ? pts * jetLagDamp : pts }

        var contributions: [RecoveryContribution] = []
        var missing: [RecoveryContribution.Kind] = []

        // HRV: higher than baseline is better (parasympathetic tone).
        // RMSSD is log-normally distributed, so the deviation is scored in
        // LOG space (lnRMSSD), the field standard used by HRV4Training /
        // Elite HRV and by the dead ScoreCalculator path we are unifying on
        // (decision doc D4; Plews 2013, refs [2][3][8]). When a 7-day
        // rolling RMSSD mean is supplied it is the comparison signal
        // (`hrv7dMean`), not the single night, because the readiness signal
        // is the trend of lnRMSSD vs the personal band rather than one
        // noisy reading; without it we fall back to tonight's value.
        //
        // JUDGMENT CALL: lnGain 150. A ln-deviation of +0.10 (~+10.5% raw
        // RMSSD) is worth ~+15 raw points and the 28-point cap needs about
        // a +0.19 ln-deviation (~+21% raw), matching the +/-20% HRV alert
        // band the literature uses, so ordinary good nights read good, not
        // perfect. Re-anchors the prior linear gain of 110 onto the log
        // scale (a small linear gain is far too weak in ln-space).
        if let base = hrvBaseline, base > 0,
           let reading = (hrv7dMean ?? hrv), reading > 0 {
            let lnGain = 150.0
            let lnDev = log(reading) - log(base)
            let points = cap(jetLagAdjust(shaped(lnGain * lnDev) * confidence(hrvSamples)),
                             recoveryHRVCap)
            // Surface tonight's reading as the displayed value when present,
            // so the breakdown UI still shows the night's number even when
            // the term was scored on the 7-day mean.
            contributions.append(RecoveryContribution(
                kind: .hrv, points: points, value: hrv ?? reading, baseline: base))
        } else {
            missing.append(.hrv)
        }

        // Resting HR: LOWER than baseline is better. The term is
        // baseline/rhr - 1 so a resting HR below the personal average
        // ADDS recovery (a depressed RHR signals good recovery).
        if let rhr, let base = rhrBaseline, rhr > 0, base > 0 {
            let points = cap(jetLagAdjust(shaped(100 * (base / rhr - 1)) * confidence(rhrSamples)),
                             recoveryRHRCap)
            contributions.append(RecoveryContribution(
                kind: .rhr, points: points, value: rhr, baseline: base))
        } else {
            missing.append(.rhr)
        }

        // Sleep quality around the 50 midpoint.
        let sleepPoints = cap(shaped(0.45 * (Double(sleepScore) - 50)), recoverySleepCap)
        contributions.append(RecoveryContribution(
            kind: .sleep, points: sleepPoints, value: Double(sleepScore), baseline: nil))

        // Rest credit when yesterday was calm.
        let restBonus = min(model.restBonusCap,
                            Double(max(0, 30 - yesterdayStrain)) / 30 * model.restBonusCap)
        if restBonus > 0.5 {
            contributions.append(RecoveryContribution(
                kind: .rest, points: restBonus, value: nil, baseline: nil))
        }

        let baseline = 50.0
        let rawTotal = baseline + contributions.reduce(0) { $0 + $1.points }

        // Soft knee above 82 instead of a hard clamp at 100: strong
        // days land in the high 80s to mid 90s and a displayed 100
        // needs every term at its cap at once. A score that pinned
        // at 100 for days carried no information.
        let compressed = rawTotal > 82
            ? 82 + 18 * tanh((rawTotal - 82) / 20)
            : rawTotal
        let score = Int(min(100, max(0, compressed)).rounded())
        return RecoveryBreakdown(score: score, baseline: baseline, rawTotal: rawTotal,
                                 contributions: contributions, missing: missing)
    }

    /// Recovery (0-100). Thin wrapper over `recoveryBreakdown` so the
    /// score and the displayed breakdown can never diverge. Same model
    /// as the mock engine so both sources score identically.
    static func recovery(hrv: Double?, hrvBaseline: Double?,
                         hrv7dMean: Double? = nil,
                         rhr: Double?, rhrBaseline: Double?,
                         sleepScore: Int, yesterdayStrain: Int,
                         model: RecoveryModel = .balanced,
                         jetLagResidualH: Double = 0) -> Int {
        recoveryBreakdown(hrv: hrv, hrvBaseline: hrvBaseline, hrv7dMean: hrv7dMean,
                          rhr: rhr, rhrBaseline: rhrBaseline,
                          sleepScore: sleepScore, yesterdayStrain: yesterdayStrain,
                          model: model, jetLagResidualH: jetLagResidualH).score
    }

    /// Whether a day's recovery should render as "no data" rather than a number.
    /// Missing means there is no score AND no autonomic input on record: recovery
    /// is a readiness score, so with no HRV / RHR / sleep it cannot exist. A real
    /// computed 0 with any input present is a value, not a gap, and stays visible.
    static func recoveryMissing(score: Int?, hrv: Double?,
                                            rhr: Double?, sleepHours: Double?) -> Bool {
        (score ?? 0) <= 0 && hrv == nil && rhr == nil && sleepHours == nil
    }

    /// Whether a day's SLEEP should render as "no data" rather than a number.
    /// Missing means no score AND no night on record: a sleep score is derived
    /// from a recorded night, so with nothing slept there is nothing to score.
    ///
    /// This is what a fresh day looks like between midnight and the morning the
    /// night is written to HealthKit: the night that just ended belongs to the
    /// PREVIOUS day (`RealHealthSnapshot.sleep` is gated on the wake day), so
    /// today owns no night and the score is the 0 sentinel, not a measurement.
    /// Printed as "0%" that sentinel reads as a catastrophic night; it has to
    /// read as pending. A real computed 0 with a night present is a value, not
    /// a gap, and stays visible.
    static func sleepMissing(score: Int?, sleepHours: Double?) -> Bool {
        (score ?? 0) <= 0 && sleepHours == nil
    }

    /// Whether a day's STRAIN should render as "no data" rather than a number.
    /// Missing means no strain AND no movement of any kind on record: strain is
    /// built from the day's zone seconds and active calories, so with no steps,
    /// no active energy and no exercise minutes there is nothing to score yet.
    ///
    /// Unlike sleep this is a statement about the day being YOUNG rather than
    /// about a gate: a strain of 0 at 02:00 is arithmetically true and still
    /// meaningless, because the day is two hours old. A day that recorded even
    /// a little movement keeps its honest 0, which is a real "you were still".
    static func strainMissing(score: Int?, steps: Double?,
                                          activeEnergy: Double?,
                                          exerciseMinutes: Double?) -> Bool {
        (score ?? 0) <= 0 && steps == nil && activeEnergy == nil
            && exerciseMinutes == nil
    }

    // MARK: Energy bank ledger (two-process model)

    // The energy battery follows the two-process model of sleep
    // regulation (Borbely 1982; Borbely, Daan, Wirz-Justice & Deboer
    // 2016): readiness is the inverse of homeostatic sleep pressure
    // (Process S, which builds while awake and dissipates during
    // sleep), modulated by the circadian rhythm (Process C), minus the
    // acute fatigue of the day's training load.

    /// Overnight refill efficiency (Process S dissipation): a perfect
    /// night closes the headroom at this efficiency. Sourced from the
    /// canonical engine so the daily ledger, the intraday curve, and the
    /// body-battery tile all charge identically. Calibrated so a perfect
    /// night from a typical low reserve gains ~+50 (Garmin 40-60 band).
    /// See `VitalitySections.sleepChargeEfficiency` + docs/calculations/02-energy.md.
    static let energyChargeEfficiency = VitalitySections.sleepChargeEfficiency
    /// Homeostatic drain time constant during wake (Process S build-up),
    /// in hours. Borbely two-process value (~18.2 h).
    static let energyWakeTau = VitalitySections.wakeTau
    /// Asymptotic homeostatic drain for unbounded wakefulness. Over a
    /// real ~16 h day this yields about 29 points.
    static let energyHomeostaticMaxDrain = VitalitySections.homeostaticMaxDrain
    /// The day's training cost in battery points, SATURATING in the 0-100
    /// strain score. Forwards to the canonical section so the ledger, the
    /// intraday curve and the day timeline all price training identically.
    /// Replaced a linear `exerciseDrainMax / 100` per strain point, which
    /// made any hard day cost more than a night could return; see
    /// `VitalitySections.dailyStrainDrain`.
    static func energyStrainDrain(strain: Double) -> Double {
        VitalitySections.dailyStrainDrain(strain: strain)
    }
    /// Circadian (Process C) amplitude on the battery (Borbely).
    static let energyCircadianAmplitude = VitalitySections.circadianAmplitude

    /// Homeostatic energy drain after `awakeHours` of continuous wake
    /// (Process S build-up). Forwards to the canonical section so there
    /// is one definition of the homeostatic curve.
    static func energyHomeostaticDrain(awakeHours: Double) -> Double {
        VitalitySections.homeostaticDrain(awakeHours: awakeHours)
    }

    /// Circadian alertness modulation in [-1, 1] by clock hour, from the
    /// classic alertness rhythm: a late-morning peak (~10 h), the
    /// post-lunch dip (~15 h), an early-evening wake-maintenance bump
    /// (~19 h), and the overnight nadir (~04 h). Anchor points are
    /// linearly interpolated; the mean is ~0 so it never biases the
    /// overall level, only its shape across the hours.
    ///
    /// `phaseOffsetHours` (Sleep clinical doc Section 10.4: Process-C
    /// jet-lag hook) shifts the WHOLE curve along the clock so the body's
    /// alertness peak and post-lunch dip land at a different LOCAL clock
    /// time while re-entraining. Default 0.0 makes the output byte-for-byte
    /// identical to the no-jet-lag curve. The lookup hour is offset by
    /// SUBTRACTING the parameter:
    ///
    ///   effectiveHour = clockHour - phaseOffsetHours
    ///
    /// so a POSITIVE `phaseOffsetHours` reads the curve as if the local
    /// clock were EARLIER, which pushes every feature LATER in local time;
    /// a NEGATIVE value pulls every feature EARLIER. This is exactly the
    /// eastward-vs-westward split the doc calls for:
    ///
    ///   - Eastward trip (advance, the body clock is still partly on the
    ///     EARLIER home schedule): the alertness peak and post-lunch dip
    ///     occur LATER in local clock time, so use a POSITIVE offset.
    ///   - Westward trip (delay): features occur EARLIER, so use a
    ///     NEGATIVE offset.
    ///
    /// A caller derives the offset from a `JetLagState`:
    ///
    ///   let signed = state.direction == .advance
    ///       ? state.residualMisalignmentH      // eastward -> positive
    ///       : -state.residualMisalignmentH     // westward -> negative
    ///
    /// The magnitude is the still-unresolved `residualMisalignmentH`,
    /// which the recovery model decays to 0 as re-entrainment completes,
    /// so the curve slides back to the unshifted shape on its own.
    static func energyCircadianModulation(clockHour: Double,
                                          phaseOffsetHours: Double = 0) -> Double {
        let points: [(Double, Double)] = [
            (0, -0.7), (3, -1.0), (6, -0.6), (8, -0.1),
            (10, 0.8), (12, 0.7), (14, 0.25), (15, 0.1),
            (17, 0.45), (19, 0.55), (21, 0.15), (22, -0.2), (24, -0.7)
        ]
        let hour = ((clockHour - phaseOffsetHours).truncatingRemainder(dividingBy: 24) + 24)
            .truncatingRemainder(dividingBy: 24)
        for index in 1..<points.count where hour <= points[index].0 {
            let (h0, v0) = points[index - 1]
            let (h1, v1) = points[index]
            let t = (hour - h0) / max(0.001, h1 - h0)
            return v0 + (v1 - v0) * t
        }
        return points.last?.1 ?? 0
    }

    /// The DAILY energy ledger: energy is a STOCK carried over from
    /// day to day, not a formula recomputed from scratch. For each
    /// day d:
    ///   morning(d) = end(d-1) + (100 - end(d-1))
    ///                x sqrt(sleep(d)/100) x (1 - e^(-hours(d)/4.2)) x 0.87
    ///   end(d)     = max(5, morning(d) - homeostaticDrain(awake(d))
    ///                                   - dailyStrainDrain(strain(d)))
    /// The charge follows `VitalitySections.chargeQuality` (concave in
    /// the sleep score) times `sleepClosureFraction` (Process-S
    /// dissipation by DURATION: 8 h closes ~85% of the gap), so a good
    /// long night wakes near 85-95 instead of capping at 72% closure,
    /// and the steady state holds in the Garmin-like band instead of
    /// pinning at 0.
    /// The homeostatic term scales with how long the day kept you awake
    /// (24 - sleepHours), so short nights cost more; the strain term is
    /// the day's training fatigue. End-of-day lands at bedtime, where
    /// the circadian rhythm is ~neutral, so the daily summary leaves
    /// Process C out (it shapes the intraday curve instead). Days with
    /// no recorded night do not charge (the chart shows a gap) but the
    /// day still burns internally. Seeds at 60.
    ///
    /// The three optional series each default to empty, so a caller that has
    /// none of them gets exactly the model this function had before they
    /// existed, and the population anchor is unmoved:
    ///  - `nightMisalignmentHours`: how far that night's mid-sleep sat from
    ///    the sleeper's OWN habitual mid-sleep. Scales the charge.
    ///  - `dailyStress`: the centered daily stress (0..100). Signed, so a
    ///    tense day costs more and a serene one less.
    ///  - `illnessDeviation`: composite deviation in sigma over the tracked
    ///    vitals. One-directional extra drain.
    static func energyLedger(sleepScores: [Double?], strains: [Double?],
                             sleepHours: [Double?] = [],
                             nightMisalignmentHours: [Double?] = [],
                             dailyStress: [Double?] = [],
                             illnessDeviation: [Double?] = [])
        -> (morning: [Double?], end: [Double?]) {
        let count = max(sleepScores.count, strains.count)
        var morning: [Double?] = Array(repeating: nil, count: count)
        var end: [Double?] = Array(repeating: nil, count: count)
        var balance = 60.0
        var seen = false

        for index in 0..<count {
            let sleep = index < sleepScores.count ? sleepScores[index] : nil
            let strain = (index < strains.count ? strains[index] : nil) ?? 0
            let asleep = index < sleepHours.count ? sleepHours[index] : nil
            // Awake span drives the homeostatic drain; default to a 16 h
            // day when the night length is unknown, and keep it in a
            // plausible 6...20 h band.
            let awakeHours = asleep.map { max(6, min(20, 24 - $0)) } ?? 16
            let stress = index < dailyStress.count ? dailyStress[index] : nil
            let deviation = index < illnessDeviation.count ? illnessDeviation[index] : nil
            let misalignment = index < nightMisalignmentHours.count
                ? nightMisalignmentHours[index] : nil
            // A day can be cheaper than the backbone (a serene day credits
            // back) but never free, so the total stays a drain.
            let dayDrain = max(0, energyHomeostaticDrain(awakeHours: awakeHours)
                + energyStrainDrain(strain: strain)
                + VitalitySections.dailyStressDrain(stress: stress)
                + VitalitySections.illnessDrain(deviation: deviation))

            if let sleep {
                seen = true
                let headroom = max(0, 100 - balance)
                let charged = VitalitySections.clampBattery(
                    balance + headroom
                    * VitalitySections.chargeQuality(sleepScore: sleep)
                    * VitalitySections.sleepClosureFraction(sleepHours: asleep)
                    * VitalitySections.nightClosureMax
                    * VitalitySections.nightAlignmentMultiplier(
                        misalignmentHours: misalignment))
                let drained = VitalitySections.clampBattery(charged - dayDrain)
                morning[index] = charged
                end[index] = drained
                balance = drained
            } else if seen {
                // No recorded night: nothing charges, the day still
                // burns (kept internal so the chart shows a gap).
                balance = VitalitySections.clampBattery(balance - dayDrain)
            }
        }
        return (morning, end)
    }

    // MARK: Sleep (ONE canonical model)

    /// Age-banded target SHARE of asleep time for the REM and deep stages,
    /// as `(low, high)` fractions. The score sits at full credit inside the
    /// band and falls off below the low edge (a short surplus above the high
    /// edge is not penalized: extra deep/REM is not a fault).
    ///
    /// JUDGMENT CALL (decision doc D6; Carskadon & Dement 2005 ref [d],
    /// Moser 2009 ref [e]): REM holds ~20-25% of TST across adult ages, so
    /// its band is age-flat at 0.18...0.25. Slow-wave / deep sleep declines
    /// ~40% from young to older adults, so its target band steps DOWN with
    /// age (young ~0.16...0.23, midlife ~0.12...0.20, older ~0.08...0.16).
    /// Replaces the prior age-blind fixed divisors (deep /0.18, REM /0.22).
    static func sleepStageTargets(ageYears: Double?)
        -> (rem: (low: Double, high: Double), deep: (low: Double, high: Double)) {
        let rem = (low: 0.18, high: 0.25)
        let age = ageYears ?? 35
        let deep: (low: Double, high: Double)
        switch age {
        case ..<30:  deep = (0.16, 0.23)
        case 30..<50: deep = (0.12, 0.20)
        default:      deep = (0.08, 0.16)
        }
        return (rem, deep)
    }

    /// Credit (0...1) for a sleep stage given WHERE its share lands in the
    /// age band. Rises to 0.75 at the band's LOW edge (a healthy minimum,
    /// strong but not perfect), reaches 1.0 only at the HIGH edge and above,
    /// and falls off toward 0 below the low edge. Replaces the prior "full
    /// credit anywhere at or above the low edge", which let a merely
    /// adequate night earn a perfect stage grade and saturate the score.
    static func stageBandCredit(share: Double, band: (low: Double, high: Double)) -> Double {
        guard band.high > band.low else { return share >= band.low ? 1 : 0 }
        if share >= band.high { return 1 }
        if share >= band.low {
            return 0.75 + 0.25 * (share - band.low) / (band.high - band.low)
        }
        return max(0, 0.75 * share / max(0.0001, band.low))
    }

    /// The ONE canonical sleep score (0-100), stage-aware, age-banded, with
    /// graceful zero-and-renormalize degradation. Ports the six components
    /// of `HealthMetricsEngine.sleepScore` so the live dial and the history
    /// rollups read the SAME formula (decision doc D5) instead of the prior
    /// split (stage-aware live vs duration-only history).
    ///
    /// Relative weights (sum 95): duration vs need 40, efficiency 15,
    /// deep share 15, REM share 10, continuity 10, HR dip 5. Any component
    /// whose inputs are absent is DROPPED and its weight is redistributed
    /// across the present components (zero-and-renormalize), so a history
    /// day with only duration scores on duration alone, a day that also has
    /// REM/deep adds those, and a full night uses all six. The score
    /// therefore degrades gracefully without ever switching formulas.
    ///
    /// - Parameters:
    ///   - asleepSeconds: total time in any asleep stage (required).
    ///   - needSeconds: personalized sleep need.
    ///   - inBedSeconds: total time in bed (asleep + awake), for efficiency.
    ///   - remSeconds / deepSeconds: stage totals when known.
    ///   - awakeningCount: number of awake segments, for continuity.
    ///   - nightHR / dayRHR: overnight vs day resting HR, for the dip term.
    ///   - ageYears: drives the age-banded deep/REM targets.
    static func sleepScore(asleepSeconds: Int?,
                           needSeconds: Int,
                           inBedSeconds: Int? = nil,
                           remSeconds: Int? = nil,
                           deepSeconds: Int? = nil,
                           awakeningCount: Int? = nil,
                           nightHR: Double? = nil,
                           dayRHR: Double? = nil,
                           ageYears: Double? = nil) -> Int? {
        guard let terms = sleepScoreTerms(asleepSeconds: asleepSeconds, needSeconds: needSeconds,
                                          inBedSeconds: inBedSeconds, remSeconds: remSeconds,
                                          deepSeconds: deepSeconds, awakeningCount: awakeningCount,
                                          nightHR: nightHR, dayRHR: dayRHR, ageYears: ageYears)
        else { return nil }
        let totalWeight = terms.reduce(0) { $0 + $1.weight }
        guard totalWeight > 0 else { return nil }
        // Zero-and-renormalize: present weights are rescaled to sum 100 so
        // the score keeps its 0-100 meaning whatever data is available.
        let raw = terms.reduce(0) { $0 + $1.weight * $1.value } / totalWeight * 100
        return Int(min(100, max(0, raw)).rounded())
    }

    /// The present components of ``sleepScore(asleepSeconds:needSeconds:inBedSeconds:remSeconds:deepSeconds:awakeningCount:nightHR:dayRHR:ageYears:)``,
    /// each with its relative weight and its 0...1 credit, before the
    /// renormalization. The score is exactly their weighted mean times 100,
    /// so a page that explains the score reads these and never recomputes it.
    static func sleepScoreTerms(asleepSeconds: Int?,
                                needSeconds: Int,
                                inBedSeconds: Int? = nil,
                                remSeconds: Int? = nil,
                                deepSeconds: Int? = nil,
                                awakeningCount: Int? = nil,
                                nightHR: Double? = nil,
                                dayRHR: Double? = nil,
                                ageYears: Double? = nil) -> [(kind: String, weight: Double, value: Double)]? {
        guard let asleep = asleepSeconds, asleep > 0 else { return nil }
        let need = Double(max(1, needSeconds))
        let targets = sleepStageTargets(ageYears: ageYears)

        // Each entry: (kind, weight, normalized 0...1). Present components only.
        var terms: [(kind: String, weight: Double, value: Double)] = []

        // Duration vs need (weight 40): ratio^2 to full at the need, with a
        // gentle oversleep falloff so a long lie-in is mildly, not harshly,
        // penalized (NSF 7-9h, Chaput 2020 optimum 7-8h; refs [f][g]).
        let ratio = Double(asleep) / need
        let durationNorm: Double
        if ratio <= 1 {
            durationNorm = min(1, ratio * ratio)
        } else if ratio <= 1.2 {
            durationNorm = 1
        } else {
            durationNorm = max(0.6, 1 - (ratio - 1.2) * 0.8)
        }
        terms.append(("duration", 40, durationNorm))

        // Efficiency (weight 15): 0.85 -> 0, 1.0 -> 1. Needs time-in-bed.
        if let inBed = inBedSeconds, inBed > 0 {
            let efficiency = Double(asleep) / Double(inBed)
            terms.append(("efficiency", 15, min(1, max(0, (efficiency - 0.85) / 0.15))))
        }

        // Deep share (weight 15): graded by WHERE in the age band it lands.
        // The band's low edge is a healthy minimum (0.75); full credit needs
        // the strong end of the range; below the low edge falls off toward 0.
        if let deep = deepSeconds {
            let share = Double(deep) / Double(asleep)
            terms.append(("deep", 15, stageBandCredit(share: share, band: targets.deep)))
        }

        // REM share (weight 10): same graded-in-band shape.
        if let rem = remSeconds {
            let share = Double(rem) / Double(asleep)
            terms.append(("rem", 10, stageBandCredit(share: share, band: targets.rem)))
        }

        // Continuity (weight 10): each awakening costs 8%.
        if let count = awakeningCount {
            terms.append(("continuity", 10, max(0, 1 - Double(count) * 0.08)))
        }

        // HR dip (weight 5): overnight HR below day resting HR. Needs both.
        if let nightHR, let dayRHR, dayRHR > 0, nightHR > 0 {
            terms.append(("dip", 5, min(1, max(0, ((dayRHR - nightHR) / dayRHR) / 0.10))))
        }

        return terms
    }

    /// Sleep score from a HYPNOGRAM, given as `(stage, seconds)` pairs where
    /// stage is one of "awake" / "rem" / "core" / "deep".
    ///
    /// This exists so the live dial and the history series cannot decompose a
    /// night differently, which is exactly what they were doing: the live path
    /// passed all nine inputs to `sleepScore` while `sleepScoreSeries` passed
    /// four, dropping efficiency (15), continuity (10) and the HR dip (5). The
    /// zero-and-renormalize rule then rescaled the remaining 65 back up to
    /// 100, so the SAME night scored ~81 for the energy ledger and ~70 on the
    /// Sleep page. Renormalizing is right for a night whose data does not
    /// exist; it is not right for one whose data exists and was never passed.
    ///
    /// The nil-guards below are the reason this has to be shared rather than
    /// copied. Each one is a way to fabricate a good score out of missing data:
    ///  - no awake segment at all means the hypnogram never measured wake, so
    ///    `inBed == asleep` and efficiency would read a perfect 100%;
    ///  - the same absence would score continuity as "zero awakenings", a
    ///    flawless night, when nothing was counted.
    /// Both are dropped instead, so the term is absent rather than perfect.
    static func sleepScore(hypnogram: [(stage: String, seconds: Int)],
                           needSeconds: Int,
                           nightHR: Double? = nil,
                           dayRHR: Double? = nil,
                           ageYears: Double? = nil) -> Int? {
        guard let night = hypnogramInputs(hypnogram) else { return nil }
        return sleepScore(asleepSeconds: night.asleep,
                          needSeconds: needSeconds,
                          inBedSeconds: night.inBed,
                          remSeconds: night.rem,
                          deepSeconds: night.deep,
                          awakeningCount: night.awakenings,
                          nightHR: nightHR,
                          dayRHR: dayRHR,
                          ageYears: ageYears)
    }

    /// The same night as ``sleepScore(hypnogram:needSeconds:nightHR:dayRHR:ageYears:)``
    /// reads it, as its labelled components.
    static func sleepScoreTerms(hypnogram: [(stage: String, seconds: Int)],
                                needSeconds: Int,
                                nightHR: Double? = nil,
                                dayRHR: Double? = nil,
                                ageYears: Double? = nil) -> [(kind: String, weight: Double, value: Double)]? {
        guard let night = hypnogramInputs(hypnogram) else { return nil }
        return sleepScoreTerms(asleepSeconds: night.asleep,
                               needSeconds: needSeconds,
                               inBedSeconds: night.inBed,
                               remSeconds: night.rem,
                               deepSeconds: night.deep,
                               awakeningCount: night.awakenings,
                               nightHR: nightHR,
                               dayRHR: dayRHR,
                               ageYears: ageYears)
    }

    /// A hypnogram reduced to the score's inputs, with the nil guards
    /// described above: a term whose data was never measured is absent.
    static func hypnogramInputs(_ hypnogram: [(stage: String, seconds: Int)])
        -> (asleep: Int, inBed: Int?, rem: Int?, deep: Int?, awakenings: Int?)? {
        var inBed = 0, awakeSeconds = 0, awakeCount = 0, deep = 0, rem = 0
        for segment in hypnogram {
            inBed += segment.seconds
            switch segment.stage {
            case "awake": awakeSeconds += segment.seconds; awakeCount += 1
            case "deep":  deep += segment.seconds
            case "rem":   rem += segment.seconds
            default:      break
            }
        }
        let asleep = inBed - awakeSeconds
        guard asleep > 0 else { return nil }
        return (asleep,
                awakeSeconds > 0 ? inBed : nil,
                rem > 0 ? rem : nil,
                deep > 0 ? deep : nil,
                awakeCount > 0 ? awakeCount : nil)
    }

    /// Back-compat history entrypoint: a sleep score from DURATION ONLY.
    /// Now a thin wrapper over the canonical `sleepScore` with no stage,
    /// efficiency, continuity or dip inputs, so a duration-only history day
    /// scores on the SAME formula the live dial uses (the duration term,
    /// renormalized to the full 0-100 range). Callers that also have the
    /// per-day `remHours` / `deepHours` series should call `sleepScore`
    /// directly so those days pick up their stage credit.
    static func durationSleepScore(hours: Double?, needSeconds: Int) -> Int? {
        guard let hours else { return nil }
        return sleepScore(asleepSeconds: Int(hours * 3600), needSeconds: needSeconds)
    }

    // MARK: Nap score

    /// A lightweight nap quality score (0-100). A nap is NOT measured against
    /// a full night's sleep need, so this is deliberately separate from
    /// `sleepScore`: it reads only how restful the nap itself was. Three
    /// present-only components, zero-and-renormalized exactly like the night
    /// score so the value keeps its 0-100 meaning whatever data is on hand:
    ///   efficiency 45 (asleep / time-in-nap), continuity 25 (awakenings),
    ///   duration-fit 30 (a power nap and a full cycle score high; the
    ///   mid-length inertia zone and very short naps score lower).
    /// Nil when there is no asleep time to score.
    static func napScore(asleepSeconds: Int?,
                         inNapSeconds: Int? = nil,
                         awakeningCount: Int? = nil) -> Int? {
        guard let asleep = asleepSeconds, asleep > 0 else { return nil }

        var terms: [(weight: Double, value: Double)] = []

        // Efficiency (45): 0.70 -> 0, 1.0 -> 1. Needs the nap's in-bed span.
        if let inNap = inNapSeconds, inNap > 0 {
            let efficiency = Double(asleep) / Double(inNap)
            terms.append((45, min(1, max(0, (efficiency - 0.70) / 0.30))))
        }
        // Continuity (25): each awakening costs 12%.
        if let count = awakeningCount {
            terms.append((25, max(0, 1 - Double(count) * 0.12)))
        }
        // Duration fit (30): a curve over the asleep minutes.
        terms.append((30, napDurationFit(minutes: Double(asleep) / 60)))

        let totalWeight = terms.reduce(0) { $0 + $1.weight }
        guard totalWeight > 0 else { return nil }
        let raw = terms.reduce(0) { $0 + $1.weight * $1.value } / totalWeight * 100
        return Int(min(100, max(0, raw)).rounded())
    }

    /// Nap duration appropriateness, 0...1, from asleep MINUTES. Piecewise
    /// linear over research-guided control points: a power nap (~12-30 min)
    /// and a full sleep cycle (~85-100 min) score high; the mid-length
    /// "sleep inertia" band (~45-70 min, likely to wake mid-deep) and very
    /// short naps score lower; an over-long nap tapers off.
    static func napDurationFit(minutes: Double) -> Double {
        let points: [(x: Double, y: Double)] = [
            (0, 0.0), (5, 0.45), (12, 1.0), (30, 1.0), (45, 0.78),
            (60, 0.62), (85, 0.90), (100, 0.92), (120, 0.75), (180, 0.50)
        ]
        if minutes <= points.first!.x { return points.first!.y }
        if minutes >= points.last!.x { return points.last!.y }
        for i in 1..<points.count where minutes <= points[i].x {
            let a = points[i - 1], b = points[i]
            let t = (minutes - a.x) / (b.x - a.x)
            return a.y + (b.y - a.y) * t
        }
        return points.last!.y
    }

    // MARK: Today's TRIMP (strain sources)

    /// Today's TRIMP honoring the Settings strain sources. The
    /// workout share is its zone minutes (its calories stand in when
    /// no heart rate was recorded); the daily share is the rest of
    /// the day's zones OR the non-workout active kilocalories,
    /// whichever is larger. Moving without a tracked workout (and
    /// even without the watch's HR samples) still counts, so the
    /// calories you burn always reach the score.
    ///
    /// Both kcal fallbacks divide by the SHARED `activeKcalPerTrimp`, so a
    /// kilocalorie produces the SAME TRIMP today as it does in the history
    /// estimate (`estimatedTRIMP`). This removes the prior ~5x scale break
    /// at the today/history boundary (the old `/10.0` and `/12.0` divisors,
    /// decision doc D1.c). The real HR zone-seconds Edwards TRIMP still
    /// wins via `max(...)` whenever it exists, so kcal is only a no-HR
    /// floor.
    static func todayTRIMP(dayZoneSeconds: [Int], workoutZoneSeconds: [Int],
                           activeKcal: Double = 0, workoutKcal: Double = 0,
                           includeWorkouts: Bool, includeDaily: Bool) -> Double {
        let dayTrimp = edwardsTRIMP(zoneSeconds: Array(dayZoneSeconds.dropFirst()))
        let workoutZoneTrimp = min(dayTrimp, edwardsTRIMP(zoneSeconds: workoutZoneSeconds))

        let workoutPart = max(workoutZoneTrimp, workoutKcal / activeKcalPerTrimp)
        let dailyKcal = max(0, activeKcal - workoutKcal)
        let dailyPart = max(dayTrimp - workoutZoneTrimp, dailyKcal / activeKcalPerTrimp)

        switch (includeWorkouts, includeDaily) {
        case (true, true): return workoutPart + dailyPart
        case (true, false): return workoutPart
        case (false, true): return dailyPart
        case (false, false): return 0
        }
    }
}
