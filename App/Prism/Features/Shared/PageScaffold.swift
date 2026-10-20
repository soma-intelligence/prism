//
//  PageScaffold.swift
//  Prism
//

import SwiftUI
import SomaUI

/// The shape every page shares: a kicker, a title, and a grid that reflows on
/// its own.
///
/// The grid is `.adaptive`, so the column count follows the width available
/// rather than a device check: one code path serves a phone, a folded cover
/// screen, an unfolded one, an iPad in Slide Over, and a resized Mac window.
///
/// It draws no chrome of its own. A tab page's top bar is the navigation bar's
/// toolbar (see `tabPageChrome`), so the scroll view already starts under it and
/// runs beneath it with the system's edge effect.
struct PageScaffold<Content: View>: View {
    let eyebrow: LocalizedStringResource
    let title: LocalizedStringResource
    let content: Content

    @Environment(\.somaTheme) private var theme

    init(
        eyebrow: LocalizedStringResource,
        title: LocalizedStringResource,
        @ViewBuilder content: () -> Content
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.content = content()
    }

    var body: some View {
        SomaPageScroll {
            VStack(alignment: .leading, spacing: theme.metrics.browseSectionSpacing) {
                VStack(alignment: .leading, spacing: theme.metrics.cardHeaderSpacing) {
                    Text(eyebrow)
                        .somaFont(theme.typography.eyebrow)
                        .textCase(.uppercase)
                        .foregroundStyle(theme.colors.inkSecondary.color)

                    Text(title)
                        .somaFont(theme.typography.display)
                        .foregroundStyle(theme.colors.inkPrimary.color)
                }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: theme.metrics.cardMinWidth), spacing: theme.metrics.cardSpacing)],
                    spacing: theme.metrics.cardSpacing
                ) {
                    content
                }
            }
            .padding(theme.metrics.pagePadding)
            .frame(maxWidth: theme.metrics.pageMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(theme.colors.canvas.color.ignoresSafeArea())
    }
}

/// The same page shape as ``PageScaffold``, laying its content into a column
/// rather than an adaptive grid.
///
/// A grid is right for cards, which tile. It is wrong for a run of browse
/// groups, which are full width by construction: at the card grid's minimum
/// width an iPad would put two settings sections side by side, and a settings
/// section that shares a row with another one stops reading as a section.
///
/// It carries no top bar of its own either: a settings page lives inside a
/// sheet, which has its own title and its own way out.
struct ListScaffold<Content: View>: View {
    let eyebrow: LocalizedStringResource
    let title: LocalizedStringResource
    let content: Content

    @Environment(\.somaTheme) private var theme

    init(
        eyebrow: LocalizedStringResource,
        title: LocalizedStringResource,
        @ViewBuilder content: () -> Content
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.content = content()
    }

    var body: some View {
        SomaPageScroll {
            VStack(alignment: .leading, spacing: theme.metrics.browseSectionSpacing) {
                VStack(alignment: .leading, spacing: theme.metrics.cardHeaderSpacing) {
                    Text(eyebrow)
                        .somaFont(theme.typography.eyebrow)
                        .textCase(.uppercase)
                        .foregroundStyle(theme.colors.inkSecondary.color)

                    Text(title)
                        .somaFont(theme.typography.display)
                        .foregroundStyle(theme.colors.inkPrimary.color)
                }

                content
            }
            .padding(theme.metrics.pagePadding)
            // The navigation bar already reserves the sheet's top safe area.
            .frame(maxWidth: theme.metrics.pageMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(theme.colors.canvas.color.ignoresSafeArea())
    }
}

/// A card that states one value and what it means.
struct MetricCard: View {
    let eyebrow: LocalizedStringKey
    let value: String
    let unit: String
    let note: LocalizedStringKey

    @Environment(\.somaTheme) private var theme

    var body: some View {
        SomaCard {
            VStack(alignment: .leading, spacing: 8) {
                Text(eyebrow)
                    .somaFont(theme.typography.eyebrow)
                    .textCase(.uppercase)
                    .foregroundStyle(theme.colors.inkSecondary.color)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value)
                        .somaFont(theme.typography.metric)
                    Text(unit)
                        .somaFont(theme.typography.caption)
                        .foregroundStyle(theme.colors.inkSecondary.color)
                }
                .foregroundStyle(theme.colors.inkPrimary.color)

                Text(note)
                    .somaFont(theme.typography.caption)
                    .foregroundStyle(theme.colors.inkSecondary.color)
            }
        }
    }
}

/// A card that carries a sentence rather than a number.
struct NoteCard: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey

    @Environment(\.somaTheme) private var theme

    var body: some View {
        SomaCard {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .somaFont(theme.typography.title)
                    .foregroundStyle(theme.colors.inkPrimary.color)

                Text(message)
                    .somaFont(theme.typography.body)
                    .foregroundStyle(theme.colors.inkSecondary.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
