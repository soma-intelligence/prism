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

extension Insight {
    /// Where it sits, as the status word set under a name.
    var status: SomaReadingStatus {
        switch position {
        case .within: .normal
        case .above: .above
        case .below: .below
        case nil: .none
        }
    }

    /// The cue as a label for a reading.
    var cueLabel: LocalizedStringResource? {
        cue.map { LocalizedStringResource(stringLiteral: $0) }
    }
}

extension BodyBiomarker.Status {
    /// The status word a Body tile or a Today row sets under its name.
    var reading: SomaReadingStatus {
        switch self {
        case .normal: .normal
        case .above: .above
        case .below: .below
        case .increasing: .trend("Increasing")
        case .decreasing: .trend("Decreasing")
        case .stabilizing: .trend("Stabilizing")
        case .none: .none
        }
    }
}

extension MetricDetailMath.Standing {
    /// The status word for a reading read against its band.
    var reading: SomaReadingStatus {
        switch status {
        case .normal: .normal
        case .above: .above
        case .below: .below
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
