//
//  FitnessAge.swift
//  Prism
//

import Foundation

/// Fitness age from Apple Health: the age at which the average person of your
/// sex has the VO2 max you have now (the HUNT study's idea, Nes 2013).
///
/// It needs one thing, a VO2 max reading. Sex sharpens it: without one, the
/// average of the two norms is used. Your own age is not an input, it is what
/// the answer is read against, so a missing date of birth never hides it.
///
/// The norms are the ones ``BiologicalAge`` scores VO2 max against (ACSM, by
/// decade), joined into one line, so the two pages never disagree on what a
/// reading is worth. The pod's own fitness age, from a visit, replaces this
/// one once it exists.
nonisolated enum FitnessAge {
    /// The age each norm is pinned to: the middle of its decade.
    static let anchors: [Double] = [25, 35, 45, 55, 65, 75]
    static let male: [Double] = [48, 44, 40, 36, 32, 28]
    static let female: [Double] = [42, 38, 34, 30, 26, 23]

    /// The youngest and oldest age the line answers with. Past them a
    /// reading says "fitter than a twenty year old" or "less fit than an
    /// eighty five year old", and a number would claim more than the norms
    /// hold.
    static let youngest = 20
    static let oldest = 85

    /// The average VO2 max at `age`, for `sex`, or the mean of the two norms
    /// when the sex is not known.
    static func norm(age: Double, sex: LabSex?) -> Double {
        let values: [Double] = switch sex {
        case .male: male
        case .female: female
        case nil: zip(male, female).map { ($0 + $1) / 2 }
        }
        return interpolate(age, xs: anchors, ys: values)
    }

    /// The fitness age for a VO2 max in ml/kg/min, or nil without one.
    static func estimate(vo2Max: Double?, sex: LabSex?) -> Int? {
        guard let vo2Max, vo2Max.isFinite, vo2Max > 0 else { return nil }
        let values: [Double] = switch sex {
        case .male: male
        case .female: female
        case nil: zip(male, female).map { ($0 + $1) / 2 }
        }
        // The norm falls with age, so the line is read backwards: VO2 max in,
        // age out. Reversed, both arrays rise.
        let age = interpolate(vo2Max, xs: values.reversed(), ys: anchors.reversed())
        return min(max(Int(age.rounded()), youngest), oldest)
    }

    /// Straight lines between the points, and the end segments carried on
    /// past them. `xs` rises.
    private static func interpolate(_ x: Double, xs: [Double], ys: [Double]) -> Double {
        guard xs.count >= 2, xs.count == ys.count else { return ys.first ?? 0 }
        var index = xs.count - 2
        for candidate in 0..<(xs.count - 1) where x <= xs[candidate + 1] {
            index = candidate
            break
        }
        let (x0, x1, y0, y1) = (xs[index], xs[index + 1], ys[index], ys[index + 1])
        return y0 + (x - x0) * (y1 - y0) / (x1 - x0)
    }
}

extension LabSex {
    /// The profile's answer as the norms read it: other, or prefer not to
    /// say, reads as not known, and the average of the two norms is used.
    nonisolated init?(_ sex: BiologicalSex?) {
        switch sex {
        case .male: self = .male
        case .female: self = .female
        case .other, nil: return nil
        }
    }
}
