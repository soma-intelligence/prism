//
//  PulseTodayLayoutTests.swift
//  PrismTests
//

import Testing
import SomaUI
@testable import Prism

/// Today's cards and its foot after the 2026-10-19 redesign: last night shows
/// by default, drawn as its stages without the score, and the foot opens every
/// aspect's readings.
@MainActor
struct PulseTodayLayoutTests {
    @Test("Last night is on Today by default, among the top cards, not under Your aspects")
    func sleepShowsByDefault() {
        let layout = HomeTodayLayout.standard
        #expect(layout.shown == [.tonight, .sleep, .energy, .today])
        #expect(!layout.hidden.contains(.sleep))
        #expect(!HomeTodayCard.sleep.isAspect)
    }

    @Test("A layout stored before the redesign keeps the person's choice")
    func storedLayoutIsKept() {
        let stored = HomeTodayLayout(stored: "tonight,energy,today|sleep,heart,body,nutrition,stand,cycle,environment")
        #expect(stored.shown == [.tonight, .energy, .today])
        #expect(stored.hidden.contains(.sleep))
    }

    @Test("The foot's grid holds the six aspects once each, and each opens its own page")
    func footOpensEveryAspect() {
        #expect(Set(HomeTodayFoot.order) == Set(SomaAspect.allCases))
        #expect(HomeTodayFoot.order.count == SomaAspect.allCases.count)
        #expect(Set(HomeTodayFoot.order.map(TodayRoutes.tile)).count == SomaAspect.allCases.count)
    }
}
