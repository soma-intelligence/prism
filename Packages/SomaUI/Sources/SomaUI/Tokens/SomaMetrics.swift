//
//  SomaMetrics.swift
//  SomaUI
//

import SwiftUI

/// The measurements the chrome is built from.
///
/// A consumer that needs a denser or roomier bar edits these rather than
/// forking the component.
public struct SomaMetrics: Sendable, Equatable {
    /// Height of one tab's touch area.
    public var tabHeight: CGFloat
    /// Floor for a tab's share of the row; above it the tabs split evenly.
    public var tabMinWidth: CGFloat
    /// Point size of a tab's glyph.
    public var tabGlyphSize: CGFloat
    /// Point size of a tab's glyph once the labels are dropped.
    public var tabGlyphSizeAccessible: CGFloat
    /// Inset between the tabs and the glass capsule's edge.
    public var barPadding: CGFloat
    /// Gap between the tab capsule and the trailing accessory.
    public var barPieceSpacing: CGFloat
    /// Diameter of a round glass accessory.
    public var accessoryDiameter: CGFloat
    /// Height of the content row that rides the tab view's bottom accessory.
    ///
    /// A floor and not a fixed height: the row grows with Dynamic Type instead
    /// of clipping its label at the largest accessibility sizes.
    public var accessoryRowHeight: CGFloat
    /// The same row once the accessory has slid inline beside the minimized
    /// bar, where everything has to read inside a tab bar's height.
    public var accessoryRowHeightInline: CGFloat
    /// Inset between that row's content and the accessory's edge.
    public var accessoryRowPadding: CGFloat
    /// The same inset, inline.
    public var accessoryRowPaddingInline: CGFloat
    /// Gap between the row's mark and its label.
    public var accessoryRowSpacing: CGFloat
    /// The same gap, inline.
    public var accessoryRowSpacingInline: CGFloat
    /// Edge of the mark that opens the row.
    public var accessoryMarkDiameter: CGFloat
    /// The same mark, inline.
    public var accessoryMarkDiameterInline: CGFloat
    /// Diameter of a round glass icon button.
    public var iconButtonDiameter: CGFloat
    /// Diameter of a profile picture.
    public var avatarDiameter: CGFloat
    /// Edge of the square the Soma mark fills.
    public var markSize: CGFloat
    /// Smallest touch target the system will accept.
    public var minimumTapTarget: CGFloat
    /// Gap between the bar and the edge it floats against.
    public var barEdgePadding: CGFloat
    /// Height of the one glass capsule the header chrome sits in.
    public var chromeCapsuleHeight: CGFloat
    /// Width of one slot inside that capsule.
    public var chromeSlotWidth: CGFloat
    /// Height of the blur that anchors the floating header.
    public var headerBlurHeight: CGFloat
    /// Height of one segment of a segmented control: the pill the selected one
    /// sits in.
    public var segmentHeight: CGFloat
    /// Inset between a segment's label and the edge of its pill.
    public var segmentLabelPadding: CGFloat
    /// Gap between two segments.
    public var segmentSpacing: CGFloat
    /// Inset between the segments and the glass track they sit in.
    public var segmentTrackPadding: CGFloat
    /// Narrowest the sidebar column may be drawn.
    public var sidebarMinWidth: CGFloat
    /// The width the sidebar opens at.
    public var sidebarIdealWidth: CGFloat
    /// Widest the sidebar column may be dragged.
    public var sidebarMaxWidth: CGFloat
    /// Opacity of the tonal capsule that marks the selected tab.
    public var selectionFillOpacity: Double
    /// Widest the bar grows on a roomy screen, where filling the row would
    /// leave the tabs marooned at opposite edges.
    public var barMaxWidthRegular: CGFloat
    /// Corner radius of anything that sits on the page as a surface: a card,
    /// a group of rows, a photograph, a tile. One radius, so neighbours line up.
    public var cardCornerRadius: CGFloat
    /// Corner radius of a control set inside a card: a field, a filled
    /// button, a segmented track, a tile within a card. Concentric with the
    /// card at the standard inset: the card's radius minus the space between.
    public var controlCornerRadius: CGFloat
    /// Corner radius of a chip, a tag, a thumbnail at a card's padding, or the
    /// selected piece inside a control. Concentric with the control.
    public var chipCornerRadius: CGFloat
    /// Inset between a card's edge and its content.
    public var cardPadding: CGFloat
    /// Opacity of the single hairline that separates a card from its ground.
    public var hairlineOpacity: Double
    /// Narrowest a card gets before a page grid drops to fewer columns.
    public var cardMinWidth: CGFloat
    /// Inset between a page's content and the window edge.
    public var pagePadding: CGFloat
    /// Widest a column of page content grows before it stops and centres.
    public var pageMaxWidth: CGFloat
    /// Radius of the breathing glow behind a living element.
    public var glowRadius: CGFloat
    /// Opacity the glow breathes between.
    public var glowOpacityRange: ClosedRange<Double>

