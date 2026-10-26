//
//  PreventEquationsTests.swift
//  PrismTests
//

import Foundation
import Testing
@testable import Prism

/// PREVENT is a published model, so the port is held to the published numbers
/// rather than to whatever it happens to print. The worked example below is the
/// one the PREVENT R package (preventr) documents for the base model; matching
/// it to a tenth of a percent on all six estimates means the coefficients, the
/// standardisation and the logistic sum came across intact.
@Suite("PREVENT equations")
struct PreventEquationsTests {

    /// A 50 year old woman: total cholesterol 200, HDL 45, systolic 160 on
    /// treatment, diabetes, no statin, not smoking, eGFR 90, BMI 35.
    let documented = CardiometabolicRiskInputs(
        ageYears: 50, sex: .female,
        totalCholesterolMgDl: 200, hdlMgDl: 45,
        systolicBP: 160, egfr: 90,
        statinUse: false, bpMedicationUse: true,
        currentSmoker: false, diabetes: true
    )

    /// An unremarkable 55 year old, the baseline each factor is moved from.
    func person(_ sex: LabSex, change: (inout CardiometabolicRiskInputs) -> Void = { _ in }) -> CardiometabolicRiskInputs {
        var inputs = CardiometabolicRiskInputs(
            ageYears: 55, sex: sex,
            totalCholesterolMgDl: 210, hdlMgDl: 50,
            systolicBP: 125, egfr: 85,
            statinUse: false, bpMedicationUse: false,
            currentSmoker: false, diabetes: false
        )
        change(&inputs)
        return inputs
    }

    func accepted(_ result: Result<Double, PreventEquations.Ineligibility>) -> Bool {
        if case .success = result { return true }
        return false
    }

    func percent(_ outcome: PreventEquations.Outcome, _ horizon: PreventEquations.Horizon,
                 _ inputs: CardiometabolicRiskInputs, bmi: Double? = 27) throws -> Double {
        try PreventEquations.risk(outcome: outcome, horizon: horizon, inputs: inputs, bodyMassIndexKgM2: bmi).get()
    }

    // MARK: The published example

    @Test("The documented example reads 14.7, 9.2 and 8.1 percent at ten years")
    func documentedTenYear() throws {
        let total = try percent(.totalCVD, .tenYear, documented, bmi: 35)
        let ascvd = try percent(.ascvd, .tenYear, documented, bmi: 35)
        let heartFailure = try percent(.heartFailure, .tenYear, documented, bmi: 35)
        #expect(abs(total - 14.7) < 0.05)
        #expect(abs(ascvd - 9.2) < 0.05)
        #expect(abs(heartFailure - 8.1) < 0.05)
    }

    @Test("The documented example reads 53.0, 35.4 and 39.0 percent at thirty years")
    func documentedThirtyYear() throws {
        let total = try percent(.totalCVD, .thirtyYear, documented, bmi: 35)
        let ascvd = try percent(.ascvd, .thirtyYear, documented, bmi: 35)
        let heartFailure = try percent(.heartFailure, .thirtyYear, documented, bmi: 35)
        #expect(abs(total - 53.0) < 0.05)
        #expect(abs(ascvd - 35.4) < 0.05)
        #expect(abs(heartFailure - 39.0) < 0.05)
    }

    @Test("Every outcome and horizon has coefficients for both sexes")
    func everyModelSourced() {
        for outcome in PreventEquations.Outcome.allCases {
            for horizon in PreventEquations.Horizon.allCases {
                #expect(PreventEquations.isSourced(outcome: outcome, horizon: horizon))
            }
        }
    }

    // MARK: Direction

    @Test("Pressure, smoking, diabetes and age each raise the risk",
          arguments: LabSex.allCases, PreventEquations.Outcome.allCases)
    func factorsRaiseRisk(sex: LabSex, outcome: PreventEquations.Outcome) throws {
        for horizon in PreventEquations.Horizon.allCases {
            let base = try percent(outcome, horizon, person(sex))
            let pressure = try percent(outcome, horizon, person(sex) { $0.systolicBP = 150 })
            let smoking = try percent(outcome, horizon, person(sex) { $0.currentSmoker = true })
            let diabetes = try percent(outcome, horizon, person(sex) { $0.diabetes = true })
            let younger = try percent(outcome, horizon, person(sex) { $0.ageYears = 45 })
            #expect(pressure > base, "\(horizon)")
            #expect(smoking > base, "\(horizon)")
            #expect(diabetes > base, "\(horizon)")
            #expect(younger < base, "\(horizon)")
        }
    }

