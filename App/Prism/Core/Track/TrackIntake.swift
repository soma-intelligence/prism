//
//  TrackIntake.swift
//  Prism
//
//  The drinks a person logs and the arithmetic of the glass, with the caffeine per cup
//  its intake tool uses (a brewed cup 80 mg, a tea 45 mg, both for a 250 ml
//  cup).
//

import Foundation

/// What went into the glass.
nonisolated enum TrackDrink: String, Codable, CaseIterable, Identifiable, Sendable {
    case water
    case coffee
    case tea

    var id: String { rawValue }

    var title: String {
        switch self {
        case .water: "Water"
        case .coffee: "Coffee"
        case .tea: "Tea"
        }
    }

    /// Caffeine in one millilitre.
    var caffeinePerMl: Double {
        switch self {
        case .water: 0
        case .coffee: 80.0 / 250
        case .tea: 45.0 / 250
        }
    }

    /// The glasses offered under the big one, in ml.
    var presets: [Double] {
        switch self {
        case .water: [150, 250, 330, 500]
        case .coffee: [30, 150, 250, 350]
        case .tea: [150, 250, 350, 500]
        }
    }

    /// The most one glass holds.
    var capacity: Double {
        switch self {
        case .water: 1000
        case .coffee, .tea: 500
        }
    }

    /// One detent of the drag.
    var step: Double {
        switch self {
        case .water: 50
        case .coffee: 10
        case .tea: 25
        }
    }

    /// Where the sheet starts.
    var usual: Double {
        switch self {
        case .water: 250
        case .coffee: 150
        case .tea: 250
        }
    }

    func caffeine(ml: Double) -> Double { (ml * caffeinePerMl).rounded() }
}

nonisolated enum TrackIntake {
    /// The day's water goal: two litres.
    static let defaultGoalMl: Double = 2000
    /// One glass in the day's row of glasses.
    static let glassMl: Double = 250

    /// The share of a glass that is full, 0...1.
    static func fill(forValue value: Double, max: Double) -> Double {
        guard max > 0 else { return 0 }
        return Swift.min(1, Swift.max(0, value / max))
    }

    /// The value a fill stands for, snapped to the step and clamped.
    static func value(forFill fill: Double, max: Double, step: Double) -> Double {
        let raw = Swift.min(1, Swift.max(0, fill)) * max
        guard step > 0 else { return raw }
        return Swift.min(max, Swift.max(0, (raw / step).rounded() * step))
    }

    /// How many step lines were crossed between two values: one detent tap
    /// for each.
    static func stepsCrossed(from: Double, to: Double, step: Double) -> Int {
        guard step > 0, from != to else { return 0 }
        let epsilon = step * 1e-6
        let low = Int(((Swift.min(from, to) + epsilon) / step).rounded(.down))
        let high = Int(((Swift.max(from, to) + epsilon) / step).rounded(.down))
        return Swift.max(0, high - low)
    }

    /// The day's row of glasses: how full each one is, the goal cut into
    /// 250 ml glasses, the last one partly full.
    static func glasses(total: Double, goal: Double) -> [Double] {
        let count = Swift.max(1, Int((goal / glassMl).rounded(.up)))
        return (0..<count).map { index in
            fill(forValue: total - Double(index) * glassMl, max: glassMl)
        }
    }

    /// "1.6", "2", "0.25": litres with at most two decimals and none trailing.
    static func litres(_ ml: Double) -> String {
        let litres = ml / 1000
        let rounded = (litres * 10).rounded() / 10
        return rounded == rounded.rounded() ? "\(Int(rounded))" : String(format: "%.1f", rounded)
    }
}
