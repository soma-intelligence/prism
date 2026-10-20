//
//  SomaArticleCoverTests.swift
//  SomaUITests
//

import Testing
import SwiftUI
@testable import SomaUI

@Suite("Article cover")
struct SomaArticleCoverTests {
    private let seeds = (0..<200).map { "article-\($0)" }

    @Test("A seed draws the same cover every time")
    func deterministic() {
        #expect(SomaArticleCoverArt(seed: "sleep-regularity") == SomaArticleCoverArt(seed: "sleep-regularity"))
        #expect(SomaArticleCoverArt(seed: "sleep-regularity") != SomaArticleCoverArt(seed: "deep-sleep"))
    }

    @Test("A library of covers uses every composition, none of them most of the time")
    func varied() {
        let counts = Dictionary(grouping: seeds.map { SomaArticleCoverArt(seed: $0).composition }, by: { $0 }).mapValues(\.count)
        #expect(Set(counts.keys) == Set(SomaArticleCoverArt.Composition.allCases))
        #expect(counts.values.allSatisfy { $0 < seeds.count / 2 })
    }

    @Test("The glyph sits on the cover, clear of its edges, and rings have room")
    func placed() {
        for seed in seeds {
            let art = SomaArticleCoverArt(seed: seed)
            #expect((0.1...0.9).contains(art.glyph.x), "\(seed)")
            #expect((0.1...0.9).contains(art.glyph.y), "\(seed)")
            #expect(!art.rings.isEmpty)
            #expect(art.rings.allSatisfy { $0.radius > 0 && $0.strength > 0 && $0.strength <= 1 })
        }
    }

    @Test("The drifting second tone is never the cover's own tone")
    func drift() {
        for seed in seeds {
            let art = SomaArticleCoverArt(seed: seed)
            for tone in SomaTrackTone.allCases {
                #expect(art.drift(from: tone) != tone)
            }
        }
    }

    @Test("The wash runs corner to opposite corner")
    func wash() {
        for seed in seeds {
            let art = SomaArticleCoverArt(seed: seed)
            #expect(art.washStart != art.washEnd)
            #expect(abs(art.washStart.x - art.washEnd.x) == 1 && abs(art.washStart.y - art.washEnd.y) == 1)
        }
    }
}
