//
//  MindMeetingStress.swift
//  Prism
//
//  Which meetings line up with a rise in stress, and by how much. The rules:
//
//  The measure is with minus without, at the same clock slot. "With" is the
//  mean stress in the series' slot on the days it happened; "without" is the
//  mean in the same slot on control days that carry no meeting there and are
//  the same kind of day (weekday or weekend). Comparing against the day's own
//  level instead would crown every nine o'clock meeting.
//
//  A series under a floor is found, not zero, and nothing here or on the page
//  that renders it may say a meeting causes stress: it is a correlation.
//

import Foundation

nonisolated enum MindMeetingStress {
    /// Under three days it is a meeting, not a series.
    static let minimumOccurrences = 3
    /// Under five control days the "without" term is noise.
    static let minimumControlDays = 5
    /// A delta claims a direction only this many standard errors from zero.
    static let directionalZ = 2.0
    /// Usable buckets a slot mean needs, capped by the slot's own width.
    static let minimumBucketsPerTerm = 2
    /// Longer than this, an event is a block of time rather than a meeting.
    static let longestMeeting: TimeInterval = 4 * 60 * 60

    // MARK: - Today

    /// One meeting today and the stress it held.
    struct Meeting: Equatable, Sendable, Identifiable {
        var event: MindCalendarEvent
        /// The highest usable bucket in its window, nil when none was read.
        var peak: Double?
        var id: String { event.id }
    }

    struct Today: Equatable, Sendable {
        var meetings: [Meeting]
        /// Minutes in meetings, overlaps counted once.
        var minutes: Double
        var peak: Meeting? { meetings.filter { $0.peak != nil }.max { ($0.peak ?? 0) < ($1.peak ?? 0) } }
        /// Meetings that peaked above the usual range.
        func raised(over usual: ClosedRange<Double>?) -> [Meeting] {
            guard let usual else { return [] }
            return meetings.filter { ($0.peak ?? 0) > usual.upperBound }
        }
    }

    /// The events that read as meetings: timed, under four hours, and not
    /// something the classifier knows to be restorative, social or travel.
    static func meetings(in events: [MindCalendarEvent]) -> [MindCalendarEvent] {
        events.filter { event in
            let length = event.end.timeIntervalSince(event.start)
            guard length > 0, length <= longestMeeting else { return false }
            switch MindEventClassifier.category(title: event.title, calendarTitle: event.calendarTitle) {
            case .meeting, .focus, .admin, .unknown: return true
            case .restorative, .social, .travel, .care, .food: return false
            }
        }
        .sorted { $0.start < $1.start }
    }

    static func today(_ curve: MindStressDayCurve?, events: [MindCalendarEvent]) -> Today {
        let found = meetings(in: events)
        let rows = found.map { event -> Meeting in
            guard let curve else { return Meeting(event: event, peak: nil) }
            let values = curve.buckets(from: event.start, to: event.end).compactMap(curve.value)
            return Meeting(event: event, peak: values.max())
        }
        return Today(meetings: rows, minutes: coveredMinutes(found))
    }

    /// Minutes the events cover, an overlap counted once.
    static func coveredMinutes(_ events: [MindCalendarEvent]) -> Double {
        var total: TimeInterval = 0
        var reach: Date?
        for event in events.sorted(by: { $0.start < $1.start }) {
            let start = max(event.start, reach ?? event.start)
            if event.end > start { total += event.end.timeIntervalSince(start) }
            reach = max(reach ?? event.end, event.end)
        }
        return total / 60
    }

    // MARK: - Mornings and afternoons

    struct Halves: Equatable, Sendable {
        /// Meetings in the window with a reading.
        var meetings: Int
        /// The average peak of meetings starting before 12:00.
        var morning: Double?
        /// The average peak of meetings starting at 14:00 or later.
        var afternoon: Double?
    }

    static func halves(days: [MindStressDayCurve], events: [MindCalendarEvent], calendar: Calendar) -> Halves {
        var morning: [Double] = []
        var afternoon: [Double] = []
        let byDay = Dictionary(grouping: meetings(in: events)) { calendar.startOfDay(for: $0.start) }
        for curve in days {
            for event in byDay[curve.day] ?? [] {
                guard let peak = curve.buckets(from: event.start, to: event.end).compactMap(curve.value).max() else { continue }
                let hour = calendar.component(.hour, from: event.start)
                if hour < 12 { morning.append(peak) } else if hour >= 14 { afternoon.append(peak) }
            }
        }
        return Halves(meetings: morning.count + afternoon.count, morning: MindUsual.mean(morning), afternoon: MindUsual.mean(afternoon))
    }

    // MARK: - Recurring series

    struct Series: Equatable, Sendable, Identifiable {
        var key: String
        var title: String
        var slot: Range<Int>
        var found: Int
        var scored: Int
        var controlDays: Int
        var meanWith: Double
        var meanWithout: Double
        var standardError: Double

        var id: String { key }
        var delta: Double { meanWith - meanWithout }
        var isDirectional: Bool { abs(delta) >= MindMeetingStress.directionalZ * standardError }
    }

    /// The key a series is grouped under: the title, folded.
    static func key(_ event: MindCalendarEvent) -> String {
        MindEventClassifier.normalize(event.title).trimmingCharacters(in: .whitespaces)
    }

    static func series(
        days: [MindStressDayCurve],
        events: [MindCalendarEvent],
        calendar: Calendar
    ) -> [Series] {
        let readable = days.filter { $0.usableCount >= MindStressRadar.minimumCovered }
        let curveByDay = Dictionary(readable.map { ($0.day, $0) }, uniquingKeysWith: { first, _ in first })
        let found = meetings(in: events)

        struct Occurrence { var day: Date; var event: MindCalendarEvent; var slot: Range<Int> }
        let occurrences = found.map { event -> Occurrence in
            let day = calendar.startOfDay(for: event.start)
            let axis = MindStressDayCurve(day: day, samples: [])
            return Occurrence(day: day, event: event, slot: axis.buckets(from: event.start, to: event.end))
        }
        var busy: [Date: [Range<Int>]] = [:]
        for occurrence in occurrences { busy[occurrence.day, default: []].append(occurrence.slot) }
        let groups = Dictionary(grouping: occurrences) { key($0.event) }

        func isWeekend(_ day: Date) -> Bool { calendar.isDateInWeekend(day) }
        func mean(_ curve: MindStressDayCurve, _ slot: Range<Int>) -> Double? {
            let values = slot.compactMap(curve.value)
            guard !slot.isEmpty, values.count >= min(minimumBucketsPerTerm, slot.count) else { return nil }
            return values.reduce(0, +) / Double(values.count)
        }

        var scored: [Series] = []
        for (key, group) in groups where !key.isEmpty {
            // The most frequent slot, the earliest on a tie.
            let counts = Dictionary(grouping: group, by: \.slot).mapValues(\.count)
            guard let slot = counts.max(by: { lhs, rhs in
                lhs.value != rhs.value ? lhs.value < rhs.value : lhs.key.lowerBound > rhs.key.lowerBound
            })?.key,
                let latest = group.max(by: { $0.day < $1.day }) else { continue }
            let seriesDays = Set(group.map(\.day))
            let weekendSeries = seriesDays.filter(isWeekend).count * 2 > seriesDays.count

            var with: [Double] = []
            var seen = Set<Date>()
            for occurrence in group where occurrence.slot.overlaps(slot) && isWeekend(occurrence.day) == weekendSeries {
                guard seen.insert(occurrence.day).inserted,
                      let curve = curveByDay[occurrence.day], let value = mean(curve, slot) else { continue }
                with.append(value)
            }
            var without: [Double] = []
            for curve in readable where !seriesDays.contains(curve.day) && isWeekend(curve.day) == weekendSeries {
                guard !(busy[curve.day] ?? []).contains(where: { $0.overlaps(slot) }),
                      let value = mean(curve, slot) else { continue }
                without.append(value)
            }
            guard with.count >= minimumOccurrences, without.count >= minimumControlDays else { continue }
            scored.append(Series(
                key: key, title: latest.event.title, slot: slot,
                found: seriesDays.count, scored: with.count, controlDays: without.count,
                meanWith: average(with), meanWithout: average(without),
                standardError: (variance(with) / Double(with.count) + variance(without) / Double(without.count)).squareRoot()
            ))
        }
        return scored.sorted { $0.delta != $1.delta ? $0.delta > $1.delta : $0.key < $1.key }
    }

    private static func average(_ values: [Double]) -> Double {
        values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }

    private static func variance(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let mean = average(values)
        return values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count - 1)
    }
}
