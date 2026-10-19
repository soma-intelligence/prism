//
//  ActivityStatus.swift
//  Prism
//

import Foundation

/// How a person says they are this week: the context their days are read in.
///
/// The Home activity pill sets it. Five older cases (active, sick, injured, on
/// vacation, traveling) fold into four, because sick and injured change the
/// reading the same way and a holiday is a planned rest. Those older stored
/// names still map in, so a value saved under one keeps its meaning.
///
/// It is a choice, never derived: nothing infers it from the numbers. What it
/// changes today is how Ask answers a training question and the mark the
/// calendar puts under a day.
nonisolated enum ActivityStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case training
    case resting
    case travelling
    case unwell

    var id: String { rawValue }

    /// Reads a stored name, Soma's own or one of the older names.
    init?(storedName: String) {
        if let own = ActivityStatus(rawValue: storedName) {
            self = own
            return
        }
        switch storedName {
        case "active": self = .training
        case "vacation": self = .resting
        case "travel": self = .travelling
        case "sick", "injured": self = .unwell
        default: return nil
        }
    }

    var title: String {
        switch self {
        case .training: String(localized: "Training")
        case .resting: String(localized: "Resting")
        case .travelling: String(localized: "Travelling")
        case .unwell: String(localized: "Unwell")
        }
    }

    /// The line under the title in the picker.
    var summary: String {
        switch self {
        case .training: String(localized: "Your usual routine.")
        case .resting: String(localized: "A planned break. Ask Soma holds back hard training.")
        case .travelling: String(localized: "A trip. The day is marked on your calendar.")
        case .unwell: String(localized: "Ill or injured. Ask Soma holds back hard training.")
        }
    }

    /// What the status changes, as the legend spells it out.
    var legend: String {
        switch self {
        case .training:
            String(localized: "Your usual routine. Nothing changes, and the day carries no mark on your calendar.")
        case .resting:
            String(localized: "A planned break. Asked whether to train hard, Ask Soma says to hold back, and the day is marked on your calendar. Your scores read as usual.")
        case .travelling:
            String(localized: "A new time zone or routine. The day is marked on your calendar so you can see it later. Your scores read as usual.")
        case .unwell:
            String(localized: "Ill or injured. Asked whether to train hard, Ask Soma says to hold back, and the day is marked on your calendar. Your scores read as usual.")
        }
    }

    var symbol: String {
        switch self {
        case .training: "figure.run"
        case .resting: "moon.fill"
        case .travelling: "globe"
        case .unwell: "allergens"
        }
    }

    /// Whether a day read under this status carries a mark on the calendar.
    /// Training is the usual, so it carries none.
    var marksCalendar: Bool { self != .training }

    /// Whether a hard session should be discouraged, whatever the numbers say.
    var holdsTrainingBack: Bool { self == .resting || self == .unwell }
}

/// One change of status, and the day it took effect from.
nonisolated struct ActivityStatusChange: Codable, Equatable, Sendable {
    var from: Date
    var status: ActivityStatus
}

/// The status in force on any day, from the list of changes.
nonisolated enum ActivityStatusHistory {
    /// The status that held on `day`: the last change made on or before it,
    /// Training before the first one.
    static func status(on day: Date, changes: [ActivityStatusChange], calendar: Calendar) -> ActivityStatus {
        let end = calendar.startOfDay(for: day).addingTimeInterval(86_400)
        return changes
            .filter { $0.from < end }
            .max { $0.from < $1.from }?
            .status ?? .training
    }

    /// The list after choosing `status` at `date`. A second change on the same
    /// day replaces the first: the calendar keeps one status a day.
    static func recording(_ status: ActivityStatus, at date: Date, in changes: [ActivityStatusChange], calendar: Calendar) -> [ActivityStatusChange] {
        var kept = changes.filter { !calendar.isDate($0.from, inSameDayAs: date) }
        kept.append(ActivityStatusChange(from: date, status: status))
        return kept.sorted { $0.from < $1.from }
    }
}

/// Where the status and its history live: this phone's defaults.
@MainActor
@Observable
final class ActivityStatusStore {
    static let shared = ActivityStatusStore()

    /// Soma's key. The older `user.activityStatus` key is read once, as a seed.
    static let storageKey = "soma.activityStatus"
    static let historyKey = "soma.activityStatus.history"
    static let legacyKey = "user.activityStatus"

    private(set) var current: ActivityStatus
    private(set) var changes: [ActivityStatusChange]

    private let defaults: UserDefaults
    private let calendar: Calendar

    init(defaults: UserDefaults = .standard, calendar: Calendar = .current) {
        self.defaults = defaults
        self.calendar = calendar
        let stored = defaults.string(forKey: Self.storageKey) ?? defaults.string(forKey: Self.legacyKey)
        current = stored.flatMap(ActivityStatus.init(storedName:)) ?? .training
        if let data = defaults.data(forKey: Self.historyKey),
           let decoded = try? JSONDecoder().decode([ActivityStatusChange].self, from: data) {
            changes = decoded
        } else {
            changes = []
        }
    }

    func set(_ status: ActivityStatus, at date: Date = Date()) {
        current = status
        changes = ActivityStatusHistory.recording(status, at: date, in: changes, calendar: calendar)
        defaults.set(status.rawValue, forKey: Self.storageKey)
        if let data = try? JSONEncoder().encode(changes) {
            defaults.set(data, forKey: Self.historyKey)
        }
    }

    func status(on day: Date) -> ActivityStatus {
        guard !changes.isEmpty else { return calendar.isDateInToday(day) ? current : .training }
        return ActivityStatusHistory.status(on: day, changes: changes, calendar: calendar)
    }
}
