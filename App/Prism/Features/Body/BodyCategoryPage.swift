//
//  BodyCategoryPage.swift
//  Prism
//

import SwiftUI
import SomaUI
import HealthExportCore

/// One Health category in the Vault, laid out as iOS 27 Apple Health lays a
/// category out: the page washed in the category's hue under a large title,
/// a card per data type that has readings this week (its name in the hue, the
/// latest value large, seven small bars), then every type with nothing in a
/// plain list under "No Data Available".
struct BodyCategoryPage: View {
    let category: BodyCategory

    @Environment(HealthDashboard.self) private var health
    @Environment(\.somaTheme) private var theme

    @State private var summaries: [BodyDataType: VaultWeekSummary] = [:]
    @State private var hasRead = false

    private var withData: [BodyDataType] {
        category.types.filter { summaries[$0]?.hasData == true }
    }

    private var withoutData: [BodyDataType] {
        category.types.filter { summaries[$0]?.hasData != true }
    }

    var body: some View {
        let metrics = theme.metrics

        ScrollView {
            LazyVStack(alignment: .leading, spacing: metrics.cardSpacing) {
                if !withData.isEmpty {
                    heading("Past 7 Days")
                    ForEach(withData) { type in
                        if let summary = summaries[type] {
                            NavigationLink(value: VaultRoute.dataType(type)) {
                                SomaHealthSummaryCard(
                                    symbol: category.symbol,
                                    title: LocalizedStringResource(stringLiteral: type.title),
                                    hue: category.hue,
                                    date: summary.date,
                                    value: summary.value,
                                    unit: summary.unit,
                                    bars: summary.bars
                                )
                            }
                            .buttonStyle(.somaGlassPress)
                        }
                    }
                }

                if hasRead, !withoutData.isEmpty {
                    heading("No Data Available")
                        .padding(.top, metrics.cardSpacing)
                    SomaBrowseGroup(withoutData, hasGlyphs: false) { type in
                        NavigationLink(value: VaultRoute.dataType(type)) {
                            SomaBrowseRow(title: type.title)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                } else if !hasRead {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, metrics.leadSpacing)
                }
            }
            .padding(.horizontal, metrics.pagePadding)
            .padding(.bottom, metrics.pagePadding)
            .frame(maxWidth: metrics.pageMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background {
            // The category's hue at the top, fading into the ground: pinned to
            // the screen, so a pull never shows a band of bare ground above it.
            ZStack(alignment: .top) {
                theme.colors.canvas.color
                LinearGradient(
                    colors: [category.hue.start.color.opacity(0.55), category.hue.start.color.opacity(0)],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 340)
            }
            .ignoresSafeArea()
        }
        .navigationTitle(category.title)
#if os(iOS)
        .navigationBarTitleDisplayMode(.large)
#endif
        .task { await load() }
        .refreshable { await load() }
    }

    private func heading(_ text: LocalizedStringResource) -> some View {
        Text(text)
            .somaFont(theme.typography.title)
            .fontWeight(.bold)
            .foregroundStyle(theme.colors.inkPrimary.color)
            .accessibilityAddTraits(.isHeader)
            .padding(.horizontal, theme.metrics.browseRowPadding)
    }

    private func load() async {
        guard let source = await health.prepare(category.metrics.map(\.identifier)) else {
            hasRead = true
            return
        }
        let reader = VaultReader(source: source)
        let now = Date()
        let read = await withTaskGroup(of: (BodyDataType, VaultWeekSummary).self) { group in
            for type in category.types {
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
        summaries = read
        hasRead = true
    }
}

/// What a category card says about one data type's week.
struct VaultWeekSummary: Sendable, Equatable {
    var bars: [Double?]
    var value: String?
    var unit: String?
    var date: String?

    var hasData: Bool { value != nil || bars.contains { $0 != nil } }

    /// A sum (steps, daylight) shows its last day with readings; a reading
    /// taken at a moment (heart rate, weight) shows the latest one.
    static func make(_ metric: HealthMetric, points: [VaultPoint], latest: HealthReading?) -> VaultWeekSummary {
        let bars = points.map(\.value)
        let isSum = metric.kind == .quantity && metric.aggregation == .cumulative
        let isCount = metric.kind == .category
        let dateStyle = Date.FormatStyle().month(.abbreviated).day()

        if isSum || isCount, let last = points.last(where: { $0.value != nil }), let value = last.value {
            return VaultWeekSummary(
                bars: bars,
                value: VaultFormat.number(isCount ? value : VaultFormat.scaled(value, unit: metric.unit)),
                unit: isCount ? String(localized: "records") : metric.unit.shortLabel,
                date: last.interval.start.formatted(dateStyle)
            )
        }
        if let latest {
            let formatted = VaultFormat.value(of: latest, metric: metric)
            return VaultWeekSummary(bars: bars, value: formatted.value, unit: formatted.unit, date: latest.end.formatted(dateStyle))
        }
        return VaultWeekSummary(bars: bars, value: nil, unit: nil, date: nil)
    }
}

#if DEBUG
#Preview("Category") {
    NavigationStack {
        BodyCategoryPage(category: BodyCatalog.categories[4])
    }
    .environment(HealthDashboard(source: VaultPreviewSource()))
}
#endif
