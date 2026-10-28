//
//  AspectPageParts.swift
//  Prism
//
//  The pieces every score page and aspect page share, so they all read the
//  way a metric's page reads (group 3's rhythm): a head with the number and
//  a calm ring, the days as a chart against the person's usual with a few
//  facts under it, then the page's own cards, then the readings it is built
//  from as quiet rows that open each one.
//

import SwiftUI
import SomaUI
import HealthExportCore

// MARK: - The maths

/// The span a score page's chart shows.
enum AspectSpan: String, CaseIterable, Identifiable, Hashable {
    case week
    case month

    var id: String { rawValue }
    var days: Int { self == .week ? 7 : 30 }
    var title: String { self == .week ? "Week" : "Month" }
}

/// What a page's head, chart and facts say about a run of days, worked out
/// from the values alone so each piece is tested without a Health store.
///
/// The values are one per day, oldest first, the last one today (which may
/// still be filling in). A missing day is nil and never counts as zero.
enum AspectPageMath {
    /// The person's usual: the middle half of the finished days (today left
    /// out), once at least five of them hold a value.
    static func usual(_ values: [Double?]) -> ClosedRange<Double>? {
        let finished = values.dropLast().compactMap { $0 }.sorted()
        guard finished.count >= 5 else { return nil }
        let low = quantile(finished, 0.25)
        let high = quantile(finished, 0.75)
        return low...max(low, high)
    }

    /// The latest value and how many days back it is (0 for today).
    static func latest(_ values: [Double?]) -> (value: Double, back: Int)? {
        guard let index = values.lastIndex(where: { $0 != nil }), let value = values[index] else { return nil }
        return (value, values.count - 1 - index)
    }

    /// The tone of a value against the usual: inside is good, outside is
    /// worth a look unless that way is good news.
    static func tone(_ value: Double?, usual: ClosedRange<Double>?, higherIsBetter: Bool?) -> SomaCueTone {
        guard let value, let usual else { return .neutral }
        if usual.contains(value) { return .good }
        guard let higherIsBetter else { return .watch }
        return (value > usual.upperBound) == higherIsBetter ? .good : .watch
    }

    /// The facts under the chart: the usual, this week against the week
    /// before, and how many of the last thirty days sat in the usual.
    static func facts(_ values: [Double?], usual: ClosedRange<Double>?, higherIsBetter: Bool?,
                      format: (Double) -> String) -> [SomaFact] {
        var facts: [SomaFact] = []
        if let usual {
            facts.append(SomaFact("Your usual", value: "\(format(usual.lowerBound)) to \(format(usual.upperBound))"))
        } else {
            facts.append(SomaFact("Your usual", value: nil, detail: "Needs a few days"))
        }
        if let week = weekFact(values, higherIsBetter: higherIsBetter, format: format) { facts.append(week) }
        if let days = usualDaysFact(values, usual: usual) { facts.append(days) }
        return facts
    }

    /// The last seven days' average, and how it moved against the seven
    /// before: "Up 4", "Down 6", "Steady".
    static func weekFact(_ values: [Double?], higherIsBetter: Bool?, format: (Double) -> String) -> SomaFact? {
        let recent = values.suffix(7).compactMap { $0 }
        guard recent.count >= 3 else { return nil }
        let mean = recent.reduce(0, +) / Double(recent.count)
        let before = values.dropLast(7).suffix(7).compactMap { $0 }
        guard before.count >= 3 else { return SomaFact("This week", value: format(mean), detail: "On average") }
        let past = before.reduce(0, +) / Double(before.count)
        let change = mean - past
        let spread = max(abs(past) * 0.03, 0.5)
        guard abs(change) >= spread else {
            return SomaFact("This week", value: format(mean), detail: "Steady")
        }
        let rising = change > 0
        let tone: SomaCueTone = higherIsBetter.map { $0 == rising ? .good : .watch } ?? .neutral
        return SomaFact("This week", value: format(mean),
                        detail: (rising ? "Up " : "Down ") + format(abs(change)), tone: tone)
    }

    /// How many of the finished days in the last thirty sat in the usual.
    static func usualDaysFact(_ values: [Double?], usual: ClosedRange<Double>?) -> SomaFact? {
        guard let usual else { return nil }
        let finished = values.dropLast().suffix(30).compactMap { $0 }
        guard !finished.isEmpty else { return nil }
        let inside = finished.filter { usual.contains($0) }.count
        return SomaFact("Usual days", value: "\(inside) of \(finished.count)")
    }

