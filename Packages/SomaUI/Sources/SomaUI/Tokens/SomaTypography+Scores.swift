//
//  SomaTypography+Scores.swift
//  SomaUI
//

import SwiftUI

/// The score pages' roles, derived from the scale rather than added to it.
public extension SomaTypography {
    /// The number inside a score page's gauge: the metric role at hero size,
    /// set at its own size rather than scaled up, so it stays crisp. Tabular,
    /// so a page that moves from 69 to 71 does not shift.
    var scoreGaugeFigure: SomaFontSpec {
        var spec = metric
        spec.size = metric.size * 1.8
        spec.tracking = metric.tracking * 2
        spec.weight = .light
        spec.digits = .tabular
        return spec
    }
}
