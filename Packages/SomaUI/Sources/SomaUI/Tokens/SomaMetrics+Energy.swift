//
//  SomaMetrics+Energy.swift
//  SomaUI
//

import CoreGraphics

/// The sizes the energy bank draws with: the battery at the head of the
/// page, the two tiles under it, the day's curve and the rows of what moved
/// it.
///
/// Computed, like the score sizes, so they add no stored field to the theme.
public extension SomaMetrics {
    /// The battery's body, nub left out.
    var bankBatteryWidth: CGFloat { 236 }
    var bankBatteryHeight: CGFloat { 112 }
    var bankBatteryCornerRadius: CGFloat { 30 }
    /// The rim round the body.
    var bankBatteryRim: CGFloat { 3 }
    /// The gap between the rim and the charge inside it.
    var bankBatteryInset: CGFloat { 7 }
    /// The terminal at the battery's end.
    var bankBatteryNubWidth: CGFloat { 9 }
    var bankBatteryNubHeight: CGFloat { 38 }
    var bankBatteryNubGap: CGFloat { 4 }
    /// How far the charge's glow spreads.
    var bankBatteryGlow: CGFloat { 18 }
    /// How strongly the glow shows.
    var bankBatteryGlowOpacity: Double { 0.45 }

    /// The day's plot, axis and glyph row left out.
    var bankChartHeight: CGFloat { 200 }
    /// The row of glyphs over the plot that names each band.
    var bankChartGlyphRow: CGFloat { 22 }
    /// The column on the trailing edge that holds the level labels.
    var bankChartGutter: CGFloat { 30 }
    /// The curve's stroke.
    var bankChartLine: CGFloat { 3 }
    /// The cap drawn along the top of a band.
    var bankChartBandCap: CGFloat { 2 }
    /// How strongly a band (sleep, a workout, the peak window) is shaded.
    var bankChartBandOpacity: Double { 0.16 }
    /// How strongly the fill under the curve shows at the curve itself.
    var bankChartFillOpacity: Double { 0.42 }
    /// The dot that marks now on the curve.
    var bankChartNowDot: CGFloat { 12 }

    /// The tinted disc that holds an event's glyph.
    var bankEntryGlyph: CGFloat { 36 }
    /// The track an event's charge or drain is drawn on.
    var bankEntryBarWidth: CGFloat { 64 }
    var bankEntryBarHeight: CGFloat { 6 }
    /// The trailing column that holds an event's signed number.
    var bankEntryValueColumn: CGFloat { 48 }

    /// A day of the history.
    var bankHistoryHeight: CGFloat { 160 }
    var bankHistoryBarGap: CGFloat { 3 }
}
