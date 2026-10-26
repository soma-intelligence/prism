//
//  GlobalSettings.swift
//  Prism
//

import Foundation
import SomaUI

/// A time of day, in minutes after midnight, so a reminder or a cutoff is one
/// comparable number rather than two fields.
nonisolated struct ClockTime: Codable, Hashable, Comparable, Sendable {
    var minutes: Int

    init(minutes: Int) {
        self.minutes = ((minutes % 1440) + 1440) % 1440
    }

    init(hour: Int, minute: Int = 0) {
        self.init(minutes: hour * 60 + minute)
    }

    var hour: Int { minutes / 60 }
    var minute: Int { minutes % 60 }

    /// 07:30, the way every Soma page writes a time.
    var text: String { String(format: "%02d:%02d", hour, minute) }

    static func < (lhs: ClockTime, rhs: ClockTime) -> Bool { lhs.minutes < rhs.minutes }

    /// Whether this time falls inside the window from `start` to `end`, a
    /// window that may run past midnight (22:30 to 07:00).
    func isInside(from start: ClockTime, until end: ClockTime) -> Bool {
        if start == end { return false }
        if start < end { return self >= start && self < end }
        return self >= start || self < end
    }

    func adding(minutes delta: Int) -> ClockTime { ClockTime(minutes: minutes + delta) }
}

// MARK: - Notifications

/// Which reminders a person wants, and when.
nonisolated struct NotificationPreferences: Codable, Equatable, Sendable {
    var morningCheckIn = true
    var morningTime = ClockTime(hour: 7, minute: 30)
    var eveningCheckIn = true
    var eveningTime = ClockTime(hour: 21)
    var eveningNudges = true
    var podVisits = true
    var bloodTests = true
    var tools = true
    var sourceQuiet = true
    var afterSession = false
    var quietHours = true
    var quietFrom = ClockTime(hour: 22, minute: 30)
    var quietUntil = ClockTime(hour: 7)
}

nonisolated extension NotificationPreferences {
    /// Field by field: a reminder added in a later build starts on its
    /// default and leaves every other choice as it was.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self()
        morningCheckIn = container.value(.morningCheckIn, or: defaults.morningCheckIn)
        morningTime = container.value(.morningTime, or: defaults.morningTime)
        eveningCheckIn = container.value(.eveningCheckIn, or: defaults.eveningCheckIn)
        eveningTime = container.value(.eveningTime, or: defaults.eveningTime)
        eveningNudges = container.value(.eveningNudges, or: defaults.eveningNudges)
        podVisits = container.value(.podVisits, or: defaults.podVisits)
        bloodTests = container.value(.bloodTests, or: defaults.bloodTests)
        tools = container.value(.tools, or: defaults.tools)
        sourceQuiet = container.value(.sourceQuiet, or: defaults.sourceQuiet)
        afterSession = container.value(.afterSession, or: defaults.afterSession)
        quietHours = container.value(.quietHours, or: defaults.quietHours)
        quietFrom = container.value(.quietFrom, or: defaults.quietFrom)
        quietUntil = container.value(.quietUntil, or: defaults.quietUntil)
    }
}

// MARK: - Customization

nonisolated enum AnswerLength: String, Codable, CaseIterable, Identifiable, Sendable {
    case short, detailed
    var id: String { rawValue }
    var title: String {
        switch self {
        case .short: String(localized: "Short")
        case .detailed: String(localized: "Detailed")
        }
    }
}

nonisolated enum SkinType: Int, Codable, CaseIterable, Identifiable, Sendable {
    case one = 1, two, three, four, five, six
    var id: Int { rawValue }
    /// Fitzpatrick types, as Apple Health names them.
    var title: String {
        let numerals = ["I", "II", "III", "IV", "V", "VI"]
        return String(localized: "Type \(numerals[rawValue - 1])")
    }
}

/// What "usual" means for this person, and the targets set against it.
/// Goals, zones, the data window, skin type and answers.
nonisolated struct CustomizationPreferences: Codable, Equatable, Sendable {
    /// How many days make a usual range.
    var usualWindowDays = 90
    var moveGoalKilocalories = 600
    var zoneTwoMinutesPerWeek = 150
    var waterMillilitres = 2200
    var lastMealBy = ClockTime(hour: 20, minute: 30)
    var answers: AnswerLength = .short
    var skinType: SkinType?

    static let usualWindows = [30, 60, 90]
    static let moveGoals = Array(stride(from: 200, through: 1200, by: 50))
    static let zoneTwoTargets = Array(stride(from: 60, through: 300, by: 15))
    static let waterTargets = Array(stride(from: 1000, through: 4000, by: 100))
    static let mealCutoffs = stride(from: 17 * 60, through: 23 * 60, by: 30).map { ClockTime(minutes: $0) }
}

