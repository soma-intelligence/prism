//
//  StressEngine.swift
//  HealthScoring (ported from the previous app, behaviour unchanged)
//
//  Two-model stress engine:
//
//  ACUTE helpers (hrvDeficit01, hrElevation01, stressValue, instantaneous,
//  curve) implement the Firstbeat acute model used by EnergyEngine and the
//  intraday HR curve. Exercise raises stress in that model. These helpers
//  are untouched.
//
//  DAILY model (daily, dailyValue, centeredStress, robustSpread) uses a
//  centered personal-distribution approach: HRV and RHR are z-scored
//  against the user's own trailing baseline and spread. Exercise is
//  intentionally excluded. A typical day reads ~35, a rested day <22,
//  a tense day >70.
//
//  Conceptual grounding: Baevsky Stress Index (SI inversely proportional
//  to HRV breadth) informs the HRV term; Garmin bands (0-25 / 26-50 /
//  51-75 / 76-100) align with the Band enum.
//

import Foundation

enum StressEngine {

    enum Band: String, Sendable, Hashable { case rest, low, medium, high }

    /// HRV weight (parasympathetic). One of the two tunable judgment calls.
    static let hrvWeight = 0.60
    /// HR weight (sympathetic).
    static let hrWeight = 0.40

    /// Centered-scale logistic constants. Chosen so a typical day (z=0) reads
    /// ~35, z=+2 ~82, z=-1.5 ~12. Locked by StressEngineTests anchor cases.
    static let centerZ0 = 0.58
    static let centerSlope = 0.94
    /// Spread floors so a flat window cannot divide by ~0.
    static let logHRVSpreadFloor = 0.05
    static let rhrSpreadFloor = 2.0

    // MARK: Acute helpers (untouched)

    /// Core stress value 0..100 from the two normalised drivers.
    static func stressValue(hrvDeficit01: Double, hrElevation01: Double) -> Double {
        let d = min(1, max(0, hrvDeficit01))
        let e = min(1, max(0, hrElevation01))
        return min(100, max(0, 100 * (hrvWeight * d + hrWeight * e)))
    }

    /// Parasympathetic withdrawal: how far HRV sits below baseline, 0..1.
    /// Above baseline clamps to 0 (no stress contribution).
    static func hrvDeficit01(hrv: Double?, baseline: Double?) -> Double {
        guard let hrv, let baseline, baseline > 0 else { return 0 }
        return min(1, max(0, (baseline - hrv) / baseline))
    }

    /// Sympathetic activation: HR above rest, scaled by HALF the HR
    /// reserve so ordinary daily elevations land mid-scale and only
    /// near-max efforts saturate. 0..1.
    static func hrElevation01(hr: Double?, restingHR: Double?, maxHR: Double?) -> Double {
        guard let hr, let rest = restingHR else { return 0 }
        let top = maxHR ?? (rest + 140)
        let reserve = max(1, (top - rest) * 0.5)
        return min(1, max(0, (hr - rest) / reserve))
    }

    /// Garmin-aligned display band.
    static func band(for stress: Double) -> Band {
        switch stress {
        case ..<26: return .rest
        case ..<51: return .low
        case ..<76: return .medium
        default:    return .high
        }
    }

    /// Instantaneous stress at one intraday bucket: HR drives the shape,
    /// the day's HRV deficit sets the floor (HRV is sparse intraday).
    static func instantaneous(hr: Double?, inputs: VitalityInputs) -> Double {
        let deficit = hrvDeficit01(hrv: inputs.hrv, baseline: inputs.hrvBaseline)
        let elevation = hrElevation01(hr: hr,
                                      restingHR: inputs.restingHR,
                                      maxHR: inputs.maxHR)
        return stressValue(hrvDeficit01: deficit, hrElevation01: elevation)
    }

    /// Intraday stress curve (tier `.rich`). One sample per non-nil
    /// intraday HR bucket; nil buckets are skipped (honest gaps).
    static func curve(inputs: VitalityInputs) -> [VitalitySample] {
        guard let hr = inputs.intradayHeartRate else { return [] }
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: inputs.now)
        var out: [VitalitySample] = []
        for (i, bucket) in hr.enumerated() {
            guard let bpm = bucket else { continue }
            let date = cal.date(byAdding: .minute,
                                value: i * inputs.bucketMinutes, to: dayStart) ?? dayStart
            guard date <= inputs.now else { break }
            out.append(VitalitySample(date: date,
                                      value: instantaneous(hr: bpm, inputs: inputs)))
        }
        return out
    }

    // MARK: Centered daily model

    /// Robust spread = 1.4826 * MAD (consistent SD estimator under normality),
    /// floored. Fewer than 2 values -> floor.
    static func robustSpread(_ values: [Double], floor: Double) -> Double {
        guard values.count >= 2 else { return floor }
        let sorted = values.sorted()
        let median = StressEngine.median(sorted)
        let devs = sorted.map { abs($0 - median) }.sorted()
        let mad = StressEngine.median(devs)
        return max(floor, 1.4826 * mad)
    }

    private static func median(_ sorted: [Double]) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let n = sorted.count
        return n % 2 == 1 ? sorted[n / 2]
                          : (sorted[n / 2 - 1] + sorted[n / 2]) / 2
    }

    /// Centered 0..100 from the composite autonomic z-score.
    static func centeredStress(z: Double) -> Double {
        let v = 100 / (1 + exp(-(z - centerZ0) / centerSlope))
        return min(100, max(0, v))
    }

    /// Daily stress summary. Exercise is NOT a term (excluded by product
    /// decision); training strain no longer feeds stress.
    static func daily(inputs: VitalityInputs) -> Double? {
        dailyValue(hrv: inputs.hrv,
                   hrvBaseline: inputs.hrvBaseline,
                   hrvSpread: inputs.hrvSpread,
                   restingHR: inputs.restingHR,
                   restingHRBaseline: inputs.restingHRBaseline,
                   rhrSpread: inputs.rhrSpread)
    }

    /// Centered daily stress from raw scalars. Returns nil when neither
    /// autonomic driver is available (honest gap, never a false 0). HRV is
    /// z-scored in LOG space (HRV is log-normal); weights renormalize over the
    /// drivers actually present (0.6 HRV / 0.4 RHR when both exist).
    static func dailyValue(hrv: Double?,
                           hrvBaseline: Double?,
                           hrvSpread: Double?,
                           restingHR: Double?,
                           restingHRBaseline: Double?,
                           rhrSpread: Double?) -> Double? {
        var weightSum = 0.0
        var weighted = 0.0

        if let hrv, let base = hrvBaseline, hrv > 0, base > 0 {
            let spread = max(hrvSpread ?? 0, logHRVSpreadFloor)
            let z = (log(base) - log(hrv)) / spread
            weighted += hrvWeight * z
            weightSum += hrvWeight
        }
        if let rhr = restingHR, let base = restingHRBaseline, base > 0 {
            let spread = max(rhrSpread ?? 0, rhrSpreadFloor)
            let z = (rhr - base) / spread
            weighted += hrWeight * z
            weightSum += hrWeight
        }

        guard weightSum > 0 else { return nil }
        return centeredStress(z: weighted / weightSum)
    }
}