    /// Shortest a browse row is drawn before its own content grows it.
    public var browseRowMinHeight: CGFloat
    /// Inset between a browse row's content and the group's edge.
    public var browseRowPadding: CGFloat
    /// Gap between a browse row's glyph column and its title.
    public var browseRowSpacing: CGFloat
    /// Width of the column a browse row's glyph is centred in.
    ///
    /// A column and not an intrinsic width: glyphs differ in how much ink they
    /// carry, and titles that start at different x positions read as a ragged
    /// list rather than a column.
    public var browseGlyphColumn: CGFloat
    /// Point size of a browse row's glyph.
    public var browseGlyphSize: CGFloat
    /// Point size of the chevron that says a browse row opens something.
    public var browseChevronSize: CGFloat
    /// Gap between one browse section and the next.
    public var browseSectionSpacing: CGFloat
    /// Gap between a browse section's heading and its group.
    public var browseHeadingSpacing: CGFloat
    /// Inset above and below a browse row's content, on top of its floor
    /// height. What keeps a wrapped title off the separator.
    public var browseRowVerticalPadding: CGFloat
    /// Opacity of the line between two browse rows.
    ///
    /// Its own token rather than ``hairlineOpacity``: a card's rim separates a
    /// surface from the ground behind it, while this one divides two rows on
    /// the same surface, and has to carry at a glance down a long list.
    public var browseSeparatorOpacity: Double
    /// Opacity of the wash a browse row fills with while pressed.
    public var browsePressOpacity: Double

    /// The record button's outer diameter.
    public var shutterDiameter: CGFloat
    /// Width of the record button's white ring.
    public var shutterRingWidth: CGFloat
    /// Gap between the ring and the red inside it.
    public var shutterGap: CGFloat
    /// Side of the red square the record button shows while recording.
    public var shutterStopSide: CGFloat
    /// Corner radius of that square.
    public var shutterStopCornerRadius: CGFloat
    /// Diameter of a camera control beside the record button.
    public var cameraControlDiameter: CGFloat
    /// Corner radius of the last capture's thumbnail.
    public var cameraThumbnailCornerRadius: CGFloat
    /// Height of a pill laid on the camera's picture.
    public var cameraPillHeight: CGFloat
    /// Height of a pill in the camera's top bar, and of the recording timer.
    public var cameraTopPillHeight: CGFloat
    /// Corner radius of the recording timer.
    public var cameraTimerCornerRadius: CGFloat
    /// Gap between two labels of a mode strip.
    public var modeStripSpacing: CGFloat
    /// Gap above the mode strip and between it and the shutter row.
    public var modeStripGap: CGFloat
    /// Gap between the shutter row and the foot of the safe area.
    public var shutterRowBottomPadding: CGFloat
    /// Opacity of the dark band the camera's controls sit on over the picture.
    public var cameraBandOpacity: Double

