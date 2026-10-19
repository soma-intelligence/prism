//
//  SomaMarkTests.swift
//  SomaUITests
//

import SwiftUI
import Testing
@testable import SomaUI

@Suite("Mark")
struct SomaMarkTests {
    @Test("The trace parses whole: the arms, the dot, and every curve it spells")
    func traceParsesWhole() throws {
        let outline = try #require(SomaMarkShape.outline)

        var moves = 0
        var curves = 0
        var closes = 0
        outline.forEach { element in
            switch element {
            case .move: moves += 1
            case .curve: curves += 1
            case .closeSubpath: closes += 1
            default: break
            }
        }

        #expect(moves == 2)
        #expect(closes == 2)
        #expect(curves == SomaMarkShape.trace.filter { $0 == "C" }.count)
    }

    @Test("The trace reaches every edge of its box")
    func traceFillsItsBox() throws {
        let bounds = try #require(SomaMarkShape.outline).boundingRect

        #expect(abs(bounds.minX) < 1)
        #expect(abs(bounds.minY) < 1)
        #expect(abs(bounds.maxX - SomaMarkShape.box) < 1)
        #expect(abs(bounds.maxY - SomaMarkShape.box) < 1)
    }

    @Test("A wide frame gets a square mark in its centre, never a stretched one")
    func fitsAndCentres() {
        let bounds = SomaMarkShape()
            .path(in: CGRect(x: 0, y: 0, width: 300, height: 100))
            .boundingRect

        #expect(abs(bounds.width - bounds.height) < 1)
        #expect(abs(bounds.midX - 150) < 1)
        #expect(abs(bounds.midY - 50) < 1)
    }

    @Test("A command the parser does not read refuses the whole trace")
    func unknownCommandIsRefused() {
        #expect(SomaMarkShape.path(from: "M0 0L10 10Z") == nil)
    }

    @Test("The mark is smaller on the pointer scale")
    func pointerMarkIsSmaller() {
        #expect(SomaMetrics.pointer.markSize < SomaMetrics.touch.markSize)
    }
}
