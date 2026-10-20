//
//  MindCalendarInsights.swift
//  Prism
//
//  What the calendar says about stress: a few plain lines, such as
//  "Afternoons with three or more meetings line up with higher stress".
//
//  Everything here runs on the phone, over values already in memory, and
//  keeps nothing: the events come from EventKit as the page reads them and
//  are reduced at once to counts, minutes and times of day. No title is
//  kept, compared or shown: an event's title is only read by the classifier
//  to sort it into a kind (work, people, movement), and the lines name
//  kinds, weekdays and parts of the day, never an event.
//
//  The scoring is deliberately simple and deterministic. Each line compares
//  two groups of past weekdays (weekends are left out, so a busy Tuesday is
//  never set against a lazy Sunday) and speaks only when both groups hold at
//  least ``minimumDays`` days and the gap clears a floor: ``stressFloor``
//  points of stress, or ``hrvFloorShare`` of HRV and ``hrvFloorMilliseconds``.
//  The lines are ranked by the size of the gap against its floor, and at
//  most ``limit`` are shown. A correlation, never a cause: no line says a
//  meeting causes stress.
//

import Foundation
import HealthExportCore

nonisolated enum MindCalendarInsights {
    /// Days each side of a comparison needs.
    static let minimumDays = 3
    /// Points of stress a gap needs before it is a line.
    static let stressFloor: Double = 8
    /// The share of HRV a gap needs, and the milliseconds.
    static let hrvFloorShare = 0.05
    static let hrvFloorMilliseconds: Double = 3
    /// Lines shown at most.
    static let limit = 3
    /// A meeting starting this soon after the last one ended is back to back.
    static let backToBackGap: TimeInterval = 10 * 60
    /// Meetings that make a busy afternoon, and a busy day.
    static let busyAfternoon = 3
    static let busyDay = 4
    /// The hours read as the day, and as the afternoon.
    static let dayHours = 8..<20
    static let afternoonHours = 12..<18

    /// One past day, reduced to numbers.
    struct Day: Equatable, Sendable {
        var day: Date
        var isWeekend: Bool
        var meetings: Int
        var afternoonMeetings: Int
        /// Minutes in meetings, an overlap counted once.
        var busyMinutes: Double
        /// Meetings that start within ``backToBackGap`` of the one before.
        var backToBack: Int
        /// Whether the day held time with people or movement.
        var hasBreak: Bool
        /// The mean of the day's readable half hours, 08:00 to 20:00.
        var stress: Double?
        /// The mean of its readable afternoon half hours, 12:00 to 18:00.
        var afternoonStress: Double?
        /// HRV the next morning.
        var nextHRV: Double?
    }

    struct Insight: Equatable, Sendable, Identifiable {
        enum Kind: String, Sendable {
            case busyAfternoons, busyDays, backToBack, nextMorningHRV, weekday, breaks
        }

        var kind: Kind
        /// The line itself.
        var text: String
        /// What it rests on, in a few words.
        var detail: String
        /// Whether it reads as a cost (stress up, HRV down).
        var isCost: Bool
        /// The gap over its floor: what ranks the lines.
        var strength: Double

        var id: String { kind.rawValue }
    }

    // MARK: - Days

    /// Each past day with a stress curve, against the calendar and the next
    /// morning's HRV. Today is left out: it is not over.
    static func days(
        curves: [MindStressDayCurve],
        events: [MindCalendarEvent],
        hrvByDay: [Date: Double],
        now: Date,
        calendar: Calendar
    ) -> [Day] {
        let today = calendar.startOfDay(for: now)
        let meetings = Dictionary(grouping: MindMeetingStress.meetings(in: events)) { calendar.startOfDay(for: $0.start) }
        let breaks = Set(events.filter { event in
            switch MindEventClassifier.category(title: event.title, calendarTitle: event.calendarTitle) {
            case .social, .restorative: true
            default: false
            }
        }.map { calendar.startOfDay(for: $0.start) })

        return curves.filter { $0.day < today }.map { curve in
            let found = (meetings[curve.day] ?? []).sorted { $0.start < $1.start }
            var backToBack = 0
            for index in found.indices.dropFirst() {
                let gap = found[index].start.timeIntervalSince(found[index - 1].end)
                if gap >= -backToBackGap, gap <= backToBackGap { backToBack += 1 }
            }
            let next = calendar.date(byAdding: .day, value: 1, to: curve.day).flatMap { hrvByDay[$0] }
            return Day(
                day: curve.day,
                isWeekend: calendar.isDateInWeekend(curve.day),
                meetings: found.count,
                afternoonMeetings: found.filter { afternoonHours.contains(calendar.component(.hour, from: $0.start)) }.count,
                busyMinutes: MindMeetingStress.coveredMinutes(found),
                backToBack: backToBack,
                hasBreak: breaks.contains(curve.day),
                stress: mean(curve, hours: dayHours),
                afternoonStress: mean(curve, hours: afternoonHours),
                nextHRV: next
            )
        }
    }

    /// The mean of a curve's readable half hours inside `hours`, when at
    /// least ``MindStressRadar/minimumCovered`` of them were read.
    static func mean(_ curve: MindStressDayCurve, hours: Range<Int>) -> Double? {
        let perHour = 60 / MindStressDayCurve.bucketMinutes
        let values = (hours.lowerBound * perHour..<hours.upperBound * perHour).compactMap(curve.value)
        guard values.count >= MindStressRadar.minimumCovered else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    // MARK: - Lines

    /// The lines worth saying, strongest first, at most ``limit``.
    static func insights(_ days: [Day], calendar: Calendar) -> [Insight] {
        let weekdays = days.filter { !$0.isWeekend }
        var found: [Insight] = []

        // Busy afternoons against quiet ones.
        if let gap = gap(weekdays, \.afternoonStress,
                         when: { $0.afternoonMeetings >= busyAfternoon }, against: { $0.afternoonMeetings <= 1 }) {
            found.append(stressLine(.busyAfternoons, gap,
                                    up: String(localized: "Afternoons with three or more meetings line up with higher stress."),
                                    down: String(localized: "Your stress holds lower on afternoons with three or more meetings.")))
        }

        // Busy days against light ones.
        if let gap = gap(weekdays, \.stress,
                         when: { $0.meetings >= busyDay }, against: { $0.meetings <= 1 }) {
            found.append(stressLine(.busyDays, gap,
                                    up: String(localized: "Days with four or more meetings run more stressed."),
                                    down: String(localized: "Days with four or more meetings run calmer than light ones.")))
        }

        // Back to back against spaced out, among days with two meetings or more.
        let meetingDays = weekdays.filter { $0.meetings >= 2 }
        if let gap = gap(meetingDays, \.stress, when: { $0.backToBack >= 2 }, against: { $0.backToBack == 0 }) {
            found.append(stressLine(.backToBack, gap,
                                    up: String(localized: "Back to back meetings line up with higher stress than spaced out ones."),
                                    down: String(localized: "Back to back meetings and your stress don't line up so far.")))
        }

        // The next morning's HRV after busy days and after light ones.
        if let gap = gap(weekdays, \.nextHRV, floor: 0, when: { $0.meetings >= busyDay }, against: { $0.meetings <= 1 }),
           gap.against > 0 {
            let share = abs(gap.delta) / gap.against
            if share >= hrvFloorShare, abs(gap.delta) >= hrvFloorMilliseconds {
                let ms = Int(abs(gap.delta).rounded())
                found.append(Insight(
                    kind: .nextMorningHRV,
                    text: gap.delta < 0
                        ? String(localized: "After days with four or more meetings, your HRV the next morning runs \(ms) ms lower.")
                        : String(localized: "After days with four or more meetings, your HRV the next morning holds up."),
                    detail: gap.delta < 0
                        ? String(localized: "\(ms) ms lower, \(gap.when) days against \(gap.others)")
                        : String(localized: "\(ms) ms higher, \(gap.when) days against \(gap.others)"),
                    isCost: gap.delta < 0,
                    strength: share / hrvFloorShare
                ))
            }
        }

        // The weekday whose meeting afternoons run highest.
        if let weekday = weekdayLine(weekdays, calendar: calendar) { found.append(weekday) }

        // Time with people or movement on the calendar.
        if let gap = gap(weekdays, \.stress, when: \.hasBreak, against: { !$0.hasBreak }), gap.delta < 0 {
            found.append(stressLine(.breaks, gap,
                                    up: "",
                                    down: String(localized: "Days with time for people or movement on the calendar run calmer.")))
        }

        return Array(found.sorted { $0.strength != $1.strength ? $0.strength > $1.strength : $0.kind.rawValue < $1.kind.rawValue }
            .prefix(limit))
    }

    /// Two groups of days and the gap between their means of `value`.
    struct Gap: Equatable, Sendable {
        var with: Double
        var against: Double
        var when: Int
        var others: Int
        var delta: Double { with - against }
    }

    /// Nil when either side has fewer than ``minimumDays`` days with a value,
    /// or when the gap is under `floor` (``stressFloor`` unless said).
    static func gap(_ days: [Day], _ value: KeyPath<Day, Double?>, floor: Double = stressFloor,
                    when: (Day) -> Bool, against: (Day) -> Bool) -> Gap? {
        let with = days.filter(when).compactMap { $0[keyPath: value] }
        let without = days.filter { !when($0) && against($0) }.compactMap { $0[keyPath: value] }
        guard with.count >= minimumDays, without.count >= minimumDays else { return nil }
        let gap = Gap(with: average(with), against: average(without), when: with.count, others: without.count)
        if abs(gap.delta) < floor { return nil }
        return gap
    }

    private static func stressLine(_ kind: Insight.Kind, _ gap: Gap, up: String, down: String) -> Insight {
        let points = Int(abs(gap.delta).rounded())
        return Insight(
            kind: kind,
            text: gap.delta > 0 ? up : down,
            detail: gap.delta > 0
                ? String(localized: "\(points) points higher, \(gap.when) days against \(gap.others)")
                : String(localized: "\(points) points lower, \(gap.when) days against \(gap.others)"),
            isCost: gap.delta > 0,
            strength: abs(gap.delta) / stressFloor
        )
    }

    /// The weekday whose afternoons with meetings run highest, when it runs
    /// at least ``stressFloor`` above the other weekdays' meeting afternoons.
    static func weekdayLine(_ days: [Day], calendar: Calendar) -> Insight? {
        let meetingDays = days.filter { $0.afternoonMeetings > 0 && $0.afternoonStress != nil }
        let byWeekday = Dictionary(grouping: meetingDays) { calendar.component(.weekday, from: $0.day) }
        let means = byWeekday.compactMapValues { group -> Double? in
            group.count >= minimumDays ? average(group.compactMap(\.afternoonStress)) : nil
        }
        guard let top = means.max(by: { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }) else { return nil }
        let others = meetingDays.filter { calendar.component(.weekday, from: $0.day) != top.key }.compactMap(\.afternoonStress)
        guard others.count >= minimumDays else { return nil }
        let delta = top.value - average(others)
        guard delta >= stressFloor else { return nil }
        // The weekday's full name, read off one of its days in the
        // person's own language.
        let style = Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone).weekday(.wide)
        let name = byWeekday[top.key]?.first.map { $0.day.formatted(style) } ?? calendar.weekdaySymbols[(top.key - 1) % 7]
        return Insight(
            kind: .weekday,
            text: String(localized: "\(name) afternoons with meetings line up with your highest stress."),
            detail: String(localized: "\(Int(delta.rounded())) points above other weekdays, \(byWeekday[top.key]?.count ?? 0) of them"),
            isCost: true,
            strength: delta / stressFloor
        )
    }

    private static func average(_ values: [Double]) -> Double {
        values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }

    /// The whole reduction: days, then lines.
    static func lines(curves: [MindStressDayCurve], events: [MindCalendarEvent], hrv: [HealthReading],
                      now: Date, calendar: Calendar) -> [Insight] {
        // The morning's readings only: the night and the small hours before
        // noon, the HRV a busy day would leave behind.
        let mornings = hrv.filter { calendar.component(.hour, from: $0.start) < 12 }
        let byDay = hrvByDay(mornings.map { (start: $0.start, value: $0.value) }, calendar: calendar)
        return insights(days(curves: curves, events: events, hrvByDay: byDay, now: now, calendar: calendar), calendar: calendar)
    }

    /// The day's mean HRV, by the start of the day it was read on.
    static func hrvByDay(_ readings: [(start: Date, value: Double)], calendar: Calendar) -> [Date: Double] {
        Dictionary(grouping: readings) { calendar.startOfDay(for: $0.start) }
            .mapValues { group in group.map(\.value).reduce(0, +) / Double(group.count) }
    }
}
