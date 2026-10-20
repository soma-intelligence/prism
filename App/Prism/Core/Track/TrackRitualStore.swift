//
//  TrackRitualStore.swift
//  Prism
//

import Foundation
import Observation
import SwiftUI
import SomaUI

/// When in the day a ritual is kept.
nonisolated enum TrackRitualMoment: String, Codable, CaseIterable, Identifiable, Sendable {
    case morning, evening

    var id: String { rawValue }

    var title: String {
        switch self {
        case .morning: "Morning"
        case .evening: "Evening"
        }
    }

    var tone: SomaTrackTone {
        switch self {
        case .morning: .sand
        case .evening: .dusk
        }
    }

    var glyph: SomaTrackGlyph.Kind {
        switch self {
        case .morning: .wake
        case .evening: .evening
        }
    }
}

/// One step of a ritual: what it is called and the glyph it wears.
nonisolated struct TrackRitualStep: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var title: String
    /// A ``SomaTrackGlyph/Kind`` name. One this build does not know draws as
    /// a tag, so a newer file still opens.
    var glyph: String

    var kind: SomaTrackGlyph.Kind { SomaTrackGlyph.Kind(rawValue: glyph) ?? .tag }
}

/// A short routine: the steps kept at one moment of the day, in order.
nonisolated struct TrackRitual: Codable, Hashable, Identifiable, Sendable {
    var id: String { moment.rawValue }
    var moment: TrackRitualMoment
    var steps: [TrackRitualStep]

    private enum CodingKeys: String, CodingKey { case moment, steps }
}

/// The person's two rituals, morning and evening, and which steps were done
/// on which day.
///
/// Kept on the device as one JSON file in Application Support,
/// `rituals.json`, beside the Journal's. A step removed later keeps its old
/// ticks in the file but no longer counts.
@MainActor
@Observable
final class TrackRitualStore {
    static let shared = TrackRitualStore()

    private(set) var rituals: [TrackRitual]
    /// The ids of the steps done, keyed by the day's stamp, `yyyy-MM-dd`.
    private(set) var done: [String: Set<String>]

    private let url: URL?
    private let calendar: Calendar

    /// What a new person starts with: three small steps each side of the day.
    static let starter: [TrackRitual] = [
        TrackRitual(moment: .morning, steps: [
            TrackRitualStep(id: "morning-daylight", title: "Daylight, 10 minutes", glyph: "daylight"),
            TrackRitualStep(id: "morning-water", title: "A glass of water", glyph: "drink"),
            TrackRitualStep(id: "morning-stretch", title: "Stretch", glyph: "stretch"),
        ]),
        TrackRitual(moment: .evening, steps: [
            TrackRitualStep(id: "evening-screens", title: "Screens away", glyph: "screens"),
            TrackRitualStep(id: "evening-breathe", title: "Breathe, 5 minutes", glyph: "breathe"),
            TrackRitualStep(id: "evening-read", title: "Read a few pages", glyph: "read"),
        ]),
    ]

    /// The glyphs a new step can wear, in the order the picker offers them.
    static let stepGlyphs: [SomaTrackGlyph.Kind] = [
        .daylight, .drink, .stretch, .walk, .breathe, .meditation, .read, .journal,
        .screens, .cold, .sauna, .supplement, .meal, .sleep, .coffee, .tag,
    ]

    private struct Stored: Codable {
        var rituals: [TrackRitual]
        var done: [String: Set<String>]
    }

    /// - Parameter url: where the record lives. Nil keeps it in memory, for
    ///   previews and tests.
    init(url: URL? = TrackRitualStore.defaultURL, calendar: Calendar = .current) {
        self.url = url
        self.calendar = calendar
        if let url, let data = try? Data(contentsOf: url),
           let stored = try? JSONDecoder().decode(Stored.self, from: data) {
            rituals = Self.complete(stored.rituals)
            done = stored.done
        } else {
            rituals = Self.starter
            done = [:]
        }
    }

    nonisolated static var defaultURL: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return base.appending(path: "rituals.json")
    }

    /// One ritual for each moment, in the day's order, whatever the file held.
    private static func complete(_ rituals: [TrackRitual]) -> [TrackRitual] {
        TrackRitualMoment.allCases.map { moment in
            rituals.first { $0.moment == moment } ?? TrackRitual(moment: moment, steps: [])
        }
    }

    // MARK: Reading

    func ritual(_ moment: TrackRitualMoment) -> TrackRitual {
        rituals.first { $0.moment == moment } ?? TrackRitual(moment: moment, steps: [])
    }

    func isDone(_ step: TrackRitualStep, on date: Date) -> Bool {
        done[stamp(date)]?.contains(step.id) ?? false
    }

    /// The share of a ritual's steps done on a day, 0...1, or nil when the
    /// ritual has no steps.
    func share(_ moment: TrackRitualMoment, on date: Date) -> Double? {
        let steps = ritual(moment).steps
        guard !steps.isEmpty else { return nil }
        let ticked = done[stamp(date)] ?? []
        return Double(steps.filter { ticked.contains($0.id) }.count) / Double(steps.count)
    }

    // MARK: Writing

    func toggle(_ step: TrackRitualStep, on date: Date) {
        let key = stamp(date)
        var ticked = done[key] ?? []
        if ticked.contains(step.id) { ticked.remove(step.id) } else { ticked.insert(step.id) }
        done[key] = ticked.isEmpty ? nil : ticked
        save()
    }

    func addStep(_ title: String, glyph: SomaTrackGlyph.Kind, to moment: TrackRitualMoment) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = rituals.firstIndex(where: { $0.moment == moment }) else { return }
        let step = TrackRitualStep(id: "\(moment.rawValue)-\(UUID().uuidString.prefix(8).lowercased())",
                                   title: trimmed, glyph: glyph.rawValue)
        rituals[index].steps.append(step)
        save()
    }

    func removeStep(_ id: String, from moment: TrackRitualMoment) {
        guard let index = rituals.firstIndex(where: { $0.moment == moment }) else { return }
        rituals[index].steps.removeAll { $0.id == id }
        save()
    }

    func moveSteps(in moment: TrackRitualMoment, from source: IndexSet, to destination: Int) {
        guard let index = rituals.firstIndex(where: { $0.moment == moment }) else { return }
        rituals[index].steps.move(fromOffsets: source, toOffset: destination)
        save()
    }

    // MARK: Days

    func stamp(_ date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private func save() {
        guard let url else { return }
        let stored = Stored(rituals: rituals, done: done)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(stored).write(to: url, options: SomaFileStorage.protectedAtomicOptions)
        } catch {
            // A failed write keeps the day in memory; the next change tries
            // again.
        }
    }
}
