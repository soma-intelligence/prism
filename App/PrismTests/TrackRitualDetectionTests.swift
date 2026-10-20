//
//  TrackRitualDetectionTests.swift
//  PrismTests
//

import Foundation
import Testing
import HealthExportCore
@testable import Prism

/// Ritual steps Apple Health ticks: which glyphs have a rule, the windows
/// they are read in, each rule against readings, and how the person's own
/// tick or untick wins.
@MainActor
@Suite("Track ritual detection")
struct TrackRitualDetectionTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }()

    func at(_ day: Int, _ hour: Double) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day))!.addingTimeInterval(hour * 3600)
    }

    func reading(_ identifier: String, _ value: Double, from start: Date, minutes: Double) -> HealthReading {
        let metric = HealthMetricCatalog.metric(for: identifier)!
        return HealthReading(metric: identifier, value: value, unit: metric.unit, start: start,
                             end: start.addingTimeInterval(minutes * 60))
    }

    func workout(_ activity: Int, from start: Date, minutes: Double) -> HealthReading {
        reading("HKWorkoutTypeIdentifier", Double(activity), from: start, minutes: minutes)
    }

    func step(_ glyph: String, _ title: String) -> TrackRitualStep {
        TrackRitualStep(id: glyph, title: title, glyph: glyph)
    }

    /// A night asleep ending at `hour` on `day`.
    func night(ending day: Int, at hour: Double) -> [HealthReading] {
        [reading("HKCategoryTypeIdentifierSleepAnalysis", 3, from: at(day, hour - 7), minutes: 7 * 60)]
    }

    // MARK: Rules

    @Test("Daylight, walks, stretches, breathing, water and exercise have rules; screens and reading do not")
    func rules() {
        typealias Rule = TrackRitualDetection.Rule
        #expect(TrackRitualDetection.rule(for: step("daylight", "Daylight, 10 minutes")) == Rule.daylight(minutes: 10))
        #expect(TrackRitualDetection.rule(for: step("daylight", "Morning light")) == Rule.daylight(minutes: 10))
        #expect(TrackRitualDetection.rule(for: step("walk", "Walk 20 min")) == Rule.walk(minutes: 20))
        #expect(TrackRitualDetection.rule(for: step("stretch", "Stretch")) == Rule.stretch)
        #expect(TrackRitualDetection.rule(for: step("breathe", "Breathe, 5 minutes")) == Rule.mindful(minutes: 5))
        #expect(TrackRitualDetection.rule(for: step("meditation", "Meditate")) == Rule.mindful(minutes: 1))
        #expect(TrackRitualDetection.rule(for: step("drink", "A glass of water")) == Rule.water)
        #expect(TrackRitualDetection.rule(for: step("exercise", "Move")) == Rule.workout)
        #expect(TrackRitualDetection.rule(for: step("screens", "Screens away")) == nil)
        #expect(TrackRitualDetection.rule(for: step("read", "Read a few pages")) == nil)
    }

    @Test("The morning runs from waking to noon, a late riser keeps four hours, the evening from 17:00, all cut at now")
    func windows() {
        let morning = TrackRitualDetection.window(.morning, on: at(20, 0), wake: at(20, 6.5), now: at(20, 22), calendar: calendar)
        #expect(morning == DateInterval(start: at(20, 6.5), end: at(20, 12)))
        let late = TrackRitualDetection.window(.morning, on: at(20, 0), wake: at(20, 11), now: at(20, 22), calendar: calendar)
        #expect(late == DateInterval(start: at(20, 11), end: at(20, 15)))
        let unknown = TrackRitualDetection.window(.morning, on: at(20, 0), wake: nil, now: at(20, 9), calendar: calendar)
        #expect(unknown == DateInterval(start: at(20, 4), end: at(20, 9)))
        let evening = TrackRitualDetection.window(.evening, on: at(20, 0), wake: nil, now: at(20, 19), calendar: calendar)
        #expect(evening == DateInterval(start: at(20, 17), end: at(20, 19)))
        #expect(TrackRitualDetection.window(.evening, on: at(20, 0), wake: nil, now: at(20, 9), calendar: calendar) == nil)
    }

    @Test("Daylight counts only the minutes inside the morning window")
    func daylight() {
        let window = DateInterval(start: at(20, 7), end: at(20, 12))
        let rule = TrackRitualDetection.Rule.daylight(minutes: 10)
        let id = TrackRitualSignals.Metric.daylight
        // Twelve minutes, half of them before waking: six count.
        var signals = TrackRitualSignals(daylight: [reading(id, 12, from: at(20, 6.9), minutes: 12)])
        #expect(!TrackRitualDetection.holds(rule, in: window, signals: signals))
        signals.daylight.append(reading(id, 5, from: at(20, 9), minutes: 5))
        #expect(TrackRitualDetection.holds(rule, in: window, signals: signals))
        // An afternoon outside does not tick the morning.
        let afternoon = TrackRitualSignals(daylight: [reading(id, 40, from: at(20, 14), minutes: 40)])
        #expect(!TrackRitualDetection.holds(rule, in: window, signals: afternoon))
    }

    @Test("A walk is a walking workout, or ten minutes in a row at walking pace; a long quiet hour is not")
    func walk() {
        let window = DateInterval(start: at(20, 7), end: at(20, 12))
        let rule = TrackRitualDetection.Rule.walk(minutes: 10)
        let id = TrackRitualSignals.Metric.steps
        #expect(TrackRitualDetection.holds(rule, in: window, signals: TrackRitualSignals(workouts: [workout(52, from: at(20, 8), minutes: 25)])))
        #expect(!TrackRitualDetection.holds(rule, in: window, signals: TrackRitualSignals(workouts: [workout(37, from: at(20, 8), minutes: 25)])))
        // 1,100 steps over twelve minutes: about 92 a minute.
        let brisk = TrackRitualSignals(steps: [reading(id, 1_100, from: at(20, 8), minutes: 12)])
        #expect(TrackRitualDetection.holds(rule, in: window, signals: brisk))
        // 700 steps spread over an hour is pottering about.
        let quiet = TrackRitualSignals(steps: [reading(id, 700, from: at(20, 8), minutes: 60)])
        #expect(!TrackRitualDetection.holds(rule, in: window, signals: quiet))
        // Five brisk minutes are not a ten minute walk.
        let short = TrackRitualSignals(steps: [reading(id, 500, from: at(20, 8), minutes: 5)])
        #expect(!TrackRitualDetection.holds(rule, in: window, signals: short))
    }

    @Test("Stretching is a yoga or flexibility workout; breathing needs the step's minutes of mindfulness")
    func stretchAndMindful() {
        let window = DateInterval(start: at(20, 17), end: at(20, 23))
        #expect(TrackRitualDetection.holds(.stretch, in: window, signals: TrackRitualSignals(workouts: [workout(57, from: at(20, 18), minutes: 20)])))
        #expect(!TrackRitualDetection.holds(.stretch, in: window, signals: TrackRitualSignals(workouts: [workout(50, from: at(20, 18), minutes: 20)])))
        let id = "HKCategoryTypeIdentifierMindfulSession"
        let three = TrackRitualSignals(mindful: [reading(id, 0, from: at(20, 21), minutes: 3)])
        #expect(!TrackRitualDetection.holds(.mindful(minutes: 5), in: window, signals: three))
        #expect(TrackRitualDetection.holds(.mindful(minutes: 1), in: window, signals: three))
        let six = TrackRitualSignals(mindful: [reading(id, 0, from: at(20, 21), minutes: 6)])
        #expect(TrackRitualDetection.holds(.mindful(minutes: 5), in: window, signals: six))
    }

    @Test("Water and exercise: any water in the window, a workout of ten minutes or more")
    func waterAndWorkout() {
        let window = DateInterval(start: at(20, 7), end: at(20, 12))
        let water = TrackRitualSignals(water: [reading(TrackRitualSignals.Metric.water, 250, from: at(20, 7.5), minutes: 0)])
        #expect(TrackRitualDetection.holds(.water, in: window, signals: water))
        let lateWater = TrackRitualSignals(water: [reading(TrackRitualSignals.Metric.water, 250, from: at(20, 15), minutes: 0)])
        #expect(!TrackRitualDetection.holds(.water, in: window, signals: lateWater))
        #expect(TrackRitualDetection.holds(.workout, in: window, signals: TrackRitualSignals(workouts: [workout(50, from: at(20, 8), minutes: 30)])))
        #expect(!TrackRitualDetection.holds(.workout, in: window, signals: TrackRitualSignals(workouts: [workout(50, from: at(20, 8), minutes: 5)])))
    }

    @Test("Detection reads the morning from the night's wake time, day by day")
    func detectedByDay() {
        let rituals = TrackRitualStore.starter
        let id = TrackRitualSignals.Metric.daylight
        // Woke at 8 on the 19th, outside at 7:30 (before waking) and not
        // after; woke at 6:30 on the 20th, outside at 7 for 15 minutes.
        let signals = TrackRitualSignals(
            sleep: night(ending: 19, at: 8) + night(ending: 20, at: 6.5),
            daylight: [reading(id, 15, from: at(19, 7.5), minutes: 15), reading(id, 15, from: at(20, 7), minutes: 15)]
        )
        let found = TrackRitualDetection.detected(rituals, days: [at(19, 0), at(20, 0)], signals: signals,
                                                  now: at(20, 20), calendar: calendar)
        #expect(found[at(19, 0)] == nil)
        #expect(found[at(20, 0)] == ["morning-daylight"])
    }

    // MARK: Store

    @Test("A Health tick counts and is marked; the person can untick it, and tick it back")
    func override() {
        let store = TrackRitualStore(url: nil, calendar: calendar)
        let daylight = store.ritual(.morning).steps[0]
        let today = at(20, 9)
        store.setDetected([at(20, 0): [daylight.id]])
        #expect(store.isDone(daylight, on: today))
        #expect(store.isFromHealth(daylight, on: today))
        #expect(store.share(.morning, on: today) == 1.0 / 3)

        store.toggle(daylight, on: today)
        #expect(!store.isDone(daylight, on: today))
        #expect(!store.isFromHealth(daylight, on: today))
        // A fresh read does not tick it again.
        store.setDetected([at(20, 0): [daylight.id]])
        #expect(!store.isDone(daylight, on: today))

        store.toggle(daylight, on: today)
        #expect(store.isDone(daylight, on: today))
        #expect(!store.isFromHealth(daylight, on: today))
    }

    @Test("Ticked again by hand after an untick, a step stays done when Health no longer shows it")
    func retickSurvivesDetectionChange() {
        let store = TrackRitualStore(url: nil, calendar: calendar)
        let daylight = store.ritual(.morning).steps[0]
        let today = at(20, 9)
        store.setDetected([at(20, 0): [daylight.id]])
        store.toggle(daylight, on: today)
        store.toggle(daylight, on: today)
        #expect(store.done["2026-10-20"] == [daylight.id])
        #expect(store.undone.isEmpty)

        // Health's next read drops the step: the tick by hand holds.
        store.setDetected([:])
        #expect(store.isDone(daylight, on: today))
    }

    @Test("A step the person ticked stays ticked whatever Health reads, and is not marked as Health's")
    func manual() {
        let store = TrackRitualStore(url: nil, calendar: calendar)
        let water = store.ritual(.morning).steps[1]
        store.toggle(water, on: at(20, 9))
        store.setDetected([:])
        #expect(store.isDone(water, on: at(20, 9)))
        #expect(!store.isFromHealth(water, on: at(20, 9)))
    }

    @Test("Untickings are saved; a file from before them still opens")
    func roundTrip() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "rituals-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = TrackRitualStore(url: url, calendar: calendar)
        let daylight = store.ritual(.morning).steps[0]
        store.setDetected([at(20, 0): [daylight.id]])
        store.toggle(daylight, on: at(20, 9))

        let reopened = TrackRitualStore(url: url, calendar: calendar)
        reopened.setDetected([at(20, 0): [daylight.id]])
        #expect(!reopened.isDone(daylight, on: at(20, 9)))

        let old = #"{"rituals":[],"done":{"2026-10-20":["morning-water"]}}"#
        try Data(old.utf8).write(to: url)
        let older = TrackRitualStore(url: url, calendar: calendar)
        #expect(older.done["2026-10-20"] == ["morning-water"])
        #expect(older.undone.isEmpty)
    }
}
