//
//  VaultDataTypePage.swift
//  Prism
//
//  The page every metric opens on, from a Body tile, a Today row, a
//  category or the Vault: today's value and what it means over one tall
//  chart of a chosen span against the person's usual, one quiet line, and
//  where the readings came from. The long words wait behind the info control.
//

import SwiftUI
import SomaUI
import HealthExportCore

/// One data type, top to bottom: the stage (when the number is from, the
/// number, one line on what it means, over the chart with the usual band,
/// the average and the high and low on it; reading the chart reads the
/// number), one quiet line and the span picker, then the sources and the way
/// into every reading. The category's other types sit in the title's menu;
/// what the metric is and how its band is read sit in the info sheet.
///
/// The math is in ``MetricDetailMath``, the words in ``MetricPageWords`` and
/// ``MetricAbout``, the per metric choices in ``MetricProfile``; this view
/// reads and lays out.
struct VaultDataTypePage: View {
    let subject: VaultSubject

    init(type: BodyDataType) { subject = .health(type) }
    init(subject: VaultSubject) { self.subject = subject }

    @Environment(HealthDashboard.self) private var health
    @Environment(\.somaTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The metric showing: the one opened, or a sibling switched to in place.
    @State private var current: VaultSubject?
    @State private var period: VaultPeriod?
    /// The year and today's hours, with the metric they were read for: a
    /// sibling picked from the title shows a blank chart until its own data
    /// lands, never the last metric's under its name.
    @State private var read: VaultLoaded<VaultSubject, VaultMasterRead>?
    @State private var siblings: [VaultSubject] = []
    /// The sources, with the metric and span they were read for.
    @State private var sourcesRead: VaultLoaded<WindowKey, [VaultMasterReader.Origin]>?
    @State private var showsInfo = false

    private var shown: VaultSubject { current ?? subject }
    /// The year of the metric showing, nil until it is read.
    private var master: MetricMaster? { read?.value(for: shown)?.master }
    /// Today's hours, read straight from the store: the Day chart, and
    /// whether the metric is read through the day at all.
    private var hours: [VaultPoint] { read?.value(for: shown)?.hours ?? [] }
    private var origins: [VaultMasterReader.Origin] {
        sourcesRead?.value(for: WindowKey(subject: shown, period: span)) ?? []
    }
    /// The HealthKit type behind the page, nil for a score.
    private var type: BodyDataType? { if case .health(let type) = shown { type } else { nil } }
    private var score: ScoreMetric? { if case .score(let score) = shown { score } else { nil } }
    private var identifier: String { type?.metric.identifier ?? score?.identifier ?? "" }
    private var profile: MetricProfile { score?.profile(health.scores) ?? MetricProfile.of(identifier) }
    private var calendar: Calendar { .current }
    /// The category's hue: the chart is never ink only.
    private var hue: SomaHealthHue {
        if let type { return BodyCategory.containing(type)?.hue ?? .other }
        return .sleep
    }
    /// The aspect whose wash the page wears: the category's, or the score's.
    private var aspect: SomaAspect? {
        if let type { return BodyCategory.containing(type)?.aspect }
        return score?.aspect
    }
    private var isSleep: Bool { identifier == MetricProfile.sleep }
    private var isCount: Bool { type?.metric.kind == .category && !isSleep }
    private var dayIsUseful: Bool { type != nil && !isSleep && !isCount && hours.filter { $0.value != nil }.count >= 3 }
    private var offered: [VaultPeriod] { MetricPageWords.ranges(dayIsUseful: dayIsUseful) }
    private var span: VaultPeriod {
        if let period, offered.contains(period) { return period }
        return MetricPageWords.opening(profile.period, offered: offered)
    }
    private var kind: MetricPageWords.Kind {
        if score != nil { return .score }
        if isSleep { return .night }
        if profile.accumulates || isCount { return .total }
        return .reading(manyADay: dayIsUseful)
    }
    private var title: String {
        if let score { return score.title }
        return MetricPageWords.title(identifier: identifier, fallback: shown.title)
    }

    var body: some View {
        let metrics = theme.metrics
        let detail = self.detail

        SomaPageScroll {
            VStack(alignment: .leading, spacing: metrics.leadSpacing) {
                stage(detail)

                sources
            }
            .padding(metrics.pagePadding)
            .frame(maxWidth: metrics.pageMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        // The aspect's weather across the top, as on the score pages and the
        // category pages that open this one.
        .aspectWash(aspect)
        .navigationTitle(title)
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .toolbarTitleMenu {
            if !siblings.isEmpty {
                ForEach(siblings) { sibling in
                    Button {
                        current = sibling
                    } label: {
                        if sibling == shown {
                            Label(siblingTitle(sibling), systemImage: "checkmark")
                        } else {
                            Text(siblingTitle(sibling))
                        }
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showsInfo = true
                } label: {
                    Image(systemName: "info.circle")
                }
                .accessibilityLabel(Text("About \(title)"))
            }
        }
        .sheet(isPresented: $showsInfo) {
            SomaInfoSheet(title: title, sections: infoSections(detail))
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .task(id: shown) { await loadMaster() }
        .task(id: WindowKey(subject: shown, period: span)) { await loadSources() }
        .refreshable {
            await loadMaster()
            await loadSources()
        }
    }

    // MARK: - Parts

    /// The head and the chart as one piece: the number and what it means
    /// over the span's chart, the quiet line and the span picker under it.
    @ViewBuilder
    private func stage(_ detail: Detail) -> some View {
        let lead = SomaMetricLead(
            caption: detail.caption,
            value: detail.heroValue,
            unit: detail.unit,
            meaning: detail.meaning?.text,
            tone: detail.meaning?.tone ?? .neutral
        )
        let periods = offered.count > 1
            ? offered.map { SomaSegment(id: $0, title: LocalizedStringResource(stringLiteral: MetricPageWords.title($0))) }
            : []
        if master != nil {
            SomaMetricStage(
                lead: lead,
                buckets: detail.buckets,
                style: chartStyle,
                hue: hue,
                domain: detail.domain,
                usualLabel: detail.usualLabel,
                average: detail.average,
                summary: detail.summaryLabel,
                note: detail.note,
                periods: periods,
                period: Binding(get: { span }, set: { period = $0 })
            )
            // A sibling is another metric: it draws in afresh rather than
            // morphing out of the last one.
            .id(shown)
        } else {
            // Holds the stage's room until the metric is read, so the
            // sources under it never jump.
            SomaMetricStage(lead: lead, buckets: [], style: chartStyle, hue: hue, domain: 0...1, summary: detail.summaryLabel)
                .opacity(0)
        }
    }

    @ViewBuilder
    private var sources: some View {
        let listed = MetricPageWords.sources(origins)
        if let type {
            VStack(alignment: .leading, spacing: theme.metrics.cardSpacing) {
                Text("Sources")
                    .somaFont(theme.typography.eyebrow)
                    .foregroundStyle(theme.colors.inkSecondary.color)
                    .accessibilityAddTraits(.isHeader)
                SomaSourceList(listed) {
                    NavigationLink(value: VaultRoute.allData(type)) {
                        SomaBrowseRow(title: "All readings")
                            .contentShape(.rect)
                    }
                    .buttonStyle(.somaBrowseRow)
                }
                .animation(reduceMotion ? nil : theme.motion.chartFade, value: listed)
            }
            .padding(.top, theme.metrics.cardSpacing)
        }
    }

    private var chartStyle: SomaMetricChartStyle {
        switch profile.chart {
        case .bars: .bars
        case .line: .line
        case .points: .points
        case .bloodPressure: .ranges
        }
    }

    private func siblingTitle(_ sibling: VaultSubject) -> String {
        switch sibling {
        case .health(let type): MetricPageWords.title(identifier: type.metric.identifier, fallback: type.title)
        case .score(let score): score.title
        }
    }

    private func infoSections(_ detail: Detail) -> [SomaInfoSection] {
        MetricAbout.sections(
            identifier: identifier,
            title: title,
            band: detail.band,
            isReference: detail.isReference,
            accumulates: profile.accumulates,
            hasSources: type != nil,
            unit: detail.unit,
            format: format
        )
    }

    // MARK: - What the page shows

    private struct WindowKey: Hashable {
        var subject: VaultSubject
        var period: VaultPeriod
    }

    private struct Detail {
        var caption: String?
        var heroValue: String?
        var unit: String?
        var meaning: MetricPageWords.Meaning?
        var band: ClosedRange<Double>?
        var isReference = false
        var buckets: [SomaChartBucket] = []
        var domain: ClosedRange<Double> = 0...1
        var usualLabel: String?
        var average: SomaChartAverage?
        var summaryLabel = ""
        var note: String?
    }

    private var detail: Detail {
        var detail = Detail()
        detail.unit = unitLabel
        guard let master else { return detail }

        let band = MetricDetailMath.band(master.days, profile: profile)
        let standing = MetricDetailMath.standing(master.days, profile: profile)
        let lastIndex = master.lastIndex
        let lastDay = lastIndex.map { master.date(at: $0, calendar: calendar) }
        let today = calendar.startOfDay(for: .now)
        let todayOpen = profile.accumulates && lastDay.map { calendar.isDate($0, inSameDayAs: today) } == true
        let value = lastIndex.flatMap { master.days[$0] }
        let known = master.days.compactMap { $0 }.count

        detail.band = standing.band
        detail.isReference = standing.isReference
        detail.caption = MetricPageWords.caption(for: lastDay, kind: kind, calendar: calendar)
        detail.heroValue = heroValue(master)
        detail.meaning = MetricPageWords.meaning(
            value: value,
            band: standing.band,
            isReference: standing.isReference,
            known: known,
            todayOpen: todayOpen,
            risingIsGood: profile.risingIsGood,
            format: format,
            unit: unitLabel
        )

        // The chart: hours of today straight from the store, the rest
        // folded from the daily year.
        let now = Date.now
        let window = span.interval(endingAt: now, calendar: calendar)
        let folded: [MetricDetailMath.Bucket]
        if span == .day {
            let dayBand = master.index(of: now, calendar: calendar).flatMap { band?.range(at: $0) }
            // A total's usual is for a whole day; an hour has none.
            folded = hours.map {
                MetricDetailMath.Bucket(interval: $0.interval, value: $0.value.map(scaled), band: profile.accumulates ? nil : dayBand)
            }
        } else {
            folded = MetricDetailMath.buckets(
                master, band: band, intervals: span.buckets(endingAt: now, calendar: calendar), calendar: calendar
            )
        }
        let openLast = todayOpen && span != .day
        detail.buckets = folded.enumerated().map { index, bucket in
            let note = MetricPageWords.meaning(
                value: bucket.value, band: bucket.band, isReference: standing.isReference, known: known,
                todayOpen: openLast && index == folded.count - 1, risingIsGood: profile.risingIsGood,
                format: format, unit: unitLabel
            )
            return SomaChartBucket(
                id: index,
                value: bucket.value,
                low: bucket.secondary,
                band: bucket.band,
                axisLabel: MetricPageWords.axisLabel(span, index: index, count: folded.count, start: bucket.interval.start, calendar: calendar),
                readout: MetricPageWords.readout(span, interval: bucket.interval),
                valueText: bucket.value.map { value in bucket.secondary.map { "\(format(value))/\(format($0))" } ?? format(value) },
                note: note?.text,
                tone: note?.tone ?? .neutral
            )
        }
        let values = folded.compactMap(\.value) + folded.compactMap(\.secondary)
        detail.domain = MetricDetailMath.domain(
            values: values, bands: folded.compactMap(\.band), ceiling: profile.ceiling,
            zeroBased: profile.chart == .bars
        )
        if let range = folded.compactMap(\.band).last {
            detail.usualLabel = MetricPageWords.usualKey(range, isReference: standing.isReference, format: format)
        }
        detail.summaryLabel = MetricPageWords.summaryLabel(span, kind: kind, span: window, now: now, calendar: calendar)
        let shownValues = folded.compactMap(\.value)
        // A day of a total is a sum, not a level: no average line across
        // its hours.
        if !shownValues.isEmpty, !(span == .day && profile.accumulates), score?.isClock != true {
            let mean = shownValues.reduce(0, +) / Double(shownValues.count)
            detail.average = SomaChartAverage(value: mean, text: MetricPageWords.averageKey(mean, kind: kind, format: format, unit: unitLabel))
        }

        // One quiet line: the month against the one before, and either where
        // body composition is heading or how many days sat in the band. The
        // usual and the average are on the chart's key.
        let openTail = todayOpen ? 1 : 0
        let trend = score?.isClock == true ? nil : MetricPageWords.trendFact(
            days: master.days, openDayTail: openTail, risingIsGood: profile.risingIsGood,
            accumulates: profile.accumulates, format: format
        )
        let projected = profile.projects
            ? MetricPageWords.projectionFact(MetricDetailMath.projections(master.days), format: format, unit: unitLabel)
            : nil
        let inBand = projected == nil ? MetricPageWords.daysInBandFact(days: master.days, band: band, openDayTail: openTail) : nil
        detail.note = known == 0 ? nil : MetricPageWords.note(trend: trend, projection: projected, inBand: inBand)
        return detail
    }

    /// The latest day's value: the total so far for a sum, last night for
    /// sleep, systolic over diastolic for pressure, else the day's mean, so
    /// the number and its line are read against the same band.
    private func heroValue(_ master: MetricMaster) -> String? {
        guard let index = master.lastIndex, let value = master.days[index] else { return nil }
        if let secondary = master.secondary {
            guard let low = secondary[index] else { return format(value) }
            return "\(format(value))/\(format(low))"
        }
        return format(value)
    }

    private var unitLabel: String? {
        if let score { return score.unit }
        if isSleep { return nil }
        if isCount { return "records" }
        guard let type else { return nil }
        return MetricPageWords.unit(identifier: identifier, fallback: type.metric.unit.shortLabel)
    }

    private func scaled(_ value: Double) -> Double {
        guard let type, !isCount else { return value }
        return VaultFormat.scaled(value, unit: type.metric.unit)
    }

    private func format(_ value: Double) -> String {
        if isSleep || score?.isDuration == true {
            return SomaFormat.duration(value * 3600)
        }
        if score?.isClock == true {
            let hour = value.truncatingRemainder(dividingBy: 24)
            return PulseWording(calendar: calendar, locale: .current).clock((hour < 0 ? hour + 24 : hour) * 3600)
        }
        if readsWhole { return VaultFormat.number(value.rounded()) }
        return VaultFormat.number(value)
    }

    /// Beats, pressure, milliseconds and counts read as whole numbers: a
    /// day's mean of 71.8 bpm says no more than 72.
    private var readsWhole: Bool {
        guard let type, identifier != "HKQuantityTypeIdentifierRespiratoryRate" else { return false }
        return [.countPerMinute, .millimeterOfMercury, .millisecond, .count].contains(type.metric.unit)
    }

    // MARK: - Reading

    private func loadMaster() async {
        if let score {
            await health.loadScores()
            guard !Task.isCancelled, let scores = health.scores else { return }
            read = VaultLoaded(key: .score(score), value: VaultMasterRead(
                master: MetricMaster(today: calendar.startOfDay(for: .now), days: score.days(scores)), hours: []))
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
        let readsHours = metric.identifier != MetricProfile.sleep && metric.kind != .category
        async let day: [VaultPoint] = readsHours ? VaultReader(source: source).series(metric, period: .day, now: .now) : []
        let (read, today) = await (year, day)
        guard !Task.isCancelled else { return }
        withAnimation(reduceMotion ? nil : theme.motion.chartFade) {
            self.read = VaultLoaded(key: .health(type), value: VaultMasterRead(master: read, hours: today))
        }
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

    /// The sources behind the span on show.
    private func loadSources() async {
        let key = WindowKey(subject: shown, period: span)
        guard let type else {
            sourcesRead = VaultLoaded(key: key, value: [])
            return
        }
        let metric = type.metric
        guard let source = await health.prepare([metric.identifier]) else { return }
        let window = span.interval(endingAt: .now, calendar: calendar)
        let found = await VaultMasterReader(source: source).origins(metric, in: window)
        guard !Task.isCancelled else { return }
        sourcesRead = VaultLoaded(key: key, value: found)
    }
}

/// A value read for one key, such as the metric a page shows: handed back
/// only while the page still asks for that key, so a switch never shows the
/// last key's value under the new one.
struct VaultLoaded<Key: Hashable, Value> {
    var key: Key
    var value: Value

    func value(for current: Key) -> Value? {
        key == current ? value : nil
    }
}

/// A metric's year, and today's hours.
struct VaultMasterRead {
    var master: MetricMaster
    var hours: [VaultPoint]
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
