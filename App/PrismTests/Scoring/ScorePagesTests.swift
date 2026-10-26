//
//  ScorePagesTests.swift
//  PrismTests
//
//  Lane 3, the score pages: every sentence a page says is checked against
//  the numbers it says it about, and a page before its gate says so instead
//  of inventing a number.
//

import Foundation
import Testing
import HealthScoring
@testable import Prism

@Suite("Score pages")
@MainActor
struct ScorePagesTests {
    let base = SomaScoresTests()

    var scores: SomaScores { SomaScores.compute(base.inputs(nights: 30)) }
    var thin: SomaScores { SomaScores.compute(base.inputs(nights: 3)) }

    // MARK: Words for numbers

    @Test("Durations, clocks and signed changes read the way the pages print them")
    func formats() {
        #expect(ScoreMath.hoursMinutes(7.2) == "7:12")
        #expect(ScoreMath.duration(hours: 70.0 / 60) == "1 h 10")
        #expect(ScoreMath.duration(hours: 0.5) == "30 min")
        #expect(ScoreMath.clock(23 + 10.0 / 60) == "23:10")
        #expect(ScoreMath.clock(24.5) == "00:30")
        #expect(ScoreMath.signed(2.1, decimals: 1) == "+2.1")
        #expect(ScoreMath.signed(-0.4, decimals: 1) == "\u{2212}0.4")
        #expect(ScoreMath.signed(0.01, decimals: 1) == "0.0")
    }

    @Test("A value outside its usual band on the worse side is flagged, never a missing one")
    func usualLine() {
        let usual = ScoringUsual(center: 55, low: 52, high: 58, count: 20)
        let high = ScoreMath.usualLine(title: "Resting", value: 61, usual: usual, worse: .higher, format: { "\(Int($0))" })
        #expect(high.isOff)
        #expect(high.detail == "usual 52 to 58")
        let low = ScoreMath.usualLine(title: "Resting", value: 50, usual: usual, worse: .higher, format: { "\(Int($0))" })
        #expect(!low.isOff)
        let none = ScoreMath.usualLine(title: "Resting", value: nil, usual: nil, worse: .higher, format: { "\(Int($0))" })
        #expect(none.value == nil && none.position == nil && !none.isOff)
    }

    @Test("The trend table compares seven day means and leaves out a period it cannot reach")
    func trendRows() {
        let series: [Double?] = Array(repeating: 50, count: 23) + Array(repeating: 60, count: 7)
        let rows = ScoreMath.trendRows(series, deadBand: 2, higherIsWorse: false)
        #expect(rows.map(\.days) == [3, 7, 14])
        #expect(rows.first { $0.days == 7 }?.change == "+10.0")
        #expect(rows.first { $0.days == 7 }?.direction == "Rising")
        #expect(rows.first { $0.days == 3 }?.direction == "Rising")
    }

    // MARK: Pages before the gate

    @Test("Before seven nights, recovery and sleep say what fills them")
    func gated() {
        let recovery = ScorePages.recovery(thin, nil)
        #expect(recovery.lead.value == nil)
        #expect(recovery.lead.headline == "Recovery needs seven nights.")
        #expect(recovery.move == nil)
        let sleep = ScorePages.sleep(thin, nil)
        #expect(sleep.lead.value == nil)
        #expect(sleep.parts.isEmpty)
        #expect(ScorePages.debt(thin).value == nil)
    }

    // MARK: Pages with data

    @Test("Recovery's word and headline follow its band")
    func recoveryWords() {
        let page = ScorePages.recovery(scores, nil)
        let value = try! #require(page.lead.value)
        #expect(page.lead.word == ScorePages.recoveryWord(value))
        #expect(page.lines.map(\.title) == ["HRV", "Resting heart rate", "Sleep", "Breathing"])
        #expect(page.terms.count == scores.recoveryTerms.count)
    }

    @Test("Sleep's parts add up to its score")
    func sleepParts() {
        let page = ScorePages.sleep(scores, nil)
        let value = try! #require(page.lead.value)
        #expect(Int(page.parts.reduce(0) { $0 + $1.points }.rounded()) == value)
        #expect(!page.stages.isEmpty)
    }

    @Test("Strain states its target when recovery sets one")
    func strainTarget() {
        let page = ScorePages.strain(scores, nil)
        if let target = scores.strainTarget {
            #expect(page.lead.change == "Target \(target.lowerBound) to \(target.upperBound) today")
        }
        #expect(page.zones.isEmpty)
    }

    @Test("Night dip reads last night's beats against the resting baseline")
    func nightDip() {
        var inputs = ScoreDetailInputs(now: base.now)
        let start = base.day(0, hour: 1)
        inputs.lastNightBeats = (0..<20).map {
            ScoringTimedValue(start: start.addingTimeInterval(Double($0) * 600), end: start, value: 49)
        }
        inputs.nightHeartRate = [50, 50, 49]
        let dip = try! #require(ScorePages.nightDip(scores, inputs))
        let today = try! #require(dip.today)
        #expect(today.meanSleepingHR == 49)
        #expect(today.percent > 0)
        #expect(dip.nights.count == 3)
    }

    @Test("Breathing flags nights above the usual band running")
    func breathing() {
        var inputs = ScoreDetailInputs(now: base.now)
        inputs.respiratory = Array(repeating: 14.0, count: 10) + [16.5, 16.8]
        let page = ScorePages.breathing(inputs)
        #expect(page.headline == "Above your range for two nights running.")
        #expect(page.value == 16.8)
    }

    @Test("The peak window waits for three nights")
    func peak() {
        let empty = ScorePages.peak(scores, ScoreDetailInputs(now: base.now))
        #expect(empty.day == nil)
        var inputs = ScoreDetailInputs(now: base.now)
        inputs.nights = (0..<5).reversed().map {
            ScoringNightWindow(start: base.day(-$0 - 1, hour: 23), end: base.day(-$0, hour: 7))
        }
        let page = ScorePages.peak(scores, inputs, calendar: base.calendar)
        #expect(page.day != nil)
        #expect(page.day?.nights == 5)
    }
}
