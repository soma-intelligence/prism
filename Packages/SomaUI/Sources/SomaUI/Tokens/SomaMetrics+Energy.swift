//
//  SomaMetrics+Energy.swift
//  SomaUI
//

import CoreGraphics

/// The sizes the energy bank draws with: the charge cell at the head of the
/// page, the day as a row of bars and the rows of what moved it.
///
/// Computed, like the score sizes, so they add no stored field to the theme.
public extension SomaMetrics {
    /// The charge cell at the head of the energy page, and the small one on
    /// Today's card: an upright pebble that fills from the foot.
    var energyCellWidth: CGFloat { 60 }
    var energyCellHeight: CGFloat { 124 }
    var energyCellCompactWidth: CGFloat { 30 }
    var energyCellCompactHeight: CGFloat { 58 }
    /// How round the cell is, as a share of its width.
    var energyCellRoundness: CGFloat { 0.4 }
    /// The gap between the cell's rim and the charge inside it, as a share of
    /// its width.
    var energyCellInset: CGFloat { 0.09 }
    /// How far the charge's surface tilts at the height of a slosh, as a
    /// share of the cell's width.
    var energyCellSlosh: CGFloat { 0.14 }

    /// The day as a row of bars, one an hour: their height, the gap between
    /// them and the faint track an hour still to come keeps.
    var energyTimelineHeight: CGFloat { 56 }
    var energyTimelineCompactHeight: CGFloat { 34 }
    var energyTimelineGap: CGFloat { 2 }
    var energyTimelineSlots: Int { 24 }
    /// How strongly an hour to come shows.
    var energyTimelineFutureOpacity: Double { 0.5 }

    /// The row that holds the clock labels under the day's hours.
    var bankChartGlyphRow: CGFloat { 22 }

    /// The tinted disc that holds an event's glyph.
    var bankEntryGlyph: CGFloat { 36 }
    /// The track an event's charge or drain is drawn on.
    var bankEntryBarWidth: CGFloat { 64 }
    var bankEntryBarHeight: CGFloat { 6 }
    /// The trailing column that holds an event's signed number.
    var bankEntryValueColumn: CGFloat { 48 }

    /// The gap between the words and numbers of one fact under the cell or
    /// beside the day's title: "Woke with 77 at 06:17".
    var energyFactSpacing: CGFloat { 4 }

    /// A day of the history.
    var bankHistoryHeight: CGFloat { 160 }
    var bankHistoryBarGap: CGFloat { 3 }
}

/// Sizes other components still read, kept from the parallel design lines.
public extension SomaMetrics {
    /// The battery's body, nub left out.
    var bankBatteryWidth: CGFloat { 236 }
    /// The day's plot, axis and glyph row left out.
    var bankChartHeight: CGFloat { 200 }
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
}
