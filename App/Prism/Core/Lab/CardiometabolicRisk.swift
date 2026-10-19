//
//  CardiometabolicRisk.swift
//  Prism
//
//  Cardiometabolic risk: the CKD-EPI 2021
//  eGFR, the inputs PREVENT needs resolved from a panel, a blood pressure
//  reading and the person's answers, the six PREVENT estimates, the lipid
//  enhancers PREVENT does not read, and the leave one out drivers.
//
//  Nothing absent is ever filled with a population mean: an input that is
//  missing is listed, so the page shows what to add rather than a wrong
//  number. PREVENT reads non-HDL cholesterol and the creatinine only eGFR,
//  never LDL and never a cystatin C eGFR.
//
//  A wellness estimate, never a diagnosis.
//

import Foundation

// MARK: - eGFR

nonisolated enum EGFR {
    /// CKD-EPI 2021, creatinine only, race free: the variant PREVENT was fit on.
    static func ckdEpi2021(creatinineMgDl: Double, ageYears: Double, sex: LabSex) -> Double {
        let kappa = sex == .female ? 0.7 : 0.9
        let alpha = sex == .female ? -0.241 : -0.302
        let ratio = creatinineMgDl / kappa
        return 142 * pow(min(ratio, 1), alpha) * pow(max(ratio, 1), -1.200)
            * pow(0.9938, ageYears) * (sex == .female ? 1.012 : 1.0)
    }

    /// CKD-EPI 2021 with cystatin C: sharper, shown, never fed to PREVENT.
    static func ckdEpi2021CystatinC(creatinineMgDl: Double, cystatinCMgL: Double, ageYears: Double, sex: LabSex) -> Double {
        let kappa = sex == .female ? 0.7 : 0.9
        let alpha = sex == .female ? -0.219 : -0.144
        let cr = creatinineMgDl / kappa
        let cys = cystatinCMgL / 0.8
        return 135 * pow(min(cr, 1), alpha) * pow(max(cr, 1), -0.544)
            * pow(min(cys, 1), -0.323) * pow(max(cys, 1), -0.778)
            * pow(0.9961, ageYears) * (sex == .female ? 0.963 : 1.0)
    }

    /// Creatinine stores in µmol/L; 88.42 µmol/L is 1 mg/dL.
    static let micromolPerMilligram = 88.42
}

// MARK: - The person's answers

/// Four yes or no answers PREVENT needs and no sensor can give, plus sex
/// when Health does not know it. Each counts only once the person has
/// answered it here.
nonisolated struct CardiometabolicProfile: Codable, Sendable, Equatable {
    var statinUse: Bool?
    var bpMedicationUse: Bool?
    var currentSmoker: Bool?
    var diabetes: Bool?
    var sex: LabSex?

    enum Question: String, CaseIterable, Identifiable, Sendable {
        case smoker, diabetes, bpMedication, statin

        var id: String { rawValue }

        var title: String {
            switch self {
            case .smoker: "Smoking"
            case .diabetes: "Diabetes"
            case .bpMedication: "Blood pressure medicine"
            case .statin: "A statin"
            }
        }

        var prompt: String {
            switch self {
            case .smoker: "Do you smoke now?"
            case .diabetes: "Have you been told you have diabetes?"
            case .bpMedication: "Do you take medicine for blood pressure?"
            case .statin: "Do you take a statin?"
            }
        }
    }

    func answer(_ question: Question) -> Bool? {
        switch question {
        case .smoker: currentSmoker
        case .diabetes: diabetes
        case .bpMedication: bpMedicationUse
        case .statin: statinUse
        }
    }

    mutating func set(_ question: Question, _ value: Bool?) {
        switch question {
        case .smoker: currentSmoker = value
        case .diabetes: diabetes = value
        case .bpMedication: bpMedicationUse = value
        case .statin: statinUse = value
        }
    }
}

// MARK: - Inputs

