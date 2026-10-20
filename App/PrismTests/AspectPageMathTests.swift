//
//  AspectPageMathTests.swift
//  PrismTests
//

import Foundation
import Testing
import SomaUI
@testable import Prism

/// What the score pages and aspect pages say about a run of days, and the
/// two sleep pages' sums.
@MainActor
struct AspectPageMathTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    @Test("The usual is the middle half of the finished days, once five of them hold a value")
    func usual() {
        let days: [Double?] = [50, 60, nil, 70, 80, 90, 10]
        let usual = AspectPageMath.usual(days)
        #expect(usual == 60...80)
        #expect(AspectPageMath.usual([50, 60, 70, 80, 99]) == nil)
    }

    @Test("Inside the usual is good; outside is worth a look unless that way is good news")
    func tone() {
        #expect(AspectPageMath.tone(65, usual: 60...70, higherIsBetter: true) == .good)
        #expect(AspectPageMath.tone(80, usual: 60...70, higherIsBetter: true) == .good)
        #expect(AspectPageMath.tone(50, usual: 60...70, higherIsBetter: true) == .watch)
        #expect(AspectPageMath.tone(80, usual: 60...70, higherIsBetter: false) == .watch)
        #expect(AspectPageMath.tone(80, usual: 60...70, higherIsBetter: nil) == .watch)
        #expect(AspectPageMath.tone(nil, usual: 60...70, higherIsBetter: true) == .neutral)
    }

    @Test("The facts: the usual, this week against last, and the usual days")
    func facts() {
        let days: [Double?] = Array(repeating: 60, count: 23) + [70, 72, 74, 70, 72, 74, 76]
        let facts = AspectPageMath.facts(days, usual: 59...61, higherIsBetter: true) { String(Int($0.rounded())) }
        #expect(facts.map(\.label) == ["Your usual", "This week", "Usual days"])
        #expect(facts[0].value == "59 to 61")
        #expect(facts[1].value == "73")
        #expect(facts[1].detail?.hasPrefix("Up ") == true)
        #expect(facts[1].tone == .good)
        #expect(facts[2].value == "23 of 29")
        let steady = AspectPageMath.weekFact(Array(repeating: 60, count: 14), higherIsBetter: true) { "\($0)" }
        #expect(steady?.detail == "Steady")
        #expect(AspectPageMath.facts([nil, nil], usual: nil, higherIsBetter: true) { "\($0)" }.first?.value == nil)
    }

    @Test("A week labels every day, a month every seventh back from today, and a missing day stays empty")
    func buckets() {
        let now = Date(timeIntervalSince1970: 1_792_500_000)
        let days: [Double?] = (0..<30).map { $0 == 28 ? nil : Double($0) }
        let week = AspectPageMath.buckets(days, span: .week, usual: nil, now: now, calendar: calendar) { "\($0)" }
        #expect(week.count == 7)
        #expect(week.allSatisfy { $0.axisLabel != nil })
        #expect(week.last?.readout == "Today")
        #expect(week[5].value == nil)
        let month = AspectPageMath.buckets(days, span: .month, usual: 1...2, now: now, calendar: calendar) { "\($0)" }
        #expect(month.count == 30)
        #expect(month.filter { $0.axisLabel != nil }.count == 5)
        #expect(month.last?.axisLabel != nil)
        #expect(month.first?.band == 1...2)
        let short = AspectPageMath.buckets([1, 2], span: .week, usual: nil, now: now, calendar: calendar) { "\($0)" }
        #expect(short.count == 7 && short.prefix(5).allSatisfy { $0.value == nil })
    }

    @Test("A score's plot runs from zero to its scale; a reading's fits its values and usual")
    func domain() {
        #expect(AspectPageMath.domain([20, 30], usual: nil, scale: 100) == 0...100)
        let fitted = AspectPageMath.domain([56, 66], usual: 55...58, scale: nil)
        #expect(fitted.lowerBound < 55 && fitted.upperBound > 66)
        #expect(AspectPageMath.latest([1, 2, nil])?.value == 2)
        #expect(AspectPageMath.latest([1, 2, nil])?.back == 1)
        #expect(AspectPageMath.average([10, 20, nil], span: .week) == 15)
    }

    @Test("Last night's head: the time asleep against the need, and a wait without a night")
    func lastNightHero() {
        let hero = LastNightHero.make(asleep: 7.5 * 3600, need: 8, nights: [7, 7.2, 7.4, 7.1, 6.9, 7.3, 7.5])
        #expect(hero.value == "7h 30m")
        #expect(hero.detail == "Need 8h")
        #expect(hero.share == 7.5 / 8)
        #expect(hero.usual != nil)
        let none = LastNightHero.make(asleep: nil, need: 8, nights: [])
        #expect(none.value == nil && none.share == nil)
        #expect(LastNightHero.span(7.9) == "7h 54m")
    }

    @Test("Sleep averages: durations as hours and minutes, bedtimes averaged across midnight")
    func sleepAverages() {
        var detail = SomaScores.Detail()
        detail.sleepHours = Array(repeating: 7.5, count: 30)
        detail.deepHours = Array(repeating: 1.2, count: 30)
        detail.remHours = Array(repeating: nil, count: 30)
        detail.bedHour = Array(repeating: 23.5, count: 15) + Array(repeating: 0.5, count: 15)
        detail.wakeHour = Array(repeating: 7, count: 30)
        let rows = SleepAverages.make(detail)
        #expect(rows.map(\.title) == ["Asleep", "Deep", "REM", "Bedtime", "Woke up"])
        #expect(rows[0].week == "7:30")
        #expect(rows[2].week == nil)
        #expect(rows[3].month == "00:00")
        #expect(rows[4].week == "07:00")
        let windows = SleepAverages.windows(detail, nights: 14, calendar: calendar)
        #expect(windows.count == 14)
        #expect(windows.last?.bed == 0.5)
        #expect(SleepAverages.rhythmNote(detail) == "Bedtime within 5 min on most nights")
    }

    @Test("A category's head counts what read this week; no night means no disturbance rows")
    func countLineAndDisturbances() {
        #expect(LastNightDisturbances.rows(nil, calendar: calendar).isEmpty)
        #expect(BodyCategoryPage.countLine(withData: nil, of: 12) == "12 measures")
        #expect(BodyCategoryPage.countLine(withData: 0, of: 12) == "Nothing read this week")
        #expect(BodyCategoryPage.countLine(withData: 6, of: 12) == "6 of 12 read this week")
    }

    @Test("Every category wears an aspect's glyph, except the ones that belong to none")
    func categoryAspects() {
        let titles = Dictionary(uniqueKeysWithValues: BodyCatalog.categories.map { ($0.title, $0.aspect) })
        #expect(titles["Mental Wellbeing"] == .mind)
        #expect(titles["Nutrition"] == .gut)
        #expect(titles["Vitals"] == .heart)
        #expect(titles["Hearing"] == .some(nil))
    }

    @Test("A Trends card's glyphs: the cause's aspect leading to the effect's")
    func linkAspects() {
        #expect(LinkDriver.sleepLength.aspect == .sleep)
        #expect(LinkDriver.strain.aspect == .activity)
        #expect(LinkDriver.tag("alcohol").aspect == .gut)
        #expect(LinkDriver.tag("meditation").aspect == .mind)
        #expect(LinkOutcome.sleepOnset.columnText([23.5, 23.5]) == "23:30")
        #expect(LinkOutcome.hrv.columnText([52, 54]) == "53")
        #expect(LinkOutcome.hrv.columnText([]) == nil)
    }

    @Test("A day under a finger says where it sits against the usual, and an edge that reads the same counts as within")
    func slotNote() {
        let format: (Double) -> String = { String(Int($0.rounded())) }
        #expect(AspectPageMath.slotNote(64, usual: 56...58, higherIsBetter: false, format: format)?.text == "Above your usual")
        #expect(AspectPageMath.slotNote(64, usual: 56...58, higherIsBetter: false, format: format)?.tone == .watch)
        #expect(AspectPageMath.slotNote(50, usual: 56...58, higherIsBetter: false, format: format)?.tone == .good)
        #expect(AspectPageMath.slotNote(58.4, usual: 56...58, higherIsBetter: false, format: format)?.text == "Within your usual")
        #expect(AspectPageMath.slotNote(nil, usual: 56...58, higherIsBetter: nil, format: format) == nil)
        #expect(AspectPageMath.slotNote(60, usual: nil, higherIsBetter: nil, format: format) == nil)
    }

    @Test("The quiet line folds this week and the usual days; the key names the average and the usual")
    func noteAndKey() {
        let days: [Double?] = Array(repeating: 56, count: 23) + [60, 61, 60, 62, 61, 60, 63]
        let format: (Double) -> String = { String(Int($0.rounded())) }
        let usual = AspectPageMath.usual(days)
        let note = AspectPageMath.note(days, usual: usual, higherIsBetter: false, unit: "bpm", format: format)
        #expect(note?.hasPrefix("This week 61 bpm, up") == true)
        #expect(note?.contains("days in your usual") == true)
        let key = AspectPageMath.key(days, span: .week, usual: 56...58, unit: "bpm", format: format)
        #expect(key.average?.text == "Average 61 bpm")
        #expect(key.usual == "Usual 56 to 58")
        #expect(AspectPageMath.note([nil, nil], usual: nil, higherIsBetter: nil, unit: nil, format: format) == nil)
    }
}
