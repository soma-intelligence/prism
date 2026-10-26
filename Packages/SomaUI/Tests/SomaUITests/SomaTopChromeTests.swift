//
//  SomaTopChromeTests.swift
//  SomaUITests
//

import Testing
import SwiftUI
@testable import SomaUI

@Suite("Top chrome")
struct SomaTopChromeTests {
    // MARK: Part switcher

    @Test("A swipe lands on the next part past a third of the width or on a flick, and never past the ends")
    func swipeLanding() {
        let land = { (index: Int, translation: CGFloat, velocity: CGFloat) in
            SomaPartMath.landing(from: index, count: 3, translation: translation, velocity: velocity,
                                 width: 400, reach: 0.32, flick: 420)
        }
        #expect(land(0, -200, 0) == 1)
        #expect(land(1, 200, 0) == 0)
        #expect(land(1, -60, 0) == 1)
        #expect(land(1, -60, -900) == 2)
        #expect(land(1, 60, 900) == 0)
        // A flick against the drag sends it back.
        #expect(land(1, -200, 900) == 1)
        #expect(land(0, 250, 900) == 0)
        #expect(land(2, -250, -900) == 2)
    }

    @Test("Past the first or last part the strip follows less and less")
    func swipeResists() {
        let near = SomaPartMath.resisted(40, width: 400)
        let far = SomaPartMath.resisted(400, width: 400)
        #expect(near > 0 && near < 40)
        #expect(far > near && far < 400 * 0.18)
        #expect(SomaPartMath.resisted(-40, width: 400) == -near)
    }

    @Test("The parts slide on a short smooth spring, and cross fade quickly under Reduce Motion")
    func partMotion() {
        let motion = SomaMotion.standard
        #expect(motion.partSwitch == .smooth(duration: 0.35))
        #expect(motion.partFadeDuration > 0 && motion.partFadeDuration < 0.3)
    }

    // MARK: Edge fade

    @Test("The fade is absent at rest and during a pull, and fully drawn once the page has gone up its ramp")
    func fadeRisesWithTheScroll() {
        #expect(SomaEdgeFade.strength(scrolled: -40, ramp: 44) == 0)
        #expect(SomaEdgeFade.strength(scrolled: 0, ramp: 44) == 0)
        #expect(SomaEdgeFade.strength(scrolled: 22, ramp: 44) == 0.5)
        #expect(SomaEdgeFade.strength(scrolled: 600, ramp: 44) == 1)
        #expect(SomaEdgeFade.strength(scrolled: 1, ramp: 0) == 1)
    }

    @Test("The ground is nearly solid at the top, falls steadily, and is clear at the bottom")
    func fadeStops() {
        let stops = SomaEdgeFade.stops(solidRun: 0.42, topOpacity: 0.97)
        #expect(stops.first?.location == 0)
        #expect(stops.first?.opacity == 0.97)
        #expect(stops.last?.location == 1)
        #expect(stops.last?.opacity == 0)
        for (above, below) in zip(stops, stops.dropFirst()) {
            #expect(below.location >= above.location)
            #expect(below.opacity <= above.opacity)
        }
        // Solid down to where the run ends.
        #expect(stops.contains { $0.location == 0.42 && $0.opacity == 0.97 })
    }

    // MARK: Notification glyph

    @Test("The bell stays on the 24 unit grid, and the unread dot sits clear of it")
    func bellFitsTheGrid() {
        let bounds = SomaNotificationGlyphShape.bell.boundingRect
        #expect(bounds.minX >= 2 && bounds.minY >= 2)
        #expect(bounds.maxX <= 22 && bounds.maxY <= 22)

        let dot = SomaNotificationGlyphShape.unreadDot
        #expect(dot.centre.x + dot.radius <= 24 && dot.centre.y - dot.radius >= 0)
        // The dot's centre is outside the dome, so the knockout only trims the
        // shoulder rather than eating the bell.
        let crown = CGPoint(x: 12, y: 5.2)
        #expect(hypot(dot.centre.x - crown.x, dot.centre.y - crown.y) > 6)
    }
}
