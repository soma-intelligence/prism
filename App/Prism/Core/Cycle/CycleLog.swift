//
//  CycleLog.swift
//  Prism
//
//  What a person logs about their cycle. The flow and the symptoms go to
//  Apple Health, where Cycle Tracking and every other app read them too; a
//  note for the day stays on the phone, in `CycleStore`.
//
//  Every type written here is sensitive (`HealthMetricCatalog.onDemand`):
//  the cycle page asks for them when it opens, never the launch sheet, and
//  `CycleLog` refuses to write until that ask has happened. Account
//  deletion erases nothing here (owner, 2026-10-24).
//

import Foundation
import Observation
import HealthExportCore
#if canImport(HealthKit)
import HealthKit
#endif

/// How heavy a day's flow was, as Apple Health's vaginal bleeding values
/// number it.
nonisolated enum CycleFlow: Int, CaseIterable, Identifiable, Sendable {
    case light = 2
    case medium = 3
    case heavy = 4

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .light: "Light"
        case .medium: "Medium"
        case .heavy: "Heavy"
        }
    }
}

/// The symptoms the log offers, each one of Apple Health's symptom types.
nonisolated enum CycleSymptom: String, CaseIterable, Identifiable, Codable, Sendable {
    case cramps
    case bloating
    case headache
    case moodChanges
    case sleepChanges
    case hotFlashes
    case nightSweats

    var id: String { rawValue }

    var identifier: String {
        switch self {
        case .cramps: "HKCategoryTypeIdentifierAbdominalCramps"
        case .bloating: "HKCategoryTypeIdentifierBloating"
        case .headache: "HKCategoryTypeIdentifierHeadache"
        case .moodChanges: "HKCategoryTypeIdentifierMoodChanges"
        case .sleepChanges: "HKCategoryTypeIdentifierSleepChanges"
        case .hotFlashes: "HKCategoryTypeIdentifierHotFlashes"
        case .nightSweats: "HKCategoryTypeIdentifierNightSweats"
        }
    }

    var title: String {
        switch self {
        case .cramps: "Cramps"
        case .bloating: "Bloating"
        case .headache: "Headache"
        case .moodChanges: "Mood changes"
        case .sleepChanges: "Sleep changes"
        case .hotFlashes: "Hot flashes"
        case .nightSweats: "Night sweats"
        }
    }

    init?(identifier: String) {
        guard let match = Self.allCases.first(where: { $0.identifier == identifier }) else { return nil }
        self = match
    }

    /// Apple Health's severity value 1, "not present": a day logged without
    /// the symptom, which counts as no day of it.
    static let notPresentCode = 1
}

/// One sample on its way to Health, as plain values so a test can read it.
nonisolated struct CycleSample: Equatable, Sendable {
    var identifier: String
    var value: Int
    var start: Date
    var end: Date
    /// Health's "start of a cycle" flag, which every flow sample must carry;
    /// nil for a symptom.
    var startsCycle: Bool?
}

/// Where the samples go: Apple Health on a device, a spy in the tests.
protocol CycleHealthWriting: Sendable {
    /// False where Health is absent or this build carries no write usage
    /// string: asking to write without one raises an exception.
    var canWrite: Bool { get }
    func save(_ sample: CycleSample) async throws
}

/// The flow and symptom log.
@MainActor
final class CycleLog {
    enum Outcome: Equatable {
        case saved
        /// The cycle page has not asked for these types yet.
        case notAsked
        /// Health is not on this device, or this build does not write.
        case notWritten
        case failed(String)
    }

    private let writer: any CycleHealthWriting
    private let isAsked: @MainActor () -> Bool

    /// - Parameter isAsked: true once the cycle page has asked Health for
    ///   the cycle types (`HealthDashboard.hasAsked`).
    init(writer: any CycleHealthWriting, isAsked: @escaping @MainActor () -> Bool) {
        self.writer = writer
        self.isAsked = isAsked
    }

    /// A day of flow. `startsPeriod` is the first day of a period, which
    /// Health needs on every flow sample to tell periods apart.
    func write(flow: CycleFlow, on date: Date, startsPeriod: Bool, calendar: Calendar = .current) async -> Outcome {
        await save(identifier: HomeMetric.menstrualFlow, value: flow.rawValue, on: date, startsCycle: startsPeriod, calendar: calendar)
    }

    /// A symptom on a day, written as present without a severity: the log
    /// asks yes or no, never how bad.
    func write(symptom: CycleSymptom, on date: Date, calendar: Calendar = .current) async -> Outcome {
        // Severity 0 is "unspecified", Health's present without a grade.
        await save(identifier: symptom.identifier, value: 0, on: date, startsCycle: nil, calendar: calendar)
    }

