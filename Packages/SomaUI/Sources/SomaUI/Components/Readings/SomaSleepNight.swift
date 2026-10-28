//
//  SomaSleepNight.swift
//  SomaUI
//

import SwiftUI

// MARK: - Grades

/// How one part of a night went, in four words.
public enum SomaSleepGrade: Int, CaseIterable, Sendable, Comparable {
    case poor, fair, good, excellent

    public var title: LocalizedStringResource {
        switch self {
        case .poor: "Poor"
        case .fair: "Fair"
        case .good: "Good"
        case .excellent: "Excellent"
        }
    }

    /// Green for a part that went well, amber for one worth a look, red for
    /// one that went badly: the status colours, not the accent.
    public func color(_ theme: SomaTheme) -> Color {
        switch self {
        case .excellent, .good: theme.colors.statusNormal.color
        case .fair: theme.colors.statusOut.color
        case .poor: theme.colors.statusAlert.color
        }
    }

    public static func < (lhs: SomaSleepGrade, rhs: SomaSleepGrade) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// The six parts a night is graded on, in the order the grid shows them.
public enum SomaSleepFactor: String, CaseIterable, Sendable {
    case timeAsleep, heartRateDip, rem, deep, efficiency, continuity

    public var title: LocalizedStringResource {
        switch self {
        case .timeAsleep: "Time asleep"
        case .heartRateDip: "Heart rate dip"
        case .rem: "REM"
        case .deep: "Deep"
        case .efficiency: "Efficiency"
        case .continuity: "Continuity"
        }
    }

    /// The SF Symbol over the grade.
    public var symbol: String {
        switch self {
        case .timeAsleep: "clock.fill"
        case .heartRateDip: "arrow.down.heart.fill"
        case .rem: "eye.fill"
        case .deep: "zzz"
        case .efficiency: "gauge.with.dots.needle.67percent"
        case .continuity: "link"
        }
    }
}

/// One cell of the grade grid: a part, its grade and how far along its bar
/// it got, from 0 to 1. A part nothing measured has neither.
public struct SomaSleepFactorGrade: Sendable, Hashable, Identifiable {
    public var id: SomaSleepFactor { factor }
    public let factor: SomaSleepFactor
    public let grade: SomaSleepGrade?
    public let progress: Double?

    public init(factor: SomaSleepFactor, grade: SomaSleepGrade?, progress: Double?) {
        self.factor = factor
        self.grade = grade
        self.progress = progress.map { min(1, max(0, $0)) }
    }
}

// MARK: - Durations as the section prints them

enum SomaSleepClock {
    /// "7h 5m", "45m", through ``SomaFormat``.
    static func short(_ seconds: TimeInterval) -> String {
        SomaFormat.duration(seconds)
    }

}

// MARK: - Sleep period

/// The night's span on one row: a bed, "Sleep period", and bed to wake on the
/// trailing edge.
public struct SomaSleepPeriodRow: View {
    private let bed: String?
    private let wake: String?

    @Environment(\.somaTheme) private var theme

    /// Clock times as the app prints them; a missing one reads as a dash.
    public init(bed: String?, wake: String?) {
        self.bed = bed
        self.wake = wake
    }