/// One input PREVENT needs that could not be resolved.
nonisolated enum MissingRiskInput: String, Sendable, CaseIterable, Identifiable {
    case totalCholesterol, hdl, systolicBP, creatinine
    case statinUse, bpMedicationUse, currentSmoker, diabetes
    case age, sex

    var id: String { rawValue }

    var title: String {
        switch self {
        case .totalCholesterol: "Total cholesterol"
        case .hdl: "HDL cholesterol"
        case .systolicBP: "Blood pressure"
        case .creatinine: "Creatinine"
        case .statinUse: "Statin"
        case .bpMedicationUse: "Blood pressure medicine"
        case .currentSmoker: "Smoking"
        case .diabetes: "Diabetes"
        case .age: "Date of birth"
        case .sex: "Sex"
        }
    }

    /// The question that answers it, when a question does.
    var question: CardiometabolicProfile.Question? {
        switch self {
        case .statinUse: .statin
        case .bpMedicationUse: .bpMedication
        case .currentSmoker: .smoker
        case .diabetes: .diabetes
        default: nil
        }
    }

    var fromBlood: Bool { [.totalCholesterol, .hdl, .creatinine].contains(self) }
}

/// Everything PREVENT reads, fully resolved.
nonisolated struct CardiometabolicRiskInputs: Sendable, Equatable {
    var ageYears: Double
    var sex: LabSex
    var totalCholesterolMgDl: Double
    var hdlMgDl: Double
    var nonHDLMgDl: Double { totalCholesterolMgDl - hdlMgDl }
    var systolicBP: Double
    /// Always the creatinine only CKD-EPI 2021.
    var egfr: Double
    var statinUse: Bool
    var bpMedicationUse: Bool
    var currentSmoker: Bool
    var diabetes: Bool

    /// Resolves the inputs, or lists every one still missing.
    static func resolve(panel: BloodPanel?, systolicBP: Double?, ageYears: Double?, sex: LabSex?,
                        profile: CardiometabolicProfile) -> Result<CardiometabolicRiskInputs, MissingRiskInputs> {
        let total = panel?.value("totalCholesterol")
        let hdl = panel?.value("hdl")
        let creatinine = panel?.value("creatinine")

        var missing: [MissingRiskInput] = []
        if total == nil { missing.append(.totalCholesterol) }
        if hdl == nil { missing.append(.hdl) }
        if systolicBP == nil { missing.append(.systolicBP) }
        if creatinine == nil { missing.append(.creatinine) }
        if profile.statinUse == nil { missing.append(.statinUse) }
        if profile.bpMedicationUse == nil { missing.append(.bpMedicationUse) }
        if profile.currentSmoker == nil { missing.append(.currentSmoker) }
        if profile.diabetes == nil { missing.append(.diabetes) }
        if ageYears == nil { missing.append(.age) }
        if sex == nil { missing.append(.sex) }

        guard missing.isEmpty, let total, let hdl, let creatinine, let systolicBP, let ageYears, let sex,
              let statin = profile.statinUse, let bpMeds = profile.bpMedicationUse,
              let smoker = profile.currentSmoker, let diabetes = profile.diabetes
        else { return .failure(MissingRiskInputs(inputs: missing)) }

        let egfr = EGFR.ckdEpi2021(creatinineMgDl: creatinine.value / EGFR.micromolPerMilligram,
                                   ageYears: ageYears, sex: sex)
        return .success(CardiometabolicRiskInputs(
            ageYears: ageYears, sex: sex, totalCholesterolMgDl: total.value, hdlMgDl: hdl.value,
            systolicBP: systolicBP, egfr: egfr, statinUse: statin, bpMedicationUse: bpMeds,
            currentSmoker: smoker, diabetes: diabetes))
    }
}

nonisolated struct MissingRiskInputs: Error, Sendable, Equatable {
    var inputs: [MissingRiskInput]
}

// MARK: - Enhancers

