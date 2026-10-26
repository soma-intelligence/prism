//
//  SomaTypography+ScoreStyles.swift
//  SomaUI
//

import SwiftUI

/// The numbers inside the radial proposals for Today's scores
/// (``SomaScoresStyle``), derived from the scale rather than added to it.
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

    /// The halo's number: the line round it is a hairline, so the number
    /// carries the dial, larger and lighter still.
    var scoreDialFigureLarge: SomaFontSpec {
        var spec = metricCompact
        spec.size = metricCompact.size * 1.08
        spec.weight = .thin
        return spec
    }

    /// The number inside the seven day dial, whose middle is smaller: the
    /// petals round it carry the reading.
    var scoreDialFigureCompact: SomaFontSpec {
        var spec = metricCompact
        spec.size = metricCompact.size * 0.72
        spec.weight = .light
        return spec
    }
}
