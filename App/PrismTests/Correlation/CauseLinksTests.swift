//
//  CauseLinksTests.swift
//  PrismTests
//

import Foundation
import Testing
import SomaUI
@testable import Prism

/// The cause and effect engine: pairing, the high and low split, the gate,
/// and the links the Trends page builds from it.
@Suite("Cause links")
@MainActor
struct CauseLinksTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }()

    private func day(_ n: Int) -> Date {
        calendar.date(byAdding: .day, value: n, to: calendar.date(from: DateComponents(year: 2026, month: 7, day: 1))!)!
    }

    // MARK: Pairing

    @Test func pairsTheOutcomeOnTheNextDay() {
        let driver = [day(0): 10.0, day(1): 20, day(2): 30]
        let outcome = [day(1): 1.0, day(2): 2, day(3): 3, day(9): 9]
        let next = LinkMath.pairs(driver: driver, outcome: outcome, lag: .nextDay, calendar: calendar)
        #expect(next.map(\.driver) == [10, 20, 30])
        #expect(next.map(\.outcome) == [1, 2, 3])
        let same = LinkMath.pairs(driver: driver, outcome: outcome, lag: .sameDay, calendar: calendar)
        #expect(same.map(\.outcome) == [1, 2])
    }

    @Test func shiftsASeriesOntoTheNextDay() {
        let shifted = LinkMath.shifted([day(4): 5], by: 1, calendar: calendar)
        #expect(shifted == [day(5): 5])
    }

    // MARK: The gate

    @Test func statesAClearDifference() {
        let high = [60.0, 62, 61, 63, 59, 60, 62, 61]
        let low = [50.0, 52, 51, 49, 50, 53, 51, 50]
        let result = LinkMath.compare(high: high, low: low, all: high + low, gate: .level)
        #expect(result.verdict == .shown)
        #expect(result.direction == .rises)
        #expect(abs(result.delta! - 10.25) < 0.0001)
        #expect(result.highDays == 8)
        #expect(result.lowDays == 8)
        #expect(result.strength > 1)
    }

    @Test func holdsBackASideWithTooFewDays() {
        let high = [60.0, 62, 61, 63, 59, 60]
        let low = [50.0, 52, 51, 49, 50, 53, 51, 50]
        let result = LinkMath.compare(high: high, low: low, all: high + low, gate: .level)
        #expect(result.verdict == .notEnoughDays)
        #expect(!result.isShown)
    }

    @Test func holdsBackADifferenceInsideTheNoise() {
        // Ten points of day to day swing, two points apart on average.
        let high = [70.0, 50, 66, 54, 62, 58, 75, 47]
        let low = [68.0, 48, 64, 52, 60, 56, 72, 46]
        let result = LinkMath.compare(high: high, low: low, all: high + low, gate: .level)
        #expect(result.delta! > 0)
        #expect(result.verdict == .withinNoise)
        #expect(result.noise! > abs(result.delta!))
    }

    @Test func noDifferenceIsNeverALink() {
        let flat = Array(repeating: 50.0, count: 10)
        let result = LinkMath.compare(high: flat, low: flat, all: flat + flat, gate: .level)
        #expect(result.verdict == .withinNoise)
        #expect(result.direction == nil)
    }

    @Test func emptySideIsNotEnoughDays() {
        let result = LinkMath.compare(high: [], low: [1, 2, 3], all: [1, 2, 3], gate: .level)
        #expect(result.delta == nil)
        #expect(result.verdict == .notEnoughDays)
    }

    // MARK: Splits

    @Test func levelSplitTakesTheTopAndBottomThirds() {
        let pairs = (0..<30).map { LinkMath.Pair(day: day($0), driver: Double($0), outcome: Double($0) * 2) }
        let result = LinkMath.byLevel(pairs)
        #expect(result.highDays == 10)
        #expect(result.lowDays == 10)
        #expect(result.high.min() == 40)
        #expect(result.low.max() == 18)
        #expect(result.isShown)
    }

    @Test func levelSplitWithoutContrastIsHeldBack() {
        let pairs = (0..<30).map { LinkMath.Pair(day: day($0), driver: 7, outcome: Double($0 % 5)) }
        #expect(LinkMath.byLevel(pairs).verdict == .notEnoughDays)
    }

    @Test func tagSplitCountsOnlyDaysSinceTheJournalBegan() {
        var outcome: [Date: Double] = [:]
        for n in 1...40 { outcome[day(n)] = 80 }
        let tagged: Set<Date> = [day(20), day(25), day(30), day(33), day(36)]
        for tag in tagged { outcome[calendar.date(byAdding: .day, value: 1, to: tag)!] = 68 }
        let result = LinkMath.byTag(days: tagged, outcome: outcome, lag: .nextDay, since: day(10), calendar: calendar)
        #expect(result.highDays == 5)
        // Outcome days 11...40 have a driver day 10...39 on or after the start.
        #expect(result.lowDays == 25)
        #expect(result.delta == -12)
        #expect(result.direction == .falls)
    }

    // MARK: The links

    @Test func alcoholCostsSleepAndShowsAsACost() {
        var series = LinkSeries()
        var alcohol: Set<Date> = []
        for n in 0..<60 {
            let drank = n % 6 == 0
            if drank { alcohol.insert(day(n)) }
            series.sleepScore[day(n + 1)] = (drank ? 66 : 78) + Double(n % 3)
        }
        series.tagDays = ["alcohol": alcohol, "sauna": []]
        series.firstJournalDay = day(0)

        let output = CauseLinks.compute(series, calendar: calendar)
        let link = output.shown.first { $0.driver == .tag("alcohol") && $0.outcome == .sleepScore }
        #expect(link != nil)
        #expect(link?.valueText == "\u{2212}13")
        #expect(link?.tone == .cost)
        #expect(link?.caption == "10 vs 50 nights")
        #expect(link?.headline == "After drinking, your sleep score is lower")
        #expect(link?.plainTitle == "Alcohol and sleep")
        // HRV has no data: held back, named once in the pending row.
        #expect(output.pendingNames.contains("Alcohol and HRV"))
        // A tag never logged is left out altogether.
        #expect(!output.pendingNames.contains { $0.hasPrefix("Sauna") })
    }

    @Test func everyLevelLinkWaitsOnAnEmptyStore() {
        let output = CauseLinks.compute(LinkSeries(), calendar: calendar)
        #expect(output.shown.isEmpty)
        #expect(output.pending.count == CauseLinks.levels.count)
        #expect(output.pendingNames.contains("Hard days and recovery"))
    }

    @Test func strainIsSetAgainstTheNextDaysRecovery() {
        var series = LinkSeries()
        for n in 0..<45 {
            let strain = Double(n % 9) + 8
            series.strain[day(n)] = strain
            series.recovery[day(n + 1)] = 90 - 3 * strain + Double(n % 2)
        }
        let output = CauseLinks.compute(series, calendar: calendar)
        let link = output.shown.first { $0.driver == .strain && $0.outcome == .recovery }
        #expect(link?.tone == .cost)
        #expect(link?.result.direction == .falls)
        #expect(link?.caption.hasSuffix("easy days") == true)
    }

    @Test func bedtimeIsShownInMinutesWithNoTone() {
        var series = LinkSeries()
        for n in 0..<45 {
            let light = Double(n % 9) * 15
            series.daylight[day(n)] = light
            series.sleepOnset[day(n + 1)] = 24 - light / 120
        }
        let link = CauseLinks.compute(series, calendar: calendar).shown.first { $0.outcome == .sleepOnset }
        #expect(link?.outcome.unitWords == "minutes")
        #expect(link?.tone == .neutral)
        #expect((link?.effect ?? 0) < -30)
    }

    @Test func strongestLinkComesFirst() {
        let output = CauseLinks.preview
        #expect(!output.shown.isEmpty)
        let strengths = output.shown.map(\.result.strength)
        #expect(strengths == strengths.sorted(by: >))
        #expect(output.shown.allSatisfy { $0.result.isShown })
    }

    @Test func signsUseATrueMinusAndADecimalForSmallMoves() {
        func link(_ delta: Double, _ outcome: LinkOutcome) -> CauseLink {
            CauseLink(driver: .strain, outcome: outcome,
                      result: LinkMath.Result(high: [], low: [], delta: delta, spread: 1, noise: 0, verdict: .shown))
        }
        #expect(link(-8.4, .hrv).valueText == "\u{2212}8")
        #expect(link(2.44, .restingHeart).valueText == "+2.4")
        #expect(link(0.4, .sleepScore).valueText == "+0.4")
        #expect(link(-0.4, .sleepOnset).valueText == "\u{2212}24")
    }

    @Test func cardsSayALinkInPlainWords() {
        func link(_ driver: LinkDriver, _ outcome: LinkOutcome, _ delta: Double?) -> CauseLink {
            CauseLink(driver: driver, outcome: outcome,
                      result: LinkMath.Result(high: [1, 2, 3], low: [1, 2], delta: delta, spread: 1, noise: 0, verdict: .shown))
        }
        let energy = link(.sleepLength, .energy, 5.2)
        #expect(energy.headline == "After a long night, your morning energy is higher")
        #expect(energy.plainDetail == "About 5 points, across 5 nights")
        #expect(energy.driver.sideLabels == ("Long nights", "Short nights"))

        #expect(link(.strain, .recovery, -6).headline == "After a hard day, your recovery is lower")
        #expect(link(.daylight, .sleepOnset, -0.4).headline == "After a bright day, you fall asleep earlier")
        #expect(link(.daylight, .sleepOnset, -0.4).plainDetail == "About 24 minutes, across 5 days")
        #expect(link(.tag("alcohol"), .sleepScore, -11).headline == "After drinking, your sleep score is lower")
        #expect(link(.tag("alcohol"), .sleepScore, -11).driver.sideLabels == ("Alcohol", "Without"))

        // No difference yet: named, never stated.
        #expect(link(.steps, .sleepScore, nil).headline == "Active days and sleep")
        #expect(link(.steps, .sleepScore, nil).plainDetail == "5 days so far")
    }

    @Test func noCardWordsCarryArrowsOrUnitsShorthand() {
        for link in CauseLinks.preview.shown + CauseLinks.preview.pending {
            for words in [link.headline, link.plainDetail, link.plainTitle] {
                #expect(!words.contains("\u{2192}"))
                #expect(!words.contains(" pts"))
            }
        }
    }
}
