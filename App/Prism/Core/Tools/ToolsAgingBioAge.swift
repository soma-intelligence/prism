//
//  ToolsAgingBioAge.swift
//  Prism
//
//  The wearable core of the hazard based biological age model that feeds the
//  Aging Pace tool, kept pure.
//
//  PIPELINE
//  1. Each input metric (HRV, resting HR, VO2 max, steps, sleep, body fat,
//     blood pressure) arrives as a LONGITUDINAL daily series, oldest first.
//     Each series collapses to a recency weighted mean before z scoring, so a
//     single bad night never moves the estimate.
//  2. The longitudinal mean is converted to a z score against an age and sex
//     matched reference (NHANES, ACSM, overnight SDNN cohorts).
//  3. Each z score is multiplied by a per metric log hazard coefficient
//     derived from published mortality hazard ratios. The sum is the personal
//     log hazard deviation relative to an age matched peer.
//  4. That deviation converts to years on a Gompertz mortality curve
//     (gamma = ln 2 / 8 per year, mortality doubling every eight years):
//     bio age = calendar age + deviation / gamma.
//  5. Each metric is clamped at plus or minus 3 years and the total at plus or
//     minus 6, so sparse data never produces a theatrical reading.
//
//  What was left out of the port: the lifestyle layer (diet, alcohol,
//  tobacco from a journal) and the blood layer (PhenoAge and extended
//  markers). Soma has no journal or lab source for them yet; with no input
//  they contribute nothing, so the wearable result is the
//  same number a user with no logs and no labs gets.
//
//  THIS IS NOT A MEDICAL DEVICE. The coefficients are documented inline with
//  their source hazard ratios so a clinician can audit them.
//

import Foundation

extension SomaTools {

