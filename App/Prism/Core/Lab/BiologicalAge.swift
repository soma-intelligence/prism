//
//  BiologicalAge.swift
//  Prism
//
//  Biological age: Levine's PhenoAge over a blood panel,
//  and the hazard model that folds it together with what the watch and the
//  scale have measured.
//
//  Each input is turned into a z score against an age and sex matched
//  reference, weighted by a log hazard coefficient from the published
//  mortality ratios, summed, and converted into years on a Gompertz curve
//  (mortality doubling every eight years). Series are collapsed to an
//  exponentially weighted mean with a ninety day half life first, so one bad
//  night never moves the age.
//
//  A wellness estimate, never a diagnosis.
//

import Foundation

// MARK: - PhenoAge

nonisolated enum PhenoAge {
    struct Result: Sendable, Equatable {
        /// Phenotypic age in years.
        var phenotypicAge: Double
        /// Each real marker's signed contribution in years, leave one out
        /// against its population median. Indicative: the model is not
        /// linear, so these do not sum exactly to the total.
        var perMarkerYears: [BloodMarkerKey: Double]
        /// The markers imputed because the panel did not carry them.
        var imputed: Set<BloodMarkerKey>
        /// Real markers over nine.
        var completeness: Double
    }

    /// `markers` in each key's Levine unit.
    static func compute(markers: [BloodMarkerKey: Double], chronologicalAge: Double, sex: LabSex) -> Result {
        let real = Set(markers.keys)
        let imputed = Set(BloodMarkerKey.allCases).subtracting(real)

        func filled(overriding overrides: [BloodMarkerKey: Double] = [:]) -> [BloodMarkerKey: Double] {
            var all = markers
            for key in imputed { all[key] = key.referenceMedian(sex: sex) }
            for (key, value) in overrides { all[key] = value }
            return all
        }

        let age = phenoAge(filled(), chronologicalAge)
        var per: [BloodMarkerKey: Double] = [:]
        for key in real {
            per[key] = age - phenoAge(filled(overriding: [key: key.referenceMedian(sex: sex)]), chronologicalAge)
        }
        return Result(phenotypicAge: age, perMarkerYears: per, imputed: imputed,
                      completeness: Double(real.count) / Double(BloodMarkerKey.allCases.count))
    }

    /// Levine's linear predictor, the mortality score and its inversion.
    private static func phenoAge(_ m: [BloodMarkerKey: Double], _ age: Double) -> Double {
        // CRP enters as ln(mg/dL); a near zero reading is floored so a very
        // healthy value never leaves the log's domain.
        let crp = max(m[.crp] ?? 0.01, 0.01)
        let xb = -19.907
            - 0.0336 * (m[.albumin] ?? 0)
            + 0.0095 * (m[.creatinine] ?? 0)
            + 0.1953 * (m[.glucose] ?? 0)
            + 0.0954 * log(crp)
            - 0.0120 * (m[.lymphocytePercent] ?? 0)
            + 0.0268 * (m[.mcv] ?? 0)
            + 0.3306 * (m[.rdw] ?? 0)
            + 0.00188 * (m[.alp] ?? 0)
            + 0.0554 * (m[.wbc] ?? 0)
            + 0.0804 * age
        let g = 0.0076927
        let mortality = 1 - exp(-exp(xb) * (exp(120 * g) - 1) / g)
        let clamped = min(max(mortality, 1e-8), 1 - 1e-8)
        return 141.50225 + log(-0.00553 * log(1 - clamped)) / 0.090165
    }
}

// MARK: - Biological age