    /// Diameter of the orb at the head of a page: the sphere, not its halo.
    public var orbDiameter: CGFloat
    /// Diameter of the small orb that leads a row.
    public var miniOrbDiameter: CGFloat
    /// How far a finger can travel on the orb before the press lets go: past
    /// it the touch is a scroll, not a press.
    public var orbPressReach: CGFloat
    /// Room between the top bar and the orb, where its halo spreads.
    public var heroTopPadding: CGFloat
    /// Gap between the orb, its page dots and the hairline under them.
    public var heroSpacing: CGFloat
    /// Gap above the sentence a page leads with, and under the lines that
    /// explain it.
    public var leadSpacing: CGFloat
    /// Edge of one page dot under the orb.
    public var aspectDotSize: CGFloat
    /// Width the selected page dot stretches to.
    public var aspectDotSelectedWidth: CGFloat
    /// Gap between two page dots.
    public var aspectDotSpacing: CGFloat
    /// Opacity of a page dot that is not selected.
    public var aspectDotOpacity: Double
    /// Gap between a score's label and its number.
    public var scoreLabelSpacing: CGFloat
    /// Width of the triangle that says a value rose or fell.
    public var trendMarkWidth: CGFloat
    /// Height of that triangle.
    public var trendMarkHeight: CGFloat
    /// Gap between a number and its trend mark.
    public var trendMarkSpacing: CGFloat
    /// Gap between two cards in a column, and inside a card between its header and its rows.
    public var cardSpacing: CGFloat
    /// Gap between a card's title and the caption under it.
    public var cardHeaderSpacing: CGFloat
    /// Edge of the Soma mark set beside a caption.
    public var markCaptionSize: CGFloat
    /// Gap between two rows of a list of moves.
    public var moveRowSpacing: CGFloat
    /// Gap between a row's orb, its text and its check.
    public var moveRowGap: CGFloat
    /// Diameter of the check at the end of a move.
    public var checkDiameter: CGFloat
    /// How many ticks make the energy battery.
    public var energyTickCount: Int
    /// Width of one tick of the energy battery.
    public var energyTickWidth: CGFloat
    /// Height of one tick of the energy battery.
    public var energyTickHeight: CGFloat
    /// Opacity of a tick below today's level.
    public var energyFullOpacity: Double
    /// Gap between a timeline's column of times and its rail of dots.
    public var timelineTimeGap: CGFloat
    /// Gap between the rail of dots and the events beside them.
    public var timelineTextGap: CGFloat
    /// Diameter of an event's dot on the rail.
    public var timelineDotDiameter: CGFloat
    /// Diameter of the dot that marks now.
    public var timelineNowDotDiameter: CGFloat
    /// Gap between two events.
    public var timelineRowSpacing: CGFloat
    /// Diameter of the dot that names a card's aspect.
    public var identityDotDiameter: CGFloat
    /// Gap between that dot and the eyebrow beside it.
    public var identityDotSpacing: CGFloat
    /// Width of the small chart at the end of an aspect card.
    public var aspectChartWidth: CGFloat
    /// Height of that chart.
    public var aspectChartHeight: CGFloat
    /// Width of one bar in a small chart.
    public var chartBarWidth: CGFloat
    /// Radius of a bar's data end.
    public var chartBarCornerRadius: CGFloat
    /// Stroke of a line in a small chart.
    public var chartLineWidth: CGFloat
    /// Diameter of the dot on a line's last point.
    public var chartDotDiameter: CGFloat
    /// Height of the track a value sits on.
    public var chartTrackHeight: CGFloat
    /// Diameter of the dot that marks an estimate on its track.
    public var chartEstimateDiameter: CGFloat
    /// Width of the tick that marks a reference on a track.
    public var chartMarkerWidth: CGFloat
    /// Height of that tick.
    public var chartMarkerHeight: CGFloat
    /// Opacity of the marks around the one a chart is about.
    public var chartContextOpacity: Double
    /// Opacity of the span an estimate may be off by.
    public var chartSpreadOpacity: Double

