//
//  ToolsErythemalDose.swift
//  Prism
//
//  Cutaneous erythema (sunburn) time estimator. The protection counterpart
//  to `VitaminDEngine`: where that engine asks "how long in the sun to make
//  vitamin D", this one asks "how long in the sun before the skin burns".
//  Both read the same UV index and Fitzpatrick phototype; they are two sides
//  of one dose.
//
//  Model shape (UV index to time to erythema):
//    The UV Index is defined so that 1 unit = 25 mW/m2 of erythemally
//    weighted irradiance (the CIE erythemal action spectrum, WMO/WHO). The
//    minimal erythemal dose (MED), the radiant exposure that just reddens
//    skin, scales with phototype: pale type I burns at ~200 J/m2, deeply
//    pigmented type VI tolerates ~1000 J/m2. Time to burn is simply
//    dose / rate = MED / erythemalIrradiance, extended linearly by an SPF
//    that, applied correctly, multiplies the tolerated dose.
//
//  THIS IS A WELLNESS ESTIMATE, not a measured dose and not medical advice.
//  Real burn time depends on reflected UV, altitude, cloud, sweat, film
//  thickness and reapplication. Treat it as a prompt to cover up, never as
//  a licence to stay out to the last minute.
//

import Foundation

extension SomaTools {

