//
//  PreventEquations.swift
//  Prism
//
//  The AHA PREVENT 2023 base model (Khan et al., Circulation 2024): total
//  cardiovascular disease, ASCVD and heart failure, at ten and thirty years.
//  The coefficients are taken from the published model (Khan et al.,
//  Circulation 2024). The model is a logistic sum over standardised
//  predictors; every input outside the range it was validated on is refused
//  with a reason, never clamped.
//
//  A wellness estimate, never a diagnosis.
//

import Foundation
nonisolated enum PreventEquations {
    enum Outcome: String, Sendable, CaseIterable {
        case totalCVD, ascvd, heartFailure
    }
    enum Horizon: String, Sendable, CaseIterable {
        case tenYear, thirtyYear
    }
    enum Ineligibility: String, Sendable, Error {
        case ageOutsideValidatedRange
        case coefficientsNotSourced
        case sexNotSupportedByModel
        case cholesterolOutsideValidatedRange
        case systolicBPOutsideValidatedRange
        case egfrOutsideValidatedRange
        case bodyMassIndexUnavailable
        case requiredInputsMissing
    }
    static func risk(outcome: Outcome, horizon: Horizon,
                     inputs: CardiometabolicRiskInputs,
                     bodyMassIndexKgM2: Double? = nil)
        -> Result<Double, Ineligibility> {
        risk(outcome: outcome, horizon: horizon, inputs: inputs,
             bodyMassIndexKgM2: bodyMassIndexKgM2,
             vector: vector(outcome: outcome, horizon: horizon, sex: inputs.sex))
    }
    static func validAgeRange(for horizon: Horizon) -> ClosedRange<Double> {
        switch horizon {
        case .tenYear:    30...79
        case .thirtyYear: 30...59
        }
    }
    static func isSourced(outcome: Outcome, horizon: Horizon) -> Bool {
        vector(outcome: outcome, horizon: horizon, sex: .female) != nil
            && vector(outcome: outcome, horizon: horizon, sex: .male) != nil
    }
    enum Predictor: String, Sendable, CaseIterable {
        case age, ageSquared, nonHDL, hdl
        case sbpLow, sbpHigh, diabetes, smoking
        case bmiLow, bmiHigh, egfrLow, egfrHigh
        case bpMedication, statin
        case bpMedicationSBP, statinNonHDL
        case ageNonHDL, ageHDL, ageSBP
        case ageDiabetes, ageSmoking, ageBMI, ageEGFR
    }
    struct Vector: Sendable {
        let intercept: Double
        let coefficients: [Predictor: Double]
    }
    static let mgDlToMmolPerLiter: Double = 0.02586
    static let validTotalCholesterolMgDl: ClosedRange<Double> = 130...320
    static let validHDLMgDl: ClosedRange<Double> = 20...100
    static let validSystolicBP: ClosedRange<Double> = 90...200
    static let validBodyMassIndex: Range<Double> = 18.5..<40
    static func risk(outcome: Outcome, horizon: Horizon,
                     inputs: CardiometabolicRiskInputs,
                     bodyMassIndexKgM2: Double?,
                     vector: Vector?) -> Result<Double, Ineligibility> {
        if let refusal = ineligibility(outcome: outcome, horizon: horizon,
                                       inputs: inputs,
                                       bodyMassIndexKgM2: bodyMassIndexKgM2) {
            return .failure(refusal)
        }
        guard let vector else { return .failure(.coefficientsNotSourced) }
        let terms = standardizedTerms(inputs: inputs,
                                      bodyMassIndexKgM2: bodyMassIndexKgM2)
        var logOdds = vector.intercept
        for predictor in Predictor.allCases {
            guard let coefficient = vector.coefficients[predictor] else { continue }
            guard let term = terms[predictor] else {
                return .failure(.bodyMassIndexUnavailable)
            }
            logOdds += coefficient * term
        }
        return .success(100.0 * exp(logOdds) / (1.0 + exp(logOdds)))
    }
    private static func ineligibility(outcome: Outcome, horizon: Horizon,
                                      inputs: CardiometabolicRiskInputs,
                                      bodyMassIndexKgM2: Double?)
        -> Ineligibility? {
        guard inputs.sex == .male || inputs.sex == .female else {
            return .sexNotSupportedByModel
        }
        guard validAgeRange(for: horizon).contains(inputs.ageYears) else {
            return .ageOutsideValidatedRange
        }
        guard validSystolicBP.contains(inputs.systolicBP) else {
            return .systolicBPOutsideValidatedRange
        }
        guard inputs.egfr > 0 else { return .egfrOutsideValidatedRange }
        switch outcome {
        case .totalCVD, .ascvd:
            guard validTotalCholesterolMgDl.contains(inputs.totalCholesterolMgDl),
                  validHDLMgDl.contains(inputs.hdlMgDl) else {
                return .cholesterolOutsideValidatedRange
            }
            return nil
        case .heartFailure:
            guard let bmi = bodyMassIndexKgM2,
                  validBodyMassIndex.contains(bmi) else {
                return .bodyMassIndexUnavailable
            }
            return nil
        }
    }
    private static func standardizedTerms(inputs: CardiometabolicRiskInputs,
                                          bodyMassIndexKgM2: Double?)
        -> [Predictor: Double] {
        let age = (inputs.ageYears - 55.0) / 10.0
        let nonHDL = inputs.nonHDLMgDl * mgDlToMmolPerLiter - 3.5
        let hdl = (inputs.hdlMgDl * mgDlToMmolPerLiter - 1.3) / 0.3
        let sbpLow = (min(inputs.systolicBP, 110.0) - 110.0) / 20.0
        let sbpHigh = (max(inputs.systolicBP, 110.0) - 130.0) / 20.0
        let egfrLow = (min(inputs.egfr, 60.0) - 60.0) / -15.0
        let egfrHigh = (max(inputs.egfr, 60.0) - 90.0) / -15.0
        let diabetes = inputs.diabetes ? 1.0 : 0.0
        let smoking = inputs.currentSmoker ? 1.0 : 0.0
        let bpMedication = inputs.bpMedicationUse ? 1.0 : 0.0
        let statin = inputs.statinUse ? 1.0 : 0.0
        var terms: [Predictor: Double] = [
            .age: age,
            .ageSquared: age * age,
            .nonHDL: nonHDL,
            .hdl: hdl,
            .sbpLow: sbpLow,
            .sbpHigh: sbpHigh,
            .diabetes: diabetes,
            .smoking: smoking,
            .egfrLow: egfrLow,
            .egfrHigh: egfrHigh,
            .bpMedication: bpMedication,
            .statin: statin,
            .bpMedicationSBP: bpMedication * sbpHigh,
            .statinNonHDL: statin * nonHDL,
            .ageNonHDL: age * nonHDL,
            .ageHDL: age * hdl,
            .ageSBP: age * sbpHigh,
            .ageDiabetes: age * diabetes,
            .ageSmoking: age * smoking,
            .ageEGFR: age * egfrLow,
        ]
        if let bmi = bodyMassIndexKgM2 {
            let bmiHigh = (max(bmi, 30.0) - 30.0) / 5.0
            terms[.bmiLow] = (min(bmi, 30.0) - 25.0) / 5.0
            terms[.bmiHigh] = bmiHigh
            terms[.ageBMI] = age * bmiHigh
        }
        return terms
    }
    static func vector(outcome: Outcome, horizon: Horizon,
                       sex: LabSex) -> Vector? {
        switch (sex, outcome, horizon) {
        case (.female, .totalCVD, .tenYear):        Vectors.female_totalCVD_tenYear
        case (.female, .ascvd, .tenYear):           Vectors.female_ascvd_tenYear
        case (.female, .heartFailure, .tenYear):    Vectors.female_heartFailure_tenYear
        case (.female, .totalCVD, .thirtyYear):     Vectors.female_totalCVD_thirtyYear
        case (.female, .ascvd, .thirtyYear):        Vectors.female_ascvd_thirtyYear
        case (.female, .heartFailure, .thirtyYear): Vectors.female_heartFailure_thirtyYear
        case (.male, .totalCVD, .tenYear):          Vectors.male_totalCVD_tenYear
        case (.male, .ascvd, .tenYear):             Vectors.male_ascvd_tenYear
        case (.male, .heartFailure, .tenYear):      Vectors.male_heartFailure_tenYear
        case (.male, .totalCVD, .thirtyYear):       Vectors.male_totalCVD_thirtyYear
        case (.male, .ascvd, .thirtyYear):          Vectors.male_ascvd_thirtyYear
        case (.male, .heartFailure, .thirtyYear):   Vectors.male_heartFailure_thirtyYear
        }
    }
}
nonisolated extension PreventEquations {
    enum Vectors {
        static let female_totalCVD_tenYear = Vector(
            intercept: -3.307728,
            coefficients: [
                .age: 0.7939329,
                .nonHDL: 0.0305239,
                .hdl: -0.1606857,
                .sbpLow: -0.2394003,
                .sbpHigh: 0.360078,
                .diabetes: 0.8667604,
                .smoking: 0.5360739,
                .egfrLow: 0.6045917,
                .egfrHigh: 0.0433769,
                .bpMedication: 0.3151672,
                .statin: -0.1477655,
                .bpMedicationSBP: -0.0663612,
                .statinNonHDL: 0.1197879,
                .ageNonHDL: -0.0819715,
                .ageHDL: 0.0306769,
                .ageSBP: -0.0946348,
                .ageDiabetes: -0.27057,
                .ageSmoking: -0.078715,
                .ageEGFR: -0.1637806,
            ])
        static let female_ascvd_tenYear = Vector(
            intercept: -3.819975,
            coefficients: [
                .age: 0.719883,
                .nonHDL: 0.1176967,
                .hdl: -0.151185,
                .sbpLow: -0.0835358,
                .sbpHigh: 0.3592852,
                .diabetes: 0.8348585,
                .smoking: 0.4831078,
                .egfrLow: 0.4864619,
                .egfrHigh: 0.0397779,
                .bpMedication: 0.2265309,
                .statin: -0.0592374,
                .bpMedicationSBP: -0.0395762,
                .statinNonHDL: 0.0844423,
                .ageNonHDL: -0.0567839,
                .ageHDL: 0.0325692,
                .ageSBP: -0.1035985,
                .ageDiabetes: -0.2417542,
                .ageSmoking: -0.0791142,
                .ageEGFR: -0.1671492,
            ])
        static let female_heartFailure_tenYear = Vector(
            intercept: -4.310409,
            coefficients: [
                .age: 0.8998235,
                .sbpLow: -0.4559771,
                .sbpHigh: 0.3576505,
                .diabetes: 1.038346,
                .smoking: 0.583916,
                .bmiLow: -0.0072294,
                .bmiHigh: 0.2997706,
                .egfrLow: 0.7451638,
                .egfrHigh: 0.0557087,
                .bpMedication: 0.3534442,
                .bpMedicationSBP: -0.0981511,
                .ageSBP: -0.0946663,
                .ageDiabetes: -0.3581041,
                .ageSmoking: -0.1159453,
                .ageBMI: -0.003878,
                .ageEGFR: -0.1884289,
            ])
        static let female_totalCVD_thirtyYear = Vector(
            intercept: -1.318827,
            coefficients: [
                .age: 0.5503079,
                .ageSquared: -0.0928369,
                .nonHDL: 0.0409794,
                .hdl: -0.1663306,
                .sbpLow: -0.1628654,
                .sbpHigh: 0.3299505,
                .diabetes: 0.6793894,
                .smoking: 0.3196112,
                .egfrLow: 0.1857101,
                .egfrHigh: 0.0553528,
                .bpMedication: 0.2894,
                .statin: -0.075688,
                .bpMedicationSBP: -0.056367,
                .statinNonHDL: 0.1071019,
                .ageNonHDL: -0.0751438,
                .ageHDL: 0.0301786,
                .ageSBP: -0.0998776,
                .ageDiabetes: -0.3206166,
                .ageSmoking: -0.1607862,
                .ageEGFR: -0.1450788,
            ])
        static let female_ascvd_thirtyYear = Vector(
            intercept: -1.974074,
            coefficients: [
                .age: 0.4669202,
                .ageSquared: -0.0893118,
                .nonHDL: 0.1256901,
                .hdl: -0.1542255,
                .sbpLow: -0.0018093,
                .sbpHigh: 0.322949,
                .diabetes: 0.6296707,
                .smoking: 0.268292,
                .egfrLow: 0.100106,
                .egfrHigh: 0.0499663,
                .bpMedication: 0.1875292,
                .statin: 0.0152476,
                .bpMedicationSBP: -0.0276123,
                .statinNonHDL: 0.0736147,
                .ageNonHDL: -0.0521962,
                .ageHDL: 0.0316918,
                .ageSBP: -0.1046101,
                .ageDiabetes: -0.2727793,
                .ageSmoking: -0.1530907,
                .ageEGFR: -0.1299149,
            ])
        static let female_heartFailure_thirtyYear = Vector(
            intercept: -2.205379,
            coefficients: [
                .age: 0.6254374,
                .ageSquared: -0.0983038,
                .sbpLow: -0.3919241,
                .sbpHigh: 0.3142295,
                .diabetes: 0.8330787,
                .smoking: 0.3438651,
                .bmiLow: 0.0594874,
                .bmiHigh: 0.2525536,
                .egfrLow: 0.2981642,
                .egfrHigh: 0.0667159,
                .bpMedication: 0.333921,
                .bpMedicationSBP: -0.0893177,
                .ageSBP: -0.0974299,
                .ageDiabetes: -0.404855,
                .ageSmoking: -0.1982991,
                .ageBMI: -0.0035619,
                .ageEGFR: -0.1564215,
            ])
        static let male_totalCVD_tenYear = Vector(
            intercept: -3.031168,
            coefficients: [
                .age: 0.7688528,
                .nonHDL: 0.0736174,
                .hdl: -0.0954431,
                .sbpLow: -0.4347345,
                .sbpHigh: 0.3362658,
                .diabetes: 0.7692857,
                .smoking: 0.4386871,
                .egfrLow: 0.5378979,
                .egfrHigh: 0.0164827,
                .bpMedication: 0.288879,
                .statin: -0.1337349,
                .bpMedicationSBP: -0.0475924,
                .statinNonHDL: 0.150273,
                .ageNonHDL: -0.0517874,
                .ageHDL: 0.0191169,
                .ageSBP: -0.1049477,
                .ageDiabetes: -0.2251948,
                .ageSmoking: -0.0895067,
                .ageEGFR: -0.1543702,
            ])
        static let male_ascvd_tenYear = Vector(
            intercept: -3.500655,
            coefficients: [
                .age: 0.7099847,
                .nonHDL: 0.1658663,
                .hdl: -0.1144285,
                .sbpLow: -0.2837212,
                .sbpHigh: 0.3239977,
                .diabetes: 0.7189597,
                .smoking: 0.3956973,
                .egfrLow: 0.3690075,
                .egfrHigh: 0.0203619,
                .bpMedication: 0.2036522,
                .statin: -0.0865581,
                .bpMedicationSBP: -0.0322916,
                .statinNonHDL: 0.114563,
                .ageNonHDL: -0.0300005,
                .ageHDL: 0.0232747,
                .ageSBP: -0.0927024,
                .ageDiabetes: -0.2018525,
                .ageSmoking: -0.0970527,
                .ageEGFR: -0.1217081,
            ])
        static let male_heartFailure_tenYear = Vector(
            intercept: -3.946391,
            coefficients: [
                .age: 0.8972642,
                .sbpLow: -0.6811466,
                .sbpHigh: 0.3634461,
                .diabetes: 0.923776,
                .smoking: 0.5023736,
                .bmiLow: -0.0485841,
                .bmiHigh: 0.3726929,
                .egfrLow: 0.6926917,
                .egfrHigh: 0.0251827,
                .bpMedication: 0.2980922,
                .bpMedicationSBP: -0.0497731,
                .ageSBP: -0.1289201,
                .ageDiabetes: -0.3040924,
                .ageSmoking: -0.1401688,
                .ageBMI: 0.0068126,
                .ageEGFR: -0.1797778,
            ])
        static let male_totalCVD_thirtyYear = Vector(
            intercept: -1.148204,
            coefficients: [
                .age: 0.4627309,
                .ageSquared: -0.0984281,
                .nonHDL: 0.0836088,
                .hdl: -0.1029824,
                .sbpLow: -0.2140352,
                .sbpHigh: 0.2904325,
                .diabetes: 0.5331276,
                .smoking: 0.2141914,
                .egfrLow: 0.1155556,
                .egfrHigh: 0.0603775,
                .bpMedication: 0.232714,
                .statin: -0.0272112,
                .bpMedicationSBP: -0.0384488,
                .statinNonHDL: 0.134192,
                .ageNonHDL: -0.0511759,
                .ageHDL: 0.0165865,
                .ageSBP: -0.1101437,
                .ageDiabetes: -0.2585943,
                .ageSmoking: -0.1566406,
                .ageEGFR: -0.1166776,
            ])
        static let male_ascvd_thirtyYear = Vector(
            intercept: -1.736444,
            coefficients: [
                .age: 0.3994099,
                .ageSquared: -0.0937484,
                .nonHDL: 0.1744643,
                .hdl: -0.120203,
                .sbpLow: -0.0665117,
                .sbpHigh: 0.2753037,
                .diabetes: 0.4790257,
                .smoking: 0.1782635,
                .egfrLow: -0.0218789,
                .egfrHigh: 0.0602553,
                .bpMedication: 0.1421182,
                .statin: 0.0135996,
                .bpMedicationSBP: -0.0218265,
                .statinNonHDL: 0.1013148,
                .ageNonHDL: -0.0312619,
                .ageHDL: 0.020673,
                .ageSBP: -0.0920935,
                .ageDiabetes: -0.2159947,
                .ageSmoking: -0.1548811,
                .ageEGFR: -0.0712547,
            ])
        static let male_heartFailure_thirtyYear = Vector(
            intercept: -1.95751,
            coefficients: [
                .age: 0.5681541,
                .ageSquared: -0.1048388,
                .sbpLow: -0.4761564,
                .sbpHigh: 0.30324,
                .diabetes: 0.6840338,
                .smoking: 0.2656273,
                .bmiLow: 0.0833107,
                .bmiHigh: 0.26999,
                .egfrLow: 0.2541805,
                .egfrHigh: 0.0638923,
                .bpMedication: 0.2583631,
                .bpMedicationSBP: -0.0391938,
                .ageSBP: -0.1269124,
                .ageDiabetes: -0.3273572,
                .ageSmoking: -0.2043019,
                .ageBMI: -0.0182831,
                .ageEGFR: -0.1342618,
            ])
    }
}
