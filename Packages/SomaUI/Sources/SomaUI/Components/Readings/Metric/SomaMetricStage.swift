//
//  SomaMetricStage.swift
//  SomaUI
//

import SwiftUI

/// What a stage's head says when no finger is on the chart: when the number
/// is from, the number and its unit, and one line on what it means.
public struct SomaMetricLead: Equatable, Sendable {
    /// When the number is from: "Today", "Last night".
    public var caption: String?
    /// Nil for a dash.
    public var value: String?
    public var unit: String?
    /// One plain line led by a dot in `tone`: "Above your usual".
    public var meaning: String?
    /// What follows it in the secondary ink: "1 below last week".
    public var detail: String?
    public var tone: SomaCueTone

    public init(
        caption: String?,
        value: String?,
        unit: String?,
        meaning: String?,
        detail: String? = nil,
        tone: SomaCueTone = .neutral
    ) {
        self.caption = caption
        self.value = value
        self.unit = unit
        self.meaning = meaning
        self.detail = detail
        self.tone = tone
    }
}

/// The ring beside a stage's number, for a score or an aspect's reading.
public struct SomaStageDial: Equatable, Sendable {
    public enum Scale: Equatable, Sendable {
        /// A score: the ring fills to the value out of `top`.
        case fill(top: Double)
        /// A reading without a scale: a dot on the ring where it sits
        /// against the usual.
        case marker
    }

    public var aspect: SomaAspect
    public var scale: Scale
    /// The lead's value, in the chart's units.
    public var value: Double?
    /// The person's usual, in the chart's units.
    public var usual: ClosedRange<Double>?

    public init(aspect: SomaAspect, scale: Scale, value: Double?, usual: ClosedRange<Double>?) {
        self.aspect = aspect
        self.scale = scale
        self.value = value
        self.usual = usual
    }

    /// The ring for `value`, and the usual on it, as shares of the turn.
    public func ring(for value: Double?) -> (dial: SomaScoreHero.Dial, usual: ClosedRange<Double>?) {
        switch scale {
        case .fill(let top):
            let top = max(top, .ulpOfOne)
            return (.fill(value.map { $0 / top }), usual.map { ($0.lowerBound / top)...($0.upperBound / top) })
        case .marker:
            let shares = SomaScoreDialMath.marker(value, usual: usual)
            return (.marker(shares.value), shares.usual)
        }
    }
}

/// A metric's head and its chart as one piece, the centre of a metric or a
/// score page: the number large with what it means (and a score's ring),
/// then one tall chart across the page carrying the usual band, the average,
/// the latest value, the highest and the lowest, then one quiet line and the
/// span the chart covers.
///
/// Reading the chart reads the head: while a finger rests on a slot, the
/// head names that slot, its number rolls to the slot's value, its line says
/// what the value means and the ring glides to it. Lifting the finger brings
/// the lead back the same way. Under Reduce Motion the number changes in
/// place and the ring lands.
///
/// It replaces the old run of hero, readout, chart and a strip of facts,
/// where the same numbers were said two or three times.
public struct SomaMetricStage<Period: Hashable>: View {
    private let lead: SomaMetricLead
    private let dial: SomaStageDial?
    private let buckets: [SomaChartBucket]
    private let style: SomaMetricChartStyle
    private let hue: SomaHealthHue
    private let domain: ClosedRange<Double>
    private let usualLabel: String?
    private let average: SomaChartAverage?
    private let summary: String
    private let note: String?
    private let periods: [SomaSegment<Period>]
    @Binding private var period: Period

    @Environment(\.somaTheme) private var theme
    @State private var selected: Int?

    /// - Parameters:
    ///   - lead: what the head says with no finger on the chart.
    ///   - dial: a ring beside the number, for a score or an aspect.
    ///   - usualLabel: the band as the chart's key names it.
    ///   - average: the span's average, as a dotted line and in the key.
    ///   - summary: what VoiceOver reads the chart as.
    ///   - note: one quiet line under the chart: how this week moved, how
    ///     many days sat in the usual.
    ///   - periods: the spans offered; the control shows from two.
    public init(
        lead: SomaMetricLead,
        dial: SomaStageDial? = nil,
        buckets: [SomaChartBucket],
        style: SomaMetricChartStyle,
        hue: SomaHealthHue,
        domain: ClosedRange<Double>,
        usualLabel: String? = nil,
        average: SomaChartAverage? = nil,
        summary: String,
        note: String? = nil,
        periods: [SomaSegment<Period>],
        period: Binding<Period>
    ) {
        self.lead = lead
        self.dial = dial
        self.buckets = buckets
        self.style = style
        self.hue = hue
        self.domain = domain
        self.usualLabel = usualLabel
        self.average = average
        self.summary = summary
        self.note = note
        self.periods = periods
        self._period = period
    }

