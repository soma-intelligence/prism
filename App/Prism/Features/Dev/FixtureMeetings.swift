//
//  FixtureMeetings.swift
//  Prism
//

#if DEBUG && targetEnvironment(simulator)
import Foundation
import HealthExportCore

/// Four weeks of made up meetings behind and one ahead, for looking at the
/// meetings page on a simulator with no calendar. Debug only, chosen with
/// the same launch argument as the Health fixture, `-health.fixture YES`,
/// and never written anywhere.
///
/// The titles are the kind a calendar really holds: booking tools' "30
/// Minutes Meeting with" titles, invitations that list people by address,
/// and a walking call. `FixtureHealthSource` reads ``addReadings(to:now:calendar:)``
/// so each meeting gone by carries the heart and steps its verdict needs:
/// most run calm, afternoons run tenser than mornings without any one person
/// or series standing out, a walking call reads as moving, and one evening
/// meeting has no readings at all.
nonisolated enum FixtureMeetings {
    enum Mood { case calm, tense, moving, unread }

    struct Meeting {
        var event: MindCalendarEvent
        var mood: Mood
    }

    private struct Template {
        var weekday: Int
        var hour: Int
        var minute: Int
        var length: Int
        var title: String
        var people: [String]
        var series: String?
    }

    private static let team = ["jeanpaul@augura.health", "nicolas@augura.health", "camille.roux@augura.health", "ines@augura.health"]

    private static let templates: [Template] = [
        // Monday to Friday, the morning standup.
        Template(weekday: 2, hour: 9, minute: 30, length: 15, title: "Daily standup", people: team, series: "standup"),
        Template(weekday: 3, hour: 9, minute: 30, length: 15, title: "Daily standup", people: team, series: "standup"),
        Template(weekday: 4, hour: 9, minute: 30, length: 15, title: "Daily standup", people: team, series: "standup"),
        Template(weekday: 5, hour: 9, minute: 30, length: 15, title: "Daily standup", people: team, series: "standup"),
        Template(weekday: 6, hour: 9, minute: 30, length: 15, title: "Daily standup", people: team, series: "standup"),
        Template(weekday: 2, hour: 13, minute: 0, length: 60, title: "Augura Brain: status & next steps",
                 people: team + ["marc.dubois@augura.health", "sophie@augura.health"], series: "brain"),
        Template(weekday: 3, hour: 10, minute: 0, length: 30, title: "30 Minutes Meeting with Philippe Boulanger",
                 people: ["philippe.boulanger@gmail.com"]),
        Template(weekday: 3, hour: 16, minute: 0, length: 30, title: "Team update", people: ["sam@example.com"], series: "update"),
        Template(weekday: 4, hour: 15, minute: 0, length: 30, title: "30 min with Alex (Nicolas Martin)",
                 people: ["nicolas.martin@outlook.com"]),
        Template(weekday: 5, hour: 11, minute: 0, length: 45, title: "Design review",
                 people: ["camille.roux@augura.health", "ines@augura.health"], series: "design"),
        Template(weekday: 5, hour: 16, minute: 0, length: 30, title: "Hiring sync", people: ["sophie@augura.health"], series: "hiring"),
        Template(weekday: 6, hour: 14, minute: 0, length: 30, title: "1:1 Camille", people: ["camille.roux@augura.health"], series: "camille"),
    ]

    /// One new person a week, late on Wednesday: a call nobody has history
    /// with, so its forecast leans on the part of the day.
    private static let guests = ["lea.fontaine@studio.fr", "tom.becker@gmail.com", "Hana Sato", "omar@northwind.io", "ana.costa@gmail.com"]

    static func meetings(now: Date, calendar: Calendar) -> [Meeting] {
        let today = calendar.startOfDay(for: now)
        var out: [Meeting] = []
        for offset in -28...7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            let weekday = calendar.component(.weekday, from: day)
            let week = (offset + 28) / 7
            func add(_ hour: Int, _ minute: Int, _ length: Int, _ title: String, _ people: [String], series: String?, mood: Mood) {
                let start = day.addingTimeInterval(Double(hour * 3600 + minute * 60))
                out.append(Meeting(
                    event: MindCalendarEvent(
                        id: "fixture-\(title)-\(offset)", title: title, calendarTitle: "Work",
                        start: start, end: start.addingTimeInterval(Double(length * 60)),
                        attendees: people, seriesID: series.map { "fixture-" + $0 }
                    ),
                    mood: mood
                ))
            }
            for (index, template) in templates.enumerated() where template.weekday == weekday {
                add(template.hour, template.minute, template.length, template.title, template.people,
                    series: template.series, mood: mood(template, index: index, week: week))
            }
            if weekday == 4 {
                let guest = guests[week % guests.count]
                add(17, 0, 30, "Call with \(MeetingDisplay.personName(guest))", [guest], series: nil, mood: .tense)
            }
            if weekday == 5, offset > -7, offset < 0 {
                add(18, 15, 30, "Board prep", ["jeanpaul@augura.health"], series: nil, mood: .unread)
            }
        }
        return out
    }

    /// One tense meeting a month for each afternoon series, a tense morning
    /// call once, and the team update always on foot.
    private static func mood(_ template: Template, index: Int, week: Int) -> Mood {
        if template.series == "update" { return .moving }
        if template.hour >= 14 { return week == index % 4 ? .tense : .calm }
        if template.title.hasPrefix("30 Minutes") { return week == 2 ? .tense : .calm }
        return .calm
    }

    /// Heart readings every four minutes from an hour before each meeting
    /// gone by to its end, and the walking call's steps. Steps on those days
    /// are gathered into a short walk at the end of each hour, so the hours
    /// read as sitting still between them, the way a desk day does.
    static func addReadings(to out: inout [String: [HealthReading]], now: Date, calendar: Calendar) {
        let heartID = "HKQuantityTypeIdentifierHeartRate"
        let stepID = "HKQuantityTypeIdentifierStepCount"
        guard let heartMetric = HealthMetricCatalog.metric(for: heartID),
              let stepMetric = HealthMetricCatalog.metric(for: stepID) else { return }
        let past = meetings(now: now, calendar: calendar).filter { $0.event.start < now }
        let days = Set(past.map { calendar.startOfDay(for: $0.event.start) })

        out[stepID] = (out[stepID] ?? []).map { sample in
            guard days.contains(calendar.startOfDay(for: sample.start)), sample.end > sample.start else { return sample }
            let start = sample.start.addingTimeInterval(45 * 60)
            return HealthReading(
                metric: sample.metric, value: sample.value, unit: sample.unit, start: start, end: start.addingTimeInterval(10 * 60),
                source: sample.source, device: sample.device, deviceModel: sample.deviceModel
            )
        }.filter { $0.start <= now }

        func jitter(_ date: Date, _ spread: Double) -> Double {
            let seed = Int(date.timeIntervalSince1970 / 60)
            return (Double((seed * 7919) % 1000) / 1000 - 0.5) * 2 * spread
        }
        func heart(_ at: Date, _ value: Double) {
            guard at <= now else { return }
            out[heartID, default: []].append(HealthReading(
                metric: heartID, value: value, unit: heartMetric.unit, start: at, end: at,
                source: "Apple Watch", device: "Apple Watch", deviceModel: "Watch Apple Inc."
            ))
        }

        for meeting in past where meeting.mood != .unread {
            let event = meeting.event
            var at = event.start.addingTimeInterval(-60 * 60)
            while at < event.start {
                heart(at, 71 + jitter(at, 2))
                at = at.addingTimeInterval(4 * 60)
            }
            at = event.start.addingTimeInterval(60)
            while at < min(event.end, now) {
                let rise: Double = switch meeting.mood {
                case .calm: 2
                case .tense: 15
                case .moving: 24
                case .unread: 0
                }
                heart(at, 71 + rise + jitter(at, 2.5))
                at = at.addingTimeInterval(4 * 60)
            }
            if meeting.mood == .moving {
                out[stepID, default: []].append(HealthReading(
                    metric: stepID, value: 95 * event.minutes, unit: stepMetric.unit, start: event.start, end: event.end,
                    source: "iPhone"
                ))
            }
        }
    }
}

/// The fixture's meetings as a calendar source, granted from the start.
struct FixtureMeetingSource: MeetingCalendarSource {
    var name: String { "Fixture calendar" }
    var access: MindCalendar.Access { .granted }
    func requestAccess() async -> MindCalendar.Access { .granted }
    func events(from start: Date, to end: Date) -> [MindCalendarEvent] {
        FixtureMeetings.meetings(now: .now, calendar: .current)
            .map(\.event)
            .filter { $0.end > start && $0.start < end }
    }
}
#endif
