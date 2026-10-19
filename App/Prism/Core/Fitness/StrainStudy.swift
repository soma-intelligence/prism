//
//  StrainStudy.swift
//  Prism
//

import Foundation

/// Days of strain against the target band.
///
/// Every finished day with any strain
/// counts once, below, inside or above the band. Today is left out of the
/// tally because it is still filling: counting it would add a day below the
/// target every morning and take it away again after the session.
nonisolated struct StrainStudy: Equatable, Sendable {
    var below = 0
    var inside = 0
    var above = 0

    var counted: Int { below + inside + above }

    /// `series` is daily strain, oldest first, the last value today.
    init(series: [Double?], target: ClosedRange<Int>) {
        for value in series.dropLast().compactMap({ $0 }) where value > 0.5 {
            let rounded = Int(value.rounded())
            if rounded < target.lowerBound {
                below += 1
            } else if rounded > target.upperBound {
                above += 1
            } else {
                inside += 1
            }
        }
    }

    func share(_ days: Int) -> Double { counted == 0 ? 0 : Double(days) / Double(counted) }

    /// The mean strain over the last `days` days that carry a value.
    static func average(_ series: [Double?], days: Int) -> Double? {
        let values = series.suffix(days).compactMap { $0 }
        return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }
}