    /// What the head says: the lead, or the slot a finger rests on.
    public static func shown(_ lead: SomaMetricLead, picked: SomaChartBucket?) -> SomaMetricLead {
        guard let picked else { return lead }
        return SomaMetricLead(
            caption: picked.readout,
            value: picked.valueText,
            unit: lead.unit,
            meaning: picked.note,
            detail: nil,
            tone: picked.tone
        )
    }

    private var picked: SomaChartBucket? {
        selected.flatMap { index in buckets.first { $0.id == index } }
    }

    public var body: some View {
        let metrics = theme.metrics
        let head = Self.shown(lead, picked: picked)

        VStack(alignment: .leading, spacing: metrics.metricStageSpacing) {
            HStack(alignment: .center, spacing: metrics.cardSpacing) {
                SomaHeroText(caption: head.caption, value: head.value, unit: head.unit,
                             meaning: head.meaning, detail: head.detail, tone: head.tone)
                    .accessibilityElement(children: .combine)
                if let dial {
                    let ring = dial.ring(for: picked?.value ?? dial.value)
                    SomaScoreDial(aspect: dial.aspect, dial: ring.dial, usual: ring.usual)
                        .frame(width: metrics.scoreHeroDial, height: metrics.scoreHeroDial)
                }
            }
            .padding(.top, metrics.scoreHeroTopPadding)

            SomaMetricChart(
                buckets: buckets,
                style: style,
                hue: hue,
                domain: domain,
                usualLabel: usualLabel,
                average: average,
                summary: summary,
                plotHeight: metrics.metricStageHeight,
                selection: $selected
            )

            if note != nil || periods.count > 1 {
                VStack(alignment: .leading, spacing: metrics.cardSpacing) {
                    if let note {
                        Text(note)
                            .somaFont(theme.typography.caption)
                            .foregroundStyle(theme.colors.inkSecondary.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if periods.count > 1 {
                        SomaSegmentedControl(segments: periods, selection: $period)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .onChange(of: period) { selected = nil }
    }
}

public extension SomaMetricStage where Period == Int {
    /// A stage over one span, with no control to change it.
    init(
        lead: SomaMetricLead,
        dial: SomaStageDial? = nil,
        buckets: [SomaChartBucket],
        style: SomaMetricChartStyle,
        hue: SomaHealthHue,
        domain: ClosedRange<Double>,
        usualLabel: String? = nil,
        average: SomaChartAverage? = nil,
        summary: String,
        note: String? = nil
    ) {
        self.init(lead: lead, dial: dial, buckets: buckets, style: style, hue: hue, domain: domain,
                  usualLabel: usualLabel, average: average, summary: summary, note: note,
                  periods: [], period: .constant(0))
    }
}

#Preview("Metric stage") {
    @Previewable @State var span = "month"
    let days: [SomaChartBucket] = (0..<30).map { index in
        let value: Double? = index % 11 == 7 ? nil : 57 + Double((index * 7) % 9) - 4
        let note = value.map { $0 > 60 ? "Above your usual" : $0 < 54 ? "Below your usual" : "Within your usual" }
        return SomaChartBucket(id: index, value: value, band: 54...60,
                               axisLabel: index % 7 == 0 ? "\(index + 1)" : nil,
                               readout: "Day \(index + 1)", valueText: value.map { "\(Int($0))" },
                               note: note, tone: note == "Within your usual" ? .good : .watch)
    }
    ZStack {
        SomaPreviewBackdrop()
        ScrollView {
            SomaMetricStage(
                lead: SomaMetricLead(caption: "Today", value: "61", unit: "bpm", meaning: "Above your usual", tone: .watch),
                dial: SomaStageDial(aspect: .heart, scale: .marker, value: 61, usual: 54...60),
                buckets: days, style: .points, hue: .heart, domain: 48...66,
                usualLabel: "Usual 54 to 60", average: SomaChartAverage(value: 57, text: "Average 57"),
                summary: "Resting heart rate, last 30 days",
                note: "This week 59, up 2 · 18 of 27 days in your usual",
                periods: [SomaSegment(id: "week", title: "Week"), SomaSegment(id: "month", title: "Month")],
                period: $span
            )
            .padding()
        }
    }
}
