//
//  MindPreview.swift
//  Prism
//

#if DEBUG
import Foundation
import HealthExportCore
import SomaUI

/// Sample models for the Mind previews. Development only: the shipping page
/// reads Health and renders dashes when it holds nothing.
extension MindInnerSpace {
    static let preview: MindInnerSpace = {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var slots = Array(repeating: MindSlot.quiet, count: slotsPerDay)
        for index in 28...31 { slots[index] = .raised }
        for index in 40..<slotsPerDay { slots[index] = .later }
        let letters = calendar.veryShortStandaloneWeekdaySymbols
        let minutes: [Double] = [8, 0, 14, 4, 7, 0, 12]
        let week = (0..<7).map { index -> MindBar in
            let day = calendar.date(byAdding: .day, value: index - 6, to: today) ?? today
            return MindBar(day: day, letter: letters[calendar.component(.weekday, from: day) - 1], minutes: minutes[index], isToday: index == 6)
        }
        return MindInnerSpace(
            reason: "Your HRV is 44 ms, under your usual 48. Two stress peaks today, the highest 34 beats over resting at 14:10.",
            variability: 44, variabilityTrend: .down, usualVariability: 48,
            resting: 57, restingTrend: .up, mindfulToday: 12,
            energyNote: "Your energy bank is at 58 of 100: charged by last night's sleep, spent by the hours awake and today's activity.",
            energy: 58,
            energyCurve: [(0, 34), (0.1, 52), (0.2, 74), (0.3, 81), (0.4, 72), (0.5, 64), (0.6, 60), (0.66, 58)]
                .map { MindEnergyPoint(dayFraction: $0.0, level: $0.1) },
            slots: slots, week: week,
            mindfulNote: "On days with ten minutes or more, your evening HRV runs 6 ms higher.",
            ritualDetail: "Slow breathing can bring your HRV back toward 48 ms."
        )
    }()
}

extension MindInsights {
    static let preview: MindInsights = {
        let heat: [[Double]] = [
            [2, 4, 6, 8, 6, 4, 2],
            [4, 8, 14, 30, 34, 18, 6],
            [2, 6, 8, 12, 10, 6, 4],
            [4, 10, 14, 28, 26, 16, 6],
            [4, 6, 8, 10, 8, 6, 4],
            [2, 2, 4, 4, 4, 2, 2],
            [2, 2, 2, 4, 2, 4, 8],
        ]
        return MindInsights(
            hardDays: 9, shortNights: 6, calmDays: 41,
            heatmap: MindHeatmap(minutes: heat),
            peakDays: "Tue, Thu", peakPart: "afternoons",
            hardAfternoons: 9,
            precursors: [
                MindPrecursor(title: "A night under seven hours", count: 6),
                MindPrecursor(title: "A late dinner the night before", count: 4),
                MindPrecursor(title: "Coffee after 14:00", count: 3),
                MindPrecursor(title: "Hard training the day before", count: 2),
            ],
            reason: "Stress peaks cluster on Tuesday and Thursday afternoons."
        )
    }()
}

extension MindLensModel {
    static let preview: MindLensModel = {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        // Asleep to 06:30, then a morning that climbs, a loaded afternoon
        // and an evening settling: half hours to 18:00.
        let values: [Double] = [
            18, 22, 26, 24, 30, 38, 44, 52, 48, 41, 36, 44, 58, 66, 72, 78, 74, 61,
            55, 49, 62, 71, 83, 76, 69, 58, 47, 40, 36, 33, 29, 31, 35,
        ]
        let stress = values.enumerated().map { index, value in
            MindStressSample(start: today.addingTimeInterval(Double(13 + index) * 30 * 60), value: value)
        }
        let feelings: [(Double?, [String], [String])] = [
            (0.33, ["calm"], ["family"]), (nil, [], []), (-0.33, ["drained"], ["work"]), (0.67, ["happy", "grateful"], ["friends"]),
            (0, [], []), (-0.67, ["anxious", "overwhelmed"], ["work", "money"]), (0.33, ["content"], []),
            (nil, [], []), (1, ["excited", "proud"], ["fitness"]), (0.67, ["peaceful"], ["partner"]), (-0.33, ["stressed"], ["tasks"]),
            (0, ["calm"], []), (0.67, ["hopeful", "calm"], ["selfCare"]), (0.33, ["content", "grateful"], ["family", "hobbies"]),
        ]
        let moods = feelings.enumerated().map { index, item in
            MindMoodDay(
                day: calendar.date(byAdding: .day, value: index - 13, to: today) ?? today,
                valence: item.0,
                words: item.1.compactMap { MindFeeling.named($0)?.title },
                themes: item.2.compactMap { MindAssociation.named($0)?.title },
                isToday: index == 13
            )
        }
        return MindLensModel(
            now: today.addingTimeInterval(23 * 60 * 60),
            dayStart: today,
            hrv: 44, hrvTrend: .down,
            resting: 57, restingTrend: .up,
            mindfulToday: 7,
            stress: stress,
            moods: moods,
            week: MindInnerSpace.preview.week.enumerated().map { index, bar in
                var bar = bar
                bar.minutes = [8, 0, 14, 4, 12, 3, 7][index]
                return bar
            },
            heatmap: MindInsights.preview.heatmap
        )
    }()
}
#endif