    /// The chart's slots for a span: one per day, today last, labelled every
    /// day for a week and every seventh day back from today for a month.
    static func buckets(_ values: [Double?], span: AspectSpan, usual: ClosedRange<Double>?, now: Date,
                        calendar: Calendar, higherIsBetter: Bool? = nil, format: (Double) -> String,
                        bands: [ClosedRange<Double>?]? = nil) -> [SomaChartBucket] {
        let shown = Array(values.suffix(span.days))
        let padded = Array(repeating: Double?.none, count: max(0, span.days - shown.count)) + shown
        let ownBands: [ClosedRange<Double>?]? = bands.map { bands in
            let tail = Array(bands.suffix(span.days))
            return Array(repeating: nil, count: max(0, span.days - tail.count)) + tail
        }
        let today = calendar.startOfDay(for: now)
        var dayStyle = Date.FormatStyle.dateTime.weekday(.narrow)
        dayStyle.timeZone = calendar.timeZone
        var dateStyle = Date.FormatStyle.dateTime.day()
        dateStyle.timeZone = calendar.timeZone
        var readStyle = Date.FormatStyle.dateTime.weekday(.abbreviated).month(.abbreviated).day()
        readStyle.timeZone = calendar.timeZone
        return padded.enumerated().map { index, value in
            let back = padded.count - 1 - index
            let day = calendar.date(byAdding: .day, value: -back, to: today) ?? today
            let label: String? = switch span {
            case .week: day.formatted(dayStyle)
            case .month: back % 7 == 0 ? day.formatted(dateStyle) : nil
            }
            let band = ownBands.map { $0[index] } ?? usual
            let note = slotNote(value, usual: band, higherIsBetter: higherIsBetter, format: format)
            return SomaChartBucket(id: index, value: value, band: band, axisLabel: label,
                                   readout: back == 0 ? "Today" : day.formatted(readStyle),
                                   valueText: value.map(format), note: note?.text, tone: note?.tone ?? .neutral)
        }
    }

    /// What one day's value means against the usual, for the head while a
    /// finger rests on that day.
    /// A value that reads the same as an edge once formatted ("58" against
    /// "56 to 58") counts as within, so the words never contradict the
    /// numbers beside them.
    static func slotNote(_ value: Double?, usual: ClosedRange<Double>?, higherIsBetter: Bool?,
                         format: (Double) -> String = { "\($0)" }) -> (text: String, tone: SomaCueTone)? {
        guard let value, let usual else { return nil }
        let shown = format(value)
        let onEdge = shown == format(usual.lowerBound) || shown == format(usual.upperBound)
        let tone = onEdge ? .good : tone(value, usual: usual, higherIsBetter: higherIsBetter)
        if !onEdge, value > usual.upperBound { return ("Above your usual", tone) }
        if !onEdge, value < usual.lowerBound { return ("Below your usual", tone) }
        return ("Within your usual", tone)
    }

