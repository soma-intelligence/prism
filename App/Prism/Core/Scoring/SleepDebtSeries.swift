//
//  SleepDebtSeries.swift
//  Prism
//

import Foundation

/// The last fourteen nights of sleep debt, as the Sleep page's debt tile
/// draws them: the debt carried each night, and what that night alone fell
/// short of the need (below zero, what it slept over it).
///
/// Both come from the scores' own daily series, so a bar never contradicts
/// the line drawn over it, and a night with no record is nil in both.
struct SleepDebtSeries: Equatable, Sendable {
    /// Debt carried each night, in hours, oldest first.
    var debt: [Double?]
    /// Each night's need less its sleep, in hours, oldest first.
    var shortfall: [Double?]

    /// The nights the tile spans, as the debt itself does.
    static let nights = 14

    /// Last night's debt, when there is one.
    var latest: Double? { debt.last ?? nil }

    /// Whether any night has anything to draw.
    var isEmpty: Bool { !debt.contains { $0 != nil } && !shortfall.contains { $0 != nil } }

    /// The last `nights` of `detail`, the series aligned on their last day
    /// (last night) whatever their lengths.
    static func make(_ detail: SomaScores.Detail, nights: Int = nights) -> SleepDebtSeries {
        func tail(_ series: [Double?]) -> [Double?] {
            let kept = Array(series.suffix(nights))
            return Array(repeating: nil, count: nights - kept.count) + kept
        }
        let slept = tail(detail.sleepHours)
        let need = tail(detail.sleepNeedHours)
        let shortfall = zip(need, slept).map { need, slept -> Double? in
            guard let need, let slept else { return nil }
            return need - slept
        }
        return SleepDebtSeries(debt: tail(detail.sleepDebtHours), shortfall: shortfall)
    }
}
