//
//  MetricKit.swift
//  Prism
//

import SwiftUI
import SomaUI

// The pieces the fitness and metric pages share: rows of readings on one
// card, daily bars against a usual band, a line inside a band, a split bar
// with its legend, a strip of days and a ring. Each is driven by its inputs
// and the theme, and lives beside the pages because nothing outside them
// draws these shapes yet.

// MARK: - Sizes

extension SomaMetrics {
    /// A daily bar chart or a line chart on a metric page.
    var metricPlotHeight: CGFloat { 120 }
    /// The ECG trace.
    var metricTraceHeight: CGFloat { 110 }
    /// The map of routes.
    var metricMapHeight: CGFloat { 240 }
    /// The Move ring.
    var metricRingDiameter: CGFloat { 148 }
    var metricRingWidth: CGFloat { 14 }
    /// The bar a split is drawn as.
    var metricSplitHeight: CGFloat { 10 }
    /// One day in a strip of days.
    var metricStripHeight: CGFloat { 22 }
    /// Space between the columns of a table row.
    var metricColumnSpacing: CGFloat { 12 }
    /// The width of a numeric column in a table.
    var metricColumnWidth: CGFloat { 64 }
}

// MARK: - Tones

/// How strongly a mark is shaded: the aspect's hue in full, softened or
/// faint, or danger for what is too much. A tonal step and never a second
/// accent.
enum MetricTone: Equatable, Sendable {
    case full, soft, faint, danger, empty

    func color(_ theme: SomaTheme, aspect: SomaAspect) -> Color {
        let hue = theme.aspects[aspect].identity.color
        switch self {
        case .full: return hue
        case .soft: return hue.opacity(theme.metrics.chartContextOpacity + 0.3)
        case .faint: return hue.opacity(theme.metrics.chartContextOpacity)
        case .danger: return theme.colors.danger.color
        case .empty: return theme.colors.surfaceRecessed.color
        }
    }
}

// MARK: - Lead

/// The head of a metric page when Health could not be read, so a page never
/// shows its empty sentences where the truth is that nothing was asked.
enum MetricLead {
    static func override(_ status: HealthDashboard.Status) -> (title: String, reason: String)? {
        switch status {
        case .unavailable:
            return ("No Health store here.", "This device has no Apple Health. These readings come from iPhone and Apple Watch.")
        case .failed(let message):
            return ("Could not read Health.", message)
        default:
            return nil
        }
    }
}

// MARK: - Rows

/// One row of readings: what it is, a line under it, the value, and a
/// chevron when it opens a page.
struct MetricRowItem: Identifiable {
    var id: String
    var title: String
    var detail: String?
    var value: String?
    var route: MetricRoute?
    var action: (() -> Void)?

    init(_ title: String, detail: String? = nil, value: String? = nil, route: MetricRoute? = nil, id: String? = nil, action: (() -> Void)? = nil) {
        self.id = id ?? title + (detail ?? "")
        self.title = title
        self.detail = detail
        self.value = value
        self.route = route
        self.action = action
    }
}

/// Rows of readings on one card with hairlines between them, and an eyebrow
/// over the card when the rows need a name.
struct MetricRowsCard: View {
    var eyebrow: String?
    let rows: [MetricRowItem]
    var footnote: String?

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics

        VStack(alignment: .leading, spacing: metrics.cardHeaderSpacing * 2) {
            if let eyebrow {
                Text(eyebrow)
                    .somaFont(theme.typography.eyebrow)
                    .textCase(.uppercase)
                    .foregroundStyle(theme.colors.inkSecondary.color)
            }
            SomaCard {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        if index > 0 {
                            Rectangle()
                                .fill(theme.colors.inkPrimary.color.opacity(metrics.hairlineOpacity))
                                .frame(height: 1)
                        }
                        link(row)
                    }
                    if let footnote {
                        Text(footnote)
                            .somaFont(theme.typography.caption)
                            .foregroundStyle(theme.colors.inkSecondary.color)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, metrics.cardHeaderSpacing * 2)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func link(_ row: MetricRowItem) -> some View {
        if let route = row.route {
            NavigationLink(value: route) { MetricRow(row: row, opens: true) }
                .buttonStyle(.plain)
        } else if let action = row.action {
            Button(action: action) { MetricRow(row: row, opens: true) }
                .buttonStyle(.plain)
        } else {
            MetricRow(row: row, opens: false)
        }
    }
}

private struct MetricRow: View {
    let row: MetricRowItem
    let opens: Bool

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let type = theme.typography
        let colors = theme.colors

