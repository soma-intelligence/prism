//
//  SomaAspectGlyphTests.swift
//  SomaUITests
//

import Testing
import SwiftUI
@testable import SomaUI

@Suite("Aspect glyphs")
struct SomaAspectGlyphTests {
    @Test("Every aspect has an outline, and it stays on the 24 unit grid")
    func outlinesFitTheGrid() {
        for aspect in SomaAspect.allCases {
            let bounds = SomaAspectGlyphShape.outline(aspect).boundingRect
            #expect(!bounds.isEmpty, "\(aspect) draws nothing")
            #expect(bounds.minX >= 2 && bounds.minY >= 2, "\(aspect) runs off the grid")
            #expect(bounds.maxX <= 22 && bounds.maxY <= 22, "\(aspect) runs off the grid")
        }
    }

    @Test("The crescent's two circles cross, so it is drawn as a moon and not its fallback disc")
    func crescentIsAMoon() {
        let crescent = SomaAspectGlyphShape.crescent.boundingRect
        let fallback = Path(ellipseIn: CGRect(x: 3.5, y: 4.5, width: 16, height: 16)).boundingRect
        #expect(crescent != fallback)
    }

    @Test("Fitted to a frame of the wrong proportions, a glyph stays square and centred")
    func fitsSquare() {
        let path = SomaAspectGlyphShape(aspect: .heart).path(in: CGRect(x: 0, y: 0, width: 96, height: 48))
        let bounds = path.boundingRect
        #expect(bounds.minX > 24 && bounds.maxX < 72)
    }
}
