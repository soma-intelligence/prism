//
//  SomaMoodFacesTests.swift
//  SomaUITests
//

import Testing
import SwiftUI
@testable import SomaUI

@Suite("Mood faces and Mind glyphs")
struct SomaMoodFacesTests {
    @Test("Five moods from rough to great, the mouth turning up as they go")
    func moods() {
        #expect(SomaMood.allCases.count == 5)
        let bends = SomaMood.allCases.map(SomaMoodFaceShape.curve)
        #expect(bends == bends.sorted())
        #expect(bends.first! < 0 && bends.last! > 0)
        #expect(SomaMood.rough.tone != SomaMood.great.tone)
    }

    @Test("Every face and every Mind glyph stays on the 24 unit grid")
    func outlinesFitTheGrid() {
        let outlines = SomaMood.allCases.map(SomaMoodFaceShape.outline) + SomaMindGlyph.Kind.allCases.map(SomaMindGlyphShape.outline)
        for outline in outlines {
            let bounds = outline.boundingRect
            #expect(!bounds.isEmpty)
            #expect(bounds.minX >= 2 && bounds.minY >= 2 && bounds.maxX <= 22 && bounds.maxY <= 22, "\(bounds)")
        }
    }
}
