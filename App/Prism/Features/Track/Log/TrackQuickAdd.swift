//
//  TrackQuickAdd.swift
//  Prism
//

import SwiftUI
import Observation
import SomaUI

/// One tile of the Journal's quick add grid: what it opens, its name, its
/// line glyph and its calm tone.
enum TrackQuickAdd: String, CaseIterable, Identifiable, Sendable {
    case drink, meal, fast, mood, weight, breathe, sauna, coldPlunge
    case evening, wake, supplement, scan, bloodTest, height

    var id: String { rawValue }

    var title: String {
        switch self {
        case .drink: "Drink"
        case .meal: "Meal"
        case .fast: "Fast"
        case .mood: "Mood"
        case .weight: "Weight"
        case .breathe: "Breathe"
        case .sauna: "Sauna"
        case .coldPlunge: "Cold plunge"
        case .evening: "Evening"
        case .wake: "Woke"
        case .supplement: "Supplement"
        case .scan: "Scan"
        case .bloodTest: "Blood test"
        case .height: "Height"
        }
    }

    var glyph: SomaTrackGlyph.Kind {
        switch self {
        case .drink: .drink
        case .meal: .meal
        case .fast: .fast
        case .mood: .mood
        case .weight: .weight
        case .breathe: .breathe
        case .sauna: .sauna
        case .coldPlunge: .cold
        case .evening: .evening
        case .wake: .wake
        case .supplement: .supplement
        case .scan: .scan
        case .bloodTest: .bloodTest
        case .height: .height
        }
    }

    var tone: SomaTrackTone {
        switch self {
        case .drink, .coldPlunge: .tide
        case .meal, .breathe: .sage
        case .fast, .wake: .sand
        case .mood: .rose
        case .weight, .height, .scan: .stone
        case .sauna, .bloodTest: .clay
        case .evening: .dusk
        case .supplement: .moss
        }
    }

    /// The sheet it opens. Nil for the blood test, which pushes Longevity's
    /// lab page instead.
    var route: TrackRoute? {
        switch self {
        case .drink: .drink(.water)
        case .meal: .food
        case .fast: .fasting
        case .mood: .moodNow
        case .weight: .weight
        case .breathe: .practice(.meditation)
        case .sauna: .practice(.sauna)
        case .coldPlunge: .practice(.coldPlunge)
        case .evening: .evening
        case .wake: .wake
        case .supplement: .dose(nil)
        case .scan: .cameraScan
        case .bloodTest: nil
        case .height: .height
        }
    }
}

/// Which quick add tiles the Journal shows, in the person's order. Changed in
/// Track, Customize; kept on the device in the user defaults as the tiles'
/// names. Nothing saved yet means every tile, in the starting order.
@MainActor
@Observable
final class TrackQuickAddLayout {
    static let shared = TrackQuickAddLayout()

    /// The tiles on the Journal, in order.
    private(set) var shown: [TrackQuickAdd]

    private let defaults: UserDefaults
    static let key = "track.quickAddTiles"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        shown = Self.decode(defaults.stringArray(forKey: Self.key))
    }

    /// The tiles that are not on the Journal, in the starting order.
    var hidden: [TrackQuickAdd] {
        TrackQuickAdd.allCases.filter { !shown.contains($0) }
    }

    /// Reads saved names: unknown ones are dropped, a repeat is kept once,
    /// nothing saved is every tile.
    static func decode(_ names: [String]?) -> [TrackQuickAdd] {
        guard let names else { return TrackQuickAdd.allCases }
        var seen = Set<TrackQuickAdd>()
        return names.compactMap(TrackQuickAdd.init(rawValue:)).filter { seen.insert($0).inserted }
    }

    func show(_ tile: TrackQuickAdd) {
        guard !shown.contains(tile) else { return }
        shown.append(tile)
        save()
    }

    func hide(_ tile: TrackQuickAdd) {
        shown.removeAll { $0 == tile }
        save()
    }

    func move(from source: IndexSet, to destination: Int) {
        shown.move(fromOffsets: source, toOffset: destination)
        save()
    }

    private func save() {
        defaults.set(shown.map(\.rawValue), forKey: Self.key)
    }
}