nonisolated enum BiologicalAge {
    enum Confidence: Int, Comparable, Sendable {
        case insufficient, low, medium, high

        static func < (lhs: Confidence, rhs: Confidence) -> Bool { lhs.rawValue < rhs.rawValue }

        /// How wide the band around the estimate is, in years.
        var spread: Double {
            switch self {
            case .insufficient: 5
            case .low: 4
            case .medium: 3
            case .high: 2
            }
        }
    }

    /// One input and what it moved.
    struct Component: Sendable, Equatable, Identifiable {
        var id: String { label }
        var label: String
        var zScore: Double
        /// Signed years: negative reads younger.
        var yearsDelta: Double
        var windowDays: Int
        /// True for the blood markers, so the page can say where it came from.
        var isBlood: Bool
    }

    struct Result: Sendable, Equatable {
        var estimatedAge: Double
        /// Estimated minus chronological, clamped. Negative is younger.
        var deltaYears: Double
        var components: [Component]
        var coverageDays: Int
        var bloodPanels: Int

        var confidence: Confidence {
            let coverage: Confidence = switch coverageDays {
            case 90...: .high
            case 30..<90: .medium
            case 14..<30: .low
            default: bloodPanels > 0 ? .low : .insufficient
            }
            let breadth: Confidence = switch components.count {
            case 0, 1: .insufficient
            case 2: .low
            case 3: .medium
            default: .high
            }
            var tier = min(coverage, breadth)
            // Two panels or more firm up an estimate the blood carries.
            if bloodPanels >= 2, tier < .high { tier = Confidence(rawValue: tier.rawValue + 1) ?? tier }
            return tier
        }
    }

    /// What the estimate reads: daily series, oldest first, and the latest panel.
    struct Inputs: Sendable, Equatable {
        var chronologicalAge: Int
        var sex: LabSex
        var restingHR: [Double] = []
        var hrv: [Double] = []
        var vo2Max: [Double] = []
        var bmi: [Double] = []
        var steps: [Double] = []
        var sleepHours: [Double] = []
        var bodyFatPercent: [Double] = []
        var systolic: [Double] = []
        var bloodMarkers: [BloodMarkerKey: Double] = [:]
        var extendedBloodMarkers: [String: Double] = [:]
        var bloodPanels = 0
    }

    static let gompertzGamma = log(2) / 8.0
    static let yearsClamp = 6.0
    static let perComponentClamp = 3.0
    static let bloodComponentClamp = 5.0
    static let bloodCompleteTotalClamp = 8.0
    static let minBloodMarkers = 3
    static let minDays = 14
    static let minDaysHeart = 30
    static let ewmaWindowDays = 365
    static let ewmaHalfLifeDays = 90.0

    private static let betaVO2Max = 0.18
    private static let betaHRV = 0.16
    private static let betaRHRMale = 0.18
    private static let betaRHRFemale = 0.16
    private static let betaBMI = 0.10
    private static let betaSteps = 0.18
    private static let betaSleepConsistency = 0.14
    private static let betaSleepShort = 0.058
    private static let betaSleepLong = 0.122
    private static let sleepNadirHours = 7.0
    private static let betaBodyFat = 0.10
    private static let betaSystolic = 0.17
    private static let stepTau = 4_000.0
    private static let stepPivot = 7_000.0
    private static let stepBenefitSD = 0.12

    /// The estimate, or nil when nothing has enough history to say anything.
    static func compute(_ inputs: Inputs) -> Result? {
        let age = inputs.chronologicalAge
        guard age > 0 else { return nil }
        let sex = inputs.sex
        var components: [Component] = []
        var logHazard = 0.0

        func add(_ label: String, z: Double, logH: Double, days: Int) {
            let years = max(-perComponentClamp, min(perComponentClamp, logH / gompertzGamma))
            components.append(Component(label: label, zScore: z, yearsDelta: years, windowDays: days, isBlood: false))
            logHazard += years * gompertzGamma
        }

        if let s = signal(inputs.vo2Max, minDays: minDays) {
            let z = vo2MaxZ(s.mean, age: age, sex: sex)
            add("VO2 max", z: z, logH: -betaVO2Max * z, days: s.days)
        }
        if let s = signal(inputs.hrv, minDays: minDaysHeart) {
            let z = hrvZ(s.mean, age: age)
            add("HRV", z: z, logH: -betaHRV * z, days: s.days)
        }
        if let s = signal(inputs.restingHR, minDays: minDaysHeart) {
            let z = restingZ(s.mean, sex: sex)
            add("Resting heart rate", z: z, logH: -(sex == .male ? betaRHRMale : betaRHRFemale) * z, days: s.days)
        }
        if let s = signal(inputs.bmi, minDays: minDays) {
            let z = -abs(s.mean - 22.5) / 3.0
            add("BMI", z: z, logH: -betaBMI * z, days: s.days)
        }
        if let s = signal(inputs.steps, minDays: minDays), s.mean > 0 {
            let z = (stepBenefit(s.mean) - stepBenefit(stepPivot)) / stepBenefitSD
            add("Daily steps", z: z, logH: -betaSteps * z, days: s.days)
        }
        let nights = inputs.sleepHours.filter { $0.isFinite && $0 > 0 }
        if nights.count >= minDays, let z = consistencyZ(Array(nights.suffix(180))) {
            add("Sleep consistency", z: z, logH: -betaSleepConsistency * z, days: min(nights.count, 180))
        }
        if let s = signal(nights, minDays: minDays) {
            let h = s.mean
            let adverse = h < sleepNadirHours ? betaSleepShort * (sleepNadirHours - h) : betaSleepLong * (h - sleepNadirHours)
            add("Sleep duration", z: 0, logH: adverse, days: s.days)
        }
        if let s = signal(inputs.bodyFatPercent, minDays: minDays), s.mean > 0 {
            let z = bodyFatZ(s.mean, age: age, sex: sex)
            add("Body fat", z: z, logH: -betaBodyFat * z, days: s.days)
        }
        if let s = signal(inputs.systolic, minDays: minDays), s.mean > 0 {
            let z = min((120 - s.mean) / 15, 0.7)
            add("Blood pressure", z: z, logH: -betaSystolic * z, days: s.days)
        }

        var bloodComplete = false
        if inputs.bloodMarkers.count >= minBloodMarkers {
            let pheno = PhenoAge.compute(markers: inputs.bloodMarkers, chronologicalAge: Double(age), sex: sex)
            let raw = (pheno.phenotypicAge - Double(age)) * pheno.completeness
            let years = max(-bloodComponentClamp, min(bloodComponentClamp, raw))
            components.append(Component(label: "Blood panel", zScore: 0, yearsDelta: years, windowDays: 0, isBlood: true))
            logHazard += years * gompertzGamma
            bloodComplete = pheno.completeness >= 0.999
        }
        for c in extendedContributions(inputs.extendedBloodMarkers) where c.years > 0.01 {
            components.append(Component(label: c.label, zScore: 0, yearsDelta: c.years, windowDays: 0, isBlood: true))
            logHazard += c.years * gompertzGamma
        }

        guard !components.isEmpty else { return nil }
        let clamp = bloodComplete ? bloodCompleteTotalClamp : yearsClamp
        let delta = max(-clamp, min(clamp, logHazard / gompertzGamma))
        let coverage = signal(inputs.hrv, minDays: minDaysHeart)?.days
            ?? signal(inputs.restingHR, minDays: minDaysHeart)?.days
            ?? components.map(\.windowDays).max() ?? 0
        return Result(
            estimatedAge: max(15, Double(age) + delta).rounded(),
            deltaYears: delta.rounded(),
            components: components,
            coverageDays: coverage,
            bloodPanels: inputs.bloodPanels
        )
    }

    // MARK: Extended markers

    struct MarkerModel: Sendable {
        enum Mode: Sendable { case higherWorse, lowerWorse, uShaped(band: Double) }
        var id: String
        var label: String
        var mid: Double
        var sd: Double
        var beta: Double
        var mode: Mode

        func adverseZ(_ v: Double) -> Double {
            guard sd > 0 else { return 0 }
            switch mode {
            case .higherWorse: return max(0, (v - mid) / sd)
            case .lowerWorse: return max(0, (mid - v) / sd)
            case .uShaped(let band): return max(0, abs(v - mid) / sd - band)
            }
        }
    }

    /// Markers outside PhenoAge that only ever add years, and only when
    /// they sit on the adverse side of their midpoint.
    static let extendedModels: [MarkerModel] = [
        .init(id: "hba1c", label: "HbA1c", mid: 5.3, sd: 0.5, beta: 0.14, mode: .uShaped(band: 0.6)),
        .init(id: "homaIR", label: "Insulin resistance", mid: 1.0, sd: 1.0, beta: 0.09, mode: .higherWorse),
        .init(id: "insulin", label: "Fasting insulin", mid: 55, sd: 40, beta: 0.06, mode: .higherWorse),
        .init(id: "triglycerides", label: "Triglycerides", mid: 90, sd: 55, beta: 0.08, mode: .higherWorse),
        .init(id: "hdl", label: "HDL", mid: 60, sd: 15, beta: 0.10, mode: .lowerWorse),
        .init(id: "ldl", label: "LDL", mid: 100, sd: 30, beta: 0.07, mode: .higherWorse),
        .init(id: "ggt", label: "GGT", mid: 20, sd: 15, beta: 0.10, mode: .higherWorse),
        .init(id: "homocysteine", label: "Homocysteine", mid: 8, sd: 3, beta: 0.12, mode: .higherWorse),
        .init(id: "uricAcid", label: "Uric acid", mid: 300, sd: 80, beta: 0.06, mode: .higherWorse),
        .init(id: "vitaminD", label: "Vitamin D", mid: 40, sd: 15, beta: 0.08, mode: .lowerWorse),
        .init(id: "ferritin", label: "Ferritin", mid: 100, sd: 80, beta: 0.05, mode: .uShaped(band: 0.7)),
    ]

    static func extendedContributions(_ markers: [String: Double]) -> [(id: String, label: String, years: Double)] {
        extendedModels.compactMap { model in
            if model.id == "insulin", markers["homaIR"] != nil { return nil }
            guard let v = markers[model.id], v.isFinite else { return nil }
            let years = min(perComponentClamp, max(0, model.beta * model.adverseZ(v) / gompertzGamma))
            return (model.id, model.label, years)
        }
    }

    // MARK: Arithmetic

    private struct Signal { var mean: Double; var days: Int }

    private static func signal(_ series: [Double], minDays: Int) -> Signal? {
        let cleaned = series.filter(\.isFinite)
        guard cleaned.count >= minDays else { return nil }
        let window = Array(cleaned.suffix(ewmaWindowDays))
        var num = 0.0, den = 0.0
        for (i, x) in window.enumerated() {
            let w = pow(0.5, Double(window.count - 1 - i) / ewmaHalfLifeDays)
            num += w * x
            den += w
        }
        guard den > 0 else { return nil }
        return Signal(mean: num / den, days: window.count)
    }

    private static func stepBenefit(_ steps: Double) -> Double { 1 - exp(-steps / stepTau) }

    private static func consistencyZ(_ series: [Double]) -> Double? {
        guard series.count >= 14 else { return nil }
        let m = series.reduce(0, +) / Double(series.count)
        guard m > 0 else { return nil }
        let variance = series.map { pow($0 - m, 2) }.reduce(0, +) / Double(series.count)
        return (0.08 - sqrt(variance) / m) / 0.085
    }

    static func vo2MaxZ(_ v: Double, age: Int, sex: LabSex) -> Double {
        let male = sex == .male
        let (mean, sd): (Double, Double) = switch age {
        case ..<30: (male ? 48 : 42, 6)
        case 30..<40: (male ? 44 : 38, 6)
        case 40..<50: (male ? 40 : 34, 5)
        case 50..<60: (male ? 36 : 30, 5)
        case 60..<70: (male ? 32 : 26, 5)
        default: (male ? 28 : 23, 4)
        }
        return (v - mean) / sd
    }

    static func hrvZ(_ v: Double, age: Int) -> Double {
        let capped = min(max(Double(age), 18), 50)
        let mean = max(18, 40 + (48 - capped))
        return (v - mean) / max(10, mean * 0.25)
    }

    static func restingZ(_ v: Double, sex: LabSex) -> Double {
        ((sex == .male ? 68 : 72) - v) / 10
    }

    static func bodyFatZ(_ v: Double, age: Int, sex: LabSex) -> Double {
        let male = sex == .male
        let mid: Double = switch age {
        case ..<40: male ? 19 : 28
        case 40..<60: male ? 22 : 31
        default: male ? 24 : 33
        }
        return min((mid - v) / 6, 1.5)
    }
}

