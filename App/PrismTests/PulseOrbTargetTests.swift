//
//  PulseOrbTargetTests.swift
//  PrismTests
//

import Testing
import SomaUI
@testable import Prism

/// A tap on the Today orb always lands somewhere: heart, gut and body have no
/// score page, so they open their page of readings instead.
@MainActor
struct PulseOrbTargetTests {
    @Test("Every aspect the orb can wear opens a page")
    func everyAspectOpensSomething() {
        #expect(PulseOrbTarget.make(.sleep) == .score(.sleep))
        #expect(PulseOrbTarget.make(.mind) == .score(.recovery))
        #expect(PulseOrbTarget.make(.activity) == .score(.strain))
        #expect(PulseOrbTarget.make(.heart) == .category(.category("Heart")))
        #expect(PulseOrbTarget.make(.gut) == .category(.category("Nutrition")))
        #expect(PulseOrbTarget.make(.body) == .category(.category("Body Measurements")))
    }
}
