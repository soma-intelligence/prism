//
//  BodyCategoryPage.swift
//  Prism
//

import SwiftUI
import SomaUI
import HealthExportCore

/// One Health category, set in Soma's own language rather than Health's
/// (owner, 2026-10-20: the category pages looked too much like Apple
/// Health): the aspect's soft wash behind an inline title, a head with the
/// aspect's glyph and how many measures read this week, then the measures
/// with readings as quiet rows on one card (the name, when it was read, the
/// week as a small line in the aspect's tone, the latest value), and the
/// rest as plain names under "Nothing yet". The same rows a score page
/// lists its readings with, so a category reads like the pages around it.
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
        let aspect = category.aspect

        SomaPageScroll {
            VStack(alignment: .leading, spacing: metrics.leadSpacing) {
                BodyCategoryHead(category: category, withData: hasRead ? withData.count : nil)

                if !withData.isEmpty {
                    section("This week") {
                        SomaBrowseGroup(withData, hasGlyphs: false) { type in
                            NavigationLink(value: VaultRoute.dataType(type)) {
                                let summary = summaries[type]
                                SomaReadingRow(
                                    title: MetricPageWords.title(identifier: type.metric.identifier, fallback: type.title),
                                    caption: summary?.date,
                                    value: summary?.value,
                                    unit: summary?.unit,
                                    week: summary?.bars ?? [],
                                    aspect: aspect
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if hasRead, !withoutData.isEmpty {
                    section("Nothing yet") {
                        SomaBrowseGroup(withoutData, hasGlyphs: false) { type in
                            NavigationLink(value: VaultRoute.dataType(type)) {
                                SomaBrowseRow(title: MetricPageWords.title(identifier: type.metric.identifier, fallback: type.title))
                                    .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } else if !hasRead {
                    ReadingRows()
                        .padding(.top, metrics.cardSpacing)
                }
            }
            .padding(.horizontal, metrics.pagePadding)
            .padding(.bottom, metrics.pagePadding)
            .frame(maxWidth: metrics.pageMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .aspectWash(aspect)
        .navigationTitle(category.title)
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .task { await load() }
        .somaRefreshable { await load() }
    }

    private func section<Content: View>(_ title: LocalizedStringResource, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: theme.metrics.cardSpacing) {
            Text(title)
                .somaFont(theme.typography.eyebrow)
                .textCase(.uppercase)
                .foregroundStyle(theme.colors.inkSecondary.color)
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }

    private func load() async {
        guard let source = await health.prepare(category.metrics.map(\.identifier)) else {
            hasRead = true
            return
        }
        summaries = await VaultWeekSummary.read(category.types, from: source, now: Date())
        hasRead = true
    }
}

/// The head of a category: the aspect's glyph on its tinted square (or the
/// category's symbol on a recessed one, for the few that belong to no
/// aspect), the category's name, and how many of its measures read this
/// week.
private struct BodyCategoryHead: View {
    let category: BodyCategory
    let withData: Int?

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics
        let colors = theme.colors

        HStack(spacing: metrics.moveRowGap) {
            if let aspect = category.aspect {
                SomaAspectGlyph(aspect, style: .badge)
            } else {
                Image(systemName: category.symbol)
                    .foregroundStyle(colors.inkSecondary.color)
                    .frame(width: metrics.aspectBadgeSide, height: metrics.aspectBadgeSide)
                    .background(RoundedRectangle(cornerRadius: metrics.aspectBadgeCornerRadius, style: .continuous)
                        .fill(colors.surfaceRecessed.color))
            }
            VStack(alignment: .leading, spacing: metrics.readingRowLineGap) {
                Text(category.title)
                    .somaFont(theme.typography.headline)
                    .foregroundStyle(colors.inkPrimary.color)
                Text(BodyCategoryPage.countLine(withData: withData, of: category.types.count))
                    .somaFont(theme.typography.caption)
                    .foregroundStyle(colors.inkSecondary.color)
            }
        }
        .padding(.top, metrics.scoreHeroTopPadding)
        .accessibilityElement(children: .combine)
    }
}

extension BodyCategoryPage {
    /// "3 of 12 measures read this week", or the count alone before the read.
    static func countLine(withData: Int?, of total: Int) -> String {
        guard let withData else { return total == 1 ? "1 measure" : "\(total) measures" }
        if withData == 0 { return "Nothing read this week" }
        return "\(withData) of \(total) read this week"
    }
}

extension BodyCategory {
    /// The aspect a category belongs to, whose glyph and tone it wears; nil
    /// for the few that belong to none (hearing, everything else).
    var aspect: SomaAspect? {
        switch title {
        case "Activity", "Mobility": .activity
        case "Body Measurements", "Cycle Tracking", "Medications", "Symptoms": .body
        case "Heart", "Vitals", "Respiratory": .heart
        case "Mental Wellbeing": .mind
        case "Nutrition": .gut
        case "Sleep": .sleep
        default: nil
        }
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
                unit: isCount ? (value == 1 ? String(localized: "record") : String(localized: "records")) : metric.unit.shortLabel,
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
