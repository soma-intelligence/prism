//
//  ToolsAgingPace.swift
//  Prism
//
//  Pure, I/O free math for the Aging Pace tool. "Pace" is the slope of
//  biological age over calendar time, in bio years per calendar year: 1.0 is
//  aging exactly in step with the calendar, below 1.0 is gaining time back
//  (DunedinPACE style), above 1.0 is accelerating.
//
//  Two sources feed the number:
//    1. The model's own two window pace (AgingBioAge.Result.paceOfAging),
//       computed from raw HRV and resting HR z scores. The primary value:
//       unrounded, already clamped.
//    2. A continuous least squares slope over the dense day by day bio age
//       history, used as the fallback when the model could not form its two
//       windows, and always as a trend fit quality signal. The dense history
//       reports bio age at whole year resolution, so this slope is coarser,
//       which is why it is the fallback.
//
//  Around the engine sit the pure pieces the tool page needs: the drivers
//  list, the projection and what if verdicts, the calendar age from a birth
//  date, and a weekly history.
//
//  This is a wellness estimate, not a medical measurement.
//

import Foundation

extension SomaTools {

    nonisolated enum AgingPace {

        /// Believable pace window, the same bounds the model applies, so one bad
        /// month never reads as "aging three times faster".
        static let minPace = 0.4
        static let maxPace = 1.8
        static let daysPerYear = 365.25
        /// Below this fit quality the continuous slope is too noisy to trust on
        /// its own. Used only to label the trend, never to override the model.
        static let trustworthyFit = 0.2
        /// Below this many days of longitudinal coverage the pace is not
        /// defensible, so the page shows its empty state instead.
        static let minCoverageDays = 90
        /// How far back the dense history the slope is fitted through reaches.
        static let historyDays = 180
        /// Gap, in years, inside which a projection or a what if reads as
        /// "on par" rather than older or younger.
        static let parBandYears = 0.05

        /// Which input produced the resolved pace.
        enum Source: Equatable, Sendable { case model, trendFit }

        /// Interpretation band for a pace value, carried by its label.
        enum Band: Equatable, Sendable {
            /// Below 0.95x: biology aging slower than the calendar.
            case gaining
            /// 0.95x to 1.05x, both edges included: in step with the calendar.
            case holding
            /// Above 1.05x: biology aging faster than the calendar.
            case faster

            init(pace: Double) {
                switch pace {
                case ..<0.95: self = .gaining
                case 0.95...1.05: self = .holding
                default: self = .faster
                }
            }

            /// Plain English label.
            var label: String {
                switch self {
                case .gaining: return "Aging slower"
                case .holding: return "In step with the calendar"
                case .faster: return "Aging faster"
                }
            }
        }

        /// The whole resolved reading, pure and previewable.
        struct Reading: Equatable, Sendable {
            /// Bio years per calendar year. 1.0 = calendar pace.
            let pace: Double
            let source: Source
            /// r squared of the continuous trend fit, nil when it could not fit.
            let fitQuality: Double?
            /// Today's biological age estimate, in years.
            let currentBioAge: Double
            /// Today's calendar age, in years.
            let chronoAge: Double
            /// Days of longitudinal data behind the estimate.
            let coverageDays: Int

            var band: Band { Band(pace: pace) }
            /// Signed gap to the calendar (positive = biologically older).
            var gapYears: Double { currentBioAge - chronoAge }
            /// True when the trend fit is good enough to show as a trend.
            var isTrendTrustworthy: Bool { (fitQuality ?? 0) >= trustworthyFit }

            /// Biological age carried forward `years` ahead at the current pace.
            func projectedBioAge(inYears years: Double) -> Double {
                currentBioAge + pace * years
            }
            /// Calendar age `years` ahead (advances at exactly 1.0 per year).
            func projectedChronoAge(inYears years: Double) -> Double {
                chronoAge + years
            }
            /// Signed projected gap `years` ahead (positive = older).
            func projectedGap(inYears years: Double) -> Double {
                projectedBioAge(inYears: years) - projectedChronoAge(inYears: years)
            }
            /// The projection's verdict, `years` ahead.
            func projection(inYears years: Double) -> Verdict {
                Verdict(gap: projectedGap(inYears: years))
            }
        }

        // MARK: Continuous pace

        /// Least squares slope of bio age over calendar time, converted to bio
        /// years per calendar year. `points` are (day, bioAge) with `day` a real
        /// day offset (any origin), oldest first. The reconstructed history
        /// advances the calendar age one day per point, so this slope already
        /// carries the calendar drift and IS the pace. nil below five points or
        /// when the fit degenerates.
        static func continuousPace(fromDatedBioAge points: [(day: Double, bioAge: Double)])
            -> (pace: Double, rSquared: Double)? {
            guard points.count >= 5 else { return nil }
            guard let fit = fit(points: points.map { (x: $0.day, y: $0.bioAge) }) else { return nil }
            return (clamp(fit.slope * daysPerYear), fit.rSquared)
        }

        /// Prefer the model's calibrated two window value, fall back to the
        /// continuous slope. nil only when neither is available.
        static func resolvePace(modelPace: Double?,
                                historyPoints: [(day: Double, bioAge: Double)])
            -> (pace: Double, fitQuality: Double?, source: Source)? {
            let fit = continuousPace(fromDatedBioAge: historyPoints)
            if let modelPace, modelPace.isFinite {
                return (clamp(modelPace), fit?.rSquared, .model)
            }
            if let fit {
                return (fit.pace, fit.rSquared, .trendFit)
            }
            return nil
        }

        static func clamp(_ value: Double) -> Double {
            max(minPace, min(maxPace, value))
        }

        // MARK: Least squares fit

        /// A least squares fit on dated points (x in days), plus the pieces a
        /// prediction interval needs. Respects the real spacing between points.
        struct TimeFit: Sendable, Equatable {
            /// Value change per day.
            let slope: Double
            /// Value at x = 0.
            let intercept: Double
            let n: Int
            let xMean: Double
            let sxx: Double
            let residualStdError: Double
            let rSquared: Double
        }

        /// Fit `y = slope * x + intercept`. nil below five points or when the x
        /// values do not vary.
        static func fit(points: [(x: Double, y: Double)]) -> TimeFit? {
            let n = points.count
            guard n >= 5 else { return nil }
            let nD = Double(n)
            let xMean = points.map(\.x).reduce(0, +) / nD
            let yMean = points.map(\.y).reduce(0, +) / nD
            var sxx = 0.0, sxy = 0.0
            for p in points {
                sxx += (p.x - xMean) * (p.x - xMean)
                sxy += (p.x - xMean) * (p.y - yMean)
            }
            guard sxx > 0 else { return nil }
            let slope = sxy / sxx
            let intercept = yMean - slope * xMean
            var ssRes = 0.0, ssTot = 0.0
            for p in points {
                let yHat = intercept + slope * p.x
                ssRes += (p.y - yHat) * (p.y - yHat)
                ssTot += (p.y - yMean) * (p.y - yMean)
            }
            let rSquared = ssTot > 0 ? 1 - ssRes / ssTot : 0
            return TimeFit(slope: slope, intercept: intercept, n: n, xMean: xMean, sxx: sxx,
                           residualStdError: sqrt(ssRes / Double(n - 2)), rSquared: rSquared)
        }

        // MARK: History

        /// One dated bio age estimate from the dense history.
        struct HistoryPoint: Sendable, Equatable {
            let date: Date
            let bioAge: Double
        }

        /// The dense history as day offsets the engine can fit, oldest first,
        /// with the first sample at day zero.
        static func datedPoints(_ history: [HistoryPoint]) -> [(day: Double, bioAge: Double)] {
            guard let start = history.first?.date else { return [] }
            return history.map { (day: $0.date.timeIntervalSince(start) / 86_400, bioAge: $0.bioAge) }
        }

        /// One week of the history, for a compact chart.
        struct WeekPoint: Sendable, Equatable, Identifiable {
            /// 0 is the week ending on `endingOn`, 1 the one before, and so on.
            let index: Int
            let weekStart: Date
            /// Mean bio age of the samples in that week, nil for a week with none.
            let meanBioAge: Double?
            var id: Int { index }
        }

        /// Soma addition: the dense history reduced to `weeks` trailing seven day
        /// buckets, oldest first. A week with no sample is kept with a nil mean,
        /// because a missing week is information, not a gap to close.
        static func weeklyHistory(_ history: [HistoryPoint],
                                  weeks: Int = 12,
                                  endingOn end: Date,
                                  calendar: Calendar = .current) -> [WeekPoint] {
            guard weeks > 0 else { return [] }
            let dayEnd = calendar.date(byAdding: .day, value: 1,
                                       to: calendar.startOfDay(for: end)) ?? end
            return (0..<weeks).reversed().map { index in
                let upper = calendar.date(byAdding: .day, value: -7 * index, to: dayEnd) ?? dayEnd
                let lower = calendar.date(byAdding: .day, value: -7, to: upper) ?? upper
                let values = history.filter { $0.date >= lower && $0.date < upper }.map(\.bioAge)
                let mean = values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
                return WeekPoint(index: index, weekStart: lower, meanBioAge: mean)
            }
        }

        // MARK: Calendar age

        /// Calendar age in fractional years from a birth date.
        static func chronoAge(birthDate: Date, now: Date) -> Double {
            now.timeIntervalSince(birthDate) / (daysPerYear * 24 * 3600)
        }

        // MARK: Drivers

        /// One factor's signed contribution to the biological age, in years
        /// (negative pulls younger).
        struct Driver: Identifiable, Equatable, Sendable {
            let title: String
            let years: Double
            var id: String { title }
            var pullsYounger: Bool { years < 0 }
        }

        /// The model's components as drivers, biggest mover first.
        static func drivers(from components: [AgingBioAge.Component]) -> [Driver] {
            components
                .map { Driver(title: $0.metric.label, years: $0.yearsDelta) }
                .sorted { abs($0.years) > abs($1.years) }
        }

        // MARK: Verdicts

        /// Older, younger or on par, for a projected gap or a what if delta.
        enum Verdict: Equatable, Sendable {
            case older(years: Double)
            case younger(years: Double)
            case onPar

            /// `gap` positive = older. Inside plus or minus 0.05 years is on par.
            init(gap: Double) {
                if gap > AgingPace.parBandYears { self = .older(years: gap) }
                else if gap < -AgingPace.parBandYears { self = .younger(years: -gap) }
                else { self = .onPar }
            }
        }

        // MARK: What if

        /// A lever the what if card can move. Each nudges one input series by a
        /// constant and asks the same pure model again, so no new math lives in
        /// the lever itself.
        enum Lever: Equatable, Sendable {
            /// Milliseconds added to every HRV sample. The source offered 0 to 20.
            case hrv(ms: Double)
            /// Beats per minute added to every resting HR sample (negative lowers).
            case restingHR(bpm: Double)
            /// Steps added to every daily step count.
            case steps(perDay: Double)
            /// ml/kg/min added to every VO2 max sample.
            case vo2Max(mlKgMin: Double)
        }

        /// Range the source offered for the HRV lever, in ms.
        static let hrvLeverRange: ClosedRange<Double> = 0...20

        /// The inputs with one lever applied.
        static func applying(_ lever: Lever, to inputs: AgingBioAge.Inputs) -> AgingBioAge.Inputs {
            var next = inputs
            switch lever {
            case .hrv(let ms): next.hrv = inputs.hrv.map { $0 + ms }
            case .restingHR(let bpm): next.restingHR = inputs.restingHR.map { $0 + bpm }
            case .steps(let perDay): next.steps = inputs.steps.map { max(0, $0 + perDay) }
            case .vo2Max(let v): next.vo2Max = inputs.vo2Max.map { $0 + v }
            }
            return next
        }

        /// Outcome of one what if.
        struct WhatIf: Equatable, Sendable {
            /// Today's estimate, as the page shows it (whole years).
            let baselineAge: Double
            /// The estimate with the lever applied (whole years).
            let resultAge: Double
            /// Signed difference of the unrounded estimates, so a small nudge
            /// is not lost to the whole year rounding. Negative = younger.
            let deltaYears: Double
            var verdict: Verdict { Verdict(gap: deltaYears) }
        }

        /// Recompute today's biological age with one lever moved, every other
        /// input unchanged, so the delta is the lever's alone. nil when the
        /// series the lever moves is empty, or when the model has no result.
        static func whatIf(_ lever: Lever,
                           chronologicalAge: Int,
                           sex: AgingBioAge.Sex,
                           inputs: AgingBioAge.Inputs) -> WhatIf? {
            let moved: [Double]
            switch lever {
            case .hrv: moved = inputs.hrv
            case .restingHR: moved = inputs.restingHR
            case .steps: moved = inputs.steps
            case .vo2Max: moved = inputs.vo2Max
            }
            guard !moved.isEmpty,
                  let base = AgingBioAge.compute(chronologicalAge: chronologicalAge, sex: sex,
                                                 inputs: inputs),
                  let nudged = AgingBioAge.compute(chronologicalAge: chronologicalAge, sex: sex,
                                                   inputs: applying(lever, to: inputs))
            else { return nil }
            return WhatIf(baselineAge: base.estimatedAge,
                          resultAge: nudged.estimatedAge,
                          deltaYears: nudged.unroundedAge - base.unroundedAge)
        }

        // MARK: Whole model

        /// Everything one render needs.
        struct Model: Equatable, Sendable {
            let reading: Reading
            let drivers: [Driver]
            let confidence: AgingBioAge.Confidence
            /// The dense history the slope was fitted through, oldest first.
            let history: [HistoryPoint]
        }

        /// The loader's arithmetic, minus the loading. `current` is today's model
        /// result, `history` the dense 180 day history, `chronoAge` today's
        /// calendar age. nil below `minCoverageDays` or when no pace resolves.
        static func model(current: AgingBioAge.Result,
                          history: [HistoryPoint],
                          chronoAge: Double) -> Model? {
            guard current.coverageDays >= minCoverageDays else { return nil }
            guard let resolved = resolvePace(modelPace: current.paceOfAging,
                                             historyPoints: datedPoints(history)) else { return nil }
            let reading = Reading(pace: resolved.pace,
                                  source: resolved.source,
                                  fitQuality: resolved.fitQuality,
                                  currentBioAge: current.estimatedAge,
                                  chronoAge: chronoAge,
                                  coverageDays: current.coverageDays)
            return Model(reading: reading,
                         drivers: drivers(from: current.components),
                         confidence: current.confidence,
                         history: history)
        }

        /// Pace as "0.87×", with the multiplication sign.
        static func paceText(_ pace: Double) -> String {
            String(format: "%.2f\u{00D7}", pace)
        }
    }
}
