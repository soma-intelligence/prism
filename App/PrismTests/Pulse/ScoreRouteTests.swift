//
//  ScoreRouteTests.swift
//  PrismTests
//

import Foundation
import Testing
import SomaUI
@testable import Prism

/// Which score page each aspect of Today opens, and the cache that lets a
/// second visit draw at once while a fresh read waits five minutes.
@Suite("Score routes")
@MainActor
struct ScoreRouteTests {
    @Test("Every aspect opens its own page (owner, 2026-10-20)")
    func aspects() {
        #expect(ScoreRoute.aspect(.sleep) == .sleep)
        #expect(ScoreRoute.aspect(.mind) == .mind)
        #expect(ScoreRoute.aspect(.activity) == .activity)
        #expect(ScoreRoute.aspect(.heart) == .heart)
        #expect(ScoreRoute.aspect(.gut) == .gut)
        #expect(ScoreRoute.aspect(.body) == .body)
    }

    @Test("A read is kept per set of parts, and stays fresh for five minutes")
    func cache() {
        let cache = ScoreInputsCache()
        let read = Date(timeIntervalSince1970: 1_791_028_800)
        let inputs = ScoreDetailInputs(now: read)

        #expect(cache.value(for: [.heart]) == nil)
        #expect(!cache.isFresh([.heart], now: read))

        cache.store(inputs, for: [.heart], now: read)
        #expect(cache.value(for: [.heart]) == inputs)
        #expect(cache.value(for: [.heart, .nights]) == nil)
        #expect(cache.isFresh([.heart], now: read.addingTimeInterval(ScoreInputsCache.freshFor - 1)))
        #expect(!cache.isFresh([.heart], now: read.addingTimeInterval(ScoreInputsCache.freshFor)))
    }
}
