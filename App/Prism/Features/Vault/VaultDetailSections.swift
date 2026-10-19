//
//  VaultDetailSections.swift
//  Prism
//
//  The parts of a data type page: the hero, the sibling chips, the chart,
//  the trends table, the projections and the options.
//

import SwiftUI
import Charts
import SomaUI
import HealthExportCore

// MARK: - Hero

/// The latest value large, its status as a dot and a word, the band it is
/// read against, and the cue.
struct VaultHero: View {
    let value: String?
    let unit: String?
    let standing: MetricDetailMath.Standing?
    let legend: String?
    let cue: String?
    let tone: Insight.Tone

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let colors = theme.colors
        let metrics = theme.metrics
        let status = standing?.reading ?? .none

        VStack(alignment: .leading, spacing: metrics.scoreLabelSpacing) {
            HStack(alignment: .firstTextBaseline, spacing: metrics.trendMarkSpacing) {
                Text(value ?? "-")
                    .somaFont(theme.typography.display)
                    .foregroundStyle(colors.inkPrimary.color)
                if let unit, value != nil {
                    Text(unit)
                        .somaFont(theme.typography.callout)
                        .foregroundStyle(colors.inkSecondary.color)
                }
            }
            if let word = status.word, value != nil {
                HStack(spacing: 6) {
                    Circle()
                        .fill(status.color(colors))
                        .frame(width: metrics.chartPointDiameter + 2, height: metrics.chartPointDiameter + 2)
                    Text(word)
                        .foregroundStyle(status.color(colors))
                    if let legend {
                        Text(verbatim: "·").foregroundStyle(colors.inkSecondary.color)
                        Text(legend).foregroundStyle(colors.inkSecondary.color)
                    }
                }
                .somaFont(theme.typography.callout)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
            if let cue, value != nil {
                Text(cue)
                    .somaFont(theme.typography.callout)
                    .foregroundStyle(tone.cueTone.color(colors))
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Siblings

/// The other types of the category that hold data, as chips; a tap switches
/// the page in place.
struct VaultSiblingChips: View {
    let types: [VaultSubject]
    let selected: VaultSubject
    let pick: (VaultSubject) -> Void

    @Environment(\.somaTheme) private var theme

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: theme.metrics.cardSpacing) {
                ForEach(types) { type in
                    SomaChoiceChip(type.title, isOn: type == selected, style: .outline) { pick(type) }
                }
            }
        }
        .scrollClipDisabled()
    }
}

// MARK: - Chart

/// The span's chart: the band behind, a line with hollow dots for a reading,
/// dots and a moving average for a sparse one, thin bars for a total, pills
/// for blood pressure. Drag to read one bucket; the chevrons page through
/// spans.
struct VaultDetailChart: View {
    let buckets: [MetricDetailMath.Bucket]
    let hue: SomaHealthHue
    let period: VaultPeriod
    let chart: MetricProfile.Chart
    let domain: ClosedRange<Double>
    let format: (Double) -> String
    let canGoBack: Bool
    let canGoForward: Bool
    let page: (Int) -> Void

    @Environment(\.somaTheme) private var theme
    @State private var selection: Date?

    private var isEmpty: Bool { buckets.allSatisfy { $0.value == nil } }

    private var selected: MetricDetailMath.Bucket? {
        guard let selection else { return nil }
        return buckets.first { $0.interval.contains(selection) && $0.value != nil }
    }

    var body: some View {
        let colors = theme.colors

        VStack(alignment: .leading, spacing: theme.metrics.cardSpacing) {
            HStack {
                pager("chevron.left", label: "Earlier", enabled: canGoBack) { page(1) }
                Spacer(minLength: 0)
                if let selected, let value = selected.value {
                    HStack(spacing: 6) {
                        Text(selected.secondary.map { "\(format(value))/\(format($0))" } ?? format(value))
                            .foregroundStyle(colors.inkPrimary.color)
                        Text(label(for: selected.interval.start, long: true))
                            .foregroundStyle(colors.inkSecondary.color)
                    }
                    .somaFont(theme.typography.callout)
                }
                Spacer(minLength: 0)
                pager("chevron.right", label: "Later", enabled: canGoForward) { page(-1) }
            }
            plot
        }
    }

    private func pager(_ symbol: String, label: LocalizedStringResource, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .foregroundStyle(enabled ? hue.color : theme.colors.inkSecondary.color.opacity(0.4))
                .frame(width: theme.metrics.minimumTapTarget, height: theme.metrics.minimumTapTarget)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(Text(label))
    }

