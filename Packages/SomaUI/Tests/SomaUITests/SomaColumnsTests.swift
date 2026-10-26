//
//  SomaColumnsTests.swift
//  SomaUITests
//

import CoreGraphics
import Testing
@testable import SomaUI

/// How many card columns a width holds, at the sizes the app meets: a phone,
/// the two screens of a foldable, an iPad mini and a Split View third.
@Suite("Card columns")
struct SomaColumnsTests {
    private let metrics = SomaMetrics.standard

    private func columns(_ width: CGFloat) -> Int {
        SomaColumnsLayout.columnCount(
            width: width - metrics.pagePadding * 2,
            minColumnWidth: metrics.cardColumnMinWidth,
            spacing: metrics.cardSpacing,
            maxColumns: metrics.cardColumnLimit
        )
    }

    @Test("A phone in portrait, and a Split View third, read in one column")
    func phone() {
        #expect(columns(320) == 1)
        #expect(columns(402) == 1)
        #expect(columns(440) == 1)
    }

    @Test("A foldable's inner screen and an iPad mini get two")
    func roomy() {
        #expect(columns(626) == 2)
        #expect(columns(744) == 2)
        #expect(columns(1133) == 2)
    }

    @Test("The count holds at one for a width it cannot read")
    func degenerate() {
        #expect(SomaColumnsLayout.columnCount(width: 0, minColumnWidth: 280, spacing: 12, maxColumns: 2) == 1)
        #expect(SomaColumnsLayout.columnCount(width: .infinity, minColumnWidth: 280, spacing: 12, maxColumns: 2) == 1)
        #expect(SomaColumnsLayout.columnCount(width: 2000, minColumnWidth: 280, spacing: 12, maxColumns: 0) == 1)
    }

    @Test("Two panes from the theme's line, one below it")
    func widthClass() {
        #expect(SomaWidthClass(width: metrics.twoPaneMinWidth, metrics: metrics) == .regular)
        #expect(SomaWidthClass(width: metrics.twoPaneMinWidth - 1, metrics: metrics) == .compact)
    }
}
