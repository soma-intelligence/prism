//
//  SomaStageBreakdownTests.swift
//  SomaUITests
//

import CoreGraphics
import Testing
@testable import SomaUI

@Suite("Stage breakdown")
struct SomaStageBreakdownTests {
    @Test("The stages shown and their gaps fill the bar exactly, deepest first")
    func fillsTheBar() {
        let widths = SomaStageBreakdown.widths([.deep: 1_800, .core: 3_600, .rem: 1_800, .awake: 0],
                                               width: 306, gap: 3)
        #expect(widths.count == 4)
        // Three stages shown, so two gaps: 300 points shared by time.
        #expect(abs(widths[0] - 75) < 0.001)
        #expect(abs(widths[1] - 150) < 0.001)
        #expect(abs(widths[2] - 75) < 0.001)
        #expect(widths[3] == 0)
    }

    @Test("A night with no time draws an empty bar")
    func emptyNight() {
        #expect(SomaStageBreakdown.widths([:], width: 300, gap: 3) == [0, 0, 0, 0])
    }
}
