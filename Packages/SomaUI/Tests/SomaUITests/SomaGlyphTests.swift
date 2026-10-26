//
//  SomaGlyphTests.swift
//  SomaUITests
//

import SwiftUI
import Testing
@testable import SomaUI

@Suite("Glyphs")
struct SomaGlyphTests {
    @Test("Every glyph draws a line, inside its grid", arguments: SomaGlyph.Kind.allCases)
    func drawsInsideTheGrid(kind: SomaGlyph.Kind) {
        let outline = kind.outline
        #expect(!outline.stroke.isEmpty)
        let grid = SomaMetrics.touch.glyphGrid
        let bounds = outline.stroke.boundingRect.union(outline.fill.boundingRect)
        #expect(bounds.minX >= 0 && bounds.minY >= 0)
        #expect(bounds.maxX <= grid && bounds.maxY <= grid)
    }

    @Test("Every aspect has a glyph and a category ink")
    func aspectsAreCovered() {
        for aspect in SomaAspect.allCases {
            #expect(SomaGlyph.Kind(aspect).ink == SomaCategoryInk(aspect))
        }
    }

    @Test("A category ink clears 4.5:1 on a card, in both appearances", arguments: SomaCategoryInk.allCases)
    func categoryInkReads(ink: SomaCategoryInk) {
        let card = SomaColors.standard.surface
        #expect(contrast(ink.value.light, card.light) >= 4.5)
        #expect(contrast(ink.value.dark, card.dark) >= 4.5)
    }

    private func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        func luminance(_ rgb: UInt32) -> Double {
            func channel(_ shift: UInt32) -> Double {
                let c = Double((rgb >> shift) & 0xFF) / 255
                return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * channel(16) + 0.7152 * channel(8) + 0.0722 * channel(0)
        }
        let (l1, l2) = (luminance(a), luminance(b))
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }
}
