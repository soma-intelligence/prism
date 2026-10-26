//
//  FixtureRhythm.swift
//  Prism
//

#if DEBUG && targetEnvironment(simulator)
import Foundation
import HealthExportCore

/// Half a year of made up AFib History, a few heart notifications, a year of
/// walking steadiness sliding into the low band, one steadiness notification
/// and two falls (one last week, so the help line shows), for looking at the
/// heart rhythm and mobility pages on a simulator. Debug only, with the same
/// launch argument as the Health fixture, `-health.fixture YES`, and never
/// written anywhere.
nonisolated enum FixtureRhythm {
    static func addReadings(to out: inout [String: [HealthReading]], now: Date, calendar: Calendar) {
        let today = calendar.startOfDay(for: now)

        func add(_ identifier: String, daysAgo: Int, hour: Double = 9, value: Double, source: String = "Apple Watch") {
            guard let metric = HealthMetricCatalog.metric(for: identifier),
                  let day = calendar.date(byAdding: .day, value: -daysAgo, to: today) else { return }
            let start = day.addingTimeInterval(hour * 3600)
            guard start <= now else { return }
            out[identifier, default: []].append(HealthReading(
                metric: identifier, value: value, unit: metric.unit, start: start, end: start,
                source: source, device: source, deviceModel: source == "Apple Watch" ? "Watch Apple Inc." : "iPhone Apple Inc."
            ))
        }

        // AFib History: one sample a week, between 2 % and 7 %.
        for week in 0..<26 {
            let burden = 0.035 + sin(Double(week) / 3) * 0.02 + Double(week % 3) * 0.005
            add(RhythmMobilityReadings.burdenID, daysAgo: week * 7 + 1, hour: 6, value: max(0.01, burden))
        }
        add(RhythmMobilityReadings.irregularID, daysAgo: 38, hour: 3.4, value: 0)
        add(RhythmMobilityReadings.highID, daysAgo: 9, hour: 14.2, value: 0)
        add(RhythmMobilityReadings.lowID, daysAgo: 72, hour: 4.1, value: 0)

        // Steadiness from iPhone, weekly, from 58 % a year ago to 34 % now.
        for week in 0..<52 {
            let value = 0.34 + Double(week) * 0.0046 + sin(Double(week) / 2) * 0.012
            add(RhythmMobilityReadings.steadinessID, daysAgo: week * 7 + 2, hour: 12, value: value, source: "iPhone")
        }
        add(RhythmMobilityReadings.steadinessEventID, daysAgo: 23, hour: 12, value: 1, source: "iPhone")
        add(RhythmMobilityReadings.fallsID, daysAgo: 6, hour: 18.6, value: 1)
        add(RhythmMobilityReadings.fallsID, daysAgo: 150, hour: 8.3, value: 1)

        for day in 0..<60 {
            add(RhythmMobilityReadings.doubleSupportID, daysAgo: day, hour: 11, value: 0.31 + Double(day % 5) * 0.004, source: "iPhone")
            add(RhythmMobilityReadings.asymmetryID, daysAgo: day, hour: 11, value: 0.04 + Double(day % 4) * 0.005, source: "iPhone")
        }
    }
}
#endif
