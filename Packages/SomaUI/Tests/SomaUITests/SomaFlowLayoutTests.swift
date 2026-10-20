//
//  SomaFlowLayoutTests.swift
//  SomaUITests
//

import CoreGraphics
import Testing
@testable import SomaUI

@Suite("SomaFlowLayout: lines that wrap, never wider than the line")
struct SomaFlowLayoutTests {
    @Test("Items wrap to the next line when the line is full")
    func wraps() {
        let sizes = Array(repeating: CGSize(width: 60, height: 30), count: 5)
        let frames = SomaFlowLayout.frames(for: sizes, width: 200, spacing: 10, lineSpacing: 8)
        #expect(frames.map(\.minY) == [0, 0, 0, 38, 38])
        #expect(frames[1].minX == 70)
        #expect(frames.allSatisfy { $0.maxX <= 200 })
    }

    @Test("An item wider than the line is held to the line")
    func clampsWideItems() {
        let frames = SomaFlowLayout.frames(for: [CGSize(width: 40, height: 20), CGSize(width: 500, height: 20)],
                                           width: 200, spacing: 8, lineSpacing: 8)
        #expect(frames[1].width == 200)
        #expect(frames[1].minX == 0 && frames[1].minY == 28)
    }
}
