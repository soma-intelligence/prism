//
//  SomaChartMathTests.swift
//  SomaUITests
//

import Testing
import SwiftUI
@testable import SomaUI

@Suite("Metric chart geometry")
struct SomaChartMathTests {
    @Test("Slots: a centre per slot, and the slot under a point")
    func slots() {
        #expect(SomaChartMath.center(of: 0, count: 4) == 0.125)
        #expect(SomaChartMath.center(of: 3, count: 4) == 0.875)
        #expect(SomaChartMath.slot(at: 0.3, count: 4) == 1)
        #expect(SomaChartMath.slot(at: -1, count: 4) == 0)
        #expect(SomaChartMath.slot(at: 2, count: 4) == 3)
    }

    @Test("A finger on an empty slot reads the nearest one with a value")
    func nearestKnown() {
        let values: [Double?] = [1, nil, nil, 4, nil]
        #expect(SomaChartMath.nearestKnown(1, in: values) == 0)
        #expect(SomaChartMath.nearestKnown(2, in: values) == 3)
        #expect(SomaChartMath.nearestKnown(4, in: values) == 3)
        #expect(SomaChartMath.nearestKnown(0, in: [nil, nil]) == nil)
    }

    @Test("Heights are held inside the plot")
    func heights() {
        #expect(SomaChartMath.height(50, in: 0...100) == 0.5)
        #expect(SomaChartMath.height(150, in: 0...100) == 1)
        #expect(SomaChartMath.height(-5, in: 0...100) == 0)
        #expect(SomaChartMath.height(3, in: 3...3) == 0.5)
    }

    @Test("A curve runs from the first known value to the last and passes through each")
    func curveSpansKnown() {
        let curve = SomaChartMath.curve([nil, 20, 60, 40, nil], domain: 0...100, count: 5)
        #expect(curve.start == 0.3)
        #expect(abs(curve.end - 0.7) < 1e-9)
        #expect(curve.samples.count == 5)
        #expect(abs(curve.samples[0] - 0.2) < 1e-9)
        #expect(abs(curve.samples[2] - 0.6) < 1e-9)
        #expect(abs(curve.samples[4] - 0.4) < 1e-9)
    }

    @Test("Between two values the curve never overshoots them")
    func curveIsMonotone() {
        let curve = SomaChartMath.curve([10, 90, 95, 20], domain: 0...100, count: 61)
        #expect(curve.samples.allSatisfy { $0 >= 0.1 - 1e-9 && $0 <= 0.95 + 1e-9 })
    }

    @Test("One value is a flat stub; none is nothing to draw")
    func curveEdges() {
        let one = SomaChartMath.curve([nil, 50, nil, nil], domain: 0...100, count: 4)
        #expect(one.samples == [0.5, 0.5, 0.5, 0.5])
        #expect(one.end > one.start)
        #expect(SomaChartMath.curve([nil, nil], domain: 0...1, count: 4).isEmpty)
    }

    @Test("Bars thin out as a span holds more of them, within their bounds")
    func barWidth() {
        #expect(SomaChartMath.barWidth(count: 7, width: 300, share: 0.5, minimum: 2, maximum: 18) == 18)
        #expect(abs(SomaChartMath.barWidth(count: 30, width: 300, share: 0.5, minimum: 2, maximum: 18) - 5) < 1e-9)
        #expect(SomaChartMath.barWidth(count: 365, width: 300, share: 0.5, minimum: 2, maximum: 18) == 2)
    }

    @Test("Animatable samples add, subtract and scale, padding a shorter list")
    func vector() {
        var sum = SomaAnimatableVector([1, 2]) + SomaAnimatableVector([1, 1, 1])
        #expect(sum.values == [2, 3, 3])
        sum.scale(by: 2)
        #expect(sum.values == [4, 6, 6])
        #expect((SomaAnimatableVector([3, 3]) - SomaAnimatableVector([1, 2])).values == [2, 1])
        #expect(SomaAnimatableVector([3, 4]).magnitudeSquared == 25)
    }

    @Test("The highest and lowest are found among the readings, the latest left out when asked")
    func extremes() {
        let values: [Double?] = [5, 9, nil, 2, 7, 12]
        let all = SomaChartMath.extremes(values)
        #expect(all?.high == 5)
        #expect(all?.low == 3)
        let before = SomaChartMath.extremes(values, excluding: 5)
        #expect(before?.high == 1)
        #expect(before?.low == 3)
    }

    @Test("No high or low to name under three readings, or when they are all the same")
    func noExtremes() {
        #expect(SomaChartMath.extremes([4, nil, 6]) == nil)
        #expect(SomaChartMath.extremes([3, 3, 3, 3]) == nil)
        #expect(SomaChartMath.extremes([]) == nil)
    }
}
