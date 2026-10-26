import CoreGraphics
import SomaUI

/// The sizes the widgets draw with.
///
/// Computed on the theme's own scales, the way SomaUI adds a surface's sizes,
/// so they add no stored field to the theme and every view still reads them
/// through `@Environment(\.somaTheme)`. One value for touch and pointer: a
/// widget is drawn at the system's family size whatever the device.
public extension SomaMetrics {
    /// The inset WidgetKit gives a home screen widget's content.
    var widgetContentMargin: CGFloat { 16 }
    /// A ring's stroke on the medium widget and the lock screen.
    var widgetRingStroke: CGFloat { 4 }
    /// A ring's stroke on the small widget, where the ring is larger.
    var widgetRingStrokeSmall: CGFloat { 5 }
    /// How much of the ink a ring's or a bar's empty track carries.
    var widgetTrackOpacity: Double { 0.10 }
    /// How much of the ink a secondary line carries where the system flattens
    /// colour (accented and vibrant), so stale still reads as stale.
    var widgetSecondaryOpacity: Double { 0.55 }
    /// Height of a thin bar.
    var widgetBarHeight: CGFloat { 4 }
    /// Stroke of a hairline trace.
    var widgetTraceStroke: CGFloat { 1.5 }
    /// The dot that marks the latest value on a trace.
    var widgetNowDot: CGFloat { 5 }
    /// Gap between a value and the label under it.
    var widgetLabelSpacing: CGFloat { 6 }
    /// Gap between the columns of the medium widget.
    var widgetColumnSpacing: CGFloat { 16 }
    /// Gap between the rows of a lock screen widget.
    var widgetRowSpacing: CGFloat { 4 }
    /// Gap between a row's label, bar and value.
    var widgetRowGap: CGFloat { 8 }
    /// Width of a lock screen row's label column.
    var widgetRowLabelColumn: CGFloat { 58 }
    /// Width of a lock screen row's value column.
    var widgetRowValueColumn: CGFloat { 24 }
    /// Inset between a ring and the number inside it.
    var widgetRingTextInset: CGFloat { 10 }
}

/// The type roles the widgets draw with: SomaUI's own roles, chosen for the
/// family sizes, plus one for the lock screen ring.
public extension SomaTypography {
    /// The number inside the small widget's one ring.
    var widgetHero: SomaFontSpec { metric }
    /// The number inside a ring of the medium widget.
    var widgetValue: SomaFontSpec { metricCompact }
    /// The number inside the lock screen ring, where 72 points is the whole
    /// widget.
    var widgetGlance: SomaFontSpec { SomaFontSpec(size: 20, tracking: -0.4, digits: .tabular) }
    /// The one word under a value, and the age of a stale snapshot.
    var widgetLabel: SomaFontSpec { caption }
    /// A measure's word when it wears its hue: the same size, one step
    /// heavier, the way Health sets its coloured titles.
    var widgetLabelStrong: SomaFontSpec {
        var spec = caption
        spec.weight = .semibold
        return spec
    }
    /// A number on a lock screen row.
    var widgetRowValue: SomaFontSpec { captionValue }
}

/// The sizes the Vitals, Strain and Fuel widgets add.
public extension SomaMetrics {
    /// How much of the ink last night's block under the energy curve carries.
    var widgetBandOpacity: Double { 0.06 }
    /// The hypnogram's rows, from awake at the top to deep at the bottom: the
    /// lighter the sleep, the darker the ink.
    var widgetStageAwakeOpacity: Double { 1.0 }
    var widgetStageRemOpacity: Double { 0.7 }
    var widgetStageCoreOpacity: Double { 0.45 }
    var widgetStageDeepOpacity: Double { 0.25 }
    /// Height of one hypnogram row.
    var widgetStageRowHeight: CGFloat { 8 }
    /// Gap between two hypnogram rows.
    var widgetStageRowGap: CGFloat { 3 }
    /// Width of the hypnogram's word column.
    var widgetStageLabelColumn: CGFloat { 44 }
    /// Gap between a number and its unit.
    var widgetUnitSpacing: CGFloat { 3 }
    /// Width of a lock screen Vitals row's value column, wide enough for "7:12".
    var widgetVitalsValueColumn: CGFloat { 34 }
    /// Height of a seven day trace under a value.
    var widgetTraceHeight: CGFloat { 32 }
    /// Height of a seven day trace across a large widget.
    var widgetTraceHeightLarge: CGFloat { 48 }
    /// Width of a large widget's number column, beside its trace.
    var widgetLargeLabelColumn: CGFloat { 120 }
    /// Width of the medium Strain widget's stress column.
    var widgetSideColumn: CGFloat { 84 }
    /// Gap between the blocks of a large widget.
    var widgetBlockSpacing: CGFloat { 20 }
}

public extension SomaTypography {
    /// A value where three stack in a small widget, and a second figure beside
    /// a hero one.
    var widgetFigure: SomaFontSpec { title }
    /// The unit after a number.
    var widgetUnit: SomaFontSpec { caption }
}

/// The sizes the Log widget adds.
public extension SomaMetrics {
    /// Diameter of a log button: a circle a thumb can find.
    var widgetLogButton: CGFloat { 44 }
}

public extension SomaTypography {
    /// The glyph on a log button.
    var widgetGlyph: SomaFontSpec { SomaFontSpec(size: 18) }
}
