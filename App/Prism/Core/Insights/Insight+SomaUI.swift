//
//  Insight+SomaUI.swift
//  Prism
//
//  How an ``Insight`` reaches the design system's readings.
//

import Foundation
import SomaUI
import HealthExportCore

extension Insight.Tone {
    var cueTone: SomaCueTone {
        switch self {
        case .good: .good
        case .watch: .watch
        case .neutral: .neutral
        }
    }
}

extension InsightPreference {
    /// The status a reading outside its usual takes on `side`: green on the
    /// better side, amber on the other. A reading where being near the usual
    /// is what matters (wrist temperature, breathing, blood pressure) reads
    /// amber on either side: off its usual is the thing worth a look.
    func outside(_ side: SomaUsualSide) -> SomaReadingStatus {
        switch self {
        case .higher: .outside(side, better: .higher)
        case .lower: .outside(side, better: .lower)
        case .steady: side == .above ? .above : .below
        }
    }
}

extension Insight {
    /// Where it sits, as the status word set under a name, coloured by
    /// whether that side is the good one.
    var status: SomaReadingStatus {
        switch position {
        case .within: .normal
        case .above: preference.outside(.above)
        case .below: preference.outside(.below)
        case nil: .none
        }
    }

    /// The cue as a label for a reading.
    var cueLabel: LocalizedStringResource? {
        cue.map { LocalizedStringResource(stringLiteral: $0) }
    }
}

extension BodyBiomarker.Status {
    /// The status word a Body tile or a Today row sets under its name,
    /// coloured by which side of the usual is the better one for the reading
    /// (``InsightPolicy/preference``): heart rate recovery above its usual is
    /// good news, resting heart rate above it is worth a look.
    func reading(_ preference: InsightPreference) -> SomaReadingStatus {
        switch self {
        case .normal: .normal
        case .above: preference.outside(.above)
        case .below: preference.outside(.below)
        case .increasing: .trend("Increasing")
        case .decreasing: .trend("Decreasing")
        case .stabilizing: .trend("Stabilizing")
        case .none: .none
        }
    }
}

extension MetricDetailMath.Standing {
    /// The status word for a reading read against its band, coloured by
    /// which side of it is the better one.
    func reading(_ preference: InsightPreference) -> SomaReadingStatus {
        switch status {
        case .normal: .normal
        case .above: preference.outside(.above)
        case .below: preference.outside(.below)
        case .direction(.rising): .trend("Increasing")
        case .direction(.falling): .trend("Decreasing")
        case .direction(.flat): .trend("Stable")
        case .none: .none
        }
    }
}

extension InsightMetric {
    /// The hue of the category its records are listed under: sleep's for
    /// sleep, the Body catalog's for the rest.
    var hue: SomaHealthHue {
        if self == .sleepDuration { return .sleep }
        guard let metric = HealthMetricCatalog.metric(for: identifier) else { return .other }
        return BodyCategory.containing(BodyDataType(metric))?.hue ?? .other
    }
}
