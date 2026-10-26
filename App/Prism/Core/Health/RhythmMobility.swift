//
//  RhythmMobility.swift
//  Prism
//

import Foundation
import HealthExportCore

// Heart rhythm, walking steadiness and falls, worked out from what Apple
// Health already holds: the weekly AFib burden and the rhythm notifications
// from Apple Watch, walking steadiness, double support and asymmetry from
// iPhone, and the falls the watch detected. Nothing here touches HealthKit:
// the readings come in through `HealthSampleSource`, so the tests drive it
// with plain values.

// MARK: - Reading

/// A year of the rhythm and mobility readings, newest first as Health returns
/// them. Every type here is in the catalog, so `HealthAccess` asks for all of
/// them in the one sheet and nothing asks again.
nonisolated struct RhythmMobilityReadings: Equatable, Sendable {
    static let burdenID = "HKQuantityTypeIdentifierAtrialFibrillationBurden"
    static let irregularID = "HKCategoryTypeIdentifierIrregularHeartRhythmEvent"
    static let highID = "HKCategoryTypeIdentifierHighHeartRateEvent"
    static let lowID = "HKCategoryTypeIdentifierLowHeartRateEvent"
    static let steadinessID = "HKQuantityTypeIdentifierAppleWalkingSteadiness"
    static let steadinessEventID = "HKCategoryTypeIdentifierAppleWalkingSteadinessEvent"
    static let fallsID = "HKQuantityTypeIdentifierNumberOfTimesFallen"
    static let doubleSupportID = "HKQuantityTypeIdentifierWalkingDoubleSupportPercentage"
    static let asymmetryID = "HKQuantityTypeIdentifierWalkingAsymmetryPercentage"

    /// Everything the reader asks for, passed to `HealthDashboard.prepare`.
    static let identifiers = [
        burdenID, irregularID, highID, lowID,
        steadinessID, steadinessEventID, fallsID, doubleSupportID, asymmetryID,
    ]

    /// Gait samples arrive after every walk; the latest few are enough.
    static let gaitLimit = 200

    var burden: [HealthReading] = []
    var irregular: [HealthReading] = []
    var high: [HealthReading] = []
    var low: [HealthReading] = []
    var steadiness: [HealthReading] = []
    var steadinessEvents: [HealthReading] = []
    var falls: [HealthReading] = []
    var doubleSupport: [HealthReading] = []
    var asymmetry: [HealthReading] = []

    /// Reads the last year of each type. A type the store cannot read comes
    /// back empty, which the pages show as a dash.
    static func read(from source: any HealthSampleSource, now: Date = .now, calendar: Calendar = .current) async -> RhythmMobilityReadings {
        let from = calendar.date(byAdding: .year, value: -1, to: now) ?? now
        let gaitFrom = calendar.date(byAdding: .day, value: -90, to: now) ?? now

        func samples(_ identifier: String, since start: Date, limit: Int = 0) async -> [HealthReading] {
            guard let metric = HealthMetricCatalog.metric(for: identifier) else { return [] }
            return (try? await source.samples(metric, from: start, to: now, limit: limit)) ?? []
        }

        var out = RhythmMobilityReadings()
        out.burden = await samples(burdenID, since: from)
        out.irregular = await samples(irregularID, since: from)
        out.high = await samples(highID, since: from)
        out.low = await samples(lowID, since: from)
        out.steadiness = await samples(steadinessID, since: from)
        out.steadinessEvents = await samples(steadinessEventID, since: from)
        out.falls = await samples(fallsID, since: from)
        out.doubleSupport = await samples(doubleSupportID, since: gaitFrom, limit: gaitLimit)
        out.asymmetry = await samples(asymmetryID, since: gaitFrom, limit: gaitLimit)
        return out
    }

    func rhythm(now: Date = .now, calendar: Calendar = .current) -> HeartRhythmSummary {
        HeartRhythmSummary.make(burden: burden, irregular: irregular, high: high, low: low, now: now, calendar: calendar)
    }

    func mobility(now: Date = .now, calendar: Calendar = .current) -> MobilitySummary {
        MobilitySummary.make(
            steadiness: steadiness, falls: falls, events: steadinessEvents,
            doubleSupport: doubleSupport, asymmetry: asymmetry, now: now, calendar: calendar
        )
    }
}

// MARK: - Heart rhythm

/// One week of AFib History: the share of the week the watch read the heart
/// in atrial fibrillation.
nonisolated struct AFibWeek: Equatable, Sendable, Identifiable {
    var id: Date { start }
    /// The first day of the week, in the person's calendar.
    let start: Date
    /// 0 to 1.
    let burden: Double
}

