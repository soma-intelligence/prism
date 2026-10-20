//
//  SomaTypography+Energy.swift
//  SomaUI
//

import SwiftUI

/// The energy bank's roles, derived from the scale rather than added to it.
public extension SomaTypography {
    /// The level beside the charge cell: the metric role, larger and light,
    /// so the hero number is big without being heavy.
    var bankFigure: SomaFontSpec {
        var spec = metric
        spec.size = metric.size * 1.75
        spec.tracking = metric.tracking * 2
        spec.weight = .light
        return spec
    }

    /// The signed number on a charged or drained tile.
    var bankDelta: SomaFontSpec {
        var spec = metricCompact
        spec.weight = .medium
        return spec
    }
}