    public var body: some View {
        let metrics = theme.metrics
        let span: String? = if let bed, let wake { "\(bed) to \(wake)" } else { nil }

        HStack(spacing: metrics.chartLabelGap * 1.5) {
            // Set in the body role at the glyph's own size: a bare symbol
            // follows Dynamic Type while every word beside it is fixed, and
            // grew out of its frame over "Sleep period".
            Image(systemName: "bed.double.fill")
                .somaGlyph(theme.typography.body, size: metrics.sleepGlyphSize)
                .foregroundStyle(theme.colors.inkSecondary.color)
                .frame(width: metrics.sleepGlyphSize * 1.5)
            Text("Sleep period")
                .somaFont(theme.typography.body)
                .foregroundStyle(theme.colors.inkPrimary.color)
            Spacer(minLength: metrics.chartLabelGap)
            SomaNumber(span, theme.typography.rowValue)
                .foregroundStyle(theme.colors.inkPrimary.color)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Totals

/// Time in bed and time asleep, side by side, set the way Apple Health sets
/// them: a quiet label over large digits with their units small ("7h 13m",
/// through ``SomaDurationText``), both left aligned. The owner asked for Apple's sleep page
/// (2026-10-25).
///
/// A page whose hero already gives the time asleep passes `showsAsleep:
/// false`, so the screen says it once; time in bed then keeps its half.
public struct SomaSleepTotals: View {
    private let inBed: TimeInterval?
    private let asleep: TimeInterval?
    private let showsAsleep: Bool

    @Environment(\.somaTheme) private var theme

    public init(inBed: TimeInterval?, asleep: TimeInterval?, showsAsleep: Bool = true) {
        self.inBed = inBed
        self.asleep = asleep
        self.showsAsleep = showsAsleep
    }

    public var body: some View {
        HStack(alignment: .top, spacing: theme.metrics.cardSpacing) {
            total("Time in bed", inBed)
            if showsAsleep {
                total("Time asleep", asleep)
            } else {
                Color.clear.frame(maxWidth: .infinity)
            }
        }
    }

    private func total(_ title: LocalizedStringResource, _ seconds: TimeInterval?) -> some View {
        let type = theme.typography
        let colors = theme.colors

        return VStack(alignment: .leading, spacing: theme.metrics.chartLabelGap / 2) {
            Text(title)
                .somaFont(type.caption)
                .foregroundStyle(colors.inkSecondary.color)
            SomaDurationText(seconds, figures: type.metric, units: type.caption)
            .foregroundStyle(colors.inkPrimary.color)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Grade grid

/// The night's parts in a grid of two columns: a glyph, the grade in a word,
/// the part's name, and a thin bar in the grade's colour.
public struct SomaSleepGradeGrid: View {
    private let grades: [SomaSleepFactorGrade]

    @Environment(\.somaTheme) private var theme

    public init(_ grades: [SomaSleepFactorGrade]) {
        self.grades = grades
    }

    public var body: some View {
        let rows = stride(from: 0, to: grades.count, by: 2).map { Array(grades[$0..<min($0 + 2, grades.count)]) }
        let hairline = theme.colors.inkPrimary.color.opacity(theme.metrics.hairlineOpacity)

        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                if index > 0 {
                    Rectangle().fill(hairline).frame(height: 0.5)
                }
                HStack(spacing: 0) {
                    ForEach(Array(row.enumerated()), id: \.element.id) { column, grade in
                        if column > 0 {
                            Rectangle().fill(hairline).frame(width: 0.5)
                                .padding(.vertical, theme.metrics.sleepGradeCellPadding)
                        }
                        cell(grade)
                    }
                    if row.count == 1 { Color.clear.frame(maxWidth: .infinity) }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func cell(_ item: SomaSleepFactorGrade) -> some View {
        let metrics = theme.metrics
        let colors = theme.colors
        let tint = item.grade?.color(theme) ?? colors.inkSecondary.color

        return VStack(spacing: metrics.chartLabelGap / 2) {
            Image(systemName: item.factor.symbol)
                .somaGlyph(theme.typography.body, size: metrics.sleepGlyphSize)
                .foregroundStyle(colors.inkSecondary.color)
                .frame(height: metrics.sleepGlyphSize)
                .padding(.bottom, metrics.chartLabelGap / 2)
            Group {
                if let grade = item.grade {
                    Text(grade.title).somaFont(theme.typography.headerTitle)
                } else {
                    SomaMissingValue(theme.typography.headerTitle)
                }
            }
            .foregroundStyle(colors.inkPrimary.color)
            Text(item.factor.title)
                .somaFont(theme.typography.caption)
                .foregroundStyle(colors.inkSecondary.color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Capsule()
                .fill(colors.inkPrimary.color.opacity(metrics.sleepStageRingTrackOpacity))
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        Capsule()
                            .fill(tint)
                            .frame(width: proxy.size.width * (item.progress ?? 0))
                    }
                }
                .frame(width: metrics.sleepGradeBarWidth, height: metrics.sleepGradeBarHeight)
                .padding(.top, metrics.chartLabelGap)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, metrics.sleepGradeCellPadding)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(item.factor.title))
        .accessibilityValue(item.grade.map { Text($0.title) } ?? Text(verbatim: SomaFormat.notMeasured))
    }
}

// MARK: - Stage tiles

/// The four stages in a grid of two: each tile names its stage, gives its
/// time to the second in large digits and its share of the night in the
/// stage's colour, with a ring that fills to that share.
public struct SomaStageTiles: View {
    private let durations: [SomaSleepStage: TimeInterval]

    @Environment(\.somaTheme) private var theme

    /// Seconds in each stage; a stage left out reads as a dash.
    public init(_ durations: [SomaSleepStage: TimeInterval]) {
        self.durations = durations
    }

    public var body: some View {
        let total = durations.values.reduce(0, +)
        let spacing = theme.metrics.cardSpacing
        let stages = SomaSleepStage.allCases

        VStack(spacing: spacing) {
            ForEach([0, 2], id: \.self) { start in
                HStack(spacing: spacing) {
                    ForEach(stages[start..<start + 2], id: \.self) { stage in
                        SomaStageTile(stage: stage, seconds: durations[stage],
                                      share: total > 0 ? durations[stage].map { $0 / total } : nil)
                    }
                }
            }
        }
    }
}

/// One stage's tile; see `SomaStageTiles`.
public struct SomaStageTile: View {
    private let stage: SomaSleepStage
    private let seconds: TimeInterval?
    private let share: Double?

    @Environment(\.somaTheme) private var theme

    public init(stage: SomaSleepStage, seconds: TimeInterval?, share: Double?) {
        self.stage = stage
        self.seconds = seconds
        self.share = share.map { min(1, max(0, $0)) }
    }

    public var body: some View {
        let metrics = theme.metrics
        let colors = theme.colors
        let hue = stage.color(theme)
        let percent = share.map { "\(Int(($0 * 100).rounded()))%" }

        HStack(spacing: metrics.chartLabelGap) {
            VStack(alignment: .leading, spacing: 2) {
                Text(stage.title)
                    .somaFont(theme.typography.caption)
                    .foregroundStyle(colors.inkSecondary.color)
                SomaNumber(SomaFormat.duration(seconds), theme.typography.metricCompact)
                    .foregroundStyle(colors.inkPrimary.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                SomaNumber(percent, theme.typography.captionValue)
                    .foregroundStyle(hue)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ZStack {
                Circle()
                    .stroke(colors.inkPrimary.color.opacity(metrics.sleepStageRingTrackOpacity),
                            lineWidth: metrics.sleepStageRingStroke)
                Circle()
                    .trim(from: 0, to: share ?? 0)
                    .stroke(hue, style: StrokeStyle(lineWidth: metrics.sleepStageRingStroke, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .padding(metrics.sleepStageRingStroke / 2)
            .frame(width: metrics.sleepStageRingDiameter, height: metrics.sleepStageRingDiameter)
            .accessibilityHidden(true)
        }
        .padding(metrics.cardPadding)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: metrics.cardCornerRadius, style: .continuous)
                .fill(colors.surface.color)
        )
        .overlay(
            RoundedRectangle(cornerRadius: metrics.cardCornerRadius, style: .continuous)
                .strokeBorder(colors.inkPrimary.color.opacity(metrics.hairlineOpacity), lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Previews

#Preview("Sleep period and totals") {
    ZStack {
        SomaPreviewBackdrop()
        SomaCard {
            VStack(spacing: SomaMetrics.standard.spaceM) {
                SomaSleepPeriodRow(bed: "23:34", wake: "06:39")
                SomaSleepTotals(inBed: 25_522, asleep: 24_619)
                SomaSleepTotals(inBed: nil, asleep: nil)
                SomaSleepTotals(inBed: 25_522, asleep: 24_619, showsAsleep: false)
            }
        }
        .padding()
    }
}

#Preview("Sleep grades") {
    ZStack {
        SomaPreviewBackdrop()
        SomaCard {
            SomaSleepGradeGrid(SomaSleepFactor.allCases.enumerated().map { index, factor in
                let grade = SomaSleepGrade(rawValue: (index * 3 + 2) % 4)
                return SomaSleepFactorGrade(factor: factor, grade: index == 5 ? nil : grade,
                                            progress: index == 5 ? nil : 0.2 + Double(index) * 0.14)
            })
        }
        .padding()
    }
}

#Preview("Stage tiles") {
    ZStack {
        SomaPreviewBackdrop()
        SomaStageTiles([.awake: 903, .rem: 6_358, .core: 15_578, .deep: 2_681])
            .padding()
    }
}