    public init(
        tabHeight: CGFloat = 46,
        tabMinWidth: CGFloat = 60,
        tabGlyphSize: CGFloat = 22,
        tabGlyphSizeAccessible: CGFloat = 24,
        barPadding: CGFloat = 6,
        barPieceSpacing: CGFloat = 14,
        barEdgePadding: CGFloat = 8,
        chromeCapsuleHeight: CGFloat = 40,
        chromeSlotWidth: CGFloat = 44,
        headerBlurHeight: CGFloat = 132,
        segmentHeight: CGFloat = 30,
        segmentLabelPadding: CGFloat = 9,
        segmentSpacing: CGFloat = 7,
        segmentTrackPadding: CGFloat = 4,
        sidebarMinWidth: CGFloat = 230,
        sidebarIdealWidth: CGFloat = 260,
        sidebarMaxWidth: CGFloat = 320,
        accessoryDiameter: CGFloat = 58,
        accessoryRowHeight: CGFloat = 52,
        accessoryRowHeightInline: CGFloat = 44,
        accessoryRowPadding: CGFloat = 14,
        accessoryRowPaddingInline: CGFloat = 12,
        accessoryRowSpacing: CGFloat = 10,
        accessoryRowSpacingInline: CGFloat = 8,
        accessoryMarkDiameter: CGFloat = 22,
        accessoryMarkDiameterInline: CGFloat = 20,
        iconButtonDiameter: CGFloat = 44,
        avatarDiameter: CGFloat = 38,
        markSize: CGFloat = 28,
        minimumTapTarget: CGFloat = 44,
        selectionFillOpacity: Double = 0.08,
        barMaxWidthRegular: CGFloat = 560,
        cardCornerRadius: CGFloat = 24,
        controlCornerRadius: CGFloat = 12,
        chipCornerRadius: CGFloat = 8,
        cardPadding: CGFloat = 16,
        hairlineOpacity: Double = 0.10,
        cardMinWidth: CGFloat = 260,
        pagePadding: CGFloat = 16,
        pageMaxWidth: CGFloat = 900,
        glowRadius: CGFloat = 12,
        glowOpacityRange: ClosedRange<Double> = 0.2...0.4,
        browseRowMinHeight: CGFloat = 44,
        browseRowPadding: CGFloat = 16,
        browseRowSpacing: CGFloat = 12,
        browseGlyphColumn: CGFloat = 28,
        browseGlyphSize: CGFloat = 20,
        browseChevronSize: CGFloat = 13,
        browseSectionSpacing: CGFloat = 24,
        browseHeadingSpacing: CGFloat = 8,
        browseRowVerticalPadding: CGFloat = 6,
        browseSeparatorOpacity: Double = 0.14,
        browsePressOpacity: Double = 0.07,
        shutterDiameter: CGFloat = 72,
        shutterRingWidth: CGFloat = 4,
        shutterGap: CGFloat = 3,
        shutterStopSide: CGFloat = 28,
        shutterStopCornerRadius: CGFloat = 6,
        cameraControlDiameter: CGFloat = 44,
        cameraThumbnailCornerRadius: CGFloat = 8,
        cameraPillHeight: CGFloat = 28,
        cameraTopPillHeight: CGFloat = 30,
        cameraTimerCornerRadius: CGFloat = 6,
        modeStripSpacing: CGFloat = 20,
        modeStripGap: CGFloat = 16,
        shutterRowBottomPadding: CGFloat = 24,
        cameraBandOpacity: Double = 0.55,
        orbDiameter: CGFloat = 230,
        miniOrbDiameter: CGFloat = 40,
        orbPressReach: CGFloat = 10,
        heroTopPadding: CGFloat = 20,
        heroSpacing: CGFloat = 16,
        leadSpacing: CGFloat = 24,
        aspectDotSize: CGFloat = 5,
        aspectDotSelectedWidth: CGFloat = 16,
        aspectDotSpacing: CGFloat = 6,
        aspectDotOpacity: Double = 0.28,
        scoreLabelSpacing: CGFloat = 2,
        trendMarkWidth: CGFloat = 8,
        trendMarkHeight: CGFloat = 7,
        trendMarkSpacing: CGFloat = 4,
        cardSpacing: CGFloat = 12,
        cardHeaderSpacing: CGFloat = 4,
        markCaptionSize: CGFloat = 11,
        moveRowSpacing: CGFloat = 12,
        moveRowGap: CGFloat = 12,
        checkDiameter: CGFloat = 22,
        energyTickCount: Int = 48,
        energyTickWidth: CGFloat = 3,
        energyTickHeight: CGFloat = 22,
        energyFullOpacity: Double = 0.85,
        timelineTimeGap: CGFloat = 16,
        timelineTextGap: CGFloat = 12,
        timelineDotDiameter: CGFloat = 8,
        timelineNowDotDiameter: CGFloat = 10,
        timelineRowSpacing: CGFloat = 12,
        identityDotDiameter: CGFloat = 8,
        identityDotSpacing: CGFloat = 8,
        aspectChartWidth: CGFloat = 118,
        aspectChartHeight: CGFloat = 54,
        chartBarWidth: CGFloat = 11,
        chartBarCornerRadius: CGFloat = 3,
        chartLineWidth: CGFloat = 2,
        chartDotDiameter: CGFloat = 7,
        chartTrackHeight: CGFloat = 6,
        chartEstimateDiameter: CGFloat = 11,
        chartMarkerWidth: CGFloat = 1.5,
        chartMarkerHeight: CGFloat = 22,
        chartContextOpacity: Double = 0.35,
        chartSpreadOpacity: Double = 0.45
    ) {
        self.tabHeight = tabHeight
        self.tabMinWidth = tabMinWidth
        self.tabGlyphSize = tabGlyphSize
        self.tabGlyphSizeAccessible = tabGlyphSizeAccessible
        self.barPadding = barPadding
        self.barPieceSpacing = barPieceSpacing
        self.barEdgePadding = barEdgePadding
        self.chromeCapsuleHeight = chromeCapsuleHeight
        self.chromeSlotWidth = chromeSlotWidth
        self.headerBlurHeight = headerBlurHeight
        self.segmentHeight = segmentHeight
        self.segmentLabelPadding = segmentLabelPadding
        self.segmentSpacing = segmentSpacing
        self.segmentTrackPadding = segmentTrackPadding
        self.sidebarMinWidth = sidebarMinWidth
        self.sidebarIdealWidth = sidebarIdealWidth
        self.sidebarMaxWidth = sidebarMaxWidth
        self.accessoryDiameter = accessoryDiameter
        self.accessoryRowHeight = accessoryRowHeight
        self.accessoryRowHeightInline = accessoryRowHeightInline
        self.accessoryRowPadding = accessoryRowPadding
        self.accessoryRowPaddingInline = accessoryRowPaddingInline
        self.accessoryRowSpacing = accessoryRowSpacing
        self.accessoryRowSpacingInline = accessoryRowSpacingInline
        self.accessoryMarkDiameter = accessoryMarkDiameter
        self.accessoryMarkDiameterInline = accessoryMarkDiameterInline
        self.iconButtonDiameter = iconButtonDiameter
        self.avatarDiameter = avatarDiameter
        self.markSize = markSize
        self.minimumTapTarget = minimumTapTarget
        self.selectionFillOpacity = selectionFillOpacity
        self.barMaxWidthRegular = barMaxWidthRegular
        self.cardCornerRadius = cardCornerRadius
        self.controlCornerRadius = controlCornerRadius
        self.chipCornerRadius = chipCornerRadius
        self.cardPadding = cardPadding
        self.hairlineOpacity = hairlineOpacity
        self.cardMinWidth = cardMinWidth
        self.pagePadding = pagePadding
        self.pageMaxWidth = pageMaxWidth
        self.glowRadius = glowRadius
        self.glowOpacityRange = glowOpacityRange
        self.browseRowMinHeight = browseRowMinHeight
        self.browseRowPadding = browseRowPadding
        self.browseRowSpacing = browseRowSpacing
        self.browseGlyphColumn = browseGlyphColumn
        self.browseGlyphSize = browseGlyphSize
        self.browseChevronSize = browseChevronSize
        self.browseSectionSpacing = browseSectionSpacing
        self.browseHeadingSpacing = browseHeadingSpacing
        self.browseRowVerticalPadding = browseRowVerticalPadding
        self.browseSeparatorOpacity = browseSeparatorOpacity
        self.browsePressOpacity = browsePressOpacity
        self.shutterDiameter = shutterDiameter
        self.shutterRingWidth = shutterRingWidth
        self.shutterGap = shutterGap
        self.shutterStopSide = shutterStopSide
        self.shutterStopCornerRadius = shutterStopCornerRadius
        self.cameraControlDiameter = cameraControlDiameter
        self.cameraThumbnailCornerRadius = cameraThumbnailCornerRadius
        self.cameraPillHeight = cameraPillHeight
        self.cameraTopPillHeight = cameraTopPillHeight
        self.cameraTimerCornerRadius = cameraTimerCornerRadius
        self.modeStripSpacing = modeStripSpacing
        self.modeStripGap = modeStripGap
        self.shutterRowBottomPadding = shutterRowBottomPadding
        self.cameraBandOpacity = cameraBandOpacity
        self.orbDiameter = orbDiameter
        self.miniOrbDiameter = miniOrbDiameter
        self.orbPressReach = orbPressReach
        self.heroTopPadding = heroTopPadding
        self.heroSpacing = heroSpacing
        self.leadSpacing = leadSpacing
        self.aspectDotSize = aspectDotSize
        self.aspectDotSelectedWidth = aspectDotSelectedWidth
        self.aspectDotSpacing = aspectDotSpacing
        self.aspectDotOpacity = aspectDotOpacity
        self.scoreLabelSpacing = scoreLabelSpacing
        self.trendMarkWidth = trendMarkWidth
        self.trendMarkHeight = trendMarkHeight
        self.trendMarkSpacing = trendMarkSpacing
        self.cardSpacing = cardSpacing
        self.cardHeaderSpacing = cardHeaderSpacing
        self.markCaptionSize = markCaptionSize
        self.moveRowSpacing = moveRowSpacing
        self.moveRowGap = moveRowGap
        self.checkDiameter = checkDiameter
        self.energyTickCount = energyTickCount
        self.energyTickWidth = energyTickWidth
        self.energyTickHeight = energyTickHeight
        self.energyFullOpacity = energyFullOpacity
        self.timelineTimeGap = timelineTimeGap
        self.timelineTextGap = timelineTextGap
        self.timelineDotDiameter = timelineDotDiameter
        self.timelineNowDotDiameter = timelineNowDotDiameter
        self.timelineRowSpacing = timelineRowSpacing
        self.identityDotDiameter = identityDotDiameter
        self.identityDotSpacing = identityDotSpacing
        self.aspectChartWidth = aspectChartWidth
        self.aspectChartHeight = aspectChartHeight
        self.chartBarWidth = chartBarWidth
        self.chartBarCornerRadius = chartBarCornerRadius
        self.chartLineWidth = chartLineWidth
        self.chartDotDiameter = chartDotDiameter
        self.chartTrackHeight = chartTrackHeight
        self.chartEstimateDiameter = chartEstimateDiameter
        self.chartMarkerWidth = chartMarkerWidth
        self.chartMarkerHeight = chartMarkerHeight
        self.chartContextOpacity = chartContextOpacity
        self.chartSpreadOpacity = chartSpreadOpacity
    }

