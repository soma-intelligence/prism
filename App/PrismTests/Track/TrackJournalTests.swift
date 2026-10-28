//
//  TrackJournalTests.swift
//  PrismTests
//

import Foundation
import Testing
import HealthExportCore
@testable import Prism

/// The Journal's arithmetic: which week the strip shows, which reading each
/// tag is set against, and how feeling and body are counted as agreeing.
@Suite("Track journal")
struct TrackJournalTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        calendar.firstWeekday = 1
        return calendar
    }()

    func day(_ month: Int, _ day: Int, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    // MARK: Week strip

    @Test("The strip runs Monday to Sunday, whatever the calendar's first weekday")
    func weekRunsMondayToSunday() {
        // Wednesday 16 September 2026.
        let days = TrackWeek.days(containing: day(9, 16, hour: 15), calendar: calendar)
        #expect(days.count == 7)
        #expect(days.first == day(9, 14))
        #expect(days.last == day(9, 20))
        #expect(days.map { TrackWeek.letter($0, calendar: calendar) } == ["M", "T", "W", "T", "F", "S", "S"])
    }

    @Test("A Sunday belongs to the week that started the Monday before")
    func sundayClosesItsWeek() {
        let days = TrackWeek.days(containing: day(9, 20), calendar: calendar)
        #expect(days.first == day(9, 14))
    }

    @Test("Moving a week never passes today, and days after today are future")
    func weekShiftStopsAtToday() {
        let today = day(9, 29, hour: 10)
        #expect(TrackWeek.shift(day(9, 22), weeks: 1, today: today, calendar: calendar) == day(9, 29))
        #expect(TrackWeek.shift(day(9, 28), weeks: 1, today: today, calendar: calendar) == day(9, 29))
        #expect(TrackWeek.shift(day(9, 28), weeks: -1, today: today, calendar: calendar) == day(9, 21))
        #expect(TrackWeek.isFuture(day(9, 30), today: today, calendar: calendar))
        #expect(!TrackWeek.isFuture(day(9, 29, hour: 23), today: today, calendar: calendar))
    }

    // MARK: Which reading

    @Test("Each tag is read where its effect lands")
    func tagReadingChoice() {
        #expect(TrackReading.forTag("coffee-late") == .deepSleep)
        #expect(TrackReading.forTag("screens-in-bed") == .deepSleep)
        #expect(TrackReading.forTag("alcohol") == .nextMorningVariability)
        #expect(TrackReading.forTag("late-meal") == .overnightHeart)
        #expect(TrackReading.forTag("meditation") == .dayVariability)
        #expect(TrackReading.forTag("custom-1a2b3c4d") == .dayVariability)
        #expect(TrackReading.overnightHeart.better == .lower)
        #expect(TrackReading.deepSleep.better == .higher)
    }

    @Test("A night's readings are keyed by the evening before it")
    func nightKeyedByEveningBefore() {
        let wednesdayMorning = day(9, 16, hour: 7)
        let deep = HealthReading(metric: "HKCategoryTypeIdentifierSleepAnalysis", value: 4, unit: .none,
                                 start: wednesdayMorning.addingTimeInterval(-6 * 3600), end: wednesdayMorning.addingTimeInterval(-5 * 3600))
        let core = HealthReading(metric: "HKCategoryTypeIdentifierSleepAnalysis", value: 3, unit: .none,
                                 start: wednesdayMorning.addingTimeInterval(-5 * 3600), end: wednesdayMorning)
        let hrv = HealthReading(metric: "HKQuantityTypeIdentifierHeartRateVariabilitySDNN", value: 50, unit: .none,
                                start: wednesdayMorning, end: wednesdayMorning)
        let inputs = TrackInputs(now: day(9, 16, hour: 12), sleep: [deep, core], variability: [hrv],
                                 overnightHeart: [day(9, 16): 55])
        let body = TrackBody.make(from: inputs, calendar: calendar)
        #expect(body.deepSleep[day(9, 15)] == 60)
        #expect(body.nextMorningVariability[day(9, 15)] == 50)
        #expect(body.dayVariability[day(9, 16)] == 50)
        #expect(body.overnightHeart[day(9, 15)] == 55)
    }

    @Test("A costly tag reads in minutes lost, counted over the nights it cost")
    func effectWording() {
        let effect = TrackTagEffect(
            id: "coffee-late", title: "Coffee after 14:00", reading: .deepSleep,
            effect: EffectMath.Effect(delta: -18, held: 2, tries: 8)
        )
        #expect(effect.isCost)
        #expect(effect.valueText == "\u{2212}18 min")
        #expect(effect.detailText == "Deep sleep, 6 of 8 nights")

        let gathering = TrackTagEffect(
            id: "alcohol", title: "Alcohol", reading: .nextMorningVariability,
            effect: EffectMath.Effect(delta: nil, held: 0, tries: 2)
        )
        #expect(gathering.valueText == nil)
        #expect(gathering.detailText == "HRV next morning, 2 of 3 so far")
    }

    // MARK: Feel and measure

    @Test("Feeling and body agree when they point the same way")
    func agreementRule() {
        #expect(TrackJournal.agrees(feeling: 5, deviation: 4, usual: 50))
        #expect(!TrackJournal.agrees(feeling: 5, deviation: -4, usual: 50))
        #expect(TrackJournal.agrees(feeling: 1, deviation: -6, usual: 50))
        #expect(!TrackJournal.agrees(feeling: 0, deviation: 2, usual: 50))
        #expect(TrackJournal.agrees(feeling: 3, deviation: -4, usual: 50))
        #expect(!TrackJournal.agrees(feeling: 3, deviation: 8, usual: 50))
    }

    @Test("Only the last three weeks with both a feeling and a reading are counted")
    func agreementCount() {
        let today = day(9, 29, hour: 20)
        var body = TrackBody()
        var days: [Date: JournalDay] = [:]
        // Usual is 50: twenty days at 50 and the ones below around it.
        for offset in 1...40 {
            body.dayVariability[calendar.date(byAdding: .day, value: -offset, to: day(9, 29))!] = 50
        }
        func log(_ offset: Int, feeling: Int, hrv: Double) {
            let date = calendar.date(byAdding: .day, value: -offset, to: day(9, 29))!
            days[date] = JournalDay(tags: [], feeling: feeling)
            body.dayVariability[date] = hrv
        }
        log(0, feeling: 6, hrv: 60)   // agrees
        log(1, feeling: 1, hrv: 40)   // agrees
        log(2, feeling: 5, hrv: 42)   // parts
        log(3, feeling: 3, hrv: 51)   // agrees
        log(30, feeling: 6, hrv: 70)  // outside the window
        days[day(9, 25)] = JournalDay(tags: [], feeling: 4)
        body.dayVariability[day(9, 25)] = nil  // no reading, not counted

        let points = TrackJournal.feelPoints(days: days, body: body, today: today, calendar: calendar)
        #expect(points.count == 4)
        #expect(points.filter(\.agrees).count == 3)
        #expect(TrackJournal.feelNote(points) == "On every low day, your HRV was under your usual too.")
    }

    @Test("Effects count only tags logged in the window, with a stated delta first")
    func effectsOrder() {
        let today = day(9, 29, hour: 20)
        var body = TrackBody()
        var days: [Date: JournalDay] = [:]
        for offset in 1...20 {
            let date = calendar.date(byAdding: .day, value: -offset, to: day(9, 29))!
            let coffee = offset <= 4
            body.deepSleep[date] = coffee ? 40 : 60
            days[date] = JournalDay(tags: coffee ? ["coffee-late"] : (offset == 10 ? ["sauna"] : []), feeling: nil)
        }
        let tags = JournalStore.starterTags
        let effects = TrackJournal.effects(tags: tags, days: days, body: body, today: today, calendar: calendar)
        #expect(effects.map(\.id) == ["coffee-late", "sauna"])
        #expect(effects.first?.effect.delta == -20)
        #expect(effects.first?.isCost == true)
        #expect(effects.last?.effect.delta == nil)
    }
}
