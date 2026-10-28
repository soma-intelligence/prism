//
//  BodyBrowserView.swift
//  Prism
//

import SwiftUI
import SomaUI
import HealthExportCore

/// The Vault: every category Apple Health holds and every score Soma works
/// out of it, with the field that finds one.
///
/// Set in the language of the pages around it (owner, 2026-10-20: the Vault
/// did not match the app): an inline title over a head with the Vault's
/// glyph and how much it holds, the categories as tiles that wear their
/// aspect's tone around their own line glyph, then Soma's scores and the
/// night's parts as the quiet reading rows a score page lists, each with its
/// latest value and its week. The search field stays the system's own,
/// always on screen: on a page whose job is finding one of 192 things, a
/// field that has to be found first is the wrong way round.
struct BodyBrowserView: View {
    @Environment(HealthDashboard.self) private var health
    @Environment(\.somaTheme) private var theme

    @State private var query = ""

    private var matchedCategories: [BodyCategory] { BodyCatalog.searchCategories(query) }
    private var matchedTypes: [BodyDataType] { BodyCatalog.search(query) }
    private var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static let scores = ScoreMetric.allCases.filter(\.isScore)
    private static let night = ScoreMetric.allCases.filter { !$0.isScore }

    var body: some View {
        let metrics = theme.metrics

        SomaPageScroll {
            VStack(alignment: .leading, spacing: metrics.leadSpacing) {
                if isSearching {
                    results
                } else {
                    VaultHead(
                        line: VaultWords.holds(
                            measures: BodyCatalog.measureCount,
                            scores: ScoreMetric.allCases.count
                        )
                    )

                    section("Categories") {
                        LazyVGrid(
                            columns: [GridItem(.flexible(), spacing: metrics.cardSpacing),
                                      GridItem(.flexible(), spacing: metrics.cardSpacing)],
                            spacing: metrics.cardSpacing
                        ) {
                            ForEach(BodyCatalog.categories) { category in
                                VaultLink(route: .category(category)) {
                                    SomaCategoryTile(
                                        symbol: category.lineSymbol,
                                        title: category.displayTitle,
                                        caption: VaultWords.measures(category.types.count),
                                        aspect: category.aspect
                                    )
                                }
                                .buttonStyle(.somaGlassPress)
                            }
                        }
                    }

                    // What Soma works out of Health, each on the same page as
                    // a Health type.
                    scoreSection("Scores", Self.scores)
                    scoreSection("From the night", Self.night)
                }
            }
            .padding(.horizontal, metrics.pagePadding)
            .padding(.bottom, metrics.pagePadding)
            .frame(maxWidth: metrics.pageMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .softScrollEdges()
        .background(theme.colors.canvas.color.ignoresSafeArea())
        .navigationTitle("Vault")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .refreshable {
            await health.load()
            await health.loadScores()
        }
        .searchableForBrowse(text: $query)
        .task {
            await health.start()
            await health.loadScores()
        }
    }

    private func section<Content: View>(_ title: LocalizedStringResource, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: theme.metrics.cardSpacing) {
            Text(title)
                .somaFont(theme.typography.eyebrow)
                .foregroundStyle(theme.colors.inkSecondary.color)
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }

    private func scoreSection(_ title: LocalizedStringResource, _ scores: [ScoreMetric]) -> some View {
        section(title) {
            SomaBrowseGroup(scores, hasGlyphs: false) { score in
                let summary = health.scores.map { VaultScoreSummary.make(score, days: score.days($0)) }
                VaultLink(route: .score(score)) {
                    SomaReadingRow(
                        title: score.title,
                        caption: summary?.caption,
                        value: summary?.value,
                        week: summary?.week ?? [],
                        aspect: score.aspect
                    )
                }
                .buttonStyle(.somaBrowseRow)
            }
        }
    }

    /// What the search field turns the page into: the categories whose name
    /// matches, then the measures, which is the order a person scans them in.
    @ViewBuilder
    private var results: some View {
        if matchedCategories.isEmpty && matchedTypes.isEmpty {
            VStack(spacing: theme.metrics.cardHeaderSpacing) {
                Text("Nothing found")
                    .somaFont(theme.typography.headline)
                    .foregroundStyle(theme.colors.inkPrimary.color)
                Text("No measure goes by that name")
                    .somaFont(theme.typography.caption)
                    .foregroundStyle(theme.colors.inkSecondary.color)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, theme.metrics.leadSpacing)
        } else {
            if !matchedCategories.isEmpty {
                section("Categories") {
                    SomaBrowseGroup(matchedCategories, hasGlyphs: false) { category in
                        VaultLink(route: .category(category)) {
                            SomaBrowseRow(title: category.displayTitle,
                                          detail: VaultWords.measures(category.types.count))
                                .contentShape(.rect)
                        }
                        .buttonStyle(.somaBrowseRow)
                    }
                }
            }

            if !matchedTypes.isEmpty {
                section("Measures") {
                    SomaBrowseGroup(matchedTypes, hasGlyphs: false) { type in
                        VaultLink(route: .dataType(type)) {
                            SomaBrowseRow(
                                title: MetricPageWords.title(identifier: type.metric.identifier, fallback: type.title),
                                detail: health.rowValue(for: type.metric)
                            )
                            .contentShape(.rect)
                        }
                        .buttonStyle(.somaBrowseRow)
                    }
                }
            }
        }
    }
}

/// The Vault's head, set like a category's: the Vault's glyph on a recessed
/// square and how much it holds. The name is the navigation title's alone.
private struct VaultHead: View {
    let line: String

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics
        let colors = theme.colors

        HStack(spacing: metrics.moveRowGap) {
            Image(systemName: "archivebox")
                .font(.system(size: metrics.aspectBadgeGlyph * 0.82, weight: .regular))
                .foregroundStyle(colors.inkSecondary.color)
                .frame(width: metrics.aspectBadgeSide, height: metrics.aspectBadgeSide)
                .background(RoundedRectangle(cornerRadius: metrics.aspectBadgeCornerRadius, style: .continuous)
                    .fill(colors.surfaceRecessed.color))
                .accessibilityHidden(true)
            Text(line)
                .somaFont(theme.typography.body)
                .foregroundStyle(colors.inkSecondary.color)
        }
        .padding(.top, metrics.scoreHeroTopPadding)
        .accessibilityElement(children: .combine)
    }
}

extension EnvironmentValues {
    /// Set by a host that keeps the Vault beside the page it opens (the
    /// settings sheet on a roomy screen, Apple Health's Browse on an iPad):
    /// a row then shows its page in that pane instead of pushing it.
    @Entry var vaultPane: Binding<VaultRoute?>?
}

/// A row of the Vault: pushed on the stack on a phone, shown in the pane
/// beside the list where the host keeps one, with the row it shows marked by
/// a tonal step. It sets no button style of its own: a style set here, next
/// to the button, would beat the caller's (a tile's press, a row's wash).
private struct VaultLink<Label: View>: View {
    let route: VaultRoute
    @ViewBuilder let label: Label

    @Environment(\.vaultPane) private var pane
    @Environment(\.somaTheme) private var theme

    var body: some View {
        if let pane {
            let isShown = pane.wrappedValue == route
            Button { pane.wrappedValue = route } label: {
                label.contentShape(.rect)
            }
            .background(isShown ? theme.colors.inkPrimary.color.opacity(theme.metrics.selectionFillOpacity) : .clear)
            .accessibilityAddTraits(isShown ? .isSelected : [])
        } else {
            NavigationLink(value: route) {
                label.contentShape(.rect)
            }
            .zoomSource(route)
        }
    }
}

private extension View {
    /// The search field, pinned open.
    ///
    /// Always visible rather than revealed by a pull: on a screen whose whole
    /// job is finding one of 192 things, a field that has to be found first is
    /// the wrong way round. The Mac puts its own field in the toolbar, where a
    /// drawer placement does not exist and would not belong.
    func searchableForBrowse(text: Binding<String>) -> some View {
#if os(macOS)
        searchable(text: text, prompt: "Search")
#else
        searchable(text: text, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search")
#endif
    }
}

#Preview("Vault") {
    NavigationStack {
        BodyBrowserView()
    }
    .environment(HealthDashboard())
    .environment(AppRouter())
}
