//
//  SleepDebtSeriesTests.swift
//  PrismTests
//
//  The debt tile's fourteen nights: the debt carried and each night's own
//  shortfall, taken from the same daily series, aligned on last night.
//

import Foundation
import Testing
@testable import Prism

@Suite("Sleep debt series")
struct SleepDebtSeriesTests {
    @Test("Each night's shortfall is its need less its sleep, over the need below zero")
    func shortfall() {
        var detail = SomaScores.Detail()
        detail.sleepHours = [6, 8.5, nil]
        detail.sleepNeedHours = [7.5, 7.5, 7.5]
        detail.sleepDebtHours = [1.5, 0.5, 0.5]
        let series = SleepDebtSeries.make(detail, nights: 3)
        #expect(series.shortfall == [1.5, -1, nil])
        #expect(series.debt == [1.5, 0.5, 0.5])
        #expect(series.latest == 0.5)
    }

    @Test("Only the last fourteen nights are kept, and a short record is padded before, never after")
    func fourteen() {
        var detail = SomaScores.Detail()
        detail.sleepDebtHours = (0..<30).map { Double($0) }
        detail.sleepHours = Array(repeating: 7, count: 5)
        detail.sleepNeedHours = Array(repeating: 8, count: 5)
        let series = SleepDebtSeries.make(detail)
        #expect(series.debt.count == 14)
        #expect(series.debt.first == 16)
        #expect(series.debt.last == 29)
        #expect(series.shortfall.count == 14)
        #expect(series.shortfall.prefix(9).allSatisfy { $0 == nil })
        #expect(series.shortfall.last == 1)
    }

    @Test("A record with nothing in it is empty, so the tile draws an empty grid")
    func empty() {
        let series = SleepDebtSeries.make(SomaScores.Detail())
        #expect(series.isEmpty)
        #expect(series.latest == nil)
    }
}