    /// The one quiet line under the chart, folding what the facts said:
    /// "This week 60 bpm, up 2.5 · 15 of 29 days in your usual". The usual
    /// itself and the average are on the chart's key, so they are not
    /// repeated here.
    static func note(_ values: [Double?], usual: ClosedRange<Double>?, higherIsBetter: Bool?, unit: String?,
                     format: (Double) -> String) -> String? {
        var parts: [String] = []
        if let week = weekFact(values, higherIsBetter: higherIsBetter, format: format), let value = week.value {
            var line = "This week " + value + (unit.map { " " + $0 } ?? "")
            if let detail = week.detail, detail != "On average" {
                line += ", " + detail.prefix(1).lowercased() + detail.dropFirst()
            }
            parts.append(line)
        }
        if let days = usualDaysFact(values, usual: usual), let value = days.value {
            parts.append(value + " days in your usual")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The chart key's two entries: "Average 58 bpm", "Usual 56 to 58".
    static func key(_ values: [Double?], span: AspectSpan, usual: ClosedRange<Double>?, unit: String?,
                    format: (Double) -> String) -> (average: SomaChartAverage?, usual: String?) {
        let average = average(values, span: span).map {
            SomaChartAverage(value: $0, text: "Average " + format($0) + (unit.map { " " + $0 } ?? ""))
        }
        return (average, usual.map { "Usual " + format($0.lowerBound) + " to " + format($0.upperBound) })
    }

    /// The plot's foot and top: zero to the scale for a score, or the values
    /// and the usual with a little room for a reading.
    static func domain(_ values: [Double?], usual: ClosedRange<Double>?, scale: Double?) -> ClosedRange<Double> {
        if let scale { return 0...scale }
        let all = values.compactMap { $0 } + (usual.map { [$0.lowerBound, $0.upperBound] } ?? [])
        guard let low = all.min(), let high = all.max() else { return 0...1 }
        let pad = max((high - low) * 0.2, abs(high) * 0.02, 1)
        return max(0, low - pad)...(high + pad)
    }

    /// The span's average for the readout with no day picked.
    static func average(_ values: [Double?], span: AspectSpan) -> Double? {
        let known = values.suffix(span.days).compactMap { $0 }
        guard !known.isEmpty else { return nil }
        return known.reduce(0, +) / Double(known.count)
    }

    private static func quantile(_ sorted: [Double], _ q: Double) -> Double {
        guard sorted.count > 1 else { return sorted.first ?? 0 }
        let position = q * Double(sorted.count - 1)
        let lower = Int(position.rounded(.down))
        let upper = min(sorted.count - 1, lower + 1)
        let share = position - Double(lower)
        return sorted[lower] + (sorted[upper] - sorted[lower]) * share
    }
}

extension SomaAspect {
    /// The category hue a chart of this aspect draws in, the same one its
    /// metrics' pages use.
    var chartHue: SomaHealthHue {
        switch self {
        case .sleep: .sleep
        case .mind: .mind
        case .heart: .heart
        case .activity: .activity
        case .gut: .nutrition
        case .body: .body
        }
    }
}

// MARK: - The stage

/// A score's head and its month as one piece: the lead's number out of 100
/// and its word with the ring, over the chart of its days against the usual.
/// Reading the chart reads the head.
struct ScoreStage: View {
    let aspect: SomaAspect
    let lead: ScorePages.Lead
    /// The score's days, oldest first, the last one today.
    var series: [Double?] = []
    var caption: String = "Today"
    /// Whether a higher score is the good way (false for stress).
    var higherIsBetter = true
    /// Whether the days read as better or worse at all, rather than more or
    /// less (false for the day's load).
    var directional = true

    var body: some View {
        let scale = Double(lead.scale)
        let usual = AspectPageMath.usual(series)
        AspectStage(
            aspect: aspect,
            lead: SomaMetricLead(
                caption: caption,
                value: lead.value.map(String.init),
                unit: "of \(lead.scale)",
                meaning: lead.value == nil ? "Waiting for a first reading" : lead.word,
                detail: lead.change,
                tone: AspectPageMath.tone(lead.value.map(Double.init), usual: usual, higherIsBetter: higherIsBetter)
            ),
            dial: SomaStageDial(aspect: aspect, scale: .fill(top: scale), value: lead.value.map(Double.init), usual: usual),
            values: series,
            // Fitted to the days rather than drawn from zero to the top of
            // the scale, so a month of scores between 89 and 96 reads as a
            // shape and not as thirty equal bars; the ring keeps the scale.
            scale: nil,
            higherIsBetter: directional ? higherIsBetter : nil,
            style: .line
        )
    }
}

/// The head and the days as a chart against the usual, with the span the
/// chart covers under it and one quiet line: the stage every score and
/// aspect page opens on.
struct AspectStage: View {
    let aspect: SomaAspect
    let lead: SomaMetricLead
    var dial: SomaStageDial?
    let values: [Double?]
    var unit: String?
    /// The top of a score's scale; nil fits the plot to the values.
    var scale: Double? = 100
    var higherIsBetter: Bool? = true
    var style: SomaMetricChartStyle = .bars
    var format: @Sendable (Double) -> String = { String(Int($0.rounded())) }
    /// The chart's hue when it is not the aspect's own (sound, on a page
    /// with no aspect).
    var hue: SomaHealthHue?
    /// A band of its own for each day, the same length as `values`, where
    /// the right range moves (a training load's band); nil draws the usual.
    var bands: [ClosedRange<Double>?]?

    @State private var span: AspectSpan = .month

    var body: some View {
        let usual = AspectPageMath.usual(values)
        let buckets = AspectPageMath.buckets(values, span: span, usual: usual, now: Date(), calendar: .current,
                                             higherIsBetter: higherIsBetter, format: format, bands: bands)
        let key = AspectPageMath.key(values, span: span, usual: bands == nil ? usual : nil, unit: unit, format: format)
        let fitted = AspectPageMath.domain(values + (bands ?? []).flatMap { band in [band?.lowerBound, band?.upperBound] },
                                           usual: usual, scale: scale)

        SomaMetricStage(
            lead: lead,
            dial: dial,
            buckets: buckets,
            style: style,
            hue: hue ?? aspect.chartHue,
            // Bars are totals: they stand on zero, or a short day would read
            // as nothing.
            domain: style == .bars ? 0...fitted.upperBound : fitted,
            usualLabel: key.usual,
            average: key.average,
            summary: span == .week ? "Last 7 days" : "Last 30 days",
            note: AspectPageMath.note(values, usual: usual, higherIsBetter: higherIsBetter, unit: unit, format: format),
            periods: AspectSpan.allCases.map { SomaSegment(id: $0, title: LocalizedStringResource(stringLiteral: $0.title)) },
            period: $span
        )
    }
}

// MARK: - The readings

/// The readings a page is built from, as quiet rows on one card under an
/// eyebrow, each opening its own page, and a last row to every measure of
/// the aspect's category.
struct AspectReadings: View {
    let aspect: SomaAspect
    let identifiers: [String]
    /// Where "All readings" goes: the aspect's category of measures.
    var category: PulseRoute? = nil

    @Environment(HealthDashboard.self) private var health
    @Environment(\.somaTheme) private var theme
    @State private var summaries: [BodyDataType: VaultWeekSummary] = [:]

    private var types: [BodyDataType] {
        identifiers.compactMap(HealthMetricCatalog.metric(for:)).map(BodyDataType.init)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.metrics.cardSpacing) {
            Text("Readings")
                .somaFont(theme.typography.eyebrow)
                .foregroundStyle(theme.colors.inkSecondary.color)
                .accessibilityAddTraits(.isHeader)
            SomaBrowseGroup(rows, hasGlyphs: false) { row in
                switch row.target {
                case .type(let type):
                    NavigationLink(value: VaultRoute.dataType(type)) {
                        reading(type)
                    }
                    .buttonStyle(.plain)
                case .category(let route):
                    NavigationLink(value: route) {
                        SomaBrowseRow(title: "All readings")
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.top, theme.metrics.cardSpacing)
        .task { await load() }
    }

    private struct Row: Identifiable {
        enum Target { case type(BodyDataType), category(PulseRoute) }
        var id: String
        var target: Target
    }

    private var rows: [Row] {
        types.map { Row(id: $0.id, target: .type($0)) }
            + (category.map { [Row(id: "all", target: .category($0))] } ?? [])
    }

    private func reading(_ type: BodyDataType) -> some View {
        let summary = summaries[type]
        return SomaReadingRow(
            title: MetricPageWords.title(identifier: type.metric.identifier, fallback: type.title),
            caption: summary?.date,
            value: summary?.value,
            unit: summary?.unit,
            week: summary?.bars ?? [],
            aspect: aspect
        )
    }

    private func load() async {
        guard summaries.isEmpty, let source = await health.prepare(types.map(\.metric.identifier)) else { return }
        summaries = await VaultWeekSummary.read(types, from: source, now: Date())
    }
}

extension VaultWeekSummary {
    /// Each type's last seven days, ending on its latest reading.
    static func read(_ types: [BodyDataType], from source: any HealthSampleSource, now: Date) async -> [BodyDataType: VaultWeekSummary] {
        let reader = VaultReader(source: source)
        return await withTaskGroup(of: (BodyDataType, VaultWeekSummary).self) { group in
            for type in types {
                group.addTask {
                    // The seven days end on the latest reading, as Health's do:
                    // a watch left off for a week still shows its last week.
                    let latest = await reader.latestRecord(type.metric)
                    let points = await reader.series(type.metric, period: .week, now: latest?.end ?? now)
                    return (type, VaultWeekSummary.make(type.metric, points: points, latest: latest))
                }
            }
            var result: [BodyDataType: VaultWeekSummary] = [:]
            for await (type, summary) in group { result[type] = summary }
            return result
        }
    }
}
