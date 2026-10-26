//
//  ChartScale.swift
//  Prism
//
//  Round scales for the paged charts: the top of a scale on a gridline a
//  person can read (10,000 steps, not 10,437), and four or five gridlines
//  between the foot and the top.
//

import Foundation

extension MetricDetailMath {
    /// The step between gridlines for a span of `span`: 1, 2, 2.5 or 5 times
    /// a power of ten, chosen so the span holds about `count` steps.
    static func niceStep(_ span: Double, count: Int = 4) -> Double {
        guard span > 0, span.isFinite else { return 1 }
        let raw = span / Double(max(1, count))
        let power = pow(10, floor(log10(raw)))
        let fraction = raw / power
        let nice: Double = fraction <= 1 ? 1 : fraction <= 2 ? 2 : fraction <= 2.5 ? 2.5 : fraction <= 5 ? 5 : 10
        return nice * power
    }

    /// `domain` widened to whole steps: the top up and the foot down to the
    /// nearest gridline, a foot at zero kept at zero, and never past
    /// `ceiling` (a percentage stays under 100).
    ///
    /// Of three to six gridlines, the count that wastes the least room above
    /// the data wins: 9,840 steps reads on a 12,000 top, not 15,000.
    static func niceDomain(_ domain: ClosedRange<Double>, ceiling: Double?) -> ClosedRange<Double> {
        var best: ClosedRange<Double>?
        for count in 3...6 {
            let step = niceStep(domain.upperBound - domain.lowerBound, count: count)
            var low = (domain.lowerBound / step).rounded(.down) * step
            var high = (domain.upperBound / step).rounded(.up) * step
            if domain.lowerBound >= 0 { low = max(0, low) }
            if let ceiling { high = min(high, ceiling) }
            if high <= low { high = low + step }
            if let current = best, current.upperBound - current.lowerBound <= high - low { continue }
            best = low...high
        }
        return best ?? domain
    }

    /// The gridlines of a round domain, foot to top: the same three to six
    /// steps ``niceDomain(_:ceiling:)`` chose, so the top line sits on the top.
    static func niceTicks(_ domain: ClosedRange<Double>) -> [Double] {
        let span = domain.upperBound - domain.lowerBound
        let step = (3...6).map { niceStep(span, count: $0) }
            .first { ((span / $0) - (span / $0).rounded()).magnitude < 0.001 } ?? niceStep(span)
        var ticks: [Double] = []
        var value = (domain.lowerBound / step).rounded(.up) * step
        while value <= domain.upperBound + step * 0.001, ticks.count < 12 {
            ticks.append(value)
            value += step
        }
        return ticks
    }
}
