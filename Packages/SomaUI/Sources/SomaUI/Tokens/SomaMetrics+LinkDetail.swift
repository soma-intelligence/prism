//
//  SomaMetrics+LinkDetail.swift
//  SomaUI
//

import CoreGraphics

/// The proportions of a link's detail sheet: the large comparison of the two
/// sides, the outcome in time with the driver days lit, the strength meter
/// and the gate's progress bar.
///
/// Computed so they add no stored field to the theme.
public extension SomaMetrics {
    /// One side's row in the large comparison.
    var linkDetailRowHeight: CGFloat { 44 }
    /// The band between the two rows that carries the gap's bracket.
    var linkDetailGapHeight: CGFloat { 34 }
    /// The column naming each row: "With", "Without".
    var linkDetailLabelWidth: CGFloat { 64 }
    /// One day's dot in the large comparison.
    var linkDetailDot: CGFloat { 7 }
    /// Gap between the sheet's sections.
    var linkDetailSpacing: CGFloat { 20 }

    /// The strength meter: rising bars, the tallest this high.
    var linkMeterHeight: CGFloat { 14 }
    var linkMeterBarWidth: CGFloat { 4 }
    var linkMeterSpacing: CGFloat { 2 }

    /// The gate's progress bar.
    var linkProgressHeight: CGFloat { 8 }

    /// The sheet's least size where a sheet is a window (macOS).
    var linkSheetMinWidth: CGFloat { 460 }
    var linkSheetMinHeight: CGFloat { 640 }
}
