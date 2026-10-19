//
//  MindHealthBridge.swift
//  Prism
//
//  Apple Health's State of Mind, read and written, and a breathing session
//  saved as mindful minutes. `HealthSampleSource` reads quantities and
//  categories only, so Mind talks to the store directly for these two.
//
//  Launched with `-health.empty YES` the bridge asks nothing and reads
//  nothing, as the rest of the app does.
//

import Foundation
#if canImport(HealthKit)
import HealthKit
#endif

@MainActor
enum MindHealthBridge {
    /// Whether Health is there to ask at all.
    static var isAvailable: Bool {
        guard !UserDefaults.standard.bool(forKey: "health.empty") else { return false }
#if canImport(HealthKit)
        return HKHealthStore.isHealthDataAvailable()
#else
        return false
#endif
    }

#if canImport(HealthKit)
    private static let store = HKHealthStore()

    /// Asks to read and write State of Mind and to write mindful minutes. The
    /// sheet shows only what was never asked.
    static func requestAccess() async -> Bool {
        guard isAvailable else { return false }
        let share: Set<HKSampleType> = [HKObjectType.stateOfMindType(), HKCategoryType(.mindfulSession)]
        let read: Set<HKObjectType> = [HKObjectType.stateOfMindType()]
        do {
            try await store.requestAuthorization(toShare: share, read: read)
            return true
        } catch {
            return false
        }
    }

    /// State of Mind entries from `start` on, oldest first. Empty when Health
    /// holds none, refused the read, or is not there: a gap, never a feeling.
    static func moods(since start: Date) async -> [MindMoodEntry] {
        guard isAvailable else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: nil)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.stateOfMind(predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .forward)],
            limit: 4000
        )
        guard let samples = try? await descriptor.result(for: store) else { return [] }
        return samples.map { sample in
            MindMoodEntry(
                date: sample.startDate,
                kind: sample.kind == .dailyMood ? .daily : .momentary,
                valence: sample.valence,
                labels: sample.labels.compactMap(Self.name(of:)),
                associations: sample.associations.compactMap(Self.name(of:)),
                isInHealth: true
            )
        }
    }

    /// Writes one entry. False when Health refused or is not there.
    static func save(_ entry: MindMoodEntry) async -> Bool {
        guard isAvailable, await requestAccess() else { return false }
        let sample = HKStateOfMind(
            date: entry.date,
            kind: entry.kind == .daily ? .dailyMood : .momentaryEmotion,
            valence: min(max(entry.valence, -1), 1),
            labels: entry.labels.compactMap(label(named:)),
            associations: entry.associations.compactMap(association(named:))
        )
        do {
            try await store.save(sample)
            return true
        } catch {
            return false
        }
    }

    /// Saves a breathing session as mindful minutes.
    static func saveMindful(from start: Date, to end: Date) async -> Bool {
        guard isAvailable, end > start, await requestAccess() else { return false }
        let sample = HKCategorySample(type: HKCategoryType(.mindfulSession), value: HKCategoryValue.notApplicable.rawValue, start: start, end: end)
        do {
            try await store.save(sample)
            return true
        } catch {
            return false
        }
    }

    // MARK: Names

    private static let labels: [String: HKStateOfMind.Label] = [
        "calm": .calm, "content": .content, "grateful": .grateful, "relieved": .relieved,
        "happy": .happy, "hopeful": .hopeful, "peaceful": .peaceful, "confident": .confident,
        "excited": .excited, "proud": .proud, "drained": .drained, "stressed": .stressed,
        "anxious": .anxious, "worried": .worried, "frustrated": .frustrated, "irritated": .irritated,
        "sad": .sad, "overwhelmed": .overwhelmed, "lonely": .lonely, "hopeless": .hopeless,
    ]

    private static let associations: [String: HKStateOfMind.Association] = [
        "work": .work, "health": .health, "selfCare": .selfCare, "family": .family,
        "friends": .friends, "partner": .partner, "fitness": .fitness, "money": .money,
        "tasks": .tasks, "weather": .weather, "travel": .travel, "hobbies": .hobbies,
    ]

    static func label(named name: String) -> HKStateOfMind.Label? { labels[name] }
    static func association(named name: String) -> HKStateOfMind.Association? { associations[name] }
    static func name(of label: HKStateOfMind.Label) -> String? { labels.first { $0.value == label }?.key }
    static func name(of association: HKStateOfMind.Association) -> String? { associations.first { $0.value == association }?.key }
#else
    static func requestAccess() async -> Bool { false }
    static func moods(since start: Date) async -> [MindMoodEntry] { [] }
    static func save(_ entry: MindMoodEntry) async -> Bool { false }
    static func saveMindful(from start: Date, to end: Date) async -> Bool { false }
#endif
}
