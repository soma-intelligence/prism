//
//  MindJournal.swift
//  Prism
//

import Foundation
import HealthExportCore

/// What the Mind tab reads from the Journal: the tags tapped on each day, and
/// their titles. A plain copy, so the parts' arithmetic runs off the main
/// actor and a test writes one by hand.
struct MindJournal: Equatable, Sendable {
    /// Keyed by the start of the day.
    var tagsByDay: [Date: Set<String>] = [:]
    /// Tag titles by id.
    var titles: [String: String] = [:]

    func days(tagged id: String) -> Set<Date> {
        Set(tagsByDay.filter { $0.value.contains(id) }.keys)
    }

    func has(_ id: String, on day: Date) -> Bool {
        tagsByDay[day]?.contains(id) == true
    }
}

extension MindJournal {
    @MainActor
    init(_ store: JournalStore) {
        var tagsByDay: [Date: Set<String>] = [:]
        for entry in store.loggedDays where !entry.day.tags.isEmpty {
            tagsByDay[entry.date] = entry.day.tags
        }
        self.init(
            tagsByDay: tagsByDay,
            titles: Dictionary(store.tags.map { ($0.id, $0.title) }, uniquingKeysWith: { first, _ in first })
        )
    }
}

/// Daily values the parts share: evening heart rate variability, deep sleep,
/// mindful minutes, nights.
enum MindDaily {
    /// Heart rate variability from 17:00 to 08:00 the next morning, averaged,
    /// keyed by the evening's day: how the evening and the night settled.
    static func eveningVariability(_ readings: [HealthReading], calendar: Calendar) -> [Date: Double] {
        var sums: [Date: (Double, Int)] = [:]
        for reading in readings {
            let hour = calendar.component(.hour, from: reading.start)
            let start = calendar.startOfDay(for: reading.start)
            let day: Date?
            if hour >= 17 {
                day = start
            } else if hour < 8 {
                day = calendar.date(byAdding: .day, value: -1, to: start)
            } else {
                day = nil
            }
            guard let day else { continue }
            let current = sums[day] ?? (0, 0)
            sums[day] = (current.0 + reading.value, current.1 + 1)
        }
        return sums.mapValues { $0.0 / Double($0.1) }
    }

    /// Minutes of each session, summed by the day it started.
    static func minutesByDay(_ sessions: [HealthReading], calendar: Calendar) -> [Date: Double] {
        var result: [Date: Double] = [:]
        for session in sessions {
            result[calendar.startOfDay(for: session.start), default: 0] += session.end.timeIntervalSince(session.start) / 60
        }
        return result
    }
}