nonisolated extension CustomizationPreferences {
    /// Field by field, so one target this build cannot read costs only itself.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self()
        usualWindowDays = container.value(.usualWindowDays, or: defaults.usualWindowDays)
        moveGoalKilocalories = container.value(.moveGoalKilocalories, or: defaults.moveGoalKilocalories)
        zoneTwoMinutesPerWeek = container.value(.zoneTwoMinutesPerWeek, or: defaults.zoneTwoMinutesPerWeek)
        waterMillilitres = container.value(.waterMillilitres, or: defaults.waterMillilitres)
        lastMealBy = container.value(.lastMealBy, or: defaults.lastMealBy)
        answers = container.value(.answers, or: defaults.answers)
        skinType = try? container.decodeIfPresent(SkinType.self, forKey: .skinType)
    }
}

// MARK: - Units

nonisolated enum MeasureSystem: String, Codable, CaseIterable, Identifiable, Sendable {
    case metric, imperial
    var id: String { rawValue }
    var title: String { self == .metric ? String(localized: "Metric") : String(localized: "Imperial") }
    var detail: String { self == .metric ? String(localized: "kg, cm and km") : String(localized: "lb, ft and mi") }
}

nonisolated enum TemperatureUnit: String, Codable, CaseIterable, Identifiable, Sendable {
    case celsius, fahrenheit
    var id: String { rawValue }
    var title: String { self == .celsius ? "\u{00B0}C" : "\u{00B0}F" }
}

nonisolated enum GlucoseUnit: String, Codable, CaseIterable, Identifiable, Sendable {
    case milligrams, millimoles
    var id: String { rawValue }
    var title: String { self == .milligrams ? "mg/dL" : "mmol/L" }
}

nonisolated enum EnergyUnit: String, Codable, CaseIterable, Identifiable, Sendable {
    case kilocalories, kilojoules
    var id: String { rawValue }
    var title: String { self == .kilocalories ? "kcal" : "kJ" }
}

nonisolated enum ClockStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case twentyFour, twelve
    var id: String { rawValue }
    var title: String { self == .twentyFour ? String(localized: "24 hour") : String(localized: "12 hour") }
}

nonisolated enum WeekStart: Int, Codable, CaseIterable, Identifiable, Sendable {
    case sunday = 1, monday = 2, saturday = 7
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .sunday: String(localized: "Sunday")
        case .monday: String(localized: "Monday")
        case .saturday: String(localized: "Saturday")
        }
    }
}

/// How numbers are written. Seeded from the phone's own locale.
nonisolated struct UnitPreferences: Codable, Equatable, Sendable {
    var measures: MeasureSystem
    var temperature: TemperatureUnit
    var glucose: GlucoseUnit
    var energy: EnergyUnit
    var clock: ClockStyle
    var weekStart: WeekStart

    init(locale: Locale = .current, calendar: Calendar = .current) {
        let isMetric = locale.measurementSystem != .us
        measures = isMetric ? .metric : .imperial
        temperature = isMetric ? .celsius : .fahrenheit
        glucose = .milligrams
        energy = .kilocalories
        clock = .twentyFour
        weekStart = WeekStart(rawValue: calendar.firstWeekday) ?? .monday
    }
}

nonisolated extension UnitPreferences {
    /// Field by field; a unit missing from the file starts from the phone's
    /// region, as it did on the first launch.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self()
        measures = container.value(.measures, or: defaults.measures)
        temperature = container.value(.temperature, or: defaults.temperature)
        glucose = container.value(.glucose, or: defaults.glucose)
        energy = container.value(.energy, or: defaults.energy)
        clock = container.value(.clock, or: defaults.clock)
        weekStart = container.value(.weekStart, or: defaults.weekStart)
    }
}

// MARK: - Shortcuts (the log hub)

/// The six things the plus in Ask's composer offers.
nonisolated enum LogShortcut: String, Codable, CaseIterable, Identifiable, Sendable {
    case meal, workout, journal, weight, sleep, record
    var id: String { rawValue }

    var title: String {
        switch self {
        case .meal: String(localized: "Meal")
        case .workout: String(localized: "Workout")
        case .journal: String(localized: "Journal")
        case .weight: String(localized: "Weight")
        case .sleep: String(localized: "Sleep")
        case .record: String(localized: "Record")
        }
    }

    /// The line the Shortcuts page sets under the title.
    var summary: String {
        switch self {
        case .meal: String(localized: "A photo or a few words")
        case .workout: String(localized: "Kind, length and how hard")
        case .journal: String(localized: "How today felt")
        case .weight: String(localized: "A quick weigh-in")
        case .sleep: String(localized: "A nap, or last night\u{2019}s times")
        case .record: String(localized: "A lab report or a clinic letter")
        }
    }

    /// The orb a row wears, or nil for the record's glyph.
    var aspect: SomaAspect? {
        switch self {
        case .meal: .gut
        case .workout: .activity
        case .journal: .mind
        case .weight: .body
        case .sleep: .sleep
        case .record: nil
        }
    }
}