    private func save(identifier: String, value: Int, on date: Date, startsCycle: Bool?, calendar: Calendar) async -> Outcome {
        guard isAsked() else { return .notAsked }
        guard writer.canWrite else { return .notWritten }
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        do {
            try await writer.save(CycleSample(identifier: identifier, value: value, start: start, end: end, startsCycle: startsCycle))
            return .saved
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}

/// The real writer: one category sample per log, saved to Health.
nonisolated struct HealthKitCycleWriter: CycleHealthWriting {
    var canWrite: Bool {
        #if canImport(HealthKit)
        HKHealthStore.isHealthDataAvailable()
            && Bundle.main.object(forInfoDictionaryKey: "NSHealthUpdateUsageDescription") != nil
        #else
        false
        #endif
    }

    func save(_ sample: CycleSample) async throws {
        #if canImport(HealthKit)
        guard let type = HKObjectType.categoryType(forIdentifier: HKCategoryTypeIdentifier(rawValue: sample.identifier)) else { return }
        let metadata: [String: Any]? = sample.startsCycle.map { [HKMetadataKeyMenstrualCycleStart: $0] }
        let object = HKCategorySample(type: type, value: sample.value, start: sample.start, end: sample.end, metadata: metadata)
        try await HKHealthStore().save(object)
        #endif
    }
}

// MARK: - Who sees the cycle

/// Whether the cycle shows in Body and in Track's "Add to today".
nonisolated enum CycleVisibility {
    /// A person tracks a cycle when Health holds flow for them, whatever the
    /// profile says, or when their profile says female. Anyone else never
    /// meets the tile, and the page stays one search away.
    static func tracksCycle(sex: BiologicalSex?, flowOnRecord: Bool) -> Bool {
        flowOnRecord || sex == .female
    }

    /// The same, read off the profile and the cycle store.
    @MainActor
    static var tracksCycle: Bool {
        #if DEBUG && targetEnvironment(simulator)
        if FixtureCycle.isOn { return true }
        #endif
        return tracksCycle(sex: SomaProfileStore.shared.profile.sex, flowOnRecord: CycleStore.shared.flowSeenAt != nil)
    }
}

// MARK: - Notes

/// The day notes the log keeps, and when flow was last seen: one JSON file
/// in Application Support, written atomically with complete protection.
@MainActor
@Observable
final class CycleStore {
    static let shared = CycleStore(url: CycleStore.defaultURL)

    private struct Stored: Codable {
        var notes: [String: String] = [:]
        var flowSeenAt: Date?
    }

    /// Day key ("2026-10-24") to the note.
    private(set) var notes: [String: String]
    /// The last flow day the page read or the log wrote, nil until one. It
    /// is what tells the tile that this person tracks a cycle.
    private(set) var flowSeenAt: Date?
    private let url: URL?

    init(url: URL?) {
        self.url = url
        let stored = LabFiles.load(Stored.self, from: url) ?? Stored()
        notes = stored.notes
        flowSeenAt = stored.flowSeenAt
    }

    func note(on date: Date, calendar: Calendar = .current) -> String? {
        notes[Self.key(date, calendar: calendar)]
    }

    /// Sets the day's note; blank clears it.
    func setNote(_ text: String, on date: Date, calendar: Calendar = .current) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        notes[Self.key(date, calendar: calendar)] = trimmed.isEmpty ? nil : trimmed
        save()
    }

    /// Keeps the latest flow day seen.
    func markFlowSeen(_ date: Date) {
        guard flowSeenAt.map({ date > $0 }) ?? true else { return }
        flowSeenAt = date
        save()
    }

    private func save() {
        LabFiles.save(Stored(notes: notes, flowSeenAt: flowSeenAt), to: url)
    }

    static func key(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Application Support/cycle.json.
    private static var defaultURL: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appending(path: "cycle.json")
    }
}

// MARK: - Symptoms of a cycle

/// How many days of the current cycle carried each symptom.
nonisolated struct CycleSymptomTally: Equatable, Sendable {
    var symptom: CycleSymptom
    var days: Int

    /// Days with each symptom from `since` to `now`, most frequent first,
    /// symptoms with none left out.
    static func make(symptoms: [CycleSymptom: [Date]], since: Date, now: Date, calendar: Calendar) -> [CycleSymptomTally] {
        let first = calendar.startOfDay(for: since)
        return CycleSymptom.allCases.compactMap { symptom -> CycleSymptomTally? in
            let days = Set((symptoms[symptom] ?? []).filter { $0 >= first && $0 <= now }.map { calendar.startOfDay(for: $0) })
            return days.isEmpty ? nil : CycleSymptomTally(symptom: symptom, days: days.count)
        }
        // Ties keep the log's order.
        .sorted { $0.days != $1.days ? $0.days > $1.days : order($0.symptom) < order($1.symptom) }
    }

    private static func order(_ symptom: CycleSymptom) -> Int {
        CycleSymptom.allCases.firstIndex(of: symptom) ?? 0
    }
}
