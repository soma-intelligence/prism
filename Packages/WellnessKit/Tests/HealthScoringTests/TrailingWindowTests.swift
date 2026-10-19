//
//  TrailingWindowTests.swift
//  HealthScoringTests (parity suite ported from the previous app)
//
//  Pins `RealHealthMath.trailingValues(_:before:limit:maxLookback:)` to the
//  expression it replaces, element for element, and pins the lookback cap.
//
//  WHY THIS SUITE EXISTS. The expression
//
//      series[..<index].compactMap { $0 }.suffix(limit)
//
//  was the shape used to read "the last `limit` measured days before this one".
//  It is correct and it is quadratic: it walks and allocates the WHOLE prefix,
//  then throws all but `limit` away. Called once per day over a series that is
//  3650 days deep it cost, on device on 2026-08-24, 1063 ms in
//  `nightMisalignmentSeries` and most of another 940 ms in
//  `IllnessEpisodeEngine.deviationSeries`, which together were 98% of every
//  derived-memo cascade and 97% of the Home column's whole cost.
//
//  The replacement walks backward and stops at `limit`. That rewrite has one
//  classic way to be wrong: returning the OLDEST `limit` values instead of the
//  newest, or returning the newest in reverse order. Neither shows up in a
//  compile, and neither would show up in a mean either, because a circular mean
//  does not care about order. It would show up as a baseline computed from the
//  wrong month. So the tests below compare against the naive expression
//  directly, on shapes chosen to make an off-by-one visible, and `--control`
//  flips the helper to the oldest-first mistake to prove the suite catches it.
//
//  The cap is the second half. A backward walk is only bounded while the data
//  is dense: on a sparse series it still scans most of a year per day, and it
//  averages readings years apart while calling them "the last 28 nights".
//  `baselineLookbackDays` bounds it at one year, a number measured rather than
//  chosen, and the tests below pin both halves of that claim: it changes
//  nothing on a plausibly filled history, and it does cut the window that
//  reaches back three years.
//
//  Run: scripts/test_trailing_window_runtime.sh [--control]
//

import XCTest
@testable import HealthScoring

final class TrailingWindowTests: XCTestCase {

    /// The expression the helper replaces. Kept verbatim so the suite compares
    /// against the shipped behaviour and not against a paraphrase of it.
    private func naive(_ series: [Double?], before index: Int,
                       limit: Int, maxLookback: Int = uncapped) -> [Double] {
        let upper = min(index, series.count)
        let earliest = upper > maxLookback ? upper - maxLookback : 0
        return Array(series[earliest..<upper].compactMap { $0 }.suffix(limit))
    }

    /// Wide enough that no fixture reaches it, so the equivalence tests below
    /// still compare against the UNCAPPED expression this helper replaced.
    /// Deliberately not `Int.max`: the cap arithmetic used to overflow on that,
    /// and a test fixture is exactly where that would have been found.
    private static let uncapped = 1_000_000

    // MARK: Equivalence

    func testMatchesTheNaiveExpressionOnADenseSeries() {
        let series: [Double?] = (0..<200).map { Double($0) }
        for index in 0...200 {
            for limit in [1, 7, 28, 64] {
                XCTAssertEqual(RealHealthMath.trailingValues(series, before: index, limit: limit, maxLookback: Self.uncapped),
                               naive(series, before: index, limit: limit),
                               "index \(index) limit \(limit)")
            }
        }
    }

    /// Gaps are the whole point: a health series is mostly holes, and the
    /// window counts MEASURED days, not calendar days. A helper that counted
    /// slots instead of values would pass the dense test above and be wrong on
    /// every real device.
    func testMatchesTheNaiveExpressionWhenTheSeriesIsMostlyHoles() {
        // Deterministic pseudo-random holes: a seeded generator rather than
        // `Double.random`, so a failure is reproducible from the file alone.
        var state: UInt64 = 0x9E3779B97F4A7C15
        func next() -> UInt64 {
            state ^= state << 13; state ^= state >> 7; state ^= state << 17
            return state
        }
        let series: [Double?] = (0..<400).map { day in
            next() % 3 == 0 ? nil : Double(day)
        }
        for index in 0...400 {
            for limit in [1, 7, 28] {
                XCTAssertEqual(RealHealthMath.trailingValues(series, before: index, limit: limit, maxLookback: Self.uncapped),
                               naive(series, before: index, limit: limit),
                               "index \(index) limit \(limit)")
            }
        }
    }

    /// The measured values sit at the two ends, so returning the oldest window
    /// instead of the newest changes every element rather than a few.
    func testTakesTheNEWESTValuesNotTheOldest() {
        var series = [Double?](repeating: nil, count: 100)
        for day in 0..<10 { series[day] = Double(day) }          // 0...9, oldest
        for day in 90..<100 { series[day] = Double(day) }        // 90...99, newest
        let window = RealHealthMath.trailingValues(series, before: 100, limit: 5, maxLookback: Self.uncapped)
        XCTAssertEqual(window, [95, 96, 97, 98, 99])
    }

    /// Oldest first, same as the expression it replaces. A backward walk that
    /// forgets to reverse returns the right SET in the wrong order, which a
    /// mean hides and a decay-weighted or first/last read does not.
    func testReturnsOldestFirst() {
        let series: [Double?] = [10, 20, 30, 40, 50]
        XCTAssertEqual(RealHealthMath.trailingValues(series, before: 5, limit: 3, maxLookback: Self.uncapped), [30, 40, 50])
    }

    // MARK: Edges

    func testStrictlyBeforeTheIndex() {
        let series: [Double?] = [1, 2, 3]
        // Day 2 must not see its own value.
        XCTAssertEqual(RealHealthMath.trailingValues(series, before: 2, limit: 10, maxLookback: Self.uncapped), [1, 2])
    }