    /// Sized for a finger: 44pt targets, generous padding.
    public static let touch = SomaMetrics()

    /// Sized for a pointer. A cursor hits a 24pt target precisely, so the whole
    /// chrome tightens rather than carrying finger-sized slack onto a desk.
    public static let pointer = SomaMetrics(
        tabHeight: 32,
        tabMinWidth: 54,
        tabGlyphSize: 15,
        tabGlyphSizeAccessible: 19,
        barPadding: 4,
        barPieceSpacing: 10,
        barEdgePadding: 14,
        chromeCapsuleHeight: 30,
        chromeSlotWidth: 32,
        headerBlurHeight: 96,
        segmentHeight: 22,
        segmentLabelPadding: 8,
        segmentSpacing: 4,
        segmentTrackPadding: 3,
        sidebarMinWidth: 180,
        sidebarIdealWidth: 200,
        sidebarMaxWidth: 260,
        accessoryDiameter: 40,
        accessoryRowHeight: 38,
        accessoryRowHeightInline: 30,
        accessoryRowPadding: 10,
        accessoryRowPaddingInline: 8,
        accessoryRowSpacing: 8,
        accessoryRowSpacingInline: 6,
        accessoryMarkDiameter: 18,
        accessoryMarkDiameterInline: 16,
        iconButtonDiameter: 26,
        avatarDiameter: 24,
        markSize: 20,
        minimumTapTarget: 24,
        selectionFillOpacity: 0.10,
        barMaxWidthRegular: 440,
        cardCornerRadius: 16,
        controlCornerRadius: 8,
        chipCornerRadius: 4,
        cardPadding: 12,
        hairlineOpacity: 0.12,
        cardMinWidth: 230,
        pagePadding: 24,
        pageMaxWidth: 820,
        glowRadius: 10,
        glowOpacityRange: 0.15...0.3,
        browseRowMinHeight: 28,
        browseRowPadding: 12,
        browseRowSpacing: 8,
        browseGlyphColumn: 24,
        browseGlyphSize: 14,
        browseChevronSize: 11,
        browseSectionSpacing: 24,
        browseHeadingSpacing: 8,
        browseRowVerticalPadding: 6,
        browseSeparatorOpacity: 0.16,
        browsePressOpacity: 0.09,
        shutterDiameter: 52,
        shutterRingWidth: 3,
        shutterGap: 2,
        shutterStopSide: 20,
        shutterStopCornerRadius: 4,
        cameraControlDiameter: 30,
        cameraThumbnailCornerRadius: 6,
        cameraPillHeight: 22,
        cameraTopPillHeight: 24,
        cameraTimerCornerRadius: 5,
        modeStripSpacing: 16,
        modeStripGap: 12,
        shutterRowBottomPadding: 16,
        cameraBandOpacity: 0.55,
        orbDiameter: 180,
        miniOrbDiameter: 28,
        heroTopPadding: 24,
        heroSpacing: 16,
        leadSpacing: 24,
        aspectDotSize: 4,
        aspectDotSelectedWidth: 12,
        aspectDotSpacing: 5,
        aspectDotOpacity: 0.28,
        scoreLabelSpacing: 1,
        trendMarkWidth: 6,
        trendMarkHeight: 5,
        trendMarkSpacing: 3,
        cardSpacing: 8,
        cardHeaderSpacing: 4,
        markCaptionSize: 9,
        moveRowSpacing: 8,
        moveRowGap: 8,
        checkDiameter: 16,
        energyTickCount: 48,
        energyTickWidth: 2,
        energyTickHeight: 16,
        energyFullOpacity: 0.85,
        timelineTimeGap: 12,
        timelineTextGap: 8,
        timelineDotDiameter: 6,
        timelineNowDotDiameter: 8,
        timelineRowSpacing: 8,
        identityDotDiameter: 6,
        identityDotSpacing: 4,
        aspectChartWidth: 96,
        aspectChartHeight: 44,
        chartBarWidth: 8,
        chartBarCornerRadius: 2,
        chartLineWidth: 1.5,
        chartDotDiameter: 6,
        chartTrackHeight: 4,
        chartEstimateDiameter: 9,
        chartMarkerWidth: 1,
        chartMarkerHeight: 18,
        chartContextOpacity: 0.35,
        chartSpreadOpacity: 0.45
    )

#if os(macOS)
    public static let standard = pointer
#else
    public static let standard = touch
#endif

    /// Corner radius of the group a run of browse rows sits in: the card's,
    /// so a grouped list and a card beside it share one corner.
    public var browseGroupCornerRadius: CGFloat { cardCornerRadius }

    /// Outer height of the floating bar: what a consumer offsets content by.
    public var barHeight: CGFloat { tabHeight + barPadding * 2 }

    /// Height of a segmented control's glass track: a segment plus the inset
    /// above and below it.
    public var segmentTrackHeight: CGFloat { segmentHeight + segmentTrackPadding * 2 }

    /// How far above and below its track a segmented control still answers a
    /// tap: half of what the track falls short of the smallest touch target.
    public var segmentReach: CGFloat { max(0, (minimumTapTarget - segmentTrackHeight) / 2) }
}
