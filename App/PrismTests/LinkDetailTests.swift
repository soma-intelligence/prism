//
//  LinkDetailTests.swift
//  PrismTests
//

import Foundation
import Testing
import SomaUI
@testable import Prism

/// What a link's detail sheet is built from: the paired days with their side,
/// the outcome placed in time, the takeaway, the facts and the gate's progress.
@Suite("Link detail")
@MainActor
struct LinkDetailTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }()

    private func day(_ n: Int) -> Date {
        calendar.date(byAdding: .day, value: n, to: calendar.date(from: DateComponents(year: 2026, month: 7, day: 1))!)!
    }

    /// Sixty days, alcohol every sixth evening, the night after it 12 points
    /// lower.
    private func alcoholSeries(tagged: Int = 10) -> LinkSeries {
        var series = LinkSeries()
        var alcohol: Set<Date> = []
        for n in 0..<60 {
            let drank = n % 6 == 0 && alcohol.count < tagged
            if drank { alcohol.insert(day(n)) }
            series.sleepScore[day(n + 1)] = (drank ? 66 : 78) + Double(n % 3)
        }
        series.tagDays = ["alcohol": alcohol]
        series.firstJournalDay = day(0)
        return series
    }

    private func link(_ series: LinkSeries, _ driver: LinkDriver, _ outcome: LinkOutcome) -> CauseLink? {
        let output = CauseLinks.compute(series, calendar: calendar)
        return (output.shown + output.pending).first { $0.driver == driver && $0.outcome == outcome }
    }

    // MARK: Paired days

    @Test func levelSplitKeepsEveryDayWithItsSide() {
        let pairs = (0..<30).map { LinkMath.Pair(day: day(29 - $0), driver: Double($0), outcome: Double($0)) }
        let result = LinkMath.byLevel(pairs)
        #expect(result.days.count == 30)
        #expect(result.days.map(\.day) == (0..<30).map { day($0) })
        #expect(result.days.filter { $0.side == .high }.count == 10)
        #expect(result.days.filter { $0.side == .low }.count == 10)
        #expect(result.days.filter { $0.side == .between }.count == 10)
        // The highest driver sits on the earliest day here.
        #expect(result.days.first?.side == .high)
        #expect(result.days.last?.side == .low)
    }

    @Test func tagSplitKeepsEachDayOnTheDriversDay() {
        var outcome: [Date: Double] = [:]
        for n in 1...20 { outcome[day(n)] = 80 }
        let result = LinkMath.byTag(days: [day(4)], outcome: outcome, lag: .nextDay, since: day(0), calendar: calendar)
        #expect(result.days.count == 20)
        #expect(result.days.first?.day == day(0))
        #expect(result.days.filter { $0.side == .high }.map(\.day) == [day(4)])
    }

    // MARK: A shown link

    @Test func shownLinkStatesItselfInOnePhrase() throws {
        let link = try #require(link(alcoholSeries(), .tag("alcohol"), .sleepScore))
        let detail = LinkDetail(link: link, today: day(60), calendar: calendar)
        #expect(detail.progress == nil)
        #expect(detail.takeaway == "Nights after alcohol: 13 pts lower")
        #expect(detail.highLabel == "With")
        #expect(detail.lowLabel == "Without")
        #expect(detail.differenceText == "\u{2212}13 pts")
        #expect(detail.daysText == "10 vs 50")
        #expect(detail.noiseText?.hasPrefix("\u{00B1}") == true)
        #expect(detail.strengthLevel == LinkDetail.strengthSteps.count)
        #expect(detail.lagText == "Same night")
    }

    @Test func timelineEndsTodayAndLightsTheNightAfter() throws {
        let link = try #require(link(alcoholSeries(), .tag("alcohol"), .sleepScore))
        let detail = LinkDetail(link: link, today: day(60), calendar: calendar)
        #expect(detail.timeline.count == LinkDetail.window)
        #expect(detail.timeline.last?.date == day(60))
        let lit = detail.timeline.filter { $0.side == .high }
        #expect(lit.count == 10)
        // Alcohol on the evening of day 0: the night it shapes ends on day 1.
        #expect(lit.first?.date == day(1))
        #expect(lit.allSatisfy { ($0.value ?? 0) < 70 })
        // Before the first paired day nothing is drawn.
        #expect(detail.timeline.first?.value == nil)
    }

    @Test func levelLinkNamesItsSidesAndShowsMinutes() {
        var series = LinkSeries()
        for n in 0..<45 {
            let light = Double(n % 9) * 15
            series.daylight[day(n)] = light
            series.sleepOnset[day(n + 1)] = 24 - light / 120
        }
        guard let link = link(series, .daylight, .sleepOnset) else {
            Issue.record("no daylight link")
            return
        }
        let detail = LinkDetail(link: link, today: day(45), calendar: calendar)
        #expect(detail.highLabel == "Bright")
        #expect(detail.lowLabel == "Dim")
        #expect(detail.takeaway?.hasPrefix("After bright days: ") == true)
        #expect(detail.takeaway?.hasSuffix(" min earlier") == true)
        #expect(detail.high.allSatisfy { $0 > 1_000 })
    }

    @Test func lagReadsTheSameTablesAsTheEngine() {
        func text(_ driver: LinkDriver, _ outcome: LinkOutcome) -> String {
            LinkDetail.lagText(CauseLink(driver: driver, outcome: outcome,
                                         result: LinkMath.Result(high: [], low: [], delta: nil, spread: nil, noise: nil,
                                                                 verdict: .notEnoughDays)))
        }
        #expect(text(.sleepLength, .hrv) == "Same morning")
        #expect(text(.tag("alcohol"), .hrv) == "Next morning")
        #expect(text(.strain, .recovery) == "Next day")
        #expect(text(.steps, .sleepScore) == "Same night")
        #expect(text(.tag("sauna"), .sleepScore) == "Same night")
    }

    @Test func strengthFillsABarPerStep() {
        func level(_ strength: Double) -> Int {
            let result = LinkMath.Result(high: [1], low: [0], delta: strength, spread: 1, noise: 0, verdict: .shown)
            return LinkDetail(link: CauseLink(driver: .strain, outcome: .recovery, result: result),
                              today: day(0), calendar: calendar).strengthLevel
        }
        #expect(level(0.1) == 0)
        #expect(level(0.5) == 2)
        #expect(level(0.9) == 3)
        #expect(level(2) == 4)
    }

    // MARK: A link still waiting

    @Test func tagWaitingCountsItsNights() throws {
        let link = try #require(link(alcoholSeries(tagged: 3), .tag("alcohol"), .sleepScore))
        #expect(!link.result.isShown)
        let detail = LinkDetail(link: link, today: day(60), calendar: calendar)
        #expect(detail.takeaway == nil)
        #expect(detail.progress?.label == "3 of 5 nights with Alcohol")
        #expect(detail.progress?.fraction == 0.6)
    }

    @Test func tagWithoutAnOutcomeStartsAtZero() throws {
        let link = try #require(link(alcoholSeries(), .tag("alcohol"), .hrv))
        let detail = LinkDetail(link: link, today: day(60), calendar: calendar)
        #expect(detail.progress?.label == "0 of 5 nights with Alcohol")
        #expect(detail.progress?.fraction == 0)
        #expect(detail.timeline.allSatisfy { $0.value == nil })
    }

    @Test func levelWaitingCountsPairedDays() throws {
        var series = LinkSeries()
        for n in 0..<12 {
            series.steps[day(n)] = Double(n) * 1_000
            series.sleepScore[day(n + 1)] = 70
        }
        let link = try #require(link(series, .steps, .sleepScore))
        let detail = LinkDetail(link: link, today: day(12), calendar: calendar)
        #expect(detail.progress?.label == "12 of 21 days measured")
        #expect(abs((detail.progress?.fraction ?? 0) - 12.0 / 21) < 0.0001)
    }

    @Test func linkInsideTheNoiseShowsItsGapAgainstTheNoise() {
        let high = [70.0, 50, 66, 54, 62, 58, 75, 47]
        let low = [68.0, 48, 64, 52, 60, 56, 72, 46]
        let result = LinkMath.compare(high: high, low: low, all: high + low, gate: .level)
        let detail = LinkDetail(link: CauseLink(driver: .strain, outcome: .recovery, result: result),
                                today: day(0), calendar: calendar)
        let progress = detail.progress
        #expect(progress?.label.hasPrefix("Inside the noise: ") == true)
        #expect((progress?.fraction ?? 1) < 1)
    }
}
