//
//  MuscleFreshnessTests.swift
//  PrismTests
//

import Foundation
import Testing
import SomaUI
@testable import Prism

@Suite("Muscle freshness")
struct MuscleFreshnessTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func run(hoursAgo: Double, minutes: Double = 45) -> FitnessWorkout {
        let end = now.addingTimeInterval(-hoursAgo * 3600)
        return FitnessWorkout(start: end.addingTimeInterval(-minutes * 60), end: end, activity: 37)
    }

    @Test("A hard run this morning after a quiet month leaves the legs depleted")
    func depletedAfterRun() {
        let states = MuscleFreshness.states([run(hoursAgo: 25 * 24), run(hoursAgo: 3)], now: now)
        #expect(states[.legs] == .depleted)
    }

    @Test("A run three weeks ago has long since recovered")
    func recoveredAfterWeeks() {
        let states = MuscleFreshness.states([run(hoursAgo: 21 * 24)], now: now)
        #expect(states[.legs] == .recovered)
    }

    @Test("A group the month never worked has no state")
    func unworkedHasNoState() {
        let states = MuscleFreshness.states([run(hoursAgo: 48)], now: now)
        #expect(states[.chest] == nil)
        #expect(MuscleFreshness.map(states)[.chest] == SomaMuscleState.none)
    }

    @Test("Every drawn muscle maps to a group")
    func everyMuscleMaps() {
        #expect(MuscleFreshness.map([:]).count == SomaMuscle.allCases.count)
    }
}
