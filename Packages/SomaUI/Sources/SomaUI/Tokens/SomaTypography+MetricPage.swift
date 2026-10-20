//
//  SomaTypography+MetricPage.swift
//  SomaUI
//

import SwiftUI

/// A metric page's roles, derived from the scale rather than added to it.
public extension SomaTypography {
    /// The hero number at the head of a metric's page: the metric role,
    /// larger and light, so it is big without being heavy.
    var metricHero: SomaFontSpec {
        var spec = metric
        spec.size = metric.size * 1.6
        spec.tracking = metric.tracking * 1.8
        spec.weight = .light
        return spec
    }

    /// The unit beside the hero number.
    var metricHeroUnit: SomaFontSpec {
        var spec = title
        spec.weight = .regular
        return spec
    }

    /// A number in the strip of facts, and the chart's readout.
    var metricFact: SomaFontSpec {
        var spec = rowValue
        spec.size = rowValue.size + 2
        spec.weight = .medium
        return spec
    }
}
