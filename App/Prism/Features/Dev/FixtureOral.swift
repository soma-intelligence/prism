//
//  FixtureOral.swift
//  Prism
//

#if DEBUG && targetEnvironment(simulator)
import Foundation
import HealthExportCore

/// Thirty days of made up brushings, a few Journal answers and a last
/// checkup seven months ago, for looking at the mouth and teeth page on a
/// simulator. Debug only, chosen with the launch argument `-health.oral YES`,
/// and never written anywhere: neither Health, the Journal nor the screening
/// ledger sees it.
///
/// Every morning at 07:30, most evenings at 22:15 (every fourth one missed),
/// each a little under or over two minutes, so the average lands short.
enum FixtureOral {
    /// The defaults key behind `-health.oral YES`.
    nonisolated static let launchKey = "health.oral"

    nonisolated static var isOn: Bool { UserDefaults.standard.bool(forKey: launchKey) }

    static func brushings(now: Date = .now, calendar: Calendar = .current) -> [HealthReading] {
        let today = calendar.startOfDay(for: now)
        return (0..<OralSummary.windowDays).flatMap { back -> [HealthReading] in
            guard let day = calendar.date(byAdding: .day, value: -back, to: today) else { return [] }
            var times: [(minutes: Double, seconds: Double)] = [(7.5 * 60, 95 + Double((back * 37) % 40))]
            if back % 4 != 1 { times.append((22.25 * 60, 80 + Double((back * 53) % 50))) }
            return times.compactMap { item in
                let start = day.addingTimeInterval(item.minutes * 60)
                guard start <= now else { return nil }
                return HealthReading(metric: OralSummary.brushingID, value: 0, unit: .none, start: start,
                                     end: start.addingTimeInterval(item.seconds), source: "Oral-B",
                                     device: "Oral-B iO", deviceModel: "iO Oral-B")
            }
        }
    }

    static func journalDays(now: Date = .now, calendar: Calendar = .current) -> [(date: Date, day: JournalDay)] {
        let today = calendar.startOfDay(for: now)
        return (0..<OralSummary.windowDays).compactMap { back in
            guard let day = calendar.date(byAdding: .day, value: -back, to: today) else { return nil }
            var yes: Set<String> = []
            var no: Set<String> = []
            if back % 3 == 0 { yes.insert(OralTag.floss) } else { no.insert(OralTag.floss) }
            if back % 2 == 0 { yes.insert(OralTag.mouthwash) }
            if back % 7 == 0 { if back == 14 { yes.insert(OralTag.gumsBleed) } else { no.insert(OralTag.gumsBleed) } }
            return (day, JournalDay(tags: yes, declined: no))
        }
    }

    static func lastVisit(now: Date = .now, calendar: Calendar = .current) -> Date? {
        calendar.date(byAdding: .month, value: -7, to: now)
    }
}
#endif
