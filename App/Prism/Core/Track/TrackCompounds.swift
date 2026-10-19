//
//  TrackCompounds.swift
//  Prism
//
//  The one place adherence is worked out. A due day is one the declared rhythm
//  expects a dose on; it is kept when at least one dose is logged that day.
//  What a person declares (the amount, the rhythm) is an entry, never a
//  number the app computes.
//

import Foundation

/// The rhythm a person said they take something at.
nonisolated struct TrackCadence: Codable, Equatable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable, CaseIterable {
        case daily
        case weekly
        case everyNDays
        case cycleOnOff
    }

    private(set) var kind: Kind
    /// 1...7, Calendar's numbering (1 is Sunday). Weekly only.
    private(set) var weekday: Int?
    /// Every so many days, 1 or more. `everyNDays` only.
    private(set) var intervalDays: Int?
    private(set) var onDays: Int?
    private(set) var offDays: Int?

    static let daily = TrackCadence(kind: .daily)

    static func weekly(weekday: Int) -> TrackCadence? {
        (1...7).contains(weekday) ? TrackCadence(kind: .weekly, weekday: weekday) : nil
    }

    static func everyNDays(_ days: Int) -> TrackCadence? {
        days >= 1 ? TrackCadence(kind: .everyNDays, intervalDays: days) : nil
    }

    static func cycleOnOff(on: Int, off: Int) -> TrackCadence? {
        on >= 1 && off >= 1 ? TrackCadence(kind: .cycleOnOff, onDays: on, offDays: off) : nil
    }

    private init(kind: Kind, weekday: Int? = nil, intervalDays: Int? = nil, onDays: Int? = nil, offDays: Int? = nil) {
        self.kind = kind
        self.weekday = weekday
        self.intervalDays = intervalDays
        self.onDays = onDays
        self.offDays = offDays
    }
}

nonisolated enum TrackAdherence {
    struct Plan: Equatable, Sendable {
        /// The next due day from today on. Nil once the course has ended.
        var nextDueOn: Date?
        /// A dose is due today and not logged yet.
        var isDueToday: Bool
        /// Days since the oldest due day left unkept, today excluded.
        var daysLate: Int
        /// Due days kept in a row, counting back from the latest.
        var streak: Int
        var missedCount: Int
        /// Share of due days kept, 0...100. Nil before any day was due: a
        /// zero would say the person kept none.
        var adherencePercent: Double?
    }

    static func plan(
        cadence: TrackCadence,
        startedOn: Date,
        endedOn: Date? = nil,
        doseDates: [Date],
        now: Date,
        calendar: Calendar
    ) -> Plan {
        let today = calendar.startOfDay(for: now)
        let start = calendar.startOfDay(for: startedOn)
        let end = endedOn.map { calendar.startOfDay(for: $0) }
        let logged = Set(doseDates.map { calendar.startOfDay(for: $0) })

        if let end, end < today {
            return Plan(nextDueOn: nil, isDueToday: false, daysLate: 0, streak: 0, missedCount: 0,
                        adherencePercent: adherence(occurrences(cadence, from: start, through: end, calendar: calendar), logged))
        }

        let horizon = end.map { min($0, today) } ?? today
        let due = start <= horizon ? occurrences(cadence, from: start, through: horizon, calendar: calendar) : []
        let overdue = due.filter { !logged.contains($0) && $0 < today }
        let daysLate = overdue.min().map { calendar.dateComponents([.day], from: $0, to: today).day ?? 0 } ?? 0

        var next: Date?
        let first = max(start, today)
        if let limit = calendar.date(byAdding: .day, value: 366, to: first) {
            let ceiling = end.map { min($0, limit) } ?? limit
            if first <= ceiling {
                next = occurrences(cadence, from: start, through: ceiling, calendar: calendar)
                    .first { $0 >= today && !logged.contains($0) }
            }
        }

        var streak = 0
        for day in due.reversed() {
            if logged.contains(day) { streak += 1 } else { break }
        }

        return Plan(
            nextDueOn: next,
            isDueToday: due.contains(today) && !logged.contains(today),
            daysLate: daysLate,
            streak: streak,
            missedCount: overdue.count,
            adherencePercent: adherence(due, logged)
        )
    }

    /// Whether the rhythm expects a dose on `day`.
    static func isDue(_ cadence: TrackCadence, on day: Date, startedOn: Date, calendar: Calendar) -> Bool {
        let start = calendar.startOfDay(for: startedOn)
        let target = calendar.startOfDay(for: day)
        guard target >= start else { return false }
        let index = calendar.dateComponents([.day], from: start, to: target).day ?? 0
        return isOccurrence(cadence, index: index, day: target, calendar: calendar)
    }

    private static func occurrences(_ cadence: TrackCadence, from start: Date, through end: Date, calendar: Calendar) -> [Date] {
        guard start <= end else { return [] }
        var result: [Date] = []
        var day = start
        var index = 0
        while day <= end {
            if isOccurrence(cadence, index: index, day: day, calendar: calendar) { result.append(day) }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
            index += 1
        }
        return result
    }

    private static func isOccurrence(_ cadence: TrackCadence, index: Int, day: Date, calendar: Calendar) -> Bool {
        switch cadence.kind {
        case .daily:
            return true
        case .weekly:
            return cadence.weekday.map { calendar.component(.weekday, from: day) == $0 } ?? false
        case .everyNDays:
            guard let interval = cadence.intervalDays, interval >= 1 else { return false }
            return index % interval == 0
        case .cycleOnOff:
            guard let on = cadence.onDays, let off = cadence.offDays, on >= 1, off >= 1 else { return false }
            return index % (on + off) < on
        }
    }

    private static func adherence(_ due: [Date], _ logged: Set<Date>) -> Double? {
        guard !due.isEmpty else { return nil }
        return Double(due.filter { logged.contains($0) }.count) / Double(due.count) * 100
    }
}