/// Markers PREVENT does not read that still say something about vessels,
/// each against its own published cut points.
nonisolated enum RiskEnhancers {
    enum Tier: String, Sendable, Comparable {
        case optimal, borderline, elevated, high

        private var rank: Int { [.optimal, .borderline, .elevated, .high].firstIndex(of: self) ?? 0 }
        static func < (lhs: Tier, rhs: Tier) -> Bool { lhs.rank < rhs.rank }
    }

    struct Enhancer: Sendable, Identifiable, Equatable {
        var id: String
        var name: String
        var value: Double
        var unit: String
        var tier: Tier
        /// The value that ends the optimal tier, for a rail's band.
        var optimalBound: Double
        var lowerIsBetter: Bool
    }

    static func enhancers(panel: BloodPanel, sex: LabSex?) -> [Enhancer] {
        var out: [Enhancer] = []
        if let v = panel.value("apoB")?.value {
            out.append(Enhancer(id: "apoB", name: "ApoB", value: v, unit: "mg/dL",
                                tier: tier(v, [80, 100, 130]), optimalBound: 80, lowerIsBetter: true))
        }
        if let v = panel.value("lpA")?.value {
            out.append(Enhancer(id: "lpA", name: "Lp(a)", value: v, unit: "nmol/L",
                                tier: tier(v, [75, 125, 430]), optimalBound: 75, lowerIsBetter: true))
        }
        if let v = panel.value("apoA1")?.value {
            let t: Tier = v >= 140 ? .optimal : v >= 120 ? .borderline : v >= 100 ? .elevated : .high
            out.append(Enhancer(id: "apoA1", name: "ApoA1", value: v, unit: "mg/dL",
                                tier: t, optimalBound: 140, lowerIsBetter: false))
        }
        if let b = panel.value("apoB")?.value, let a = panel.value("apoA1")?.value, a > 0, let sex {
            let ratio = b / a
            let cuts = sex == .male ? [0.7, 0.8, 0.9] : [0.6, 0.7, 0.8]
            out.append(Enhancer(id: "apoBApoA1Ratio", name: "ApoB to ApoA1", value: ratio, unit: "ratio",
                                tier: tier(ratio, cuts), optimalBound: cuts[0], lowerIsBetter: true))
        }
        if let v = panel.value("lpPLA2")?.value {
            out.append(Enhancer(id: "lpPLA2", name: "Lp-PLA2", value: v, unit: "nmol/min/mL",
                                tier: tier(v, [200, 225, 300]), optimalBound: 200, lowerIsBetter: true))
        }
        if let v = panel.value("ntProBNP")?.value {
            out.append(Enhancer(id: "ntProBNP", name: "NT-proBNP", value: v, unit: "pg/mL",
                                tier: tier(v, [50, 125, 450]), optimalBound: 50, lowerIsBetter: true))
        }
        if let t = panel.value("totalCholesterol")?.value, let h = panel.value("hdl")?.value {
            let nonHDL = t - h
            out.append(Enhancer(id: "nonHDL", name: "Non-HDL cholesterol", value: nonHDL, unit: "mg/dL",
                                tier: tier(nonHDL, [130, 160, 190]), optimalBound: 130, lowerIsBetter: true))
            if let l = panel.value("ldl")?.value {
                let remnant = t - h - l
                out.append(Enhancer(id: "remnant", name: "Remnant cholesterol", value: remnant, unit: "mg/dL",
                                    tier: tier(remnant, [24, 30, 40]), optimalBound: 24, lowerIsBetter: true))
            }
        }
        return out
    }

    private static func tier(_ v: Double, _ cuts: [Double]) -> Tier {
        if v < cuts[0] { return .optimal }
        if v < cuts[1] { return .borderline }
        if v < cuts[2] { return .elevated }
        return .high
    }
}

// MARK: - Engine

