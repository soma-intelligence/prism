//
//  SomaTypography+Hero.swift
//  SomaUI
//

import SwiftUI

/// The hero value, derived from the scale rather than added to it.
public extension SomaTypography {
    /// The one value that opens a page of readings: 56 points on the finger
    /// scale, the big confident number Flighty and Fitness lead with. Regular
    /// and tight like every value, tabular so it rolls in place. Once a screen.
    var heroMetric: SomaFontSpec {
        var spec = metric
        spec.size = (metric.size * 14 / 9).rounded()
        spec.tracking = metric.tracking * 2
        spec.digits = .tabular
        return spec
    }
}
