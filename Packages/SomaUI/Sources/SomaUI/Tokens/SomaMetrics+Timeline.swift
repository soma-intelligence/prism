//
//  SomaMetrics+Timeline.swift
//  SomaUI
//

import CoreGraphics

/// The sizes the day's timeline draws with: the short list on a card and the
/// full day on its own page.
///
/// Computed, like the Pulse parts' sizes, so they add no stored field to the
/// theme.
public extension SomaMetrics {
    /// The coloured circle that carries an event's glyph.
    var timelineGlyphDiameter: CGFloat { 38 }
    /// Room between the glyph circle and the words beside it.
    var timelineGlyphGap: CGFloat { 12 }
    /// Vertical room above and below one event in the short list.
    var timelineListRowPadding: CGFloat { 11 }
    /// Room between two stats on an event's one line of numbers.
    var timelineStatSpacing: CGFloat { 10 }
    /// The pill under the short list that opens the full day.
    var timelinePillHeight: CGFloat { 40 }

    /// The column the full day's axis runs down.
    var timelineAxisColumn: CGFloat { 22 }
    /// The axis where nothing is happening, and where an event lasts.
    var timelineAxisWidth: CGFloat { 1 }
    var timelineDurationWidth: CGFloat { 3 }
    /// The ring on the axis at each hour shown.
    var timelineHourMarkDiameter: CGFloat { 5 }
    /// One hour tick, and one run of quiet hours folded into a short dotted span.
    var timelineHourRowHeight: CGFloat { 30 }
    var timelineGapRowHeight: CGFloat { 22 }
    /// The line across the day at the present moment.
    var timelineNowRowHeight: CGFloat { 28 }
    var timelineNowLineWidth: CGFloat { 1.5 }
    /// Vertical room around an event card on the full day.
    var timelineCardSpacing: CGFloat { 5 }
    /// Inside an event card on the full day.
    var timelineCardPadding: CGFloat { 12 }
    var timelineCardCornerRadius: CGFloat { 18 }
}