    nonisolated enum ErythemalDoseEngine {

        /// Erythemally weighted irradiance per UV Index unit, in W/m2. The UV
        /// Index is 40 x the erythemal irradiance in W/m2, i.e. one index unit
        /// is 0.025 W/m2 (25 mW/m2). WMO/WHO Global Solar UV Index definition.
        static let irradianceWPerM2PerUVIndex: Double = 0.025

        /// Minimal erythemal dose in J/m2 by Fitzpatrick phototype. Central
        /// values from the clinical MED ranges (Fitzpatrick 1988; Sachdeva
        /// 2009): pale skin reddens at a fraction of the dose deep skin
        /// tolerates. Kept here, not on `Fitzpatrick`, so the phototype enum
        /// stays a shared primitive with no erythemal opinion baked in.
        static func medJPerM2(_ fitzpatrick: Fitzpatrick) -> Double {
            switch fitzpatrick {
            case .typeI:   return 200
            case .typeII:  return 250
            case .typeIII: return 350
            case .typeIV:  return 450
            case .typeV:   return 600
            case .typeVI:  return 1000
            }
        }

        /// Erythemal irradiance at the ground for a UV index, in W/m2. Negative
        /// UV is floored at zero (sun down or no reading means no burn).
        static func erythemalIrradianceWPerM2(uvIndex: Double) -> Double {
            max(0, uvIndex) * irradianceWPerM2PerUVIndex
        }

        /// Minutes of UNPROTECTED sun before erythema for this phototype at the
        /// given UV, optionally extended by an SPF factor. Returns nil when
        /// there is effectively no burn risk (UV at or below zero), which the
        /// caller renders as "no burn risk right now" rather than an infinite
        /// countdown. `spf` is clamped to at least 1 (bare skin).
        ///
        /// THE FLAT MODEL: it freezes the UV for as long as the countdown runs.
        /// That holds for a single reading, and it is wrong for a whole morning:
        /// at 09:00 the UV is still climbing, so a flat estimate overshoots.
        /// When the day's curve is on hand, prefer
        /// `burnInstant(from:hourly:fitzpatrick:spf:)`. Also the page's "time to
        /// burn at the peak" when fed the day's peak UV.
        static func minutesToBurn(uvIndex: Double,
                                  fitzpatrick: Fitzpatrick,
                                  spf: Double = 1) -> Double? {
            let irradiance = erythemalIrradianceWPerM2(uvIndex: uvIndex)
            guard irradiance > 0 else { return nil }
            let seconds = medJPerM2(fitzpatrick) / irradiance * max(1, spf)
            return seconds / 60
        }

        // MARK: - Forward integration over the day

        /// One point of the day's UV curve. The engine reads nothing else from
        /// the weather, so any source that can name a UV at an instant can feed
        /// it (a forecast, or `SunBudget.estimatedHourlyUV` built from a peak).
        nonisolated struct UVSample: Equatable, Sendable {
            let date: Date
            let uv: Double

            init(date: Date, uv: Double) {
                self.date = date
                self.uv = max(0, uv)
            }
        }

        /// The instant the accumulated erythemal dose reaches this phototype's
        /// tolerance (MED, multiplied by `spf`), integrating the day's curve
        /// forward from `start`. nil when the sun the curve still has left never
        /// adds up to that dose, which is the honest reading of "you cannot burn
        /// with what is left of today", not a missing value.
        ///
        /// Why this exists next to `minutesToBurn`: the flat model answers "at
        /// THIS UV, held forever". A morning reading held forever is a fiction.
        /// UV 2.9 at 09:00 becomes 8 at 13:00, so the flat model can promise
        /// hours that the real curve spends in twenty minutes. Same dose
        /// physics, honest rate.
        ///
        /// UV is taken to vary linearly between samples, so a segment contributes
        /// its mean irradiance times its duration, and the crossing inside the
        /// final segment is solved exactly rather than snapped to the hour.
        static func burnInstant(from start: Date,
                                hourly: [UVSample],
                                fitzpatrick: Fitzpatrick,
                                spf: Double = 1) -> Date? {
            let samples = hourly.sorted { $0.date < $1.date }
            guard samples.count > 1 else { return nil }

            let tolerated = medJPerM2(fitzpatrick) * max(1, spf)
            var remaining = tolerated

            for (index, sample) in samples.enumerated().dropLast() {
                let next = samples[index + 1]
                let span = next.date.timeIntervalSince(sample.date)
                guard span > 0, next.date > start else { continue }

                // A segment straddling `start` counts only from `start`, at the
                // UV interpolated there. Without this the walk would credit the
                // user dose from sun that already fell.
                let entered = max(sample.date, start)
                let head = entered.timeIntervalSince(sample.date) / span
                let uvAtEntry = sample.uv + (next.uv - sample.uv) * head
                let duration = next.date.timeIntervalSince(entered)

                let dose = irradianceWPerM2PerUVIndex * (uvAtEntry + next.uv) / 2 * duration
                if dose < remaining {
                    remaining -= dose
                    continue
                }

                let fraction = crossing(from: uvAtEntry, to: next.uv,
                                        seconds: duration, dose: remaining)
                return entered.addingTimeInterval(duration * fraction)
            }

            return nil
        }

        /// Where inside one segment the accumulated dose lands, as a fraction of
        /// its duration. UV ramps linearly from `from` to `to`, so the dose grows
        /// as a quadratic in that fraction and the crossing is one root of it.
        /// Returns 1 when the segment carries no UV at all, which the caller has
        /// already excluded by reaching this far.
        private static func crossing(from: Double, to: Double,
                                     seconds: TimeInterval, dose: Double) -> Double {
            guard seconds > 0 else { return 0 }
            let scale = irradianceWPerM2PerUVIndex * seconds
            // a x^2 + b x + c, with the dose still owed carried as a negative c.
            let a = (to - from) / 2
            let b = from
            let c = -dose / scale

            if abs(a) < 1e-12 {
                guard b > 1e-12 else { return 1 }
                return min(1, max(0, -c / b))
            }
            let discriminant = b * b - 4 * a * c
            guard discriminant >= 0 else { return 1 }
            let root = sqrt(discriminant)
            // The dose only ever grows, so the crossing is the first root that
            // falls inside the segment.
            let roots = [(-b + root) / (2 * a), (-b - root) / (2 * a)]
                .filter { $0 >= 0 && $0 <= 1 }
                .sorted()
            return roots.first ?? 1
        }
    }
}
