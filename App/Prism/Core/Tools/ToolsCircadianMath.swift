//
//  ToolsCircadianMath.swift
//  Prism
//
//  Angular arithmetic on clock hours.
//

import Foundation

extension SomaTools {

    /// Angular arithmetic on clock hours in [0, 24). All circadian phase math
    /// lives on a 24-hour circle, so averaging and distance must wrap (23:00 and
    /// 01:00 average to midnight, not noon).
    nonisolated enum CircadianMath {

        /// Wrap any hour value into [0, 24).
        static func wrap24(_ hour: Double) -> Double {
            var x = hour.truncatingRemainder(dividingBy: 24)
            if x < 0 { x += 24 }
            return x
        }

        /// Circular mean of clock hours, in [0, 24). Returns nil when the mean is
        /// undefined: an empty input, or a near-antipodal/evenly-spread set whose
        /// resultant vector length is ~0 (e.g. [0, 12] or [6, 18]). atan2(0, 0)
        /// would otherwise report a confident but meaningless midnight.
        static func circularMeanHours(_ hours: [Double]) -> Double? {
            guard !hours.isEmpty else { return nil }
            let twoPi = 2 * Double.pi
            var s = 0.0, c = 0.0
            for h in hours {
                let a = h / 24 * twoPi
                s += sin(a)
                c += cos(a)
            }
            guard hypot(s, c) > 1e-9 else { return nil }
            let mean = atan2(s, c) / twoPi * 24
            return wrap24(mean)
        }

        /// Circular standard deviation of clock hours, in hours. Uses the
        /// resultant-vector length R: SD = sqrt(-2 ln R), scaled from radians to
        /// hours. Returns nil on an empty input or a near-zero resultant (an
        /// evenly-spread or antipodal set), which rejects degenerate cases like
        /// circularMeanHours does. The returned value grows without bound as
        /// dispersion increases; callers must clamp the result to their required
        /// range.
        static func circularStdDevHours(_ hours: [Double]) -> Double? {
            guard !hours.isEmpty else { return nil }
            let twoPi = 2 * Double.pi
            var s = 0.0, c = 0.0
            for h in hours {
                let a = h / 24 * twoPi
                s += sin(a)
                c += cos(a)
            }
            let r = hypot(s, c) / Double(hours.count)
            guard r > 1e-9 else { return nil }
            // Clamp R to <= 1 against floating error so log stays real.
            let rClamped = min(1.0, r)
            let sdRadians = sqrt(-2 * log(rClamped))
            return sdRadians / twoPi * 24
        }

        /// Shortest distance between two clock hours, in [0, 12].
        static func circularDistanceHours(_ a: Double, _ b: Double) -> Double {
            var d = abs(wrap24(a) - wrap24(b))
            if d > 12 { d = 24 - d }
            return d
        }

        /// Shortest SIGNED distance from `reference` to `hour` on the 24 h face, in
        /// (-12, 12]. Negative means `hour` falls earlier on the clock than
        /// `reference`, positive means later.
        ///
        /// The signed sibling of `circularDistanceHours`, for the cases that need to
        /// know which side of an anchor an hour sits on. Comparing wrapped clock
        /// hours with `<` and `>` instead is the classic midnight trap: 23:30 is one
        /// hour BEFORE 00:30, not twenty-three after.
        static func signedDeltaHours(from reference: Double, to hour: Double) -> Double {
            var d = wrap24(hour) - wrap24(reference)
            if d > 12 { d -= 24 }
            if d <= -12 { d += 24 }
            return d
        }
    }
}