/// What kind of rhythm notification Apple Watch sent.
nonisolated enum RhythmEventKind: String, Equatable, Sendable, CaseIterable {
    case irregular, high, low

    var title: String {
        switch self {
        case .irregular: "Irregular rhythm"
        case .high: "High heart rate"
        case .low: "Low heart rate"
        }
    }

    /// What set the notification off, from Apple's own description of each.
    var detail: String {
        switch self {
        case .irregular: "Several readings in a row looked like atrial fibrillation."
        case .high: "Above the limit set on your watch while you seemed still for ten minutes."
        case .low: "Below the limit set on your watch for ten minutes."
        }
    }
}

nonisolated struct RhythmEvent: Equatable, Sendable, Identifiable {
    var id: String { "\(kind.rawValue)\(date.timeIntervalSince1970)" }
    let kind: RhythmEventKind
    let date: Date
}

/// AFib burden week by week and the rhythm notifications of the year.
nonisolated struct HeartRhythmSummary: Equatable, Sendable {
    /// Weeks of AFib History shown, about six months.
    static let shownWeeks = 26

    /// Oldest first.
    let weeks: [AFibWeek]
    /// Newest first, within the last twelve months.
    let events: [RhythmEvent]

    /// The latest week's burden, 0 to 1, or nil when there is none.
    var latestBurden: Double? { weeks.last?.burden }

    /// The latest week against the one before it, in the same 0 to 1 units.
    var change: Double? {
        guard weeks.count >= 2 else { return nil }
        return weeks[weeks.count - 1].burden - weeks[weeks.count - 2].burden
    }

    var hasIrregular: Bool { events.contains { $0.kind == .irregular } }

    var hasData: Bool { !weeks.isEmpty || !events.isEmpty }

    static func make(
        burden: [HealthReading],
        irregular: [HealthReading],
        high: [HealthReading],
        low: [HealthReading],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> HeartRhythmSummary {
        let weekFloor = calendar.date(byAdding: .weekOfYear, value: -shownWeeks, to: now) ?? now
        let yearFloor = calendar.date(byAdding: .year, value: -1, to: now) ?? now

        // Apple writes one burden sample a week; two in one week are averaged.
        var byWeek: [Date: [Double]] = [:]
        for reading in burden where reading.start >= weekFloor && reading.start <= now {
            let start = calendar.dateInterval(of: .weekOfYear, for: reading.start)?.start ?? calendar.startOfDay(for: reading.start)
            byWeek[start, default: []].append(reading.value)
        }
        let weeks = byWeek
            .map { AFibWeek(start: $0.key, burden: $0.value.reduce(0, +) / Double($0.value.count)) }
            .sorted { $0.start < $1.start }

        let tagged = irregular.map { (RhythmEventKind.irregular, $0) } + high.map { (.high, $0) } + low.map { (.low, $0) }
        let events = tagged
            .filter { $0.1.start >= yearFloor && $0.1.start <= now }
            .map { RhythmEvent(kind: $0.0, date: $0.1.start) }
            .sorted { $0.date > $1.date }

        return HeartRhythmSummary(weeks: weeks, events: events)
    }

    /// A burden as AFib History writes it. Apple's feature reports anything
    /// under its 2 % floor as "2% or less" (Apple, AFib History instructions
    /// for use, 2022), so a smaller number is never shown as if it were read.
    static func burdenText(_ burden: Double?) -> String {
        guard let burden else { return "-" }
        if burden <= 0.02 { return "2% or less" }
        return "\(Int((burden * 100).rounded()))%"
    }
}

// MARK: - Mobility

/// Apple's walking steadiness bands. OK is 40 % and up, low is 20 % up to 40,
/// very low is under 20 % (Apple, "Measuring Walking Quality Through iPhone
/// Mobility Metrics", 2021: very low means a much higher chance of a fall in
/// the next twelve months).
nonisolated enum SteadinessLevel: String, Equatable, Sendable {
    case ok, low, veryLow, unknown

    static let okFloor = 0.40
    static let lowFloor = 0.20

    /// `fraction` is 0 to 1, Health's canonical percent.
    static func of(_ fraction: Double?) -> SteadinessLevel {
        guard let fraction else { return .unknown }
        if fraction >= okFloor { return .ok }
        if fraction >= lowFloor { return .low }
        return .veryLow
    }

    var title: String {
        switch self {
        case .ok: "OK"
        case .low: "Low"
        case .veryLow: "Very low"
        case .unknown: "-"
        }
    }
}

/// A walking steadiness notification, by the code Apple stores
/// (`HKCategoryValueAppleWalkingSteadinessEvent`).
nonisolated enum SteadinessEventKind: Int, Equatable, Sendable {
    case initialLow = 1, initialVeryLow = 2, repeatLow = 3, repeatVeryLow = 4

    var title: String {
        switch self {
        case .initialLow: "Steadiness fell to low"
        case .initialVeryLow: "Steadiness fell to very low"
        case .repeatLow: "Still low"
        case .repeatVeryLow: "Still very low"
        }
    }
}

nonisolated struct SteadinessEvent: Equatable, Sendable, Identifiable {
    var id: Date { date }
    let kind: SteadinessEventKind
    let date: Date
}

/// Walking steadiness, its notifications, the falls of the last twelve
/// months and the two gait readings behind steadiness.
nonisolated struct MobilitySummary: Equatable, Sendable {
    /// A fall this recent puts the help line at the top of the page.
    static let recentFallDays = 30

    /// What the page says first after a recent fall. Watch fall detection
    /// cannot tell whether the person hit their head or blacked out, so the
    /// line names those cases plainly. CDC STEADI asks every older adult who
    /// fell in the past year to tell their doctor (CDC STEADI, 2023).
    static let fallHelpLine = "You fell recently. If you hit your head, blacked out or still hurt, call emergency services or get seen today. Otherwise tell your doctor: a fall is worth a check, even without an injury."

    /// The latest steadiness, 0 to 1, or nil.
    let steadiness: Double?
    let level: SteadinessLevel
    /// Steadiness over the last twelve months, oldest first.
    let history: [HealthReading]
    /// Newest first.
    let events: [SteadinessEvent]
    /// Falls of the last twelve months, newest first.
    let falls: [HealthReading]
    let fallsLast12Months: Int
    let lastFall: Date?
    /// The latest double support time and walking asymmetry, 0 to 1.
    let doubleSupport: Double?
    let asymmetry: Double?
    /// Set when a fall happened in the last ``recentFallDays`` days.
    let helpLine: String?

    var hasData: Bool {
        steadiness != nil || !events.isEmpty || !falls.isEmpty || doubleSupport != nil || asymmetry != nil
    }

    static func make(
        steadiness: [HealthReading],
        falls: [HealthReading],
        events: [HealthReading],
        doubleSupport: [HealthReading] = [],
        asymmetry: [HealthReading] = [],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> MobilitySummary {
        let yearFloor = calendar.date(byAdding: .year, value: -1, to: now) ?? now
        let gaitFloor = calendar.date(byAdding: .day, value: -90, to: now) ?? now
        let recentFloor = calendar.date(byAdding: .day, value: -recentFallDays, to: now) ?? now
        func within(_ readings: [HealthReading], since floor: Date) -> [HealthReading] {
            readings.filter { $0.start >= floor && $0.start <= now }
        }

        let history = within(steadiness, since: yearFloor).sorted { $0.start < $1.start }
        let latest = history.last?.value
        let year = within(falls, since: yearFloor).sorted { $0.start > $1.start }
        let count = Int(year.reduce(0) { $0 + $1.value }.rounded())
        let steadinessEvents = within(events, since: yearFloor)
            .compactMap { reading in SteadinessEventKind(rawValue: Int(reading.value)).map { SteadinessEvent(kind: $0, date: reading.start) } }
            .sorted { $0.date > $1.date }
        let recentFall = year.contains { $0.start >= recentFloor }

        return MobilitySummary(
            steadiness: latest,
            level: .of(latest),
            history: history,
            events: steadinessEvents,
            falls: year,
            fallsLast12Months: count,
            lastFall: year.first?.start,
            doubleSupport: within(doubleSupport, since: gaitFloor).max { $0.start < $1.start }?.value,
            asymmetry: within(asymmetry, since: gaitFloor).max { $0.start < $1.start }?.value,
            helpLine: recentFall ? fallHelpLine : nil
        )
    }
}

// MARK: - Body tiles

/// The two Body tiles this reads into, each shown only when its readings
/// hold something from the last year. A person without a watch sees no Heart
/// rhythm tile; one without an iPhone carried on walks sees no Mobility tile.
nonisolated enum RhythmMobilityTile: String, Equatable, Sendable, CaseIterable {
    case heartRhythm, mobility

    static func shown(_ readings: RhythmMobilityReadings, now: Date = .now, calendar: Calendar = .current) -> [RhythmMobilityTile] {
        var tiles: [RhythmMobilityTile] = []
        if readings.rhythm(now: now, calendar: calendar).hasData { tiles.append(.heartRhythm) }
        if readings.mobility(now: now, calendar: calendar).hasData { tiles.append(.mobility) }
        return tiles
    }
}
