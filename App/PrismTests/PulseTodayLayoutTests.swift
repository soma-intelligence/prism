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

    @Test("Without a night the sleep card has no line and no stages, so it says what it waits for")
    func sleepCardWithoutANight() {
        #expect(PulseSleepCard.night(nil) == nil)
        #expect(PulseSleepCard.line(nil) == nil)
    }

    @Test("The foot's grid holds the six aspects once each, and each opens its page of readings")
    func footOpensEveryAspect() {
        #expect(Set(HomeTodayFoot.order) == Set(SomaAspect.allCases))
        #expect(HomeTodayFoot.order.count == SomaAspect.allCases.count)
        for aspect in HomeTodayFoot.order {
            guard case .category(let title) = PulseRoute.aspect(aspect) else { continue }
            #expect(BodyCatalog.categories.contains { $0.title == title }, "\(aspect) opens no page")
        }
    }
}
