//
//  SomaChartMath.swift
//  SomaUI
//
//  The geometry behind a metric's chart, as pure functions over values so
//  each is tested without drawing: where a bucket sits, how a value maps to
//  the plot's height, and a series resampled to a fixed count of points so a
//  week can morph into a month.
//

import Foundation
import SwiftUI

/// A series of evenly spaced values, any of them missing, resampled to a
/// fixed count of points between its first and last known values.
public struct SomaChartCurve: Equatable, Sendable {
    /// Where the curve starts and ends, as shares of the plot's width.
    public var start: Double
    public var end: Double
    /// Heights as shares of the plot (0 at the foot, 1 at the top), evenly
    /// spaced from `start` to `end`.
    public var samples: [Double]

    public init(start: Double, end: Double, samples: [Double]) {
        self.start = start
        self.end = end
        self.samples = samples
    }

    /// Nothing to draw.
    public static func flat(count: Int) -> SomaChartCurve {
        SomaChartCurve(start: 0, end: 1, samples: Array(repeating: 0, count: max(2, count)))
    }

    public var isEmpty: Bool { samples.isEmpty }
}

public enum SomaChartMath {
    /// The centre of slot `index` of `count`, as a share of the width.
    public static func center(of index: Int, count: Int) -> Double {
        guard count > 0 else { return 0.5 }
        return (Double(index) + 0.5) / Double(count)
    }

    /// The slot under a point `x` shares of the width across.
    public static func slot(at x: Double, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return min(count - 1, max(0, Int((x * Double(count)).rounded(.down))))
    }

    /// The slot nearest `index` that holds a value, the slot itself first.
    public static func nearestKnown(_ index: Int, in values: [Double?]) -> Int? {
        guard !values.isEmpty else { return nil }
        for distance in 0..<values.count {
            for candidate in [index - distance, index + distance] where values.indices.contains(candidate) {
                if values[candidate] != nil { return candidate }
            }
        }
        return nil
    }

    /// A value as a share of the plot's height, held inside it.
    public static func height(_ value: Double, in domain: ClosedRange<Double>) -> Double {
        let span = domain.upperBound - domain.lowerBound
        guard span > 0 else { return 0.5 }
        return min(1, max(0, (value - domain.lowerBound) / span))
    }

    /// The series as a curve through its known values, `count` points long.
    ///
    /// The curve runs from the first known value's slot to the last one's,
    /// passes through every known value, and bends between them with a
    /// monotone cubic, so it never overshoots a peak the data did not reach.
    /// A single value is a flat stub one slot wide. Empty when nothing is
    /// known.
    public static func curve(_ values: [Double?], domain: ClosedRange<Double>, count: Int) -> SomaChartCurve {
        let known: [(x: Double, y: Double)] = values.enumerated().compactMap { index, value in
            value.map { (center(of: index, count: values.count), height($0, in: domain)) }
        }
        guard let first = known.first, let last = known.last, count >= 2 else {
            return SomaChartCurve(start: 0, end: 1, samples: [])
        }
        if known.count == 1 {
            let half = 0.5 / Double(values.count)
            return SomaChartCurve(start: first.x - half, end: first.x + half, samples: Array(repeating: first.y, count: count))
        }
        let slopes = monotoneSlopes(known)
        let samples = (0..<count).map { step -> Double in
            let x = first.x + (last.x - first.x) * Double(step) / Double(count - 1)
            return min(1, max(0, hermite(known, slopes: slopes, at: x)))
        }
        return SomaChartCurve(start: first.x, end: last.x, samples: samples)
    }

    /// Fritsch and Carlson's tangents: the curve between two points stays
    /// between their heights.
    static func monotoneSlopes(_ points: [(x: Double, y: Double)]) -> [Double] {
        let n = points.count
        guard n > 1 else { return [0] }
        var secants: [Double] = []
        for index in 0..<(n - 1) {
            let dx = points[index + 1].x - points[index].x
            secants.append(dx > 0 ? (points[index + 1].y - points[index].y) / dx : 0)
        }
        var slopes = [Double](repeating: 0, count: n)
        slopes[0] = secants[0]
        slopes[n - 1] = secants[n - 2]
        if n > 2 {
            for index in 1..<(n - 1) {
                let before = secants[index - 1], after = secants[index]
                slopes[index] = before * after <= 0 ? 0 : (before + after) / 2
            }
        }
        for index in 0..<(n - 1) where secants[index] == 0 {
            slopes[index] = 0
            slopes[index + 1] = 0
        }
        for index in 0..<(n - 1) where secants[index] != 0 {
            let a = slopes[index] / secants[index]
            let b = slopes[index + 1] / secants[index]
            let length = a * a + b * b
            if length > 9 {
                let scale = 3 / length.squareRoot()
                slopes[index] = scale * a * secants[index]
                slopes[index + 1] = scale * b * secants[index]
            }
        }
        return slopes
    }

    static func hermite(_ points: [(x: Double, y: Double)], slopes: [Double], at x: Double) -> Double {
        guard let upper = points.firstIndex(where: { $0.x >= x }) else { return points.last?.y ?? 0 }
        if upper == 0 { return points[0].y }
        let lower = upper - 1
        let p0 = points[lower], p1 = points[upper]
        let h = p1.x - p0.x
        guard h > 0 else { return p1.y }
        let t = (x - p0.x) / h
        let t2 = t * t, t3 = t2 * t
        return (2 * t3 - 3 * t2 + 1) * p0.y + (t3 - 2 * t2 + t) * h * slopes[lower]
            + (-2 * t3 + 3 * t2) * p1.y + (t3 - t2) * h * slopes[upper]
    }

    /// The width of one bar for `count` slots across `width` points.
    public static func barWidth(count: Int, width: CGFloat, share: CGFloat, minimum: CGFloat, maximum: CGFloat) -> CGFloat {
        guard count > 0 else { return minimum }
        return min(maximum, max(minimum, width / CGFloat(count) * share))
    }
}

// MARK: - Animatable samples

/// A list of numbers SwiftUI can interpolate, so a curve glides from one
/// shape to another. Lists of different lengths meet at the longer one's
/// length: the shorter is padded with its last value, or with zeros when it
/// is empty.
public struct SomaAnimatableVector: VectorArithmetic, Sendable {
    public var values: [Double]

    public init(_ values: [Double]) { self.values = values }

    public static var zero: SomaAnimatableVector { SomaAnimatableVector([]) }

    private static func paired(_ lhs: [Double], _ rhs: [Double]) -> ([Double], [Double]) {
        let count = max(lhs.count, rhs.count)
        func padded(_ values: [Double]) -> [Double] {
            values.count == count ? values : values + Array(repeating: values.last ?? 0, count: count - values.count)
        }
        return (padded(lhs), padded(rhs))
    }

    public static func + (lhs: SomaAnimatableVector, rhs: SomaAnimatableVector) -> SomaAnimatableVector {
        let (a, b) = paired(lhs.values, rhs.values)
        return SomaAnimatableVector(zip(a, b).map(+))
    }

    public static func - (lhs: SomaAnimatableVector, rhs: SomaAnimatableVector) -> SomaAnimatableVector {
        let (a, b) = paired(lhs.values, rhs.values)
        return SomaAnimatableVector(zip(a, b).map(-))
    }

    public mutating func scale(by rhs: Double) {
        values = values.map { $0 * rhs }
    }

    public var magnitudeSquared: Double { values.reduce(0) { $0 + $1 * $1 } }
}
