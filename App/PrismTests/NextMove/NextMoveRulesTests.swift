//
//  NextMoveRulesTests.swift
//  PrismTests
//

import Foundation
import Testing
@testable import Prism

/// Each Next move rule on its own, at the edge where it starts to speak. The
/// arbiter's tests read the winner; these read the rule, so a threshold that
/// drifts by one fails here even when another rule would have won anyway.
/// Every move a rule makes is also held to the card's contract: its id
/// starts with the rule's, it sits in the rule's domain, and it carries a
/// receipt.
@Suite("Next move rules")
@MainActor
struct NextMoveRulesTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }()

    func context(_ hour: Int, _ minute: Int = 0) -> NextMoveContext {
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 26, hour: hour, minute: minute))!
        return NextMoveContext(now: now, calendar: calendar)
    }

    /// The rule's move for `ctx`, checked against the card's contract.
    func move(_ rule: some NextMoveRule, _ ctx: NextMoveContext,
              sourceLocation: SourceLocation = #_sourceLocation) -> NextMoveCandidate? {
        let candidate = rule.evaluate(ctx)
        if let candidate {
            #expect(candidate.id.hasPrefix(rule.id + "."), sourceLocation: sourceLocation)
            #expect(candidate.domain == rule.domain, sourceLocation: sourceLocation)
            #expect(!candidate.evidence.isEmpty, sourceLocation: sourceLocation)
        }
        return candidate
    }

    @Test("Every rule in the catalog has its own id")
    func catalogIDs() {
        let ids = NextMoveRules.catalog.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test("Resting heart rate speaks from five above the usual, and is urgent from ten")
    func restingHeartRate() {
        var ctx = context(10)
        ctx.restingHeartRateBaseline = 56
        // The rise is read in whole beats: 4.4 is four, 4.9 is already five.
        ctx.restingHeartRate = 60.4
        #expect(move(RestingHeartRateRule(), ctx) == nil)

        ctx.restingHeartRate = 61
        let rising = move(RestingHeartRateRule(), ctx)
        #expect(rising?.tier == .improve)
        #expect(rising?.evidence == [NextMoveEvidence(label: "Resting heart rate", value: "61 against 56 bpm")])

        ctx.restingHeartRate = 66
        #expect(move(RestingHeartRateRule(), ctx)?.tier == .urgent)

        ctx.restingHeartRateBaseline = 0
        #expect(move(RestingHeartRateRule(), ctx) == nil)
    }

    @Test("Recovery speaks from eight under the usual, is urgent from twenty five, and shows HRV when it is known")
    func recoveryDeficit() {
        var ctx = context(10)
        ctx.recoveryObjective = 60
        ctx.recoveryScore = 53
        #expect(move(RecoveryDeficitRule(), ctx) == nil)

        ctx.recoveryScore = 52
        let low = move(RecoveryDeficitRule(), ctx)
        #expect(low?.tier == .improve)
        #expect(low?.evidence == [NextMoveEvidence(label: "Recovery against your usual", value: "52 of 60")])

        ctx.recoveryScore = 35
        ctx.hrv = 38.4
        ctx.hrvBaseline = 51.6
        let urgent = move(RecoveryDeficitRule(), ctx)
        #expect(urgent?.tier == .urgent)
        #expect(urgent?.evidence.last == NextMoveEvidence(label: "HRV", value: "38 against 52 ms"))
    }

    @Test("Water speaks from 400 ml short, asks a round amount, and keeps to the afternoon")
    func hydration() {
        var ctx = context(14)
        ctx.waterTargetMl = 2_200
        ctx.waterMl = 1_801
        #expect(move(HydrationGapRule(), ctx) == nil)

        ctx.waterMl = 1_000
        let drink = move(HydrationGapRule(), ctx)
        #expect(drink?.title == "Drink 1000 ml")
        #expect(drink?.evidence == [NextMoveEvidence(label: "Water today", value: "1000 of 2200 ml")])
        #expect(drink?.parts == [.midday, .afternoon])
        #expect(drink?.door == .quickAdd)

        ctx.waterTargetMl = 0
        #expect(move(HydrationGapRule(), ctx) == nil)
    }

    @Test("Protein speaks from 25 g under the usual day, and asks for the gap at dinner")
    func protein() {
        var ctx = context(17)
        ctx.proteinUsualGrams = 110
        ctx.proteinGrams = 86
        #expect(move(ProteinGapRule(), ctx) == nil)

        ctx.proteinGrams = 70
        let eat = move(ProteinGapRule(), ctx)
        #expect(eat?.title == "40 g of protein at dinner")
        #expect(eat?.message == "70 g so far; your days usually reach 110 g.")
        #expect(eat?.door == .logMeal)

        ctx.proteinUsualGrams = 0
        #expect(move(ProteinGapRule(), ctx) == nil)
    }

    @Test("Energy speaks only on a big day, well under two thirds of what was burned, and never on an empty log")
    func energyDeficit() {
        var ctx = context(18)
        ctx.energyBurnedKcal = 2_400
        ctx.dietaryEnergyKcal = 1_300
        #expect(move(EnergyDeficitRule(), ctx) == nil)

        ctx.dietaryEnergyKcal = 1_000
        let eat = move(EnergyDeficitRule(), ctx)
        #expect(eat?.title == "Eat 550 kcal more")
        #expect(eat?.evidence == [NextMoveEvidence(label: "Eaten against burned", value: "1000 of 2400 kcal")])

        ctx.dietaryEnergyKcal = 0
        #expect(move(EnergyDeficitRule(), ctx) == nil)

        ctx.dietaryEnergyKcal = 200
        ctx.energyBurnedKcal = 1_399
        #expect(move(EnergyDeficitRule(), ctx) == nil)
    }

    @Test("The evening check-in waits for the evening of the person's day and closes once answered")
    func eveningCheckIn() {
        var open = context(19)
        open.checkedInToday = false
        let ask = move(EveningCheckInRule(), open)
        #expect(ask?.tier == .maintain)
        #expect(ask?.parts == [.evening])

        var answered = context(21)
        answered.checkedInToday = true
        #expect(move(EveningCheckInRule(), answered) == nil)
    }
}