    func testEmptyAtTheStartOfTheSeries() {
        let series: [Double?] = [1, 2, 3]
        XCTAssertEqual(RealHealthMath.trailingValues(series, before: 0, limit: 10, maxLookback: Self.uncapped), [])
    }

    func testEmptyForANonPositiveLimit() {
        let series: [Double?] = [1, 2, 3]
        XCTAssertEqual(RealHealthMath.trailingValues(series, before: 3, limit: 0, maxLookback: Self.uncapped), [])
    }

    func testEmptySeriesAndAllNilSeries() {
        XCTAssertEqual(RealHealthMath.trailingValues([], before: 5, limit: 28, maxLookback: Self.uncapped), [])
        XCTAssertEqual(RealHealthMath.trailingValues([nil, nil, nil], before: 3, limit: 28, maxLookback: Self.uncapped), [])
    }

    /// The call sites pass an index they have already range-checked, but a
    /// helper that traps on an index past the end turns a defensive caller into
    /// a crash. Clamping matches `series[..<min(index, count)]`.
    func testAnIndexPastTheEndClampsInsteadOfTrapping() {
        let series: [Double?] = [1, 2, 3]
        XCTAssertEqual(RealHealthMath.trailingValues(series, before: 999, limit: 28, maxLookback: Self.uncapped), [1, 2, 3])
    }

    // MARK: The lookback cap

    /// The cap is measured, not picked: at 365 days it changed 0 of ~2000
    /// evaluated days on both a 90%-filled and a 12%-filled 3650-day series.
    /// This is that claim as a test rather than as a comment in a commit.
    func testA365DayCapChangesNothingOnAPlausiblyFilledHistory() {
        var state: UInt64 = 0x9E3779B97F4A7C15
        func next() -> UInt64 {
            state ^= state << 13; state ^= state >> 7; state ^= state << 17
            return state
        }
        // Shaped like the device log: 3650 slots, nothing before day 1642,
        // then a reading most days.
        let series: [Double?] = (0..<3650).map { day in
            guard day >= 1642 else { return nil }
            return next() % 100 < 90 ? Double(day % 50) + 40 : nil
        }
        for index in stride(from: 0, to: 3650, by: 7) {
            XCTAssertEqual(
                RealHealthMath.trailingValues(series, before: index, limit: 28,
                                              maxLookback: RealHealthMath.baselineLookbackDays),
                naive(series, before: index, limit: 28),
                "index \(index)")
        }
    }

    /// What the cap is FOR. Two readings a year apart are not "the last 28
    /// nights", and the uncapped walk would average them anyway.
    func testTheCapRefusesAWindowStitchedFromYearsApart() {
        var series = [Double?](repeating: nil, count: 1000)
        series[0] = 50            // one reading, ~3 years before the read
        series[900] = 60          // one reading, recent
        let capped = RealHealthMath.trailingValues(
            series, before: 1000, limit: 28,
            maxLookback: RealHealthMath.baselineLookbackDays)
        XCTAssertEqual(capped, [60], "only the reading inside the last year survives")
        XCTAssertEqual(naive(series, before: 1000, limit: 28), [50, 60],
                       "the uncapped walk reached back three years, which is the bug")
    }

    func testTheCapCountsSlotsNotValues() {
        // 10 readings, all inside the last 5 slots.
        var series = [Double?](repeating: nil, count: 100)
        for day in 95..<100 { series[day] = Double(day) }
        XCTAssertEqual(RealHealthMath.trailingValues(series, before: 100, limit: 28, maxLookback: 5),
                       [95, 96, 97, 98, 99])
        // One slot further back is outside a 4-slot cap.
        XCTAssertEqual(RealHealthMath.trailingValues(series, before: 100, limit: 28, maxLookback: 4),
                       [96, 97, 98, 99])
    }

    func testANonPositiveLookbackReturnsEmpty() {
        let series: [Double?] = [1, 2, 3]
        XCTAssertEqual(RealHealthMath.trailingValues(series, before: 3, limit: 28, maxLookback: 0), [])
    }

    /// `upper - maxLookback` traps on overflow, and "no cap" is spelled with a
    /// very large number. Pinning it here because the trap would not appear in
    /// any normal fixture: it needs a cap near `Int.max` and a short series.
    func testAHugeLookbackDoesNotOverflow() {
        let series: [Double?] = [1, 2, 3]
        XCTAssertEqual(RealHealthMath.trailingValues(series, before: 3, limit: 28,
                                                     maxLookback: Int.max),
                       [1, 2, 3])
    }

    // MARK: The guard the call sites depend on

    /// Both call sites replaced `fullPrefix.count >= minimum` with
    /// `window.count >= minimum`. Those agree only while `limit >= minimum`,
    /// which holds at both sites (28 >= 7). This pins the equivalence so a
    /// later tuning of either constant fails here rather than silently
    /// widening or narrowing a baseline.
    func testCountGuardAgreesWithTheFullPrefixWhileLimitCoversTheMinimum() {
        let minimum = 7
        let limit = 28
        var state: UInt64 = 0x2545F4914F6CDD1D
        func next() -> UInt64 {
            state ^= state << 13; state ^= state >> 7; state ^= state << 17
            return state
        }
        let series: [Double?] = (0..<300).map { day in
            next() % 4 == 0 ? Double(day) : nil
        }
        for index in 0...300 {
            let fullPrefixCount = series[..<index].compactMap { $0 }.count
            let windowCount = RealHealthMath.trailingValues(series, before: index, limit: limit, maxLookback: Self.uncapped).count
            XCTAssertEqual(fullPrefixCount >= minimum, windowCount >= minimum,
                           "index \(index): prefix \(fullPrefixCount), window \(windowCount)")
        }
    }
}
