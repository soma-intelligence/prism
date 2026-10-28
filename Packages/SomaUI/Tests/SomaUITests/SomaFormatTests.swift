//
//  SomaFormatTests.swift
//  SomaUITests
//

import Foundation
import SwiftUI
import Testing
@testable import SomaUI

@Suite("Format")
struct SomaFormatTests {
    let english = Locale(identifier: "en_US")

    @Test("A duration reads in narrow units, whole minutes, a zero part left out")
    func duration() {
        #expect(SomaFormat.duration(7 * 3_600 + 54 * 60, locale: english) == "7h 54m")
        #expect(SomaFormat.duration(45 * 60, locale: english) == "45m")
        #expect(SomaFormat.duration(12 * 3_600, locale: english) == "12h")
        // Rounded to the nearest minute, never below zero.
        #expect(SomaFormat.duration(7 * 3_600 + 53 * 60 + 40, locale: english) == "7h 54m")
        #expect(SomaFormat.duration(-30, locale: english) == "0m")
    }

    @Test("Nothing measured stays nil, so the view draws the missing mark")
    func missing() {
        let none: TimeInterval? = nil
        #expect(SomaFormat.duration(none, locale: english) == nil)
        let noNumber: Double? = nil
        #expect(SomaFormat.number(noNumber, locale: english) == nil)
    }

    @Test("A hero's duration splits into figures and the locale's units")
    func parts() {
        let parts = SomaFormat.durationParts(7 * 3_600 + 54 * 60, locale: english)
        #expect(parts == [.init(value: "7", unit: "h"), .init(value: "54", unit: "m")])
        #expect(SomaFormat.durationParts(45 * 60, locale: english) == [.init(value: "45", unit: "m")])
    }

    @Test("A number is grouped the locale's way, to the places asked for")
    func number() {
        #expect(SomaFormat.number(8_412, locale: english) == "8,412")
        #expect(SomaFormat.number(36.54, decimals: 1, locale: english) == "36.5")
    }

    @Test("Above or below the usual reads good on the better side, watch on the other, neutral when neither")
    func direction() {
        #expect(SomaBetterSide.higher.tone(.above) == .good)
        #expect(SomaBetterSide.higher.tone(.below) == .watch)
        #expect(SomaBetterSide.lower.tone(.above) == .watch)
        #expect(SomaBetterSide.lower.tone(.below) == .good)
        #expect(SomaBetterSide.neither.tone(.above) == .neutral)
        let recovery = SomaReadingStatus.outside(.above, better: .higher)
        #expect(recovery.word.map { String(localized: $0) } == "Above your usual")
        #expect(SomaReadingStatus.outside(.below, better: .lower).word.map { String(localized: $0) } == "Below your usual")
    }
}