    private var plot: some View {
        let hairline = theme.colors.inkPrimary.color.opacity(theme.metrics.chartGridOpacity)
        let ink = theme.colors.inkSecondary.color
        let smoothed = MetricDetailMath.smoothed(buckets.map(\.value))

        return Chart {
            ForEach(buckets) { bucket in
                if let band = bucket.band {
                    AreaMark(
                        x: .value("Time", bucket.interval.start, unit: period.bucket),
                        yStart: .value("Low", band.lowerBound),
                        yEnd: .value("High", band.upperBound),
                        series: .value("Series", "band")
                    )
                    .foregroundStyle(theme.colors.statusNormal.color.opacity(theme.metrics.chartBandOpacity))
                    .interpolationMethod(.monotone)
                }
            }
            ForEach(Array(buckets.enumerated()), id: \.element.id) { index, bucket in
                if let value = bucket.value {
                    mark(bucket, value: value, trend: smoothed[index])
                }
            }
            if let selected {
                RuleMark(x: .value("Selected", selected.interval.start, unit: period.bucket))
                    .foregroundStyle(ink.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1))
            }
        }
        .chartXScale(domain: (buckets.first?.interval.start ?? .now)...(buckets.last?.interval.end ?? .now))
        .chartYScale(domain: domain)
        .chartXSelection(value: $selection)
        .chartXAxis {
            AxisMarks(values: .stride(by: xStride.component, count: xStride.count)) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(label(for: date, long: false))
                            .somaFont(theme.typography.captionValue)
                            .foregroundStyle(ink)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(hairline)
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text(format(number))
                            .somaFont(theme.typography.captionValue)
                            .foregroundStyle(ink)
                    }
                }
            }
        }
        .overlay {
            if isEmpty {
                Text("No data")
                    .somaFont(theme.typography.caption)
                    .foregroundStyle(ink)
            }
        }
        .frame(height: theme.metrics.chartPlotHeight * 1.8)
    }

    @ChartContentBuilder
    private func mark(_ bucket: MetricDetailMath.Bucket, value: Double, trend: Double?) -> some ChartContent {
        let x = PlottableValue.value("Time", bucket.interval.start, unit: period.bucket)
        let color = hue.color
        let metrics = theme.metrics
        switch chart {
        case .bars:
            BarMark(x: x, y: .value("Value", value), width: .fixed(metrics.chartThinBarWidth))
                .foregroundStyle(color)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: metrics.chartThinBarRadius, topTrailingRadius: metrics.chartThinBarRadius))
        case .bloodPressure:
            RuleMark(x: x, yStart: .value("Diastolic", bucket.secondary ?? value), yEnd: .value("Systolic", value))
                .foregroundStyle(color)
                .lineStyle(StrokeStyle(lineWidth: metrics.chartThinBarWidth, lineCap: .round))
        case .points:
            if let trend {
                LineMark(x: x, y: .value("Trend", trend), series: .value("Series", "trend"))
                    .foregroundStyle(color.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: metrics.chartStroke, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.catmullRom)
            }
            PointMark(x: x, y: .value("Value", value))
                .foregroundStyle(color)
                .symbolSize(metrics.chartPointDiameter * metrics.chartPointDiameter * 1.4)
        case .line:
            LineMark(x: x, y: .value("Value", value), series: .value("Series", "value"))
                .foregroundStyle(color)
                .lineStyle(StrokeStyle(lineWidth: metrics.chartStroke, lineCap: .round, lineJoin: .round))
            PointMark(x: x, y: .value("Value", value))
                .symbol {
                    Circle()
                        .strokeBorder(color, lineWidth: 1.2)
                        .background(Circle().fill(theme.colors.surface.color))
                        .frame(width: metrics.chartPointDiameter, height: metrics.chartPointDiameter)
                }
        }
    }

    private var xStride: (component: Calendar.Component, count: Int) {
        switch period {
        case .day: (.hour, 6)
        case .week: (.day, 1)
        case .month: (.day, 7)
        case .threeMonths: (.month, 1)
        case .sixMonths: (.month, 1)
        case .year: (.month, 3)
        }
    }

    private func label(for date: Date, long: Bool) -> String {
        if long {
            return switch period {
            case .day: date.formatted(.dateTime.hour().minute())
            case .week, .month: date.formatted(.dateTime.month(.abbreviated).day())
            case .threeMonths, .sixMonths: "Week of " + date.formatted(.dateTime.month(.abbreviated).day())
            case .year: date.formatted(.dateTime.month(.abbreviated).year())
            }
        }
        return switch period {
        case .day: date.formatted(.dateTime.hour())
        case .week: date.formatted(.dateTime.weekday(.abbreviated))
        case .month: date.formatted(.dateTime.day())
        case .threeMonths, .sixMonths, .year: date.formatted(.dateTime.month(.abbreviated))
        }
    }
}

// MARK: - Trends analysis

/// The change over 3, 7, 14, 30 and 90 days: an arrow, the signed change,
/// the verdict and an eight point line, then when the last reading was.
struct VaultTrendsTable: View {
    let rows: [MetricDetailMath.TrendRow]
    let unit: String?
    let last: Date?
    let hue: SomaHealthHue
    let format: (Double) -> String

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let colors = theme.colors
        let metrics = theme.metrics