    nonisolated enum AgingBioAge {

        /// Biological sex as the reference ranges need it. Anything that is not
        /// `.male` reads the female reference, which is what the source model did.
        enum Sex: String, Sendable, Equatable, Codable {
            case male, female
        }

        /// Longitudinal daily series, oldest first. Empty means "no data", and a
        /// series shorter than its floor is silently left out.
        struct Inputs: Sendable, Equatable {
            var restingHR: [Double] = []
            var hrv: [Double] = []
            var vo2Max: [Double] = []
            var sleepEfficiency: [Double] = []
            var bmi: [Double] = []
            var steps: [Double] = []
            var sleepHours: [Double] = []
            var bodyFatPercent: [Double] = []
            var systolicBP: [Double] = []

            init(restingHR: [Double] = [], hrv: [Double] = [], vo2Max: [Double] = [],
                 sleepEfficiency: [Double] = [], bmi: [Double] = [], steps: [Double] = [],
                 sleepHours: [Double] = [], bodyFatPercent: [Double] = [],
                 systolicBP: [Double] = []) {
                self.restingHR = restingHR
                self.hrv = hrv
                self.vo2Max = vo2Max
                self.sleepEfficiency = sleepEfficiency
                self.bmi = bmi
                self.steps = steps
                self.sleepHours = sleepHours
                self.bodyFatPercent = bodyFatPercent
                self.systolicBP = systolicBP
            }
        }

        /// Which metric a component comes from. A closed set, so a page can
        /// name it in its own words instead of parsing a label.
        enum Metric: String, Sendable, Equatable, CaseIterable {
            case vo2Max, hrv, restingHR, sleepEfficiency, bmi, steps
            case sleepConsistency, sleepDuration, bodyComposition, bloodPressure

            /// Plain English label, the one the source model used.
            var label: String {
                switch self {
                case .vo2Max: return "VO2 Max"
                case .hrv: return "HRV"
                case .restingHR: return "Resting HR"
                case .sleepEfficiency: return "Sleep efficiency"
                case .bmi: return "BMI"
                case .steps: return "Daily steps"
                case .sleepConsistency: return "Sleep consistency"
                case .sleepDuration: return "Sleep duration"
                case .bodyComposition: return "Body composition"
                case .bloodPressure: return "Blood pressure"
                }
            }
        }

        struct Component: Sendable, Equatable {
            let metric: Metric
            /// Z score against the age and sex matched reference, from the
            /// trailing longitudinal mean. Positive = better than the norm.
            let zScore: Double
            /// Years this metric contributed. Negative pulls younger.
            let yearsDelta: Double
            /// Log hazard contribution (beta times z), before the Gompertz
            /// inversion.
            let logHazardDelta: Double
            /// Days that fed this component's longitudinal mean.
            let windowDays: Int
        }

        enum Confidence: Int, Sendable, Comparable {
            case insufficient = 0, low, medium, high
            static func < (lhs: Confidence, rhs: Confidence) -> Bool { lhs.rawValue < rhs.rawValue }
        }

        struct Result: Sendable, Equatable {
            /// The estimate, rounded to whole years: a wearable hazard estimate
            /// clamped to a handful of years cannot claim 0.1 year precision.
            let estimatedAge: Double
            /// The same estimate before rounding. What a what if lever reads, so
            /// a small nudge is not swallowed by the whole year rounding.
            let unroundedAge: Double
            /// Age acceleration, rounded. Negative = younger than the calendar.
            let deltaYears: Double
            /// Personal log hazard deviation, before the Gompertz inversion.
            let logHazardDelta: Double
            /// Bio years per calendar year from the two window comparison, or nil
            /// without 90 days of HRV and resting HR.
            let paceOfAging: Double?
            /// 0 to 100, inverse of long term HRV variability.
            let resilience: Double?
            let components: [Component]
            /// Days behind the dominant signal (HRV, falling back to resting HR).
            let coverageDays: Int

            /// The weaker of coverage and component count. Both have to clear
            /// the bar before a reading is called high confidence.
            var confidence: Confidence {
                let coverageTier: Confidence
                switch coverageDays {
                case 90...: coverageTier = .high
                case 30..<90: coverageTier = .medium
                case 14..<30: coverageTier = .low
                default: coverageTier = .insufficient
                }
                let componentTier: Confidence
                switch components.count {
                case 0, 1: componentTier = .insufficient
                case 2: componentTier = .low
                case 3: componentTier = .medium
                default: componentTier = .high
                }
                return min(coverageTier, componentTier)
            }
        }

        // MARK: Gompertz constant and clamps

        /// Adult all cause mortality doubles roughly every 8 years from age 30.
        /// gamma = ln(2) / 8, so one unit of log hazard is about 11.5 years.
        static let gompertzGamma: Double = log(2) / 8.0
        /// Hard cap on the total deviation. Without bloodwork a 10 year shift
        /// cannot be defended.
        static let yearsClamp: Double = 6.0
        /// No single metric may move the age more than this.
        static let perComponentClamp: Double = 3.0

        // MARK: Longitudinal windows

        /// Floor below which a metric stops contributing.
        static let minDaysPerComponent = 14
        /// Stricter floor for HRV and resting HR, the dominant signals.
        static let minDaysHRMetrics = 30
        /// Window for the pace, resilience and consistency terms.
        static let longitudinalWindowDays = 180
        /// Window for the per metric recency weighted mean.
        static let ewmaWindowDays = 365
        /// A day 90 days old counts half as much as today.
        static let ewmaHalfLifeDays: Double = 90.0
        /// Saturating step benefit (Paluch 2022, Ding 2025, plateau near 7k).
        static let stepTau: Double = 4_000
        static let stepPivot: Double = 7_000
        static let stepBenefitSD: Double = 0.12

        // MARK: Log hazard coefficients (per +1 SD in the protective direction)

        /// VO2 max. Laukkanen 2022 meta analysis, weighted down because the
        /// watch VO2 max is itself an estimate.
        static let betaVO2Max: Double = 0.18
        /// HRV. Tegegne 2020 (EHRA): per +1 SD HR about 0.85.
        static let betaHRV: Double = 0.16
        /// Resting HR. Raisi-Estabragh 2020 (UK Biobank): per +10 bpm HR about
        /// 1.22 in men and 1.19 in women.
        static let betaRHRMale: Double = 0.18
        static let betaRHRFemale: Double = 0.16
        /// Sleep efficiency. Sabia 2021.
        static let betaSleep: Double = 0.15
        /// BMI. Aune 2016 (BMJ), U shaped around 22.5.
        static let betaBMI: Double = 0.10
        /// Daily steps. Paluch 2022, Ding 2025.
        static let betaSteps: Double = 0.18
        /// Sleep consistency. Hoopes 2023.
        static let betaSleepConsistency: Double = 0.14
        /// Sleep duration, asymmetric around a 7 h nadir (Yin 2017, JAHA).
        static let betaSleepShort: Double = 0.058
        static let betaSleepLong: Double = 0.122
        static let sleepNadirHours: Double = 7.0
        /// Body fat percent. Aune 2016, Gallagher 2000 bands.
        static let betaBodyFat: Double = 0.10
        /// Systolic pressure. Lewington 2002, per SD (about 15 mmHg).
        static let betaSystolicBP: Double = 0.17

        // MARK: Compute

        /// A hazard based biological age from longitudinal series. nil when the
        /// calendar age is not positive or every series is below its floor.
        static func compute(chronologicalAge: Int, sex: Sex, inputs: Inputs) -> Result? {
            guard chronologicalAge > 0 else { return nil }
            let age = chronologicalAge
            var components: [Component] = []
            var total: Double = 0

            func append(_ metric: Metric, z: Double, logHazard: Double, days: Int) {
                let rawYears = logHazard / gompertzGamma
                let years = max(-perComponentClamp, min(perComponentClamp, rawYears))
                let logH = years * gompertzGamma
                components.append(Component(metric: metric, zScore: z, yearsDelta: years,
                                            logHazardDelta: logH, windowDays: days))
                total += logH
            }

            if let s = longitudinalSignal(inputs.vo2Max, minDays: minDaysPerComponent) {
                let z = vo2MaxZ(v: s.mean, age: age, sex: sex)
                append(.vo2Max, z: z, logHazard: -betaVO2Max * z, days: s.windowDays)
            }
            if let s = longitudinalSignal(inputs.hrv, minDays: minDaysHRMetrics) {
                let z = hrvZ(v: s.mean, age: age)
                append(.hrv, z: z, logHazard: -betaHRV * z, days: s.windowDays)
            }
            if let s = longitudinalSignal(inputs.restingHR, minDays: minDaysHRMetrics) {
                let z = restingHRZ(v: s.mean, sex: sex)
                let beta = sex == .male ? betaRHRMale : betaRHRFemale
                append(.restingHR, z: z, logHazard: -beta * z, days: s.windowDays)
            }
            if let s = longitudinalSignal(inputs.sleepEfficiency, minDays: minDaysPerComponent) {
                let z = (s.mean - 0.85) / 0.05
                append(.sleepEfficiency, z: z, logHazard: -betaSleep * z, days: s.windowDays)
            }
            if let s = longitudinalSignal(inputs.bmi, minDays: minDaysPerComponent) {
                let z = -abs(s.mean - 22.5) / 3.0
                append(.bmi, z: z, logHazard: -betaBMI * z, days: s.windowDays)
            }
            if let s = longitudinalSignal(inputs.steps, minDays: minDaysPerComponent), s.mean > 0 {
                let z = (stepBenefit(s.mean) - stepBenefit(stepPivot)) / stepBenefitSD
                append(.steps, z: z, logHazard: -betaSteps * z, days: s.windowDays)
            }
            if inputs.sleepHours.count >= minDaysPerComponent,
               let z = consistencyZScore(series: Array(inputs.sleepHours.suffix(longitudinalWindowDays))) {
                let days = min(inputs.sleepHours.count, longitudinalWindowDays)
                append(.sleepConsistency, z: z, logHazard: -betaSleepConsistency * z, days: days)
            }
            if let s = longitudinalSignal(inputs.sleepHours, minDays: minDaysPerComponent) {
                let h = s.mean
                let adverse = h < sleepNadirHours
                    ? betaSleepShort * (sleepNadirHours - h)
                    : betaSleepLong * (h - sleepNadirHours)
                append(.sleepDuration, z: 0, logHazard: adverse, days: s.windowDays)
            }
            if let s = longitudinalSignal(inputs.bodyFatPercent, minDays: minDaysPerComponent), s.mean > 0 {
                let z = bodyFatZ(v: s.mean, age: age, sex: sex)
                append(.bodyComposition, z: z, logHazard: -betaBodyFat * z, days: s.windowDays)
            }
            if let s = longitudinalSignal(inputs.systolicBP, minDays: minDaysPerComponent), s.mean > 0 {
                let z = systolicBPZ(v: s.mean)
                append(.bloodPressure, z: z, logHazard: -betaSystolicBP * z, days: s.windowDays)
            }

            guard !components.isEmpty else { return nil }

            let yearsDelta = total / gompertzGamma
            let clamped = max(-yearsClamp, min(yearsClamp, yearsDelta))
            let bioAge = max(15, Double(age) + clamped)

            let coverage: Int = {
                if let s = longitudinalSignal(inputs.hrv, minDays: minDaysHRMetrics) { return s.windowDays }
                if let s = longitudinalSignal(inputs.restingHR, minDays: minDaysHRMetrics) { return s.windowDays }
                return components.map(\.windowDays).max() ?? 0
            }()

            return Result(estimatedAge: bioAge.rounded(),
                          unroundedAge: bioAge,
                          deltaYears: clamped.rounded(),
                          logHazardDelta: total,
                          paceOfAging: paceOfAging(chronologicalAge: age, sex: sex,
                                                   hrvSeries: inputs.hrv,
                                                   restingHRSeries: inputs.restingHR),
                          resilience: resilienceScore(hrvSeries: inputs.hrv),
                          components: components,
                          coverageDays: coverage)
        }

        // MARK: Longitudinal signal

        struct LongitudinalSignal: Sendable, Equatable {
            let mean: Double
            let windowDays: Int
        }

        /// Up to a year of history collapsed to a recency weighted mean.
        /// Non finite samples are dropped first.
        static func longitudinalSignal(_ series: [Double], minDays: Int) -> LongitudinalSignal? {
            guard series.count >= minDays else { return nil }
            let cleaned = series.filter { $0.isFinite }
            guard cleaned.count >= minDays else { return nil }
            let window = Array(cleaned.suffix(ewmaWindowDays))
            guard let m = ewmaMean(window) else { return nil }
            return LongitudinalSignal(mean: m, windowDays: window.count)
        }

        /// Exponentially recency weighted mean, newest sample at full weight.
        /// For a constant series it equals the plain mean.
        static func ewmaMean(_ xs: [Double]) -> Double? {
            guard !xs.isEmpty else { return nil }
            let n = xs.count
            var num = 0.0, den = 0.0
            for (i, x) in xs.enumerated() {
                let ageDays = Double(n - 1 - i)
                let w = pow(0.5, ageDays / ewmaHalfLifeDays)
                num += w * x
                den += w
            }
            return den > 0 ? num / den : nil
        }

        /// `1 - exp(-steps / tau)`: steep early gains, a long flat tail.
        static func stepBenefit(_ steps: Double) -> Double {
            1 - exp(-steps / stepTau)
        }

        // MARK: Pace of aging

        /// DunedinPACE idea: the same hazard model on a recent 30 day window
        /// and the 60 days before it, as bio years per calendar year. Needs 90
        /// days of HRV and resting HR. Clamped to 0.4 to 1.8.
        static func paceOfAging(chronologicalAge: Int, sex: Sex,
                                hrvSeries: [Double], restingHRSeries: [Double]) -> Double? {
            guard hrvSeries.count >= 90, restingHRSeries.count >= 90 else { return nil }
            let hrv = Array(hrvSeries.suffix(longitudinalWindowDays))
            let rhr = Array(restingHRSeries.suffix(longitudinalWindowDays))
            guard let recentHRV = mean(Array(hrv.suffix(30))),
                  let olderHRV = mean(Array(hrv.dropLast(30).suffix(60))),
                  let recentRHR = mean(Array(rhr.suffix(30))),
                  let olderRHR = mean(Array(rhr.dropLast(30).suffix(60))) else { return nil }

            let betaRHR = sex == .male ? betaRHRMale : betaRHRFemale
            let recentLogH = -betaHRV * hrvZ(v: recentHRV, age: chronologicalAge)
                - betaRHR * restingHRZ(v: recentRHR, sex: sex)
            let olderLogH = -betaHRV * hrvZ(v: olderHRV, age: chronologicalAge)
                - betaRHR * restingHRZ(v: olderRHR, sex: sex)
            // Window centres sit about 45 days apart.
            let slope = ((recentLogH - olderLogH) / gompertzGamma) / (45.0 / 365.0)
            return max(0.4, min(1.8, 1 + slope))
        }

        // MARK: Resilience

        /// HRV coefficient of variation mapped to 0...100: CV 0.10 or less is
        /// 100, CV 0.40 or more is 0 (Plews 2013).
        static func resilienceScore(hrvSeries: [Double]) -> Double? {
            guard hrvSeries.count >= 14 else { return nil }
            let window = Array(hrvSeries.suffix(longitudinalWindowDays)).filter { $0.isFinite }
            guard window.count >= 14, let m = mean(window), m > 0 else { return nil }
            let variance = window.map { pow($0 - m, 2) }.reduce(0, +) / Double(window.count)
            let cv = sqrt(variance) / m
            let raw = max(0, min(1, (0.40 - cv) / 0.30))
            return (raw * 100).rounded()
        }

        static func mean(_ xs: [Double]) -> Double? {
            guard !xs.isEmpty else { return nil }
            return xs.reduce(0, +) / Double(xs.count)
        }

        /// Sleep duration stability: CV 0.08 gives z = +1, CV 0.25 gives z = -2.
        static func consistencyZScore(series: [Double]) -> Double? {
            guard series.count >= 14, let m = mean(series), m > 0 else { return nil }
            let variance = series.map { pow($0 - m, 2) }.reduce(0, +) / Double(series.count)
            return (0.08 - sqrt(variance) / m) / 0.085
        }

        // MARK: Reference ranges

        /// VO2 max centiles by age band (ACSM, 11th edition).
        static func vo2MaxZ(v: Double, age: Int, sex: Sex) -> Double {
            let male = sex == .male
            let mean: Double
            let sd: Double
            switch age {
            case ..<30: mean = male ? 48 : 42; sd = 6
            case 30..<40: mean = male ? 44 : 38; sd = 6
            case 40..<50: mean = male ? 40 : 34; sd = 5
            case 50..<60: mean = male ? 36 : 30; sd = 5
            case 60..<70: mean = male ? 32 : 26; sd = 5
            default: mean = male ? 28 : 23; sd = 4
            }
            return (v - mean) / sd
        }

        /// Overnight SDNN norm: about 40 ms near 48 (Milton 2025), declining
        /// below 50 then flat (Barr 2021). The pre 50 slope is attenuated to
        /// 1 ms per year because the watch records SDNN over short windows. SD
        /// about 25 % of the mean.
        static func hrvZ(v: Double, age: Int) -> Double {
            let anchorAge = 48.0, anchorSDNN = 40.0, preFiftySlope = 1.0
            let cappedAge = min(max(Double(age), 18), 50)
            let mean = max(18, anchorSDNN + (anchorAge - cappedAge) * preFiftySlope)
            let sd = max(10, mean * 0.25)
            return (v - mean) / sd
        }

        /// Resting HR reference (NHANES 2017 to 2018), lower is better, so a
        /// healthy 50 bpm gives z above zero.
        static func restingHRZ(v: Double, sex: Sex) -> Double {
            let mean: Double = sex == .male ? 68 : 72
            return (mean - v) / 10
        }

        /// Body fat against Gallagher 2000 midpoints, leaner is protective, the
        /// leanness benefit capped at +1.5 SD.
        static func bodyFatZ(v: Double, age: Int, sex: Sex) -> Double {
            let male = sex == .male
            let mid: Double
            switch age {
            case ..<40: mid = male ? 19 : 28
            case 40..<60: mid = male ? 22 : 31
            default: mid = male ? 24 : 33
            }
            return min((mid - v) / 6.0, 1.5)
        }

        /// Systolic pressure against 120 mmHg, SD 15, protective side capped at
        /// +0.7 SD so hypotension is not over rewarded.
        static func systolicBPZ(v: Double) -> Double {
            min((120.0 - v) / 15.0, 0.7)
        }
    }
}
