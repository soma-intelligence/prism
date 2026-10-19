//
//  CardioFocus.swift
//  Prism
//

import Foundation

/// What a stretch of cardio trained: low aerobic time builds the base, high
/// aerobic time raises the ceiling, anaerobic time is short hard efforts.
///
/// Zones 1 and 2 are low aerobic,
/// zones 3 and 4 high aerobic, zone 5 anaerobic.
nonisolated struct CardioFocus: Equatable, Sendable {
    /// Minutes in zones 1 to 5, index 0 is zone 1.
    var zoneMinutes: [Double]

    enum Band: String, CaseIterable, Sendable, Identifiable {
        case low = "Low aerobic"
        case high = "High aerobic"
        case anaerobic = "Anaerobic"

        var id: String { rawValue }
        var title: String { rawValue }

        var zones: String {
            switch self {
            case .low: "Zones 1 and 2, builds the base"
            case .high: "Zones 3 and 4, raises the ceiling"
            case .anaerobic: "Zone 5, short hard efforts"
            }
        }
    }

    /// Zone minutes summed over the workouts that started inside `window`.
    init(workouts: [FitnessWorkout], in window: DateInterval) {
        var minutes = Array(repeating: 0.0, count: 5)
        for workout in workouts where window.contains(workout.start) {
            for (index, seconds) in workout.zoneSeconds.prefix(5).enumerated() {
                minutes[index] += seconds / 60
            }
        }
        zoneMinutes = minutes
    }

    init(zoneMinutes: [Double]) {
        self.zoneMinutes = zoneMinutes + Array(repeating: 0, count: max(0, 5 - zoneMinutes.count))
    }

    var total: Double { zoneMinutes.reduce(0, +) }

    func minutes(_ band: Band) -> Double {
        switch band {
        case .low: zoneMinutes[0] + zoneMinutes[1]
        case .high: zoneMinutes[2] + zoneMinutes[3]
        case .anaerobic: zoneMinutes[4]
        }
    }

    /// The band's whole percentage of the total, rounded to the nearest whole number.
    func percent(_ band: Band) -> Int {
        Int((minutes(band) / max(1, total) * 100).rounded())
    }

    /// The share of the total a band should hold in a good week: about 80 %
    /// easy, the polarised split endurance coaching aims for.
    static let easyShareTarget = 0.8

    /// Zone 2's usual weekly span: the least and the most over the `weeks`
    /// rolling weeks before the last seven days, counting only weeks that held
    /// a workout with heart rate. Nil with fewer than two such weeks.
    static func usualZoneTwo(_ workouts: [FitnessWorkout], now: Date, weeks: Int = 4) -> ClosedRange<Double>? {
        let week: TimeInterval = 7 * 86_400
        var totals: [Double] = []
        for offset in 1...weeks {
            let end = now.addingTimeInterval(-week * Double(offset))
            let window = DateInterval(start: end.addingTimeInterval(-week), end: end)
            let held = workouts.filter { window.contains($0.start) && $0.hasZones }
            guard !held.isEmpty else { continue }
            totals.append(CardioFocus(workouts: held, in: window).zoneMinutes[1])
        }
        guard totals.count >= 2, let low = totals.min(), let high = totals.max() else { return nil }
        return low...high
    }
}
