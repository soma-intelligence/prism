//
//  EffectMathTests.swift
//  PrismTests
//

import Foundation
import Testing
@testable import Prism

struct EffectMathTests {
    private let calendar = Calendar(identifier: .gregorian)

    private func day(_ n: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: n))!
    }

    @Test func statesTheDeltaAndHowOftenItHeld() {
        var outcome: [Date: Double] = [:]
        for n in 1...6 { outcome[day(n)] = 40 }
        outcome[day(7)] = 46
        outcome[day(8)] = 44
        outcome[day(9)] = 39
        let effect = EffectMath.effect(causeDays: [day(7), day(8), day(9)], outcome: outcome, better: .higher)
        #expect(effect.delta == 4)
        #expect(effect.held == 2)
        #expect(effect.tries == 3)
        #expect(!effect.isCost(.higher))
    }

    @Test func waitsForEnoughDaysOnBothSides() {
        let outcome = [day(1): 40.0, day(2): 41, day(3): 50]
        let effect = EffectMath.effect(causeDays: [day(3)], outcome: outcome, better: .higher)
        #expect(effect.delta == nil)
        #expect(effect.tries == 1)
    }

    @Test func aRiseInALowerIsBetterReadingIsACost() {
        var outcome: [Date: Double] = [:]
        for n in 1...5 { outcome[day(n)] = 55 }
        for n in 6...8 { outcome[day(n)] = 58 }
        let effect = EffectMath.effect(causeDays: [day(6), day(7), day(8)], outcome: outcome, better: .lower)
        #expect(effect.delta == 3)
        #expect(effect.isCost(.lower))
    }
}

@MainActor
struct JournalStoreTests {
    @Test func togglesATagOnADayAndBack() {
        let store = JournalStore(url: nil)
        let date = Date()
        store.toggle("sauna", on: date)
        #expect(store.day(date).tags == ["sauna"])
        store.toggle("sauna", on: date)
        #expect(store.day(date).tags.isEmpty)
    }

    @Test func addingATitleAlreadyListedSwitchesItOn() {
        let store = JournalStore(url: nil)
        store.setOffered(false, tag: "nap")
        let tag = store.addTag("nap")
        #expect(tag?.id == "nap")
        #expect(store.tags.filter { $0.title == "Nap" }.count == 1)
        #expect(store.offeredTags.contains { $0.id == "nap" })
    }

    @Test func feelingIsClampedToTheSevenStops() {
        let store = JournalStore(url: nil)
        store.setFeeling(9, on: Date())
        #expect(store.day(Date()).feeling == 6)
    }
}
