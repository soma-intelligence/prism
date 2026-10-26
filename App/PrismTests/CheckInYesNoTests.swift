//
//  CheckInYesNoTests.swift
//  PrismTests
//

import Foundation
import Testing
@testable import Prism

/// "Soma asks" asks only yes or no, as Whoop's journal does (owner,
/// 2026-10-24). The questions that were scales still feed the places that
/// keep a scale: a yes lands on the high end, a no on the low end.
@Suite("Soma asks: yes or no")
@MainActor
struct CheckInYesNoTests {
    @Test("Every question in the catalog is a yes or no")
    func catalogIsYesNo() {
        for question in CheckInCatalog.all {
            #expect(question.kind == .yesNo, "\(question.id) is not a yes or no")
        }
    }

    @Test("A yes is the scale's high end, a no its low end, a step stays itself")
    func steps() {
        #expect(CheckInAnswer.yes.step == 4)
        #expect(CheckInAnswer.no.step == 2)
        #expect(CheckInAnswer.scale(5).step == 5)
        #expect(CheckInAnswer.number(3).step == nil)
    }

    @Test("Energy and stress answered yes or no reach the Home check-in")
    func homeCheckIn() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let checkIn = CheckInEngine.homeCheckIn(from: ["energy": .no, "stress": .yes], over: nil, on: now)
        #expect(checkIn?.energy == 2)
        #expect(checkIn?.stress == 4)
    }
}
