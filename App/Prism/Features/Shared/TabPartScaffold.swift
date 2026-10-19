//
//  TabPartScaffold.swift
//  Prism
//

import SwiftUI
import SomaUI

/// The shape the tab parts and their deeper pages share: the aspect's weather
/// behind the head of the page, an optional headline, a row of three stats,
/// then the cards in one column.
///
/// The lenses lead with the stats and no headline (owner, 2026-10-03: fewer
/// words, the numbers and charts say it); the deeper pages still carry one.
///
/// Like ``PageScaffold`` it draws no chrome: the top bar is the navigation
/// bar's toolbar, so the page scrolls under it, and the weather runs up behind
/// the bar to the top of the screen.
struct TabPartScaffold<Cards: View>: View {
    let aspect: SomaAspect?
    let hero: SomaPageHero?
    let stats: [SomaStat]
    let cards: Cards

    @Environment(\.somaTheme) private var theme

    init(
        aspect: SomaAspect?,
        eyebrow: String?,
        title: String,
        reason: String?,
        stats: [SomaStat],
        @ViewBuilder cards: () -> Cards
    ) {
        self.aspect = aspect
        self.hero = SomaPageHero(eyebrow: eyebrow, title: title, reason: reason)
        self.stats = stats
        self.cards = cards()
    }

    /// No headline: the page opens on its stats, the way the Body lens does.
    init(
        aspect: SomaAspect?,
        stats: [SomaStat],
        @ViewBuilder cards: () -> Cards
    ) {
        self.aspect = aspect
        self.hero = nil
        self.stats = stats
        self.cards = cards()
    }

    var body: some View {
        let metrics = theme.metrics

        ScrollView {
            VStack(alignment: .leading, spacing: metrics.leadSpacing) {
                if let hero {
                    hero
                        .padding(.top, metrics.heroTopPadding)
                }
                if !stats.isEmpty {
                    SomaStatRow(stats)
                        .padding(.top, hero == nil ? metrics.heroTopPadding : 0)
                }
                VStack(alignment: .leading, spacing: metrics.cardSpacing) {
                    cards
                }
            }
            .padding(.horizontal, metrics.pagePadding)
            .padding(.bottom, metrics.pagePadding)
            .frame(maxWidth: metrics.pageMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .aspectWash(aspect)
    }
}