nonisolated enum CardiometabolicRisk {
    /// Descriptive bands for a percentage, the ones cardiology uses to talk
    /// about a ten year estimate. Not treatment thresholds.
    enum Tier: String, Sendable {
        case low, borderline, intermediate, high

        var title: String {
            switch self {
            case .low: "Low"
            case .borderline: "Borderline"
            case .intermediate: "Intermediate"
            case .high: "High"
            }
        }
    }

    struct Estimate: Sendable, Identifiable, Equatable {
        var id: String { "\(outcome.rawValue).\(horizon.rawValue)" }
        var outcome: PreventEquations.Outcome
        var horizon: PreventEquations.Horizon
        /// Nil exactly when `refusal` is set.
        var percent: Double?
        var tier: Tier?
        var refusal: PreventEquations.Ineligibility?
    }

    /// How much ten year ASCVD risk falls when one input moves to its optimum.
    struct Driver: Sendable, Identifiable, Equatable {
        var id: String
        var label: String
        var deltaPercent: Double
    }

    struct Report: Sendable, Equatable {
        var estimates: [Estimate]
        var enhancers: [RiskEnhancers.Enhancer]
        var inputs: CardiometabolicRiskInputs?
        var missing: [MissingRiskInput]
        var drivers: [Driver]
        /// The date of the panel the lipids came from.
        var panelDate: Date?

        var headline: Estimate? { estimates.first { $0.outcome == .ascvd && $0.horizon == .tenYear } }
    }

    static func report(panels: [BloodPanel], systolicBP: Double?, ageYears: Double?, sex: LabSex?,
                       profile: CardiometabolicProfile, bodyMassIndex: Double?) -> Report {
        let lipidPanel = panels
            .filter { $0.value("totalCholesterol") != nil && $0.value("hdl") != nil }
            .max { $0.date < $1.date }
        let latest = panels.max { $0.date < $1.date }
        let selected = lipidPanel ?? latest

        let resolved = CardiometabolicRiskInputs.resolve(panel: selected, systolicBP: systolicBP,
                                                         ageYears: ageYears, sex: sex, profile: profile)
        let inputs: CardiometabolicRiskInputs?
        let missing: [MissingRiskInput]
        switch resolved {
        case .success(let value): inputs = value; missing = []
        case .failure(let failure): inputs = nil; missing = failure.inputs
        }

        let estimates = PreventEquations.Outcome.allCases.flatMap { outcome in
            PreventEquations.Horizon.allCases.map { horizon -> Estimate in
                guard let inputs else {
                    return Estimate(outcome: outcome, horizon: horizon, percent: nil, tier: nil, refusal: .requiredInputsMissing)
                }
                switch PreventEquations.risk(outcome: outcome, horizon: horizon, inputs: inputs, bodyMassIndexKgM2: bodyMassIndex) {
                case .success(let percent):
                    return Estimate(outcome: outcome, horizon: horizon, percent: percent, tier: tier(percent), refusal: nil)
                case .failure(let reason):
                    return Estimate(outcome: outcome, horizon: horizon, percent: nil, tier: nil, refusal: reason)
                }
            }
        }

        var drivers: [Driver] = []
        if let inputs, case .success(let baseline) = PreventEquations.risk(
            outcome: .ascvd, horizon: .tenYear, inputs: inputs, bodyMassIndexKgM2: bodyMassIndex) {
            drivers = Self.drivers(baseline: baseline, inputs: inputs, bmi: bodyMassIndex)
        }

        return Report(
            estimates: estimates,
            enhancers: latest.map { RiskEnhancers.enhancers(panel: $0, sex: sex) } ?? [],
            inputs: inputs,
            missing: missing,
            drivers: drivers,
            panelDate: selected?.date
        )
    }

    static func tier(_ percent: Double) -> Tier {
        if percent < 5 { return .low }
        if percent < 7.5 { return .borderline }
        if percent < 20 { return .intermediate }
        return .high
    }

    private static func drivers(baseline: Double, inputs: CardiometabolicRiskInputs, bmi: Double?) -> [Driver] {
        func driver(_ id: String, _ label: String, _ change: (inout CardiometabolicRiskInputs) -> Void) -> Driver? {
            var modified = inputs
            change(&modified)
            guard case .success(let percent) = PreventEquations.risk(
                outcome: .ascvd, horizon: .tenYear, inputs: modified, bodyMassIndexKgM2: bmi) else { return nil }
            let drop = baseline - percent
            return drop > 0 ? Driver(id: id, label: label, deltaPercent: drop) : nil
        }
        return [
            driver("systolicBP", "Blood pressure") { $0.systolicBP = 110 },
            driver("nonHDL", "Non-HDL cholesterol") { $0.totalCholesterolMgDl = $0.hdlMgDl + 100 },
            driver("hdl", "HDL cholesterol") { $0.hdlMgDl = 60 },
            driver("smoking", "Smoking") { $0.currentSmoker = false },
            driver("diabetes", "Diabetes") { $0.diabetes = false },
            driver("egfr", "Kidney function") { $0.egfr = 100 },
        ]
        .compactMap { $0 }
        .sorted { $0.deltaPercent > $1.deltaPercent }
    }
}
