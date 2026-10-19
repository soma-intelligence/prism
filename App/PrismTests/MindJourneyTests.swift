//
//  MindJourneyTests.swift
//  PrismTests
//

import Foundation
import Testing
import HealthExportCore
@testable import Prism

/// Lane 5, Mind: the logic in `Prism/Core/Mind`. A fixed
/// calendar keeps the days the same on every machine.
@Suite("Mind journey")
@MainActor
struct MindJourneyTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        calendar.locale = Locale(identifier: "en_GB")
        return calendar
    }()

    /// Tuesday 29 September 2026 at `hour`:`minute`, or a day before or after.
    func at(_ hour: Int, _ minute: Int = 0, day offset: Int = 0) -> Date {
        let base = calendar.date(from: DateComponents(year: 2026, month: 9, day: 29, hour: hour, minute: minute))!
        return calendar.date(byAdding: .day, value: offset, to: base)!
    }

    func day(_ offset: Int) -> Date { calendar.startOfDay(for: at(12, day: offset)) }

    // MARK: Safety

    @Test func directWordsAreUrgent() {
        #expect(MindSafetyGuard.classify("Honestly I want to die") == .direct)
        #expect(MindSafetyGuard.classify("J’ai envie d’en finir avec tout") == .direct)
        #expect(MindSafetyGuard.check(valence: nil, labels: [], text: "I keep thinking I should hurt myself").isUrgent)
    }

    @Test func veiledDisclosureIsIndirect() {
        #expect(MindSafetyGuard.classify("I lost my job and I keep looking at the bridge") == .indirect)
        #expect(MindSafetyGuard.classify("Everyone would be better off without me") == .indirect)
        #expect(MindSafetyGuard.classify("I bought some pills today") == .indirect)
    }

    @Test func ordinaryDaysStaySafe() {
        #expect(MindSafetyGuard.classify("The product review ran over, lunch was good, we walked to the park.") == .none)
        #expect(MindSafetyGuard.classify("There is a lovely bridge by the office") == .none)
        #expect(MindSafetyGuard.check(valence: -0.2, labels: ["tired"], text: "") == .none)
    }

    @Test func aHeavyFeelingOffersHelpQuietly() {
        let level = MindSafetyGuard.check(valence: -1, labels: ["hopeless"], text: "")
        #expect(level == .heavy)
        #expect(!level.isUrgent)
    }

    @Test func everyRegionReachesAPerson() {
        #expect(MindCrisisResources.lines(region: "US").first?.dial == "988")
        #expect(MindCrisisResources.lines(region: "FR").first?.dial == "3114")
        let unknown = MindCrisisResources.lines(region: "JP")
        #expect(unknown.count == 1)
        #expect(unknown.first?.web != nil)
        #expect(MindCrisisResources.lines(region: "IT").first?.dial == "112")
        #expect(MindCrisisResources.lines(region: nil).allSatisfy { $0.url != nil })
    }

    // MARK: Stress curve and radar

    func heart(_ bpm: Double, at date: Date) -> HealthReading {
        HealthReading(metric: "hr", value: bpm, unit: .none, start: date, end: date.addingTimeInterval(60))
    }

    func curve(peaksAt hours: [Int], bpm: Double = 110, resting: Double = 60) -> MindStressDayCurve {
        var readings: [HealthReading] = []
        for hour in 8..<20 {
            for minute in stride(from: 0, to: 60, by: 10) {
                readings.append(heart(hours.contains(hour) ? bpm : resting + 5, at: at(hour, minute)))
            }
        }
        return MindStressCurve.make(day: day(0), now: at(21), heartRate: readings, resting: resting, workouts: [], asleep: [])
    }

    @Test func curveReadsHeartAboveResting() {
        let quiet = curve(peaksAt: [])
        let bucket = quiet.bucket(of: at(10))
        // 65 against a resting 60 and a ceiling of 0.72 x 190.
        let expected = 5 / (190 * 0.72 - 60) * 100
        #expect(abs((quiet.value(bucket) ?? 0) - expected) < 0.5)
        #expect(quiet.value(quiet.bucket(of: at(3))) == nil)
    }

    @Test func workoutsAndSleepAreLeftOut() {
        let run = HealthReading(metric: "workout", value: 37, unit: .none, start: at(10), end: at(11))
        let made = MindStressCurve.make(day: day(0), now: at(21), heartRate: [heart(150, at: at(10, 30))], resting: 60, workouts: [run], asleep: [at(0)..<at(7)])
        #expect(!made.isUsable(made.bucket(of: at(10, 30))))
        #expect(made.workoutBuckets.contains(made.bucket(of: at(11, 30))))
        #expect(made.sleepBuckets.contains(made.bucket(of: at(3))))
    }

    @Test func radarFindsEpisodesAndTheirMeeting() throws {
        let review = MindCalendarEvent(id: "a", title: "Product review", calendarTitle: "Work", start: at(14), end: at(15))
        let reading = try #require(MindStressRadar.reading(curve(peaksAt: [14, 15]), events: [review]))
        #expect(reading.episodes.count == 1)
        #expect(reading.worst?.trigger == "Product review")
        #expect(reading.elevatedMinutes >= 60)
        #expect(reading.pauseBucket == reading.worst?.startBucket)
    }

    @Test func aThinDayIsNotRead() {
        let thin = MindStressCurve.make(day: day(0), now: at(21), heartRate: [heart(100, at: at(9))], resting: 60, workouts: [], asleep: [])
        #expect(MindStressRadar.reading(thin, events: []) == nil)
    }

    @Test func bandsFollowTheCuts() {
        #expect(MindStressBand(25) == .rest)
        #expect(MindStressBand(26) == .low)
        #expect(MindStressBand(51) == .medium)
        #expect(MindStressBand(76) == .high)
    }

    // MARK: Meetings

    @Test func meetingsAreRecognisedAndTimed() {
        let events = [
            MindCalendarEvent(id: "1", title: "Standup", calendarTitle: "", start: at(9, 30), end: at(9, 45)),
            MindCalendarEvent(id: "2", title: "Yoga", calendarTitle: "", start: at(7), end: at(8)),
            MindCalendarEvent(id: "3", title: "Budget call", calendarTitle: "", start: at(16, 30), end: at(17, 15)),
            MindCalendarEvent(id: "4", title: "Offsite", calendarTitle: "", start: at(9), end: at(18)),
        ]
        let found = MindMeetingStress.meetings(in: events)
        #expect(found.map(\.id) == ["1", "3"])
        #expect(MindMeetingStress.coveredMinutes(found) == 60)
    }

    @Test func aRecurringMeetingIsMeasuredAgainstTheSameSlot() throws {
        var curves: [MindStressDayCurve] = []
        var events: [MindCalendarEvent] = []
        // Four weeks of weekdays; the Tuesday review runs hot, other days stay quiet at 14:00.
        for offset in -27...0 {
            let date = day(offset)
            guard !calendar.isDateInWeekend(date) else { continue }
            let isTuesday = calendar.component(.weekday, from: date) == 3
            var samples = Array(repeating: Optional(20.0), count: MindStressDayCurve.buckets)
            if isTuesday {
                samples[28] = 70
                samples[29] = 70
                let start = calendar.date(bySettingHour: 14, minute: 0, second: 0, of: date)!
                events.append(MindCalendarEvent(id: "\(offset)", title: "Design review", calendarTitle: "", start: start, end: start.addingTimeInterval(3600)))
            }
            curves.append(MindStressDayCurve(day: date, samples: samples))
        }
        let series = MindMeetingStress.series(days: curves, events: events, calendar: calendar)
        let review = try #require(series.first)
        #expect(review.title == "Design review")
        #expect(abs(review.delta - 50) < 0.01)
        #expect(review.isDirectional)
    }

    // MARK: Forecast

    @Test func forecastIsNilWithNothingInHand() {
        #expect(MindMoodForecast.forecast(.init()) == nil)
    }

    @Test func forecastFollowsItsWeights() throws {
        let reading = try #require(MindMoodForecast.forecast(.init(sleepScore: 100, overnightHRV: 60, hrvBaseline: 50)))
        // Sleep +18, HRV ratio 1.2: +8.
        #expect(abs(reading.index - 76) < 0.01)
        #expect(reading.band == .bright)
        #expect(reading.confidence == .fair)
        #expect(reading.lever == .keepRhythm)
    }

    @Test func forecastPointsAtTheWorstSignal() throws {
        let reading = try #require(MindMoodForecast.forecast(.init(sleepScore: 30, daylightMinutes: 100, priorMood: 0.6)))
        #expect(reading.lever == .protectSleep)
        #expect(reading.confidence == .good)
    }

    @Test func forecastTrackCountsCloseDays() {
        let track = MindMoodForecast.track(forecasts: [day(-2): 60, day(-1): 50, day(0): 70], felt: [day(-2): 58, day(-1): 70])
        #expect(track.within == 1)
        #expect(track.of == 2)
    }

    // MARK: Words

    @Test func classifierPicksTheMostSpecific() {
        #expect(MindEventClassifier.category(title: "Call with the physio") == .care)
        #expect(MindEventClassifier.category(title: "Weekly sync") == .meeting)
        #expect(MindEventClassifier.category(title: "Run, 10 km") == .restorative)
        #expect(MindEventClassifier.category(title: "Standup") == .meeting)
        #expect(MindEventClassifier.category(title: "Zzz") == .unknown)
        #expect(MindEventClassifier.category(title: "Blocked", calendarTitle: "Meetings") == .meeting)
    }

    @Test func valenceStopsRoundTrip() {
        #expect(MindMoodEntry.valence(stop: 0) == -1)
        #expect(MindMoodEntry.valence(stop: 6) == 1)
        #expect(MindMoodEntry.valence(stop: 3) == 0)
        for stop in 0..<MindMoodEntry.stops {
            #expect(MindMoodEntry.stop(valence: MindMoodEntry.valence(stop: stop)) == stop)
        }
        #expect(MindMoodEntry(date: at(9), kind: .momentary, valence: -0.5).mood == 25)
    }

    // MARK: Inner map

    @Test func pullsNeedEnoughMentionsAndAMajority() {
        let moods = (0..<6).map { index in
            MindMoodEntry(date: at(9, day: -index), kind: .momentary, valence: index < 3 ? 0.8 : -0.6, associations: index < 3 ? ["friends"] : ["work"])
        } + [MindMoodEntry(date: at(10), kind: .momentary, valence: 0.9, associations: ["money"])]
        let pulls = MindInnerMap.pulls(moods: moods, notes: [], calendar: calendar)
        #expect(pulls.map(\.title) == ["Friends", "Work"])
        #expect(pulls.first?.lifts == true)
        #expect(pulls.last?.lifts == false)
        #expect(pulls.last?.held == 3)
    }

    @Test func innerMapAgreesWhenBothSidesMatch() {
        let moods = [
            MindMoodEntry(date: at(9, day: -1), kind: .momentary, valence: 0.6, labels: ["calm"]),
            MindMoodEntry(date: at(9, day: -2), kind: .momentary, valence: -0.6, labels: ["anxious"]),
        ]
        let map = MindInnerMap.make(moods: moods, notes: [], hrvByDay: [day(-1): 55, day(-2): 55], usualHRV: 50, now: at(12), calendar: calendar)
        #expect(map.points.count == 2)
        #expect(map.agreeing == 1)
        #expect(map.checkIns == 2)
        #expect(map.rows.map(\.feeling.id) == ["calm", "anxious"])
    }

    // MARK: Habits and usual

    @Test func habitsSortIntoClearNeedsMoreAndNone() {
        var outcome: [Date: Double] = [:]
        var late = Set<Date>()
        var sauna = Set<Date>()
        var reading = Set<Date>()
        for offset in -29...(-1) {
            let date = day(offset)
            let isLate = offset % 3 == 0
            outcome[date] = isLate ? 55 : 65
            if isLate { late.insert(date) }
            if offset > -5 { sauna.insert(date) }
            if offset % 2 == 0 { reading.insert(date) }
        }
        let model = MindHabitEffects.make(lens: .recovery, habits: [
            (id: "late-meal", title: "Late meal", days: late),
            (id: "sauna", title: "Sauna", days: sauna),
            (id: "reading", title: "Reading", days: reading),
        ], outcome: outcome)
        #expect(model.clear.map(\.id) == ["late-meal"])
        #expect(model.clear.first?.delta == -10)
        #expect(model.needsMore.map(\.id) == ["sauna"])
        #expect(model.reason.hasPrefix("Late meal costs you the most: 10 points next morning."))
    }

    @Test func seriesKeyedByTheDayBefore() {
        let keyed = MindHabitEffects.keyedByDayBefore([50, nil, 70], today: at(9), calendar: calendar)
        #expect(keyed[day(-1)] == 70)
        #expect(keyed[day(-3)] == 50)
        #expect(keyed.count == 2)
    }

    @Test func usualRangeIsTheMiddleHalf() {
        #expect(MindUsual.range([1, 2, 3, 4]) == nil)
        #expect(MindUsual.range([1, 2, 3, 4, 5]) == 2...4)
        #expect(MindUsual.place(6, in: 2...4) == .over)
        #expect(MindUsual.place(nil, in: 2...4) == nil)
    }

    @Test func scoreWords() {
        #expect(MindScoreWords.word(58) == "Working hard")
        #expect(MindScoreWords.word(nil) == "Not read yet")
        #expect(MindScoreWords.againstLastWeek([60, 60, 60, 60, 60, 60, 60, 54]) == -6)
        #expect(MindScoreWords.againstLastWeek([nil, 54]) == nil)
    }

    // MARK: Store

    @Test func storeKeepsCorrectionsAndDeletesEverything() {
        let store = MindStore(url: nil)
        store.save(MindDayNote(day: day(0), text: "x", moments: [MindMoment(title: "Weekly sync", category: .meeting, pull: .weighed)]))
        store.correct("weekly SYNC", to: .focus)
        #expect(store.note(on: day(0))?.moments.first?.category == .focus)
        #expect(store.category(of: "Weekly sync") == .focus)
        store.keepForecast(60, for: day(0))
        store.keepForecast(40, for: day(0))
        #expect(store.forecastsByDay()[day(0)] == 60 || store.forecasts.values.first == 60)
        store.deleteAll()
        #expect(store.notes.isEmpty && !store.consent.isGiven && store.forecasts.isEmpty)
    }
}
