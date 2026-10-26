//
//  SomaScores+Fixture.swift
//  PrismTests
//

import Foundation
@testable import Prism

extension SomaScores {
    /// Scores with every value nil and every series empty, for a test to fill
    /// the fields it checks.
    static var fixture: SomaScores {
        SomaScores(
            sleep: nil, recovery: nil, strain: nil, stress: nil, energy: nil,
            energyCurve: [], sleepDebtHours: nil, sleepNeedHours: 8, strainTarget: nil,
            recoveryTerms: [], recoveryMissing: [],
            sleepTrend: nil, recoveryTrend: nil, strainTrend: nil, stressTrend: nil, energyTrend: nil,
            sleepSeries: [], recoverySeries: [], strainSeries: [], stressSeries: [], energySeries: [],
            nightsRecorded: 0
        )
    }
}