// MARK: - A panel's effect

/// What one panel says about biological age: the phenotypic age, the gap to
/// the calendar, and which markers pull which way. Nil below three markers.
nonisolated struct BloodAgeReading: Sendable, Equatable {
    struct Mover: Sendable, Equatable, Identifiable {
        var id: String { key.rawValue }
        var key: BloodMarkerKey
        var years: Double
    }

    var chronologicalAge: Double
    var phenoAge: Double
    var completeness: Double
    /// Signed: negative pulls younger. Largest effect first.
    var movers: [Mover]

    var deltaYears: Double { phenoAge - chronologicalAge }

    static func make(panel: BloodPanel, chronologicalAge: Double, sex: LabSex) -> BloodAgeReading? {
        let values = panel.phenoAgeValues
        guard values.count >= BiologicalAge.minBloodMarkers else { return nil }
        let result = PhenoAge.compute(markers: values, chronologicalAge: chronologicalAge, sex: sex)
        let movers = result.perMarkerYears
            .filter { abs($0.value) > 0.05 }
            .map { Mover(key: $0.key, years: $0.value) }
            .sorted { abs($0.years) > abs($1.years) }
        return BloodAgeReading(chronologicalAge: chronologicalAge, phenoAge: result.phenotypicAge,
                               completeness: result.completeness, movers: movers)
    }
}
