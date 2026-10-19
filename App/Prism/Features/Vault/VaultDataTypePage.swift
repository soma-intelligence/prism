//
//  VaultDataTypePage.swift
//  Prism
//
//  The page every metric opens on, from a Body tile, a Today row or the
//  Vault: every reading the app holds for the metric, in the Health look,
//  and no prose.
//

import SwiftUI
import SomaUI
import HealthExportCore

/// One data type, top to bottom: the latest value with where it stands and
/// what it means; the other types of its category; the chart over a chosen
/// span, with its band, paging and scrubbing; min, average and max; the
/// change over 3 to 90 days; projections for body composition; then every
/// record, the unit and the sources.
///
/// The math is in ``MetricDetailMath`` and the per metric choices in
/// ``MetricProfile``; this view reads and lays out.
struct VaultDataTypePage: View {
    let subject: VaultSubject

    init(type: BodyDataType) { subject = .health(type) }
    init(subject: VaultSubject) { self.subject = subject }

    @Environment(HealthDashboard.self) private var health
    @Environment(\.somaTheme) private var theme

    /// The metric showing: the one opened, or a sibling switched to in place.
    @State private var current: VaultSubject?
    @State private var period: VaultPeriod?
    /// Whole spans paged back from today.
    @State private var page = 0
    @State private var master: MetricMaster?
    @State private var latest: HealthReading?
    /// The hours of the day shown under D, which reads the store directly.
    @State private var hours: [VaultPoint] = []
    @State private var siblings: [VaultSubject] = []
    @State private var origins: [VaultMasterReader.Origin] = []

    private var shown: VaultSubject { current ?? subject }
    /// The HealthKit type behind the page, nil for a score.
    private var type: BodyDataType? { if case .health(let type) = shown { type } else { nil } }
    private var score: ScoreMetric? { if case .score(let score) = shown { score } else { nil } }
    private var identifier: String { type?.metric.identifier ?? score?.identifier ?? "" }
    private var profile: MetricProfile { score?.profile(health.scores) ?? MetricProfile.of(identifier) }
    private var span: VaultPeriod { period ?? profile.period }
    private var calendar: Calendar { .current }
    /// The category's hue: lines, bars and sparklines are never ink only.
    private var hue: SomaHealthHue {
        if let type { return BodyCategory.containing(type)?.hue ?? .other }
        return .sleep
    }
    private var isSleep: Bool { identifier == MetricProfile.sleep }
    private var isCount: Bool { type?.metric.kind == .category && !isSleep }

