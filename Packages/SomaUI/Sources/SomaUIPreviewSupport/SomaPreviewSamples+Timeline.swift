//
//  SomaPreviewSamples+Timeline.swift
//  SomaUIPreviewSupport
//

import Foundation
import SomaUI

public extension SomaPreviewSamples {
    /// The moment the sample day is read at: 19:46 on 3 October 2026.
    static let timelineNow: Date = timelineHour(19 + 46.0 / 60)

    /// A whole day with its numbers: the night, the morning's run, meals, a
    /// supplement, a stress peak, a mindful session, and the evening still to come.
    static let timelineDay: [SomaTimelineEvent] = [
        SomaTimelineEvent(id: "sleep", time: "23:38", title: "Sleep", aspect: .sleep,
                          stats: [SomaTimelineStat(symbol: "bed.double.fill", text: "7h 12m"),
                                  SomaTimelineStat(symbol: "sun.horizon.fill", text: "07:16")],
                          start: timelineHour(-22.0 / 60), end: timelineHour(7 + 16.0 / 60)),
        SomaTimelineEvent(id: "breakfast", time: "07:52", title: "Breakfast", aspect: .gut,
                          stats: [SomaTimelineStat(symbol: "flame.fill", text: "420 kcal"),
                                  SomaTimelineStat(symbol: "p.circle.fill", text: "28 g")],
                          start: timelineHour(7 + 52.0 / 60)),
        SomaTimelineEvent(id: "run", time: "08:30", title: "Outdoor run", aspect: .activity, symbol: "figure.run",
                          stats: [SomaTimelineStat(symbol: "timer", text: "42m"),
                                  SomaTimelineStat(symbol: "heart.fill", text: "152 bpm"),
                                  SomaTimelineStat(symbol: "shoeprints.fill", text: "6,240")],
                          start: timelineHour(8.5), end: timelineHour(9 + 12.0 / 60)),
        SomaTimelineEvent(id: "creatine", time: "09:30", title: "Creatine", symbol: "pills.fill",
                          stats: [SomaTimelineStat(symbol: "scalemass.fill", text: "5 g")],
                          start: timelineHour(9.5)),
        SomaTimelineEvent(id: "lunch", time: "12:40", title: "Lunch", aspect: .gut,
                          stats: [SomaTimelineStat(symbol: "flame.fill", text: "640 kcal"),
                                  SomaTimelineStat(symbol: "p.circle.fill", text: "38 g")],
                          start: timelineHour(12 + 40.0 / 60)),
        SomaTimelineEvent(id: "peak", time: "14:30", title: "Stress peak", aspect: .mind, symbol: "waveform.path.ecg",
                          stats: [SomaTimelineStat(symbol: "heart.fill", text: "104 bpm"),
                                  SomaTimelineStat(symbol: "timer", text: "18m")],
                          start: timelineHour(14.5), end: timelineHour(14.8)),
        SomaTimelineEvent(id: "mindful", time: "17:10", title: "Mindful session", aspect: .mind, symbol: "wind",
                          stats: [SomaTimelineStat(symbol: "timer", text: "10m")],
                          start: timelineHour(17 + 10.0 / 60), end: timelineHour(17 + 20.0 / 60)),
        SomaTimelineEvent(id: "dinner", time: "20:00", title: "Dinner", aspect: .gut,
                          stats: [SomaTimelineStat(symbol: "clock", text: "By 20:00")],
                          start: timelineHour(20), isPlanned: true),
        SomaTimelineEvent(id: "wind", time: "22:30", title: "Wind down", aspect: .mind, symbol: "moon.haze.fill",
                          start: timelineHour(22.5), isPlanned: true),
        SomaTimelineEvent(id: "bed", time: "23:00", title: "In bed", aspect: .sleep, symbol: "bed.double.fill",
                          stats: [SomaTimelineStat(symbol: "alarm.fill", text: "Up 07:10")],
                          start: timelineHour(23), isPlanned: true),
    ]

    /// The day so far as the Today card receives it: what happened, then now.
    static let timelineSoFar: [SomaTimelineEvent] =
        timelineDay.filter { !$0.isPlanned }
        + [SomaTimelineEvent(id: "now", time: "19:46", title: "Now", isNow: true)]

    private static func timelineHour(_ hour: Double) -> Date {
        let calendar = Calendar.current
        let day = calendar.date(from: DateComponents(year: 2026, month: 10, day: 3)) ?? Date(timeIntervalSinceReferenceDate: 0)
        return day.addingTimeInterval(hour * 3600)
    }
}