nonisolated struct ShortcutPreferences: Codable, Equatable, Sendable {
    var order: [LogShortcut] = LogShortcut.allCases
    var hidden: Set<LogShortcut> = []

    /// What the hub shows, in order. A shortcut added in a later version and
    /// missing from a stored order is appended rather than lost.
    var offered: [LogShortcut] {
        let known = order + LogShortcut.allCases.filter { !order.contains($0) }
        return known.filter { !hidden.contains($0) }
    }

    var fullOrder: [LogShortcut] {
        order + LogShortcut.allCases.filter { !order.contains($0) }
    }
}

nonisolated extension ShortcutPreferences {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self()
        order = container.value(.order, or: defaults.order)
        hidden = container.value(.hidden, or: defaults.hidden)
    }
}

// MARK: - Diagnostics

nonisolated struct DiagnosticsPreferences: Codable, Equatable, Sendable {
    var shareCrashReports = false
    var shareUsage = false
}

nonisolated extension DiagnosticsPreferences {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self()
        shareCrashReports = container.value(.shareCrashReports, or: defaults.shareCrashReports)
        shareUsage = container.value(.shareUsage, or: defaults.shareUsage)
    }
}

// MARK: - Store

/// Every app wide preference this lane owns, in one small file on the phone.
///
/// One JSON file beside the Journal's rather than a scatter of defaults keys:
/// an export or an erase then has one place to look.
@MainActor
@Observable
final class GlobalSettings {
    static let shared = GlobalSettings()

    var notifications: NotificationPreferences { didSet { save() } }
    var customization: CustomizationPreferences { didSet { save() } }
    var units: UnitPreferences { didSet { save() } }
    var shortcuts: ShortcutPreferences { didSet { save() } }
    var diagnostics: DiagnosticsPreferences { didSet { save() } }
    var programs: [ProgramEnrollment] { didSet { save() } }

    private let url: URL?
    /// True when a settings file is there but could not be opened, as while
    /// the phone is still locked: nothing is written over it then, so a
    /// change made before it opens never replaces the person's settings with
    /// the defaults.
    private let isUnopened: Bool

    private struct Stored: Codable {
        var notifications: NotificationPreferences?
        var customization: CustomizationPreferences?
        var units: UnitPreferences?
        var shortcuts: ShortcutPreferences?
        var diagnostics: DiagnosticsPreferences?
        var programs: [ProgramEnrollment]?

        init(
            notifications: NotificationPreferences?, customization: CustomizationPreferences?, units: UnitPreferences?,
            shortcuts: ShortcutPreferences?, diagnostics: DiagnosticsPreferences?, programs: [ProgramEnrollment]?
        ) {
            self.notifications = notifications
            self.customization = customization
            self.units = units
            self.shortcuts = shortcuts
            self.diagnostics = diagnostics
            self.programs = programs
        }

        /// Each section is read on its own. One this build cannot read (a
        /// field added since the file was written, a case since dropped)
        /// falls back to its defaults alone, rather than taking every other
        /// section down with it.
        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            notifications = try? container.decodeIfPresent(NotificationPreferences.self, forKey: .notifications)
            customization = try? container.decodeIfPresent(CustomizationPreferences.self, forKey: .customization)
            units = try? container.decodeIfPresent(UnitPreferences.self, forKey: .units)
            shortcuts = try? container.decodeIfPresent(ShortcutPreferences.self, forKey: .shortcuts)
            diagnostics = try? container.decodeIfPresent(DiagnosticsPreferences.self, forKey: .diagnostics)
            programs = try? container.decodeIfPresent([ProgramEnrollment].self, forKey: .programs)
        }
    }

    /// - Parameter url: nil keeps everything in memory, for previews and tests.
    init(url: URL? = GlobalSettings.defaultURL) {
        self.url = url
        let data = url.flatMap { try? Data(contentsOf: $0) }
        isUnopened = data == nil && url.map { FileManager.default.fileExists(atPath: $0.path) } == true
        let stored = data.flatMap { try? JSONDecoder().decode(Stored.self, from: $0) }
        notifications = stored?.notifications ?? NotificationPreferences()
        customization = stored?.customization ?? CustomizationPreferences()
        units = stored?.units ?? UnitPreferences()
        shortcuts = stored?.shortcuts ?? ShortcutPreferences()
        diagnostics = stored?.diagnostics ?? DiagnosticsPreferences()
        programs = stored?.programs ?? []
    }

    nonisolated static var defaultURL: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return base.appending(path: "settings.json")
    }

    private func save() {
        guard let url, !isUnopened else { return }
        let stored = Stored(
            notifications: notifications, customization: customization, units: units,
            shortcuts: shortcuts, diagnostics: diagnostics, programs: programs
        )
        guard let data = try? JSONEncoder().encode(stored) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: SomaFileStorage.protectedAtomicOptions)
    }
}