    var body: some View {
        let metrics = theme.metrics
        let detail = self.detail

        ScrollView {
            VStack(alignment: .leading, spacing: metrics.cardSpacing) {
                VaultHero(
                    value: detail.heroValue,
                    unit: detail.unit,
                    standing: detail.standing,
                    legend: detail.legend,
                    cue: detail.insight?.cue,
                    tone: detail.insight?.tone ?? .neutral
                )

                if !siblings.isEmpty {
                    VaultSiblingChips(types: siblings, selected: shown) { picked in
                        current = picked
                    }
                }

                Picker("Period", selection: Binding(get: { span }, set: { period = $0; page = 0 })) {
                    ForEach(VaultPeriod.allCases) { period in
                        Text(period.short).tag(period)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.top, metrics.cardSpacing)

                VaultDetailChart(
                    buckets: detail.buckets,
                    hue: hue,
                    period: span,
                    chart: profile.chart,
                    domain: detail.domain,
                    format: format,
                    canGoBack: canGoBack,
                    canGoForward: page > 0,
                    page: { page = max(0, page + $0) }
                )

                if let stats = detail.stats {
                    SomaStatRow([
                        SomaStat("Min", value: format(stats.minimum)),
                        SomaStat("Average", value: format(stats.average)),
                        SomaStat("Max", value: format(stats.maximum)),
                    ])
                    .padding(.top, metrics.cardSpacing)
                }

                if !detail.trends.isEmpty {
                    VaultTrendsTable(rows: detail.trends, unit: detail.unit, last: detail.lastDate, hue: hue, format: format)
                        .padding(.top, metrics.leadSpacing)
                }

                if !detail.projections.isEmpty {
                    VaultProjections(rows: detail.projections, unit: detail.unit, format: format)
                        .padding(.top, metrics.leadSpacing)
                }

                VaultOptions(type: type, unit: detail.unit, origins: origins)
                    .padding(.top, metrics.leadSpacing)
            }
            .padding(metrics.pagePadding)
            .frame(maxWidth: metrics.pageMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(theme.colors.canvas.color.ignoresSafeArea())
        .navigationTitle(shown.title)
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .task(id: shown) { await loadMaster() }
        .task(id: WindowKey(subject: shown, period: span, page: page)) { await loadWindow() }
        .refreshable {
            await loadMaster()
            await loadWindow()
        }
    }

    // MARK: - What the page shows

    private struct WindowKey: Hashable {
        var subject: VaultSubject
        var period: VaultPeriod
        var page: Int
    }

    private struct Detail {
        var heroValue: String?
        var unit: String?
        var standing: MetricDetailMath.Standing?
        var legend: String?
        var insight: Insight?
        var buckets: [MetricDetailMath.Bucket] = []
        var domain: ClosedRange<Double> = 0...1
        var stats: MetricDetailMath.Stats?
        var trends: [MetricDetailMath.TrendRow] = []
        var projections: [MetricDetailMath.Projection] = []
        var lastDate: Date?
    }

    private var windowEnd: Date { span.shifted(.now, by: page, calendar: calendar) }

    private var canGoBack: Bool {
        guard let master else { return false }
        let start = span.interval(endingAt: windowEnd, calendar: calendar).start
        return start > master.date(at: 0, calendar: calendar)
    }

    private var detail: Detail {
        var detail = Detail()
        detail.unit = unitLabel
        guard let master else { return detail }

        let band = MetricDetailMath.band(master.days, profile: profile)
        let standing = MetricDetailMath.standing(master.days, profile: profile, todayOpen: profile.accumulates)
        detail.standing = standing
        if let range = standing.band {
            detail.legend = "\(standing.isReference ? "Normal" : "Usual") \(format(range.lowerBound)) to \(format(range.upperBound))"
        }
        detail.heroValue = heroValue(master)
        detail.insight = insight(master)

        // The chart's buckets: hours of a day straight from the store, the
        // rest folded from the daily year.
        let buckets: [MetricDetailMath.Bucket]
        if span == .day, type != nil {
            let dayBand = master.index(of: windowEnd, calendar: calendar).flatMap { band?.range(at: $0) }
            buckets = hours.map { MetricDetailMath.Bucket(interval: $0.interval, value: $0.value.map(scaled), band: dayBand) }
        } else {
            buckets = MetricDetailMath.buckets(
                master, band: band, intervals: span.buckets(endingAt: windowEnd, calendar: calendar), calendar: calendar
            )
        }
        detail.buckets = buckets
        let values = buckets.compactMap(\.value) + buckets.compactMap(\.secondary)
        detail.domain = MetricDetailMath.domain(
            values: values, bands: buckets.compactMap(\.band), ceiling: profile.ceiling, zeroBased: profile.chart == .bars
        )
        detail.stats = MetricDetailMath.stats(buckets.map(\.value))

        detail.trends = MetricDetailMath.trendRows(
            master.days, risingIsGood: profile.risingIsGood, openDayTail: profile.accumulates ? 1 : 0
        )
        if profile.projects { detail.projections = MetricDetailMath.projections(master.days) }
        detail.lastDate = master.lastIndex.map { master.date(at: $0, calendar: calendar) }
        return detail
    }

    /// The day's total for a sum, last night for sleep, systolic over
    /// diastolic for pressure, else the latest record.
    private func heroValue(_ master: MetricMaster) -> String? {
        if let secondary = master.secondary {
            guard let index = master.lastIndex, let high = master.days[index], let low = secondary[index] else { return nil }
            return "\(format(high))/\(format(low))"
        }
        if isSleep || isCount || profile.accumulates {
            return master.days.last.flatMap { $0 }.map(format)
                ?? (isSleep ? master.days.suffix(2).compactMap { $0 }.last.map(format) : nil)
        }
        if let type, let latest { return format(VaultFormat.scaled(latest.value, unit: type.metric.unit)) }
        return master.lastIndex.flatMap { master.days[$0] }.map(format)
    }

    /// The engine's cue, for the metrics Soma interprets. The year is cut to
    /// the ninety days the engine reads and turned into the unit Body reads
    /// it in (km/h rather than m/s).
    private func insight(_ master: MetricMaster) -> Insight? {
        let days = Array(master.days.suffix(BodyBiomarkers.lookback))
        let insight: Insight
        if let type, let interpreted = InsightMetric.metric(for: type.metric.identifier) {
            let factor: Double = BodyBiomarkerSpec(interpreted).map { $0.display(1) / VaultFormat.scaled(1, unit: type.metric.unit) } ?? 1
            insight = InsightEngine.interpret(interpreted, days: days.map { $0.map { $0 * factor } })
        } else if let score, !score.isClock {
            let policy: InsightPolicy = switch profile.risingIsGood {
            case true: .score
            case false: InsightPolicy(preference: .lower, minimumSpread: InsightPolicy.score.minimumSpread, trendStep: InsightPolicy.score.trendStep)
            default: .load
            }
            insight = InsightEngine.interpret(days, policy: score.isDuration ? InsightPolicy(preference: policy.preference, minimumSpread: 0.25, trendStep: 0.25) : policy)
        } else {
            return nil
        }
        return insight.cue == nil ? nil : insight
    }

    private var unitLabel: String? {
        if let score { return score.unit }
        if isSleep { return nil }
        if isCount { return "records" }
        return type?.metric.unit.shortLabel
    }

    private func scaled(_ value: Double) -> Double {
        guard let type, !isCount else { return value }
        return VaultFormat.scaled(value, unit: type.metric.unit)
    }

    private func format(_ value: Double) -> String {
        let wording = PulseWording(calendar: calendar, locale: .current)
        if isSleep || score?.isDuration == true { return wording.clock(value * 3600) }
        if score?.isClock == true {
            let hour = value.truncatingRemainder(dividingBy: 24)
            return wording.clock((hour < 0 ? hour + 24 : hour) * 3600)
        }
        return VaultFormat.number(value)
    }

    // MARK: - Reading

    private func loadMaster() async {
        if let score {
            await health.loadScores()
            guard !Task.isCancelled, let scores = health.scores else { return }
            master = MetricMaster(today: calendar.startOfDay(for: .now), days: score.days(scores))
            latest = nil
            siblings = ScoreMetric.allCases
                .filter { $0.days(scores).contains { $0 != nil } }
                .map(VaultSubject.score)
            if siblings.count < 2 { siblings = [] }
            return
        }
        guard let type else { return }
        let metric = type.metric
        // Asking goes through the dashboard's once per set gate; a sensitive
        // type is asked for here, when its page opens.
        guard let source = await health.prepare([metric.identifier, MetricProfile.diastolic, MetricProfile.systolic]) else { return }
        let reader = VaultMasterReader(source: source)
        async let year = reader.master(metric, now: .now)
        async let record = VaultReader(source: source).latestRecord(metric)
        let (read, newest) = await (year, record)
        guard !Task.isCancelled else { return }
        master = read
        latest = newest
        siblings = await withData(BodyCategory.containing(type)?.types ?? [], source: source).map(VaultSubject.health)
    }

    /// The category's types that hold any record, in the category's order.
    private func withData(_ types: [BodyDataType], source: any HealthSampleSource) async -> [BodyDataType] {
        guard types.count > 1 else { return [] }
        let reader = VaultReader(source: source)
        let found = await withTaskGroup(of: (Int, Bool).self) { group in
            for (index, type) in types.enumerated() {
                group.addTask { (index, await reader.latestRecord(type.metric) != nil) }
            }
            var found: [Int: Bool] = [:]
            for await (index, has) in group { found[index] = has }
            return found
        }
        let kept = types.enumerated().filter { found[$0.offset] == true }.map(\.element)
        return kept.count > 1 ? kept : []
    }

    private func loadWindow() async {
        guard let type else {
            origins = []
            return
        }
        let metric = type.metric
        guard let source = await health.prepare([metric.identifier]) else { return }
        let window = span.interval(endingAt: windowEnd, calendar: calendar)
        if span == .day {
            let points = await VaultReader(source: source).series(metric, period: .day, now: windowEnd)
            guard !Task.isCancelled else { return }
            hours = points
        }
        let found = await VaultMasterReader(source: source).origins(metric, in: window)
        guard !Task.isCancelled else { return }
        origins = found
    }
}

/// What a data type page shows: a HealthKit type, or one of Soma's scores.
enum VaultSubject: Hashable, Identifiable {
    case health(BodyDataType)
    case score(ScoreMetric)

    var id: String {
        switch self {
        case .health(let type): type.id
        case .score(let score): score.identifier
        }
    }

    var title: String {
        switch self {
        case .health(let type): type.title
        case .score(let score): score.title
        }
    }
}

#if DEBUG
#Preview("Data type") {
    NavigationStack {
        VaultDataTypePage(type: BodyCatalog.categories[4].types[0])
    }
    .environment(HealthDashboard(source: VaultPreviewSource()))
}
#endif
