//
//  PulseArticleReader.swift
//  Prism
//

import SwiftUI
import SomaUI

/// The page an article opens to: the cover across the
/// top, a bold title and its one line, then the body set loose with room
/// between the lines, and the sources it rests on at the foot as links.
struct ArticleReader: View {
    let article: Article
    /// False only for a still render; see `ExploreScroll`.
    var scrolls = true
    /// Where the read and the save are noted, on this device only.
    var interest: ExploreInterest = .shared

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics
        let type = theme.typography
        let colors = theme.colors

        ExploreScroll(scrolls: scrolls) {
            VStack(alignment: .leading, spacing: 0) {
                SomaArticleCover(tone: article.topic.tone, mark: article.topic.mark, seed: article.slug,
                                 imageURL: article.coverImageURL, asset: article.photo?.asset, size: .reader)
                if let photo = article.photo {
                    ArticlePhotoCredit(photo: photo)
                        .padding(.top, metrics.articleTextSpacing * 2)
                }
                Color.clear.frame(height: metrics.leadSpacing)

                VStack(alignment: .leading, spacing: metrics.articleTextSpacing * 2) {
                    Text(meta)
                        .somaFont(type.eyebrow)
                        .textCase(.uppercase)
                        .foregroundStyle(colors.inkSecondary.color)
                    Text(article.title)
                        .somaFont(type.articleReaderTitle)
                        .foregroundStyle(colors.inkPrimary.color)
                        .accessibilityAddTraits(.isHeader)
                        .fixedSize(horizontal: false, vertical: true)
                    if !article.subtitle.isEmpty {
                        Text(article.subtitle)
                            .somaFont(type.body)
                            .foregroundStyle(colors.inkPrimary.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                ArticleRule()
                    .padding(.vertical, metrics.leadSpacing)

                VStack(alignment: .leading, spacing: metrics.articleBlockSpacing) {
                    ForEach(Array(ArticleMarkdown.blocks(article.body).enumerated()), id: \.offset) { _, block in
                        ArticleBlockView(block: block)
                    }
                }

                if !article.sources.isEmpty {
                    ArticleRule()
                        .padding(.vertical, metrics.leadSpacing)
                    ArticleSourceList(sources: article.sources)
                }

                Text("General wellness information, not medical advice.")
                    .somaFont(type.caption)
                    .foregroundStyle(colors.inkSecondary.color)
                    .padding(.top, metrics.leadSpacing)
            }
            .padding(.top, metrics.cardSpacing)
            .padding(.horizontal, metrics.pagePadding)
            .padding(.bottom, metrics.pagePadding * 2)
            .frame(maxWidth: metrics.pageMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(colors.canvas.color.ignoresSafeArea())
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ArticleSaveButton(isSaved: interest.isSaved(article)) {
                    interest.toggleSaved(article)
                }
            }
        }
        // Noted as the reader closes rather than as it opens: Explore holds
        // its page while covered either way, and a read noted on the way
        // out never reorders the cards under the zoom in.
        .onDisappear { interest.noteRead(article) }
    }

    /// "Sleep · 4 min · 30 Sep 2026".
    private var meta: String {
        let date = article.publishedAt.formatted(.dateTime.day().month(.abbreviated).year())
        return "\(article.topic.title) · \(article.readingTime) · \(date)"
    }
}

/// The opener for a piece linked from outside Explore.
struct PulseArticleReader: View {
    let article: PulseArticle

    var body: some View {
        ArticleReader(article: article.article)
    }
}

/// Keeps the piece in Explore's "Saved" shelf, or takes it off. The mark
/// fills when it is saved; on this device only.
private struct ArticleSaveButton: View {
    let isSaved: Bool
    let toggle: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: toggle) {
            Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
        }
        .accessibilityLabel(isSaved ? "Saved" : "Save")
        .accessibilityHint(isSaved ? "Takes it off your saved pieces" : "Keeps it in Explore under Saved")
        .sensoryFeedback(.selection, trigger: isSaved)
    }
}

