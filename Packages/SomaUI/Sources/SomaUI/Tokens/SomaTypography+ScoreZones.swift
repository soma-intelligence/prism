//
//  SomaTypography+ScoreZones.swift
//  SomaUI
//

import SwiftUI

/// The number inside Today's score dials (``SomaScoreZones``), derived from
/// the scale rather than added to it.
public extension SomaTypography {
    /// The number in the middle of a dial: light and a little large, so it
    /// reads first without weighing on the ring round it. Tabular, so it
    /// rolls in its columns.
    var scoreDialFigure: SomaFontSpec {
        var spec = metricCompact
        spec.size = metricCompact.size * 0.86
        spec.weight = .light
        return spec
    }
}
