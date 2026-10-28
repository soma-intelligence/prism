//
//  SomaSleepDebtChartTests.swift
//  SomaUITests
//

import Testing
@testable import SomaUI

@Suite("Sleep debt chart")
struct SomaSleepDebtChartTests {
    @Test("Zero is always on the scale, so the bars stand on a line and the debt rises from it")
    func zeroOnScale() throws {
        let scale = try #require(SomaSleepDebtChart.scale(debt: [1.5, 2.5, 3.2], shortfall: [0.5, 1, 0.7]))
        #expect(scale.domain.lowerBound <= 0)
        #expect(scale.domain.upperBound >= 3.2)
    }

    @Test("A night over the need reaches below zero")
    func surplus() throws {
        let scale = try #require(SomaSleepDebtChart.scale(debt: [0.2, 0], shortfall: [-1.2, 0.4]))
        #expect(scale.domain.lowerBound <= -1.2)
    }

    @Test("Nothing recorded has no scale, and the plot keeps its empty grid")
    func empty() {
        #expect(SomaSleepDebtChart.scale(debt: [nil, nil], shortfall: [nil]) == nil)
    }
}