/// "Photo: Name, Unsplash", a link to the photo's page when it has one.
private struct ArticlePhotoCredit: View {
    let photo: ArticlePhoto

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let line = Text(photo.line)
            .somaFont(theme.typography.caption)
            .foregroundStyle(theme.colors.inkSecondary.color)
        if let url = photo.url {
            Link(destination: url) { line }
                .buttonStyle(.somaGlassPress)
        } else {
            line
        }
    }
}

/// A hairline across the column.
private struct ArticleRule: View {
    @Environment(\.somaTheme) private var theme

    var body: some View {
        Rectangle()
            .fill(theme.colors.inkPrimary.color.opacity(theme.metrics.hairlineOpacity))
            .frame(height: 1)
            .accessibilityHidden(true)
    }
}

/// One block of an article body.
private struct ArticleBlockView: View {
    let block: ArticleBlock

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics
        let type = theme.typography
        let colors = theme.colors

        switch block {
        case .heading(let text):
            Text(text)
                .somaFont(type.articleHeading)
                .foregroundStyle(colors.inkPrimary.color)
                .accessibilityAddTraits(.isHeader)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, metrics.articleTextSpacing * 2)
        case .paragraph(let text):
            paragraph(text)
        case .quote(let text):
            HStack(alignment: .top, spacing: metrics.cardSpacing) {
                Rectangle()
                    .fill(colors.inkPrimary.color.opacity(metrics.hairlineOpacity * 3))
                    .frame(width: 2)
                paragraph(text)
            }
            .fixedSize(horizontal: false, vertical: true)
        case .bullets(let items):
            VStack(alignment: .leading, spacing: metrics.articleTextSpacing * 2) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: metrics.cardSpacing) {
                        Text("•")
                            .somaFont(type.body)
                            .foregroundStyle(colors.inkSecondary.color)
                            .accessibilityHidden(true)
                        paragraph(item)
                    }
                }
            }
        }
    }

    private func paragraph(_ text: String) -> some View {
        Text(ArticleMarkdown.inline(text))
            .somaFont(theme.typography.body)
            .lineSpacing(theme.metrics.articleBodyLineSpacing)
            .foregroundStyle(theme.colors.inkSecondary.color)
            .tint(theme.colors.inkPrimary.color)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The published work an article rests on, each a link when it has an
/// address.
private struct ArticleSourceList: View {
    let sources: [ArticleCitation]

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics
        let type = theme.typography
        let colors = theme.colors

        VStack(alignment: .leading, spacing: metrics.cardSpacing) {
            Text("Sources")
                .somaFont(type.eyebrow)
                .textCase(.uppercase)
                .foregroundStyle(colors.inkSecondary.color)
                .accessibilityAddTraits(.isHeader)

            ForEach(Array(sources.enumerated()), id: \.offset) { index, source in
                let label = HStack(alignment: .firstTextBaseline, spacing: metrics.cardSpacing) {
                    Text("\(index + 1)")
                        .somaFont(type.captionValue)
                        .foregroundStyle(colors.inkSecondary.color)
                    VStack(alignment: .leading, spacing: metrics.articleTextSpacing / 2) {
                        Text(source.title)
                            .somaFont(type.callout)
                            .foregroundStyle(colors.inkPrimary.color)
                            .fixedSize(horizontal: false, vertical: true)
                        if let publisher = source.publisher {
                            Text(publisher)
                                .somaFont(type.caption)
                                .foregroundStyle(colors.inkSecondary.color)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 0)
                    if source.url != nil {
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: metrics.browseChevronSize, weight: .semibold))
                            .foregroundStyle(colors.inkSecondary.color)
                            .accessibilityHidden(true)
                    }
                }
                .multilineTextAlignment(.leading)
                .contentShape(Rectangle())

                if let url = source.url {
                    Link(destination: url) { label }
                        .buttonStyle(.somaGlassPress)
                } else {
                    label
                }
            }
        }
    }
}

#Preview("Reader") {
    NavigationStack {
        ArticleReader(article: BundledArticles.sleepRegularity)
    }
}
