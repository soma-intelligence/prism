//
//  ToolsVitaminD.swift
//  Prism
//
//  Cutaneous (skin) vitamin D synthesis estimator. Given the UV index, the
//  sun's elevation, the user's Fitzpatrick skin type, and how much skin is
//  bare, it estimates how fast the body is making vitamin D and how long it
//  would take to reach a daily goal.
//
//  IMPORTANT: these are WELLNESS ESTIMATES, not medical advice and not a
//  measured dose. Real synthesis varies with age, latitude, ozone, cloud,
//  altitude, sunscreen, and individual biology. Do not use this to guide
//  supplementation; consult a clinician. See `VitaminDEstimate` for the
//  named constants and the default 1000 IU daily goal.
//
//  Model shape (UVB proxy to rate):
//    Vitamin D3 is made in skin only from UVB (~290 to 315 nm). UVB reaches
//    the ground meaningfully when the sun is high or the UV index is
//    non-trivial, hence the gate below. When the gate is open the rate
//    scales linearly with UV index (more UVB flux), the bare skin fraction
//    (more surface reacting), and a Fitzpatrick sensitivity factor (melanin
//    absorbs UVB, so darker skin synthesizes more slowly).
//

import Foundation

extension SomaTools {

    /// Named constants and defaults for the vitamin D wellness model. Grouped
    /// in one place so the calibration is auditable and reusable. Reminder:
    /// these are estimates, not medical advice.
    nonisolated enum VitaminDEstimate: Sendable {

        /// Default daily target in International Units. Roughly the commonly
        /// cited "sensible sun" daily amount for a fair skinned adult; used as
        /// the `timeToGoalMinutes` default. Not a prescription.
        static let defaultGoalIU: Double = 1000.0

        /// Default bare skin fraction: face plus forearms and hands, about a
        /// quarter of the body surface. Callers pass their own when the user
        /// reports more or less exposure.
        static let defaultExposedSkinFraction: Double = 0.25

        /// Sun elevation gate in degrees. Above this the UVB path length
        /// through the atmosphere is short enough for synthesis, independent of
        /// the reported UV index. Roughly the "vitamin D winter" threshold.
        static let elevationGateDeg: Double = 45.0

        /// UV index gate. At or above this the beam carries enough UVB to make
        /// vitamin D even when the sun sits below the elevation gate. Also the
        /// dashed threshold line on the Sun Budget day chart.
        static let uvIndexGate: Double = 3.0

        /// Calibration constant K in IU per minute, per unit of
        /// (uvIndex * exposedSkinFraction * fitzpatrickFactor). Tuned so a
        /// type II person at UV 6, sun above the gate, 0.25 skin makes about
        /// 50 * (6 * 0.25 * 0.90) = 67.5 IU/min, i.e. on the order of 1000 IU
        /// in roughly 15 minutes.
        static let synthesisConstantK: Double = 50.0
    }

    nonisolated enum VitaminDEngine {

        /// Estimated cutaneous vitamin D synthesis rate in IU per minute for the
        /// given conditions. Returns 0 when no synthesis is possible: the UVB
        /// gate is closed (sun below `elevationGateDeg` AND UV index below
        /// `uvIndexGate`), or there is no UV or no bare skin.
        /// `exposedSkinFraction` is clamped to 0...1 and negative UV is floored
        /// at 0.
        static func synthesisRateIUPerMin(uvIndex: Double,
                                          solarElevationDeg: Double,
                                          fitzpatrick: Fitzpatrick,
                                          exposedSkinFraction: Double = VitaminDEstimate.defaultExposedSkinFraction) -> Double {
            let uv = max(0.0, uvIndex)
            let skin = min(1.0, max(0.0, exposedSkinFraction))

            // UVB gate: either the sun is high enough, or the beam is strong
            // enough, for meaningful UVB at the ground.
            let gateOpen = solarElevationDeg > VitaminDEstimate.elevationGateDeg
                || uv >= VitaminDEstimate.uvIndexGate
            guard gateOpen else { return 0.0 }

            return VitaminDEstimate.synthesisConstantK
                * uv
                * skin
                * fitzpatrick.sensitivityFactor
        }

        /// Minutes of the given exposure needed to reach `goalIU` of vitamin D.
        /// Returns nil when synthesis is not possible (rate == 0), so the caller
        /// can show "no vitamin D from the sun at this time" instead of an
        /// infinite estimate. Defaults to `VitaminDEstimate.defaultGoalIU`
        /// (about 1000 IU).
        static func timeToGoalMinutes(goalIU: Double = VitaminDEstimate.defaultGoalIU,
                                      uvIndex: Double,
                                      solarElevationDeg: Double,
                                      fitzpatrick: Fitzpatrick,
                                      exposedSkinFraction: Double = VitaminDEstimate.defaultExposedSkinFraction) -> Double? {
            let rate = synthesisRateIUPerMin(uvIndex: uvIndex,
                                             solarElevationDeg: solarElevationDeg,
                                             fitzpatrick: fitzpatrick,
                                             exposedSkinFraction: exposedSkinFraction)
            guard rate > 0.0 else { return nil }
            return max(0.0, goalIU) / rate
        }

        /// The page's vitamin D card in one value: the rate and the minutes to
        /// the goal, read off the same conditions. `minutesToGoal` nil means the
        /// gate is closed and the card says so instead of printing a zero that
        /// would read as a measurement.
        nonisolated struct Synthesis: Equatable, Sendable {
            let rateIUPerMin: Double
            let minutesToGoal: Double?
            let goalIU: Double

            var isPossible: Bool { minutesToGoal != nil }
        }

        static func synthesis(uvIndex: Double,
                              solarElevationDeg: Double,
                              fitzpatrick: Fitzpatrick,
                              exposedSkinFraction: Double = VitaminDEstimate.defaultExposedSkinFraction,
                              goalIU: Double = VitaminDEstimate.defaultGoalIU) -> Synthesis {
            Synthesis(
                rateIUPerMin: synthesisRateIUPerMin(uvIndex: uvIndex,
                                                    solarElevationDeg: solarElevationDeg,
                                                    fitzpatrick: fitzpatrick,
                                                    exposedSkinFraction: exposedSkinFraction),
                minutesToGoal: timeToGoalMinutes(goalIU: goalIU,
                                                 uvIndex: uvIndex,
                                                 solarElevationDeg: solarElevationDeg,
                                                 fitzpatrick: fitzpatrick,
                                                 exposedSkinFraction: exposedSkinFraction),
                goalIU: goalIU)
        }
    }
}
