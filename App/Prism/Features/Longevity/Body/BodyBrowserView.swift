//
//  BodyBrowserView.swift
//  Prism
//

import SwiftUI
import SomaUI

/// The Vault: every category Apple Health holds, and the field that finds one,
/// laid out the way Apple Health lays out Browse: a search field that is
/// always on screen, and the catalog as one long list of categories. Each data
/// type opens onto its chart and every record behind it.
///
/// A list and not the card grid the parts use. The parts answer "how am I";
/// this page answers "where is X", and for that the eye wants a single column
/// it can run down, with every row starting at the same x.
///
/// The chrome is the system's own: the stack's bar and push, `.searchable` for
/// the field. Anything hand built here would be a second-best copy of a control
/// the person already knows, and on this screen the control is most of the
/// design.
struct BodyBrowserView: View {
    @Environment(HealthDashboard.self) private var health
    @Environment(\.somaTheme) private var theme

    @State private var query = ""

    private var matchedCategories: [BodyCategory] { BodyCatalog.searchCategories(query) }
    private var matchedTypes: [BodyDataType] { BodyCatalog.search(query) }
    private var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: theme.metrics.cardSpacing) {
                if isSearching {
                    results
                } else {
                    Text("Health Categories")
                        .somaFont(theme.typography.title)
                        .fontWeight(.bold)
                        .foregroundStyle(theme.colors.inkPrimary.color)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.horizontal, theme.metrics.browseRowPadding)

                    // iOS 27 Health's Browse: two columns of gradient tiles.
                    LazyVGrid(
                        columns: [GridItem(.flexible(), spacing: theme.metrics.cardSpacing), GridItem(.flexible(), spacing: theme.metrics.cardSpacing)],
                        spacing: theme.metrics.cardSpacing
                    ) {
                        ForEach(BodyCatalog.categories) { category in
                            NavigationLink(value: VaultRoute.category(category)) {
                                SomaCategoryTile(
                                    symbol: category.symbol,
                                    title: LocalizedStringResource(stringLiteral: category.title),
                                    hue: category.hue
                                )
                            }
                            .buttonStyle(.somaGlassPress)
                        }
                    }

                    // What Soma works out of Health: the scores and the
                    // night's parts, each on the same page as a Health type.
                    SomaBrowseSection("Soma", items: ScoreMetric.allCases, hasGlyphs: false) { score in
                        NavigationLink(value: VaultRoute.score(score)) {
                            SomaBrowseRow(title: score.title).contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, theme.metrics.browseSectionSpacing)
                }
            }
            .padding(theme.metrics.pagePadding)
            .frame(maxWidth: theme.metrics.pageMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(theme.colors.canvas.color.ignoresSafeArea())
        .navigationTitle("Vault")
#if os(iOS)
        .navigationBarTitleDisplayMode(.large)
#endif
        .refreshable { await health.load() }
        .searchableForBrowse(text: $query)
        .task { await health.start() }
    }

    /// What the search field turns the page into: the categories whose name
    /// matches, then the data types, which is the order a person scans them in.
    @ViewBuilder
    private var results: some View {
        if matchedCategories.isEmpty && matchedTypes.isEmpty {
            VStack(spacing: 6) {
                Text("No Results")
                    .somaFont(theme.typography.title)
                    .fontWeight(.bold)
                    .foregroundStyle(theme.colors.inkPrimary.color)
                Text("Nothing in Apple Health goes by that name.")
                    .somaFont(theme.typography.body)
                    .foregroundStyle(theme.colors.inkSecondary.color)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, theme.metrics.browseSectionSpacing)
        } else {
            if !matchedCategories.isEmpty {
                SomaBrowseSection("Categories", items: matchedCategories) { category in
                    NavigationLink(value: VaultRoute.category(category)) {
                        SomaBrowseRow(symbol: category.symbol, title: category.title)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }

            if !matchedTypes.isEmpty {
                SomaBrowseSection("Data Types", items: matchedTypes, hasGlyphs: false) { type in
                    NavigationLink(value: VaultRoute.dataType(type)) {
                        SomaBrowseRow(title: type.title, detail: health.rowValue(for: type.metric))
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
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
