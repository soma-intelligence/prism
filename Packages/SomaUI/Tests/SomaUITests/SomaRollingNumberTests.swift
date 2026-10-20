//
//  SomaRollingNumberTests.swift
//  SomaUITests
//

import Testing
import Foundation
@testable import SomaUI

@Suite("Rolling numbers and morphing sparklines")
struct SomaRollingNumberTests {
    @Test("The roll reads the number a formatted reading carries")
    func readsNumbers() {
        #expect(SomaRollingNumber.value(in: "58") == 58)
        #expect(SomaRollingNumber.value(in: "1,204") == 1204)
        #expect(SomaRollingNumber.value(in: "36.6") == 36.6)
        #expect(SomaRollingNumber.value(in: "36,6") == 36.6)
        #expect(SomaRollingNumber.value(in: "-0.4") == -0.4)
        #expect(SomaRollingNumber.value(in: "14°C") == 14)
        #expect(SomaRollingNumber.value(in: "40 to 85") == 40)
    }

    @Test("A dash or words carry no number")
    func noNumber() {
        #expect(SomaRollingNumber.value(in: nil) == nil)
        #expect(SomaRollingNumber.value(in: "-") == nil)
        #expect(SomaRollingNumber.value(in: "Good") == nil)
    }

    @Test("Every sparkline has the same number of points, so any two morph point for point")
    func sparkShapesMatch() {
        let week = SomaSparkShape.make([52, nil, 55, 58, nil, 61, 60], band: 50...60, samples: 24)
        let month = SomaSparkShape.make((0..<30).map { Double($0 % 7) + 50 }, band: nil, samples: 24)
        #expect(week.samples.count == 24)
        #expect(month.samples.count == 24)
        #expect(week.hasBand)
        #expect(!month.hasBand)
        #expect(week.samples.allSatisfy { (0...1).contains($0) })
    }

    @Test("One reading is a dot, none is nothing")
    func sparkShapeEdges() {
        let single = SomaSparkShape.make([nil, 4, nil], band: nil, samples: 24)
        #expect(single.isSingle)
        #expect(single.samples.isEmpty)
        let none = SomaSparkShape.make([nil, nil], band: 1...2, samples: 24)
        #expect(!none.isSingle)
        #expect(none.samples.isEmpty)
    }

    @Test("The updated note counts back from now in whole units")
    func updatedAgo() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let text = SomaUpdatedNote.ago(now.addingTimeInterval(-3 * 3_600 - 600), now: now)
        #expect(text.contains("3"))
        #expect(SomaUpdatedNote.ago(now.addingTimeInterval(60), now: now) == SomaUpdatedNote.ago(now, now: now))
    }
}
