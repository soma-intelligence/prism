//
//  MindNightStressTests.swift
//  PrismTests
//

import Foundation
import Testing
import HealthScoring
@testable import Prism

/// A fixed clock: Tuesday 2026-10-20 in UTC.
private enum Clock {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        return calendar
    }()

    static let today = calendar.date(from: DateComponents(year: 2026, month: 10, day: 20))!

    /// `hours` from today's midnight (negative for the evening before).
    static func at(_ hours: Double, from day: Date = today) -> Date {
        day.addingTimeInterval(hours * 3_600)
    }

    static func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: today)!
    }
}

@Suite("Mind: last night on the stress line")
struct MindNightStressTests {
    private func beats(every minutes: Double = 10, from: Double, to: Double, bpm: Double) -> [ScoringTimedValue] {
        stride(from: from, to: to, by: minutes / 60).map {
            ScoringTimedValue(start: Clock.at($0), end: Clock.at($0), value: bpm)
        }
    }

    @Test("The night is the one that ended today, held to six hours before midnight")
    func window() {
        let lastNight = ScoringNightWindow(start: Clock.at(-1.75), end: Clock.at(6.5))
        let before = ScoringNightWindow(start: Clock.at(-25), end: Clock.at(-17))
        let found = MindNightStress.window([before, nil, lastNight], dayStart: Clock.today, now: Clock.at(12))
        #expect(found == lastNight)

        let early = ScoringNightWindow(start: Clock.at(-9), end: Clock.at(5))
        #expect(MindNightStress.window([early], dayStart: Clock.today, now: Clock.at(12))?.start == Clock.at(-6))

        #expect(MindNightStress.window([before], dayStart: Clock.today, now: Clock.at(12)) == nil, "Yesterday's night is not last night")
        #expect(MindNightStress.window([lastNight], dayStart: Clock.today, now: Clock.at(5)) == nil, "Not over yet")
    }

    @Test("Each half hour reads heart rate against rest and the nearest HRV against baseline")
    func line() {
        let night = ScoringNightWindow(start: Clock.at(-1.8), end: Clock.at(6.6))
        let hrv = [
            ScoringTimedValue(start: Clock.at(-1), end: Clock.at(-1), value: 60),
            ScoringTimedValue(start: Clock.at(4), end: Clock.at(4), value: 30),
        ]
        let samples = MindNightStress.line(
            window: night, dayStart: Clock.today,
            heartRate: beats(from: -2, to: 7, bpm: 50), hrv: hrv,
            dayHRV: nil, hrvBaseline: 60, restingHR: 60, maxHR: 180
        )
        // 22:00 (middle 22:15 is inside) to 06:00 (middle 06:15); 06:30's
        // middle, 06:45, is after waking.
        #expect(samples.first?.start == Clock.at(-2))
        #expect(samples.last?.start == Clock.at(6))
        #expect(samples.count == 17)

        let at = Dictionary(uniqueKeysWithValues: samples.map { ($0.start, $0.value) })
        // A slow heart adds nothing; HRV on baseline leaves the floor at 0.
        #expect(at[Clock.at(-1)] == 0)
        // HRV at half its baseline: the model's floor, 60 × 0.5.
        #expect(abs((at[Clock.at(4)] ?? 0) - 30) < 0.001)
        // Two hours from either reading: the night's mean, 45 against 60.
        #expect(abs((at[Clock.at(1.5)] ?? 0) - 15) < 0.001)
    }

    @Test("A half hour with no beats is a gap, and a night with no HRV leans on the day's")
    func gapsAndFallback() {
        let night = ScoringNightWindow(start: Clock.at(0), end: Clock.at(4))
        let heart = beats(from: 0, to: 1, bpm: 50) + beats(from: 2, to: 4, bpm: 105)
        let samples = MindNightStress.line(
            window: night, dayStart: Clock.today, heartRate: heart, hrv: [],
            dayHRV: 45, hrvBaseline: 60, restingHR: 60, maxHR: 180
        )
        #expect(!samples.contains { $0.start == Clock.at(1) || $0.start == Clock.at(1.5) })
        let calm = samples.first { $0.start == Clock.at(0) }?.value ?? -1
        let raised = samples.first { $0.start == Clock.at(3) }?.value ?? -1
        #expect(abs(calm - 15) < 0.001, "The day's HRV, 45 against 60")
        #expect(raised > calm, "A heart well above rest reads higher, asleep or not")
    }

    @Test("The night and the day share no half hour")
    func complement() {
        let night = ScoringNightWindow(start: Clock.at(-1.2), end: Clock.at(6.7))
        let heart = beats(from: -2, to: 10, bpm: 70)
        let nightLine = MindNightStress.line(window: night, dayStart: Clock.today, heartRate: heart, hrv: [],
                                             dayHRV: 50, hrvBaseline: 60, restingHR: 60, maxHR: 180)
        let dayLine = ScoringIntradayStress.line(heartRate: heart, dayStart: Clock.today, now: Clock.at(10),
                                                 excluded: [night], hrv: 50, hrvBaseline: 60, restingHR: 60, maxHR: 180)
        let nightStarts = Set(nightLine.map(\.start))
        #expect(!nightLine.isEmpty && !dayLine.isEmpty)
        #expect(dayLine.allSatisfy { !nightStarts.contains($0.start) })
        // Every half hour of the morning is drawn once, by one or the other.
        let morning = (0..<20).map { Clock.at(Double($0) / 2) }
        let dayStarts = Set(dayLine.map(\.start))
        #expect(morning.allSatisfy { nightStarts.contains($0) || dayStarts.contains($0) })
    }

    @Test("The chart's day starts on the night's half hour and keeps its labels apart")
    func axis() {
        let night = MindStressNight(start: Clock.at(-1.8), end: Clock.at(6.5), samples: [])
        let axis = MindStressAxis(dayStart: Clock.today, night: night)
        #expect(axis.start == Clock.at(-2))
        #expect(axis.end == Clock.at(24))
        #expect(axis.isNight(Clock.at(3)))
        #expect(!axis.isNight(Clock.at(6.5)), "06:30's middle is after waking")
        #expect(axis.ticks.map(\.label) == ["00", "06", "12", "18", "24"], "22:00 would crowd midnight")
        #expect(abs(axis.fraction(Clock.at(0)) - 2.0 / 26) < 0.0001)

        let early = MindStressAxis(dayStart: Clock.today, night: MindStressNight(start: Clock.at(-5), end: Clock.at(5), samples: []))
        #expect(early.ticks.first?.label == "19")

        let alone = MindStressAxis(dayStart: Clock.today, night: nil)
        #expect(alone.start == Clock.today && alone.nightSpan == nil)
    }

    @Test("The line breaks where the night gives way to the day, even with no gap")
    func slotsBreakAtWaking() {
        let night = MindStressNight(start: Clock.at(-1), end: Clock.at(6), samples: [])
        let samples = (-2..<16).map { MindStressSample(start: Clock.at(Double($0) / 2), value: 20) }
        let slots = MindStressSlots(samples, dayStart: Clock.today, night: night)
        #expect(slots.runs.count == 2)
        let b = MindStressSlots.before
        #expect(slots.runs.first?.last == b + 11, "05:30 is the night's last half hour")
        #expect(slots.runs.last?.first == b + 12, "06:00 starts the day")
    }
}
