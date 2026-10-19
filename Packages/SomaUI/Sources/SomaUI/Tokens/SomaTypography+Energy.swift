//
//  SomaTypography+Energy.swift
//  SomaUI
//

import SwiftUI

/// The energy bank's roles, derived from the scale rather than added to it.
public extension SomaTypography {
    /// The level written across the battery: the metric role, larger, a step
    /// heavier so it holds over the charge's colour.
    var bankFigure: SomaFontSpec {
        var spec = metric
        spec.size = metric.size * 1.55
        spec.tracking = metric.tracking * 2
        spec.weight = .medium
        return spec
    }

    /// The percent sign beside that level.
    var bankFigureUnit: SomaFontSpec {
        var spec = metricCompact
        spec.size = metricCompact.size * 0.85
        spec.weight = .medium
        return spec
    }

    /// The signed number on a charged or drained tile.
    var bankDelta: SomaFontSpec {
        var spec = metricCompact
        spec.weight = .medium
        return spec
    }
}
