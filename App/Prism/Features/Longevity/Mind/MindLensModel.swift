//
//  MindLensModel.swift
//  Prism
//

import SwiftUI
import SomaUI
import HealthScoring

/// The three stress zones, on the 0 to 100 line Pulse's stress page draws:
/// low under 34, high from 67.
enum MindZone: Int, CaseIterable, Identifiable, Sendable {
    case low, medium, high

    var id: Int { rawValue }

    init(_ value: Double) {
        if value >= ScorePages.stressBands.high {
            self = .high
        } else if value >= ScorePages.stressBands.moderate {
            self = .medium
        } else {
            self = .low
        }
    }

    var title: LocalizedStringResource {
        switch self {
        case .low: "Low"
        case .medium: "Med"
        case .high: "High"
        }
    }

    /// The zone's data colour for the stress line: teal, amber,
    /// red. Health hues, so they read the same in both appearances.
    var hue: SomaHealthHue {
        switch self {
        case .low: .mind
        case .medium: .mobility
        case .high: .vitals
        }
    }

    var color: Color { hue.color }

    /// Where the zone sits on the 0 to 100 line.
    var range: ClosedRange<Double> {
        switch self {
        case .low: 0...ScorePages.stressBands.moderate
        case .medium: ScorePages.stressBands.moderate...ScorePages.stressBands.high
        case .high: ScorePages.stressBands.high...100
        }
    }
}

/// One half hour on today's stress line.
struct MindStressSample: Equatable, Sendable, Identifiable, Codable {
    var start: Date
    /// 0 to 100.
    var value: Double

    var id: Date { start }
    var zone: MindZone { MindZone(value) }
}

/// One day on the mood strip: how it felt, and the words named for it.
struct MindMoodDay: Equatable, Sendable, Identifiable, Codable {
    var day: Date
    /// Apple's scale, -1 to 1. Nil when nothing was logged.
    var valence: Double?
    /// Feeling titles, in the order first named.
    var words: [String] = []
    /// What had a hand in it, by title.
    var themes: [String] = []
    var isToday = false

    var id: Date { day }
}

/// The colour of a feeling, on the calm ramp the mood faces wear: clay for
/// very unpleasant, sand through the middle, sage for very pleasant.
enum MindMoodPalette {
    static func color(_ valence: Double) -> Color {
        SomaEnergyRamp.calm.value(at: (min(max(valence, -1), 1) + 1) / 2).color
    }
}

/// The five faces of the quick mood log against Mind's seven stops: the same
/// steps the evening question writes to the Journal.
nonisolated enum MindQuickMood {
    /// The stop a face logs: rough 0, low 2, okay 3, good 4, great 6.
    static func stop(_ mood: SomaMood) -> Int {
        CheckInEngine.feelingStop(fromStep: mood.rawValue + 1)
    }

    /// The face a logged valence reads as, the nearest of the five.
    static func mood(valence: Double) -> SomaMood {
        let stop = MindMoodEntry.stop(valence: valence)
        return SomaMood.allCases.min { abs(Self.stop($0) - stop) < abs(Self.stop($1) - stop) } ?? .okay
    }

    /// Today's latest mood, for the line under the faces.
    static func latestToday(_ entries: [MindMoodEntry], now: Date, calendar: Calendar) -> MindMoodEntry? {
        entries.filter { calendar.isDate($0.date, inSameDayAs: now) }.max { $0.date < $1.date }
    }
}

/// Everything the Mind lens draws, read once: plain values, so the lens
/// renders from a fixture as well as from Health.
struct MindLensModel: Equatable, Sendable, Codable {
    var now: Date
    var dayStart: Date

    var hrv: Double?
    var hrvTrend: SomaTrend?
    var resting: Double?
    var restingTrend: SomaTrend?
    var mindfulToday: Double?

    /// Today's stress, half hour by half hour, sleep and workouts left out.
    var stress: [MindStressSample] = []
    /// Last night, read on the same scale, so the line reads night then
    /// day. Nil without a night that ended today (and in a snapshot kept
    /// before the night was read).
    var night: MindStressNight?
    /// The last fourteen days, oldest first, today last.
    var moods: [MindMoodDay] = []
    /// The last seven days of mindful minutes, today last.
    var week: [MindBar] = []
    /// Sixty days of stress by weekday and two hour block.
    var heatmap = MindHeatmap(minutes: Array(repeating: Array(repeating: 0, count: MindHeatmap.columns), count: 7))

    /// Minutes a day that close the mindful ring.
    static let mindfulGoal: Double = MindInnerSpace.mindfulDayMinutes
    /// Days on the mood strip.
    static let moodDays = 14

    /// Minutes in each zone today. Nil before the first half hour is read.
    var zoneMinutes: [MindZone: Double]? {
        guard !stress.isEmpty else { return nil }
        var minutes: [MindZone: Double] = [:]
        for sample in stress {
            minutes[sample.zone, default: 0] += Double(ScoringIntradayStress.bucketMinutes)
        }
        return minutes
    }

    static func make(
        inner: MindInnerSpace,
        stress: ScorePages.Stress?,
        heatmap: MindHeatmap,
        night: MindStressNight? = nil,
        moods: [MindMoodEntry],
        feelings: [Date: Int],
        now: Date,
        calendar: Calendar
    ) -> MindLensModel {
        let today = calendar.startOfDay(for: now)
        return MindLensModel(
            now: now,
            dayStart: today,
            hrv: inner.variability,
            hrvTrend: inner.variabilityTrend,
            resting: inner.resting,
            restingTrend: inner.restingTrend,
            mindfulToday: inner.mindfulToday,
            stress: (stress?.line ?? [])
                .filter { $0.start >= today }
                .map { MindStressSample(start: $0.start, value: min(100, max(0, $0.value))) },
            night: night,
            moods: moodDays(moods, feelings: feelings, today: today, calendar: calendar),
            week: inner.week,
            heatmap: heatmap
        )
    }

    /// Fourteen days of mood: each day's entries averaged, and the Journal's
    /// evening feeling on a day with no entry.
    static func moodDays(_ entries: [MindMoodEntry], feelings: [Date: Int], today: Date, calendar: Calendar) -> [MindMoodDay] {
        let byDay = Dictionary(grouping: entries) { calendar.startOfDay(for: $0.date) }
        return (0..<moodDays).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let logged = (byDay[day] ?? []).sorted { $0.date < $1.date }
            var words: [String] = []
            var themes: [String] = []
            for entry in logged {
                for id in entry.labels {
                    let title = MindFeeling.named(id)?.title ?? id.capitalized
                    if !words.contains(title) { words.append(title) }
                }
                for id in entry.associations {
                    let title = MindAssociation.named(id)?.title ?? id.capitalized
                    if !themes.contains(title) { themes.append(title) }
                }
            }
            let valence: Double? = logged.isEmpty
                ? feelings[day].map { MindMoodEntry.valence(stop: $0) }
                : logged.map(\.valence).reduce(0, +) / Double(logged.count)
            return MindMoodDay(day: day, valence: valence, words: words, themes: themes, isToday: offset == 0)
        }
    }
}

enum MindLensFormat {
    /// Minutes the way the app writes every duration: "5h 36m", "45m".
    static func duration(_ minutes: Double, locale: Locale = .autoupdatingCurrent) -> String {
        SomaFormat.duration(minutes * 60, locale: locale)
    }

    static func whole(_ value: Double) -> String {
        Int(value.rounded()).formatted()
    }
}