        HStack(alignment: .firstTextBaseline, spacing: theme.metrics.metricColumnSpacing) {
            VStack(alignment: .leading, spacing: 3) {
                Text(row.title)
                    .somaFont(type.body)
                    .foregroundStyle(colors.inkPrimary.color)
                if let detail = row.detail {
                    Text(detail)
                        .somaFont(type.caption)
                        .foregroundStyle(colors.inkSecondary.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if row.value != nil || !opens {
                Text(row.value ?? "-")
                    .somaFont(type.rowValue)
                    .foregroundStyle(colors.inkSecondary.color)
            }
            if opens {
                Image(systemName: "chevron.right")
                    .somaFont(type.caption)
                    .foregroundStyle(colors.inkSecondary.color)
            }
        }
        .padding(.vertical, theme.metrics.browseRowVerticalPadding)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Words

/// A card that says what a reading means: an eyebrow, then a first sentence
/// in the primary ink and the rest in the secondary.
struct MetricTextCard: View {
    let eyebrow: String
    let lead: String
    var rest: String?

    @Environment(\.somaTheme) private var theme

    var body: some View {
        SomaCard {
            VStack(alignment: .leading, spacing: theme.metrics.cardHeaderSpacing * 2) {
                Text(eyebrow)
                    .somaFont(theme.typography.eyebrow)
                    .textCase(.uppercase)
                    .foregroundStyle(theme.colors.inkSecondary.color)
                MetricLeadText(lead: lead, rest: rest)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A first sentence in the primary ink and the rest in the secondary, as one
/// run of text that wraps as a paragraph.
struct MetricLeadText: View {
    let lead: String
    var rest: String?

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let first = Text(lead).foregroundStyle(theme.colors.inkPrimary.color)
        let second = Text(rest.map { " " + $0 } ?? "").foregroundStyle(theme.colors.inkSecondary.color)
        Text("\(first)\(second)")
            .somaFont(theme.typography.body)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Daily bars

/// One thin bar a day, the last one in full and the others softened, over
/// the usual band in faint green and under a dashed limit when there is one.
/// A day with no value leaves a gap on the floor.
struct MetricDailyBars: View {
    let values: [Double?]
    var usual: ClosedRange<Double>?
    var limit: Double?
    /// The value axis starts here rather than at zero, for levels such as
    /// decibels that never reach it.
    var floor: Double = 0
    var aspect: SomaAspect = .activity
    var leadingLabel: String?
    var middleLabel: String?
    var trailingLabel: String? = "Today"

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let hue = theme.aspects[aspect].identity.color
        let values = values
        let usual = usual
        let limit = limit
        let floor = floor
        let known = values.compactMap { $0 }
        let scale = SomaPlotScale(
            values: known.isEmpty ? [] : known + [floor],
            including: [usual?.lowerBound, usual?.upperBound, limit].compactMap { $0 },
            fromZero: floor == 0
        )

        SomaPlot(scale: scale, xLabels: [leadingLabel, middleLabel, trailingLabel].compactMap { $0 },
                 height: theme.metrics.metricPlotHeight) { context, space, pen in
            if let usual {
                pen.band(context, top: space.y(usual.upperBound), bottom: space.y(usual.lowerBound), in: space.plot)
            }
            let pitch = space.pitch(values.count)
            let base = space.y(max(floor, space.domain.lowerBound))
            for (index, value) in values.enumerated() {
                guard let value, value > floor else { continue }
                let isLast = index == values.count - 1
                pen.bar(context, x: space.slot(index, of: values.count), top: space.y(value), floor: base, pitch: pitch,
                        color: hue.opacity(isLast ? 1 : pen.contextOpacity))
            }
            if let limit {
                pen.rule(context, y: space.y(limit), in: space.plot)
            }
        }
        .accessibilityHidden(true)
    }
}

/// The dates under a chart: first, middle and last.
struct MetricAxis: View {
    var leading: String?
    var middle: String?
    var trailing: String?

    var body: some View {
        SomaAxisLabels([leading, middle, trailing].compactMap { $0 })
    }
}

// MARK: - A line in a band

/// Values as one line inside a band that may move day by day, in faint green,
/// with a ring on the last value. Both share one scale.
struct MetricBandChart: View {
    let values: [Double]
    var lower: [Double]?
    var upper: [Double]?
    var aspect: SomaAspect = .heart
    /// Dates under the plot, first to last.
    var axis: [String] = []

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let hue = theme.aspects[aspect].identity.color
        let values = values
        let lower = lower
        let upper = upper

        SomaPlot(scale: SomaPlotScale(values: values, including: (lower ?? []) + (upper ?? [])),
                 xLabels: axis, height: theme.metrics.metricPlotHeight) { context, space, pen in
            if let lower, let upper, lower.count == upper.count, lower.count >= 2 {
                pen.band(context,
                         upper: upper.enumerated().map { CGPoint(x: space.x($0.offset, of: upper.count), y: space.y($0.element)) },
                         lower: lower.enumerated().map { CGPoint(x: space.x($0.offset, of: lower.count), y: space.y($0.element)) })
            }
            guard values.count >= 2 else { return }
            let points = values.enumerated().map { CGPoint(x: space.x($0.offset, of: values.count), y: space.y($0.element)) }
            pen.line(context, points, color: hue)
            if values.count <= 14 {
                for point in points.dropLast() { pen.dot(context, at: point, color: hue) }
            }
            if let last = points.last { pen.ring(context, at: last, color: hue) }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Split

/// One part of a whole: its name, a line under it, the value, its share, and
/// how it is shaded in the bar.
struct MetricSplitPart: Identifiable {
    var id: String { title }
    var title: String
    var detail: String?
    var value: String?
    var share: Double
    var tone: MetricTone
}

/// A whole as one bar cut into its parts, then a legend row for each.
struct MetricSplitCard: View {
    let eyebrow: String
    let parts: [MetricSplitPart]
    var aspect: SomaAspect = .activity
    var note: String?

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics
        let type = theme.typography
        let colors = theme.colors
        let total = parts.reduce(0) { $0 + $1.share }

        SomaCard {
            VStack(alignment: .leading, spacing: metrics.cardHeaderSpacing * 2) {
                Text(eyebrow)
                    .somaFont(type.eyebrow)
                    .textCase(.uppercase)
                    .foregroundStyle(colors.inkSecondary.color)

                GeometryReader { proxy in
                    HStack(spacing: 2) {
                        if total > 0 {
                            ForEach(parts.filter { $0.share > 0 }) { part in
                                Capsule()
                                    .fill(part.tone.color(theme, aspect: aspect))
                                    .frame(width: max(metrics.metricSplitHeight / 2, (proxy.size.width - 2 * CGFloat(parts.count)) * part.share / total))
                            }
                        } else {
                            Capsule().fill(colors.surfaceRecessed.color)
                        }
                    }
                }
                .frame(height: metrics.metricSplitHeight)

                VStack(spacing: metrics.bodyRowSpacing) {
                    ForEach(parts) { part in
                        HStack(alignment: .firstTextBaseline, spacing: metrics.metricColumnSpacing) {
                            Circle()
                                .fill(part.tone.color(theme, aspect: aspect))
                                .frame(width: metrics.identityDotDiameter, height: metrics.identityDotDiameter)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(part.title)
                                    .somaFont(type.body)
                                    .foregroundStyle(colors.inkPrimary.color)
                                if let detail = part.detail {
                                    Text(detail)
                                        .somaFont(type.caption)
                                        .foregroundStyle(colors.inkSecondary.color)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Text(part.value ?? "-")
                                .somaFont(type.rowValue)
                                .foregroundStyle(colors.inkPrimary.color)
                            Text(total > 0 ? "\(Int((part.share / total * 100).rounded()))%" : "-")
                                .somaFont(type.rowValue)
                                .foregroundStyle(colors.inkSecondary.color)
                                .frame(width: metrics.metricColumnWidth * 0.7, alignment: .trailing)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }

                if let note {
                    Text(note)
                        .somaFont(type.caption)
                        .foregroundStyle(colors.inkSecondary.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

// MARK: - Strip of days

/// One cell a day, oldest first, each shaded by what the day was.
struct MetricDayStrip: View {
    let tones: [MetricTone]
    var aspect: SomaAspect = .heart

    @Environment(\.somaTheme) private var theme

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(tones.enumerated()), id: \.offset) { _, tone in
                RoundedRectangle(cornerRadius: theme.metrics.chartBarCornerRadius, style: .continuous)
                    .fill(tone.color(theme, aspect: aspect))
            }
        }
        .frame(height: theme.metrics.metricStripHeight)
        .accessibilityHidden(true)
    }
}

// MARK: - Ring

/// A share of a goal as a ring, the share written in the middle.
struct MetricRing: View {
    /// 0 upward; past 1 the ring is simply full.
    let fraction: Double?
    var aspect: SomaAspect = .activity

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics
        let hue = theme.aspects[aspect].identity.color

        ZStack {
            Circle()
                .stroke(theme.colors.surfaceRecessed.color, lineWidth: metrics.metricRingWidth)
            if let fraction, fraction > 0 {
                Circle()
                    .trim(from: 0, to: min(1, fraction))
                    .stroke(hue, style: StrokeStyle(lineWidth: metrics.metricRingWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            VStack(spacing: 2) {
                Text(fraction.map { "\(Int(($0 * 100).rounded()))%" } ?? "-")
                    .somaFont(theme.typography.metric)
                    .foregroundStyle(theme.colors.inkPrimary.color)
                Text("of goal")
                    .somaFont(theme.typography.caption)
                    .foregroundStyle(theme.colors.inkSecondary.color)
            }
        }
        .frame(width: metrics.metricRingDiameter, height: metrics.metricRingDiameter)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Dates

/// The words the metric pages write dates and numbers with.
struct MetricWords {
    var calendar: Calendar = .current
    var locale: Locale = .current

    /// Saturday 12 September.
    func day(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(locale: locale, calendar: calendar).weekday(.wide).day().month(.wide))
    }

    /// Sep 3.
    func short(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(locale: locale, calendar: calendar).month(.abbreviated).day())
    }

    /// 17:02, in the person's own clock.
    func time(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(locale: locale, calendar: calendar).hour().minute())
    }

    /// Today, Yesterday, or the day's name and date.
    func relativeDay(_ date: Date, now: Date) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        return day(date)
    }

    /// Metres as kilometres to one decimal: 10.2.
    func km(_ metres: Double) -> String {
        (metres / 1000).formatted(.number.precision(.fractionLength(1)).locale(locale))
    }

    func whole(_ value: Double) -> String {
        Int(value.rounded()).formatted(.number.locale(locale))
    }

    /// The axis labels for `days` days ending today: the first, the middle
    /// and today.
    func axis(days: Int, now: Date) -> (String?, String?, String?) {
        let today = calendar.startOfDay(for: now)
        let first = calendar.date(byAdding: .day, value: -(days - 1), to: today)
        let middle = calendar.date(byAdding: .day, value: -(days / 2), to: today)
        return (first.map(short), middle.map(short), "Today")
    }
}

// MARK: - The stage's head

extension SomaMetricLead {
    /// A metric page's head over its days (oldest first, today last): the
    /// number given, and what the last day means against the usual drawn
    /// from the same days, so the head and the chart under it agree.
    static func days(
        _ values: [Double?],
        caption: String,
        value: String?,
        unit: String?,
        higherIsBetter: Bool?,
        format: (Double) -> String,
        detail: String? = nil
    ) -> SomaMetricLead {
        let usual = AspectPageMath.usual(values)
        let last = values.last ?? nil
        let note = AspectPageMath.slotNote(last, usual: usual, higherIsBetter: higherIsBetter, format: format)
        return SomaMetricLead(
            caption: caption,
            value: value,
            unit: unit,
            meaning: value == nil ? "No reading yet" : (note?.text ?? (usual == nil ? "Your usual needs a few more days" : nil)),
            detail: detail,
            tone: note?.tone ?? .neutral
        )
    }
}
