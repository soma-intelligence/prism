//
//  BodyFitnessAge.swift
//  Prism
//

import Foundation

/// Fitness age from the watch: the age whose typical VO2 max matches yours.
///
/// The typical values are the ACSM decade means the aging pace tool reads
/// (`SomaTools.AgingBioAge.vo2MaxZ`), set at the middle of each decade and
/// joined by straight lines, so a VO2 max between two decades lands between
/// their ages. Past either end the line carries on at the slope of its last
/// decade, and the answer stays between 20 and 90.
///
/// VO2 max is the one input it needs. Your age is only what the result is
/// read against, and without a sex the two curves are averaged, as the
/// profile promises for "Other, or prefer not to say".
nonisolated enum BodyFitnessAge {
    enum Sex: Sendable, Equatable {
        case female, male, unknown
    }

    /// The middle of each decade the means describe.
    static let ages: [Double] = [25, 35, 45, 55, 65, 75]
    /// Typical VO2 max at those ages, in ml/kg/min.
    static let male: [Double] = [48, 44, 40, 36, 32, 28]
    static let female: [Double] = [42, 38, 34, 30, 26, 23]

    static let youngest = 20
    static let oldest = 90

    /// The typical curve for a sex: the average of the two when it is not
    /// known.
    static func curve(_ sex: Sex) -> [Double] {
        switch sex {
        case .male: male
        case .female: female
        case .unknown: zip(male, female).map { ($0 + $1) / 2 }
        }
    }

    /// The age, in whole years, at which the typical VO2 max equals
    /// `vo2Max`.
    static func estimate(vo2Max: Double, sex: Sex) -> Int {
        let typical = curve(sex)
        let age: Double
        if vo2Max >= typical[0] {
            let slope = (typical[0] - typical[1]) / (ages[1] - ages[0])
            age = ages[0] - (vo2Max - typical[0]) / slope
        } else if let last = typical.last, vo2Max <= last {
            let n = typical.count
            let slope = (typical[n - 2] - typical[n - 1]) / (ages[n - 1] - ages[n - 2])
            age = ages[n - 1] + (last - vo2Max) / slope
        } else {
            let i = typical.indices.dropLast().first { typical[$0] >= vo2Max && vo2Max >= typical[$0 + 1] } ?? 0
            let share = (typical[i] - vo2Max) / (typical[i] - typical[i + 1])
            age = ages[i] + share * (ages[i + 1] - ages[i])
        }
        return min(max(Int(age.rounded()), youngest), oldest)
    }

    /// What the Fitness age stat shows: the age and how it sits against
    /// yours, or what it is waiting for.
    struct Stat: Equatable, Sendable {
        var value: String?
        /// A few words under the value, or under the dash when it waits.
        var cue: String?
        /// True when the fitness age sits under your age.
        var isGood = false
    }

    /// The stat for the latest VO2 max, read against `age` when Health or
    /// the profile knows it.
    static func stat(vo2Max: Double?, age: Int?, sex: Sex) -> Stat {
        guard let vo2Max, vo2Max > 0 else { return Stat(value: nil, cue: "Needs VO2 max") }
        let fitness = estimate(vo2Max: vo2Max, sex: sex)
        guard let age else { return Stat(value: "\(fitness)", cue: nil) }
        let gap = fitness - age
        switch gap {
        case ..<0: return Stat(value: "\(fitness)", cue: "\(-gap) under your age", isGood: true)
        case 0: return Stat(value: "\(fitness)", cue: "Your age")
        default: return Stat(value: "\(fitness)", cue: "\(gap) over your age")
        }
    }
}

extension BodyFitnessAge.Sex {
    nonisolated init(_ sex: LabSex?) {
        switch sex {
        case .female: self = .female
        case .male: self = .male
        case nil: self = .unknown
        }
    }
}

extension LabSex {
    /// The profile's answer, nil for "Other, or prefer not to say".
    nonisolated init?(_ sex: BiologicalSex) {
        switch sex {
        case .female: self = .female
        case .male: self = .male
        case .other: return nil
        }
    }
}
