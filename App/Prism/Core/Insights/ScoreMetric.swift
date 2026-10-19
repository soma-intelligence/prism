//
//  ScoreMetric.swift
//  Prism
//
//  The metrics with a detail page that are not HealthKit types: Soma's
//  scores and what the scoring engine works out of a night. Each reads its
//  daily history from ``SomaScores/Detail``.
//

import Foundation

enum ScoreMetric: String, CaseIterable, Hashable, Identifiable, Sendable {
    case sleepScore, recovery, strain, stress, energy, remHours, deepHours, sleepDebt, bedtime, wakeTime

    var id: String { rawValue }

    /// The key its profile is filed under in ``MetricProfile``.
    var identifier: String { "soma.score." + rawValue }

    var title: String {
        switch self {
        case .sleepScore: "Sleep score"
        case .recovery: "Recovery"
        case .strain: "Strain"
        case .stress: "Stress"
        case .energy: "Energy bank"
        case .remHours: "REM sleep"
        case .deepHours: "Deep sleep"
        case .sleepDebt: "Sleep debt"
        case .bedtime: "Bedtime"
        case .wakeTime: "Wake time"
        }
    }

    /// What the number counts, nil when it reads as a clock or explains itself.
    var unit: String? {
        switch self {
        case .sleepScore, .recovery, .strain, .stress, .energy: "of 100"
        case .remHours, .deepHours, .sleepDebt, .bedtime, .wakeTime: nil
        }
    }

    /// Read as hours and minutes (a duration) rather than a number.
    var isDuration: Bool { self == .remHours || self == .deepHours || self == .sleepDebt }
    /// Read as a time of day: an hour past midnight, above 24 after it.
    var isClock: Bool { self == .bedtime || self == .wakeTime }

    /// One value per day, oldest first, ending today.
    func days(_ scores: SomaScores) -> [Double?] {
        let detail = scores.detail
        return switch self {
        case .sleepScore: detail.sleep
        case .recovery: detail.recovery
        case .strain: detail.strain
        case .stress: detail.stress
        case .energy: detail.energyEnd
        case .remHours: detail.remHours
        case .deepHours: detail.deepHours
        case .sleepDebt: detail.sleepDebtHours
        case .bedtime: detail.bedHour
        case .wakeTime: detail.wakeHour
        }
    }

    /// The band its page draws: the profile's fixed zone, or for strain the
    /// day's personal target.
    func profile(_ scores: SomaScores?) -> MetricProfile {
        var profile = MetricProfile.of(identifier)
        if self == .strain, let target = scores?.strainTarget {
            profile.referenceBand = Double(target.lowerBound)...Double(target.upperBound)
        }
        return profile
    }
}