        VStack(alignment: .leading, spacing: metrics.cardSpacing) {
            Text("Trends")
                .somaFont(theme.typography.headline)
                .foregroundStyle(colors.inkPrimary.color)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                ForEach(rows) { row in
                    HStack(spacing: metrics.cardSpacing) {
                        Text("\(row.days) days")
                            .foregroundStyle(colors.inkSecondary.color)
                            .frame(width: 64, alignment: .leading)
                        Image(systemName: arrow(row.direction))
                            .foregroundStyle(color(row.valence))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(change(row))
                                .somaFont(theme.typography.captionValue)
                                .foregroundStyle(colors.inkPrimary.color)
                            Text(row.verdict)
                                .foregroundStyle(color(row.valence))
                        }
                        Spacer(minLength: 0)
                        SomaSparkline(row.spark, tint: hue.color)
                            .frame(width: metrics.chartSparkHeight * 1.8, height: metrics.chartSparkHeight * 0.6)
                    }
                    .somaFont(theme.typography.caption)
                    .padding(.vertical, metrics.cardPadding * 0.6)
                    .padding(.horizontal, metrics.cardPadding)
                    .accessibilityElement(children: .combine)
                    if row.id != rows.last?.id {
                        Rectangle()
                            .fill(colors.inkPrimary.color.opacity(metrics.hairlineOpacity))
                            .frame(height: 0.5)
                            .padding(.leading, metrics.cardPadding)
                    }
                }
            }
            .background(colors.surface.color, in: .rect(cornerRadius: metrics.cardCornerRadius, style: .continuous))
            if let last {
                Text("Last data point " + last.formatted(.dateTime.month(.abbreviated).day()))
                    .somaFont(theme.typography.caption)
                    .foregroundStyle(colors.inkSecondary.color)
            }
        }
    }

    private func change(_ row: MetricDetailMath.TrendRow) -> String {
        let sign = row.change > 0 ? "+" : row.change < 0 ? "-" : ""
        let unit = unit.map { " \($0)" } ?? ""
        return sign + format(abs(row.change)) + unit
    }

    private func arrow(_ direction: MetricDetailMath.Direction) -> String {
        switch direction {
        case .rising: "arrow.up.right"
        case .falling: "arrow.down.right"
        case .flat: "arrow.right"
        }
    }

    private func color(_ valence: MetricDetailMath.Valence) -> Color {
        switch valence {
        case .good: theme.colors.statusNormal.color
        case .bad: theme.colors.statusOut.color
        case .neutral: hue.color
        }
    }
}

// MARK: - Projections

/// Where the line through the last months lands in 7, 30 and 90 days, give
/// or take its margin.
struct VaultProjections: View {
    let rows: [MetricDetailMath.Projection]
    let unit: String?
    let format: (Double) -> String

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let colors = theme.colors
        let metrics = theme.metrics
        let unit = unit.map { " \($0)" } ?? ""

        VStack(alignment: .leading, spacing: metrics.cardSpacing) {
            Text("Projected")
                .somaFont(theme.typography.headline)
                .foregroundStyle(colors.inkPrimary.color)
                .accessibilityAddTraits(.isHeader)
            HStack(alignment: .top, spacing: 0) {
                ForEach(rows) { row in
                    VStack(spacing: metrics.scoreLabelSpacing) {
                        Text("In \(row.days) days")
                            .somaFont(theme.typography.eyebrow)
                            .textCase(.uppercase)
                            .foregroundStyle(colors.inkSecondary.color)
                        Text(format(row.value) + unit)
                            .somaFont(theme.typography.metricCompact)
                            .foregroundStyle(colors.inkPrimary.color)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text("± " + format(row.margin))
                            .somaFont(theme.typography.caption)
                            .foregroundStyle(colors.inkSecondary.color)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.vertical, metrics.cardPadding)
            .background(colors.surface.color, in: .rect(cornerRadius: metrics.cardCornerRadius, style: .continuous))
        }
    }
}

// MARK: - Options

/// Every record, the unit, and the sources behind the shown span with their
/// quality marks.
struct VaultOptions: View {
    /// Nil for a score, which has no records of its own.
    let type: BodyDataType?
    let unit: String?
    let origins: [VaultMasterReader.Origin]

    @Environment(\.somaTheme) private var theme

    private enum Row: Hashable, Identifiable {
        case allData, unit
        var id: Self { self }
    }

    private var rows: [Row] { type == nil ? [.unit] : [.allData, .unit] }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.metrics.cardSpacing) {
            SomaBrowseGroup(rows, hasGlyphs: false) { row in
                switch row {
                case .allData:
                    if let type {
                        NavigationLink(value: VaultRoute.allData(type)) {
                            SomaBrowseRow(title: "Show All Data").contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                case .unit:
                    SomaBrowseRow(title: "Unit", detail: unit ?? "-", opensSomething: false)
                }
            }
            if !origins.isEmpty {
                Text("Sources")
                    .somaFont(theme.typography.headline)
                    .foregroundStyle(theme.colors.inkPrimary.color)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, theme.metrics.cardSpacing)
                SomaBrowseGroup(origins, hasGlyphs: false) { origin in
                    SomaBrowseRow(
                        title: origin.name,
                        detail: [origin.device == origin.name ? nil : origin.device, "\(origin.count)"].compactMap { $0 }.joined(separator: " · "),
                        opensSomething: false
                    ) {
                        SomaQualityMarks(filled: origin.quality.level.marks, of: ReadingQuality.scale)
                            .accessibilityLabel(Text(origin.quality.level.title))
                    }
                }
            }
        }
    }
}