    @Test("More HDL lowers the cardiovascular risk", arguments: LabSex.allCases)
    func hdlLowersRisk(sex: LabSex) throws {
        for outcome in [PreventEquations.Outcome.totalCVD, .ascvd] {
            let base = try percent(outcome, .tenYear, person(sex))
            let moreHDL = try percent(outcome, .tenYear, person(sex) { $0.hdlMgDl = 70 })
            #expect(moreHDL < base, "\(outcome)")
        }
    }

    @Test("Thirty years never reads lower than ten", arguments: LabSex.allCases)
    func longerHorizonHoldsMore(sex: LabSex) throws {
        let inputs = person(sex) { $0.ageYears = 45 }
        for outcome in PreventEquations.Outcome.allCases {
            let thirty = try percent(outcome, .thirtyYear, inputs)
            let ten = try percent(outcome, .tenYear, inputs)
            #expect(thirty >= ten, "\(outcome)")
        }
    }

    // MARK: Refusals

    @Test("Ages the model was not fitted on are refused, the edges kept")
    func ages() {
        func result(_ age: Double, _ horizon: PreventEquations.Horizon) -> Result<Double, PreventEquations.Ineligibility> {
            PreventEquations.risk(outcome: .ascvd, horizon: horizon, inputs: person(.male) { $0.ageYears = age })
        }
        #expect(result(29, .tenYear) == .failure(.ageOutsideValidatedRange))
        #expect(result(80, .tenYear) == .failure(.ageOutsideValidatedRange))
        #expect(accepted(result(30, .tenYear)))
        #expect(accepted(result(79, .tenYear)))
        #expect(result(60, .thirtyYear) == .failure(.ageOutsideValidatedRange))
        #expect(accepted(result(59, .thirtyYear)))
    }

    @Test("Cholesterol, pressure and kidney function outside the fitted range are refused")
    func inputRanges() {
        func refusal(_ change: (inout CardiometabolicRiskInputs) -> Void) -> PreventEquations.Ineligibility? {
            let result = PreventEquations.risk(outcome: .totalCVD, horizon: .tenYear, inputs: person(.female, change: change))
            if case .failure(let reason) = result { return reason }
            return nil
        }
        #expect(refusal { $0.totalCholesterolMgDl = 129 } == .cholesterolOutsideValidatedRange)
        #expect(refusal { $0.totalCholesterolMgDl = 321 } == .cholesterolOutsideValidatedRange)
        #expect(refusal { $0.hdlMgDl = 19 } == .cholesterolOutsideValidatedRange)
        #expect(refusal { $0.systolicBP = 89 } == .systolicBPOutsideValidatedRange)
        #expect(refusal { $0.systolicBP = 201 } == .systolicBPOutsideValidatedRange)
        #expect(refusal { $0.egfr = 0 } == .egfrOutsideValidatedRange)
        #expect(refusal { $0.totalCholesterolMgDl = 130; $0.systolicBP = 200 } == nil)
    }

    @Test("Heart failure needs a body mass index in range, and does not read cholesterol")
    func heartFailureInputs() {
        let inputs = person(.male)
        func result(_ bmi: Double?, _ inputs: CardiometabolicRiskInputs) -> Result<Double, PreventEquations.Ineligibility> {
            PreventEquations.risk(outcome: .heartFailure, horizon: .tenYear, inputs: inputs, bodyMassIndexKgM2: bmi)
        }
        #expect(result(nil, inputs) == .failure(.bodyMassIndexUnavailable))
        #expect(result(18.4, inputs) == .failure(.bodyMassIndexUnavailable))
        #expect(result(40, inputs) == .failure(.bodyMassIndexUnavailable))
        #expect(accepted(result(18.5, inputs)))
        #expect(accepted(result(25, person(.male) { $0.totalCholesterolMgDl = 120 })))
    }

    @Test("A model without coefficients says so, after the inputs are checked")
    func unsourcedVector() {
        let missing = PreventEquations.risk(outcome: .ascvd, horizon: .tenYear, inputs: person(.female),
                                            bodyMassIndexKgM2: nil, vector: nil)
        #expect(missing == .failure(.coefficientsNotSourced))

        let tooYoung = PreventEquations.risk(outcome: .ascvd, horizon: .tenYear, inputs: person(.female) { $0.ageYears = 25 },
                                             bodyMassIndexKgM2: nil, vector: nil)
        #expect(tooYoung == .failure(.ageOutsideValidatedRange))
    }
}
