//
//  PulseMoved.swift
//  Prism
//
//  Today's "What moved": every metric Soma interprets, read against the
//  person's usual by ``InsightEngine``, and the few that moved most, ranked.
//

import SwiftUI
import SomaUI
import HealthExportCore

extension PulseInsightItem {
    /// Two lines at most: the cue takes the status word's place, coloured
    /// by whether it is good news.
    var line: SomaReadingStatus {
        guard let cue else { return status }
        // The engine's tone, not the band's: resting heart rate at its
        // highest in a month is news to watch even inside the healthy zone.
        return .worded(LocalizedStringResource(stringLiteral: cue), insight.tone.cueTone)
    }
}

/// One interpreted metric as Today shows it.
struct PulseInsightItem: Equatable, Identifiable, Sendable {
    var id: InsightMetric { metric }
    var metric: InsightMetric
    /// The latest value with its unit, or nil for a dash.
    var value: String?
    /// The latest value alone, as ``value`` prints it, and its unit apart,
    /// for a surface that sets the two in different sizes.
    var number: String?
    var unit: String = ""
    /// The last thirty days, oldest first.
    var days: [Double?]
    var insight: Insight
    /// The cue under the value.
    var cue: String?
    /// The status word, the same one the metric's Body tile and page show.
    var status: SomaReadingStatus = .none
    /// The band the status is read against.
    var band: ClosedRange<Double>?

    static func == (lhs: PulseInsightItem, rhs: PulseInsightItem) -> Bool {
        lhs.metric == rhs.metric && lhs.value == rhs.value && lhs.days == rhs.days
            && lhs.insight == rhs.insight && lhs.cue == rhs.cue && lhs.band == rhs.band
    }
}

/// Every metric Today interprets, and the ones that moved.
struct PulseInsights: Equatable, Sendable {
    /// In ``InsightMetric`` order, which breaks ties when ranking.
    var items: [PulseInsightItem]

    static let empty = PulseInsights(items: [])

    subscript(metric: InsightMetric) -> PulseInsightItem? {
        items.first { $0.metric == metric }
    }

    /// The three to five that moved most today, highest first.
    var moved: [PulseInsightItem] {
        InsightEngine.ranked(items.map { (key: $0, insight: $0.insight) }).map(\.key)
    }

    /// Builds every item from ninety days of samples per Body reading and
    /// ninety nights of hours asleep (oldest first, ending today).
    static func make(
        readings: [BodyBiomarkerSpec: [HealthReading]],
        sleepHours: [Double?],
        now: Date,
        calendar: Calendar
    ) -> PulseInsights {
        let items = InsightMetric.allCases.map { metric -> PulseInsightItem in
            if let spec = BodyBiomarkerSpec(metric) {
                let marker = BodyBiomarkers.make(spec, readings: readings[spec] ?? [], now: now, calendar: calendar)
                return PulseInsightItem(
                    metric: metric,
                    value: marker.value.map { marker.unit.isEmpty ? $0 : "\($0) \(marker.unit)" },
                    number: marker.value,
                    unit: marker.unit,
                    days: marker.days,
                    insight: marker.insight,
                    cue: marker.cue,
                    status: marker.status.reading,
                    band: marker.band
                )
            }
            // Sleep is read as nights: a night with nothing recorded is a gap,
            // not a night of no sleep.
            let nights = sleepHours.map { hours in hours.flatMap { $0 > 0 ? $0 : nil } }
            let insight = InsightEngine.interpret(metric, days: nights)
            let last = nights.suffix(2).compactMap { $0 }.last
            let standing = MetricDetailMath.standing(nights, profile: MetricProfile.of(metric))
            return PulseInsightItem(
                metric: metric,
                value: last.map { PulseWording(calendar: calendar, locale: .current).clock($0 * 3600) },
                number: last.map { PulseWording(calendar: calendar, locale: .current).clock($0 * 3600) },
                days: Array(nights.suffix(BodyBiomarkers.days)),
                insight: insight,
                cue: last == nil ? nil : insight.cue,
                status: last == nil ? .none : standing.reading,
                band: standing.band
            )
        }
        return PulseInsights(items: items)
    }

    /// Reads what ``make`` needs: the Body readings from Health, and the
    /// nights from the scores already read.
    static func read(health: HealthDashboard, now: Date, calendar: Calendar) async -> PulseInsights? {
        guard let source = await health.prepare(BodyBiomarkers.metrics) else { return nil }
        let readings = await BodyBiomarkers.read(BodyBiomarkerSpec.interpreted, from: source, now: now, calendar: calendar)
        return make(readings: readings, sleepHours: health.scores?.detail.sleepHours ?? [], now: now, calendar: calendar)
    }
}

/// The three scores under the orb, each read against its own usual.
enum PulseScoreInsights {
    static func sleep(_ scores: SomaScores?) -> Insight {
        InsightEngine.interpret(scores?.detail.sleep ?? [], policy: .score)
    }

    /// Mind is recovery, or calm (100 minus stress) on a day without it, as
    /// ``SomaScores/mind`` reads it.
    static func mind(_ scores: SomaScores?) -> Insight {
        guard let detail = scores?.detail else { return .empty(.higher) }
        let days = zip(detail.recovery, detail.stress).map { recovery, stress in recovery ?? stress.map { 100 - $0 } }
        return InsightEngine.interpret(days, policy: .score)
    }

    static func activity(_ scores: SomaScores?) -> Insight {
        InsightEngine.interpret(scores?.detail.strain ?? [], policy: .load)
    }
}

// MARK: - The section

/// The few metrics that moved most today, each a row that opens its page in
/// the Vault. Hidden until something has a reading.
struct PulseMovedSection: View {
    let items: [PulseInsightItem]

    @Environment(\.somaTheme) private var theme

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: theme.metrics.cardSpacing) {
                Text("What moved")
                    .somaFont(theme.typography.headline)
                    .foregroundStyle(theme.colors.inkPrimary.color)
                    .accessibilityAddTraits(.isHeader)
                ForEach(items) { item in
                    PulseMovedRow(item: item)
                }
            }
        }
    }
}

private struct PulseMovedRow: View {
    let item: PulseInsightItem

    var body: some View {
        let row = SomaTrendRow(
            LocalizedStringResource(stringLiteral: item.metric.title),
            value: item.value,
            status: item.line,
            cue: nil,
            values: item.days,
            band: item.band,
            hue: item.metric.hue,
            chart: MetricProfile.of(item.metric).chart == .bars ? .bars : .line
        )
        if let metric = HealthMetricCatalog.metric(for: item.metric.identifier) {
            NavigationLink(value: VaultRoute.dataType(BodyDataType(metric))) {
                row.contentShape(.rect)
            }
            .zoomSource(VaultRoute.dataType(BodyDataType(metric)))
            .buttonStyle(.somaGlassPress)
        } else {
            row
        }
    }
}
