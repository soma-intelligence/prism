//
//  FixtureCalendar.swift
//  Prism
//

#if DEBUG && targetEnvironment(simulator)
import Foundation

/// A made up working week, for looking at Mind's calendar lines on a
/// simulator: Debug only, chosen with `-calendar.fixture YES`, read in place
/// of EventKit and never written to any calendar.
///
/// Monday, Wednesday and Friday are light (a standup and one sync, coffee with
/// a friend on Wednesday, a run club on Friday); Tuesday and Thursday carry an
/// afternoon of back to back meetings. With `-health.fixture YES` the heart
/// runs higher through those afternoons, so the lines have something to find.
nonisolated enum FixtureCalendar {
    /// The defaults key behind `-calendar.fixture YES`.
    static let launchKey = "calendar.fixture"

    static var isOn: Bool { UserDefaults.standard.bool(forKey: launchKey) }

    /// One event of the week: its hours from midnight and its title.
    private struct Slot {
        var from: Double
        var to: Double
        var title: String
        var calendar = "Work"
    }

    private static func slots(weekday: Int) -> [Slot] {
        switch weekday {
        case 3, 5:
            return [
                Slot(from: 9.5, to: 9.75, title: "Standup"),
                Slot(from: 13, to: 14, title: "Design review"),
                Slot(from: 14, to: 14.5, title: "1:1"),
                Slot(from: 14.5, to: 15.5, title: "Planning meeting"),
                Slot(from: 16, to: 16.75, title: "Budget call"),
            ]
        case 2, 4, 6:
            var light = [
                Slot(from: 9.5, to: 9.75, title: "Standup"),
                Slot(from: 11, to: 11.5, title: "Team sync"),
            ]
            if weekday == 4 { light.append(Slot(from: 12.5, to: 13.5, title: "Coffee with Sam", calendar: "Home")) }
            if weekday == 6 { light.append(Slot(from: 17.5, to: 18.5, title: "Run club", calendar: "Home")) }
            return light
        default:
            return []
        }
    }

    /// The events between two moments.
    static func events(from start: Date, to end: Date, calendar: Calendar = .current) -> [MindCalendarEvent] {
        var out: [MindCalendarEvent] = []
        var day = calendar.startOfDay(for: start)
        while day < end {
            for slot in slots(weekday: calendar.component(.weekday, from: day)) {
                let from = day.addingTimeInterval(slot.from * 3_600)
                let to = day.addingTimeInterval(slot.to * 3_600)
                guard to > start, from < end else { continue }
                out.append(MindCalendarEvent(id: "fixture-\(from.timeIntervalSince1970)", title: slot.title,
                                             calendarTitle: slot.calendar, start: from, end: to))
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return out.sorted { $0.start < $1.start }
    }

    /// Heart readings through `day` days ago's busy afternoon meetings:
    /// every quarter hour, well above the day's usual.
    static func heartRate(day: Int, calendar: Calendar = .current) -> [(hour: Double, value: Double)] {
        guard let date = calendar.date(byAdding: .day, value: -day, to: calendar.startOfDay(for: .now)) else { return [] }
        let weekday = calendar.component(.weekday, from: date)
        guard weekday == 3 || weekday == 5 else { return [] }
        return slots(weekday: weekday).filter { $0.from >= 12 }.flatMap { slot in
            stride(from: slot.from, to: slot.to, by: 0.25).map { hour in
                (hour, 96 + sin(hour * 3 + Double(day)) * 4)
            }
        }
    }
}
#endif
