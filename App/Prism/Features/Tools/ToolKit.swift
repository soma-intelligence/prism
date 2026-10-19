//
//  ToolKit.swift
//  Prism
//

import SwiftUI
import SomaUI

// The pieces every tool page is built from. Each is driven by its inputs and
// the theme alone; the pages differ in what they say, not in how they say it.

/// A tool's page: one column under the navigation bar, the canvas behind it.
///
/// A column rather than the card grid of `PageScaffold`: a tool reads top to
/// bottom, the verdict first and the reasons under it, and a grid would set a
/// chart beside the sentence that explains it.
struct ToolPage<Content: View>: View {
    let title: String
    let content: Content

    @Environment(\.somaTheme) private var theme

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        let metrics = theme.metrics
        ScrollView {
            VStack(alignment: .leading, spacing: metrics.cardSpacing) {
                content
            }
            .padding(.horizontal, metrics.pagePadding)
            .padding(.top, metrics.cardSpacing)
            .padding(.bottom, metrics.pagePadding)
            .frame(maxWidth: metrics.pageMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(theme.colors.canvas.color.ignoresSafeArea())
        .navigationTitle(title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

/// Small capitals over a section, the way every group on a tool page opens.
struct ToolEyebrow: View {
    let text: String

    @Environment(\.somaTheme) private var theme

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .somaFont(theme.typography.eyebrow)
            .textCase(.uppercase)
            .foregroundStyle(theme.colors.inkSecondary.color)
            .accessibilityAddTraits(.isHeader)
            .padding(.top, theme.metrics.cardSpacing)
    }
}

/// A sentence whose first part is in ink and the rest in grey: the reason
/// under a headline, and the body of a note card.
struct ToolReason: View {
    let lead: String
    let rest: String?

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let colors = theme.colors
        let text = Text(lead).foregroundStyle(colors.inkPrimary.color)
            + Text(rest.map { " " + $0 } ?? "").foregroundStyle(colors.inkSecondary.color)
        text
            .somaFont(theme.typography.body)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// What a tool page opens with: an eyebrow and the verdict in one line. The
/// reason is not drawn (owner, 2026-10-03: fewer words); VoiceOver reads it as
/// the headline's hint.
struct ToolHero: View {
    let eyebrow: String?
    let headline: String
    let lead: String?
    let rest: String?

    @Environment(\.somaTheme) private var theme

    init(eyebrow: String? = nil, headline: String, lead: String? = nil, rest: String? = nil) {
        self.eyebrow = eyebrow
        self.headline = headline
        self.lead = lead
        self.rest = rest
    }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.metrics.cardHeaderSpacing) {
            if let eyebrow {
                Text(eyebrow)
                    .somaFont(theme.typography.eyebrow)
                    .textCase(.uppercase)
                    .foregroundStyle(theme.colors.inkSecondary.color)
            }
            Text(headline)
                .somaFont(theme.typography.title)
                .foregroundStyle(theme.colors.inkPrimary.color)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityHint(lead.map { [$0, rest].compactMap { $0 }.joined(separator: " ") } ?? "")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Three numbers under a hairline, the row that follows a headline.
struct ToolStats: View {
    let stats: [SomaStat]

    @Environment(\.somaTheme) private var theme

    init(_ stats: [SomaStat]) { self.stats = stats }

    var body: some View {
        VStack(spacing: theme.metrics.cardSpacing) {
            ToolHairline()
            SomaStatRow(stats)
        }
        .padding(.vertical, theme.metrics.cardHeaderSpacing)
    }
}

/// One line of hairline, the separator between rows and under a headline.
struct ToolHairline: View {
    @Environment(\.somaTheme) private var theme

    var body: some View {
        Rectangle()
            .fill(theme.colors.inkPrimary.color.opacity(theme.metrics.hairlineOpacity))
            .frame(height: 1)
    }
}

/// A caption in grey under a card: the method, the caveat, the source.
struct ToolFootnote: View {
    let text: String

    @Environment(\.somaTheme) private var theme

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .somaFont(theme.typography.caption)
            .foregroundStyle(theme.colors.inkSecondary.color)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A card that carries a title and its first sentence. The grey rest is not
/// drawn (owner, 2026-10-03: fewer words).
struct ToolNoteCard: View {
    let title: String?
    let lead: String
    let rest: String?
    let foot: String?

    @Environment(\.somaTheme) private var theme

    init(title: String? = nil, lead: String, rest: String? = nil, foot: String? = nil) {
        self.title = title
        self.lead = lead
        self.rest = rest
        self.foot = foot
    }

    var body: some View {
        SomaCard {
            VStack(alignment: .leading, spacing: theme.metrics.cardHeaderSpacing) {
                if let title {
                    Text(title)
                        .somaFont(theme.typography.body)
                        .foregroundStyle(theme.colors.inkPrimary.color)
                }
                ToolReason(lead: lead, rest: nil)
                if let foot {
                    ToolFootnote(foot)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// How a value in a row reads: plain, worse than usual, or a chosen state.
enum ToolTone: Sendable {
    case plain, danger, accent
}

/// A usual band on a rail and today's value as a dot, for rows read against
/// the person's own range.
struct ToolBand: Equatable, Sendable {
    /// The rail's ends.
    var range: ClosedRange<Double>
    /// The usual band, when there is one.
    var usual: ClosedRange<Double>?
    var value: Double?
}

/// One row of a card: what it is, a second line, the value, and optionally
/// the value against its usual band.
struct ToolRow: Identifiable {
    var id: String { title + (detail ?? "") }
    var title: String
    var detail: String? = nil
    var value: String? = nil
    var tone: ToolTone = .plain
    var detailTone: ToolTone = .plain
    var band: ToolBand? = nil
}

/// A card of rows with hairlines between them, an optional title and eyebrow
/// over them.
struct ToolRowsCard: View {
    let title: String?
    let eyebrow: String?
    let rows: [ToolRow]
    let aspect: SomaAspect

    @Environment(\.somaTheme) private var theme

    init(title: String? = nil, eyebrow: String? = nil, aspect: SomaAspect = .sleep, rows: [ToolRow]) {
        self.title = title
        self.eyebrow = eyebrow
        self.aspect = aspect
        self.rows = rows
    }

    var body: some View {
        SomaCard {
            VStack(alignment: .leading, spacing: theme.metrics.cardHeaderSpacing) {
                if let title {
                    Text(title)
                        .somaFont(theme.typography.body)
                        .foregroundStyle(theme.colors.inkPrimary.color)
                }
                if let eyebrow {
                    Text(eyebrow)
                        .somaFont(theme.typography.eyebrow)
                        .textCase(.uppercase)
                        .foregroundStyle(theme.colors.inkSecondary.color)
                }
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    if index > 0 { ToolHairline() }
                    ToolRowView(row: row, aspect: aspect)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct ToolRowView: View {
    let row: ToolRow
    let aspect: SomaAspect

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let type = theme.typography
        let colors = theme.colors

        HStack(alignment: .top, spacing: theme.metrics.moveRowGap) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .somaFont(type.body)
                    .foregroundStyle(colors.inkPrimary.color)
                if let detail = row.detail {
                    Text(detail)
                        .somaFont(type.caption)
                        .foregroundStyle(tint(row.detailTone, fallback: colors.inkSecondary.color))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 6) {
                Text(row.value ?? "-")
                    .somaFont(type.rowValue)
                    .foregroundStyle(tint(row.tone, fallback: colors.inkPrimary.color))
                if let band = row.band {
                    ToolBandRail(band: band, aspect: aspect, isBad: row.tone == .danger)
                        .frame(width: theme.metrics.aspectChartWidth, height: theme.metrics.chartDotDiameter + 4)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private func tint(_ tone: ToolTone, fallback: Color) -> Color {
        switch tone {
        case .plain: fallback
        case .danger: theme.colors.danger.color
        case .accent: theme.colors.accent.color
        }
    }
}

/// The rail itself: a recessed track, the usual band in the aspect's hue, and
/// the value as a dot.
struct ToolBandRail: View {
    let band: ToolBand
    let aspect: SomaAspect
    let isBad: Bool

    @Environment(\.somaTheme) private var theme

    var body: some View {
        Canvas { context, size in
            let track = theme.metrics.chartTrackHeight
            let span = max(band.range.upperBound - band.range.lowerBound, .ulpOfOne)
            func x(_ value: Double) -> CGFloat {
                let clamped = min(max(value, band.range.lowerBound), band.range.upperBound)
                return size.width * CGFloat((clamped - band.range.lowerBound) / span)
            }
            let midY = size.height / 2
            context.fill(Path(roundedRect: CGRect(x: 0, y: midY - track / 2, width: size.width, height: track),
                              cornerRadius: track / 2),
                         with: .color(theme.colors.surfaceRecessed.color))
            if let usual = band.usual {
                let from = x(usual.lowerBound), to = x(usual.upperBound)
                context.fill(Path(roundedRect: CGRect(x: from, y: midY - track / 2, width: max(to - from, track), height: track),
                                  cornerRadius: track / 2),
                             with: .color(theme.aspects[aspect].identity.color.opacity(theme.metrics.chartSpreadOpacity * 2)))
            }
            if let value = band.value {
                let dot = theme.metrics.chartDotDiameter
                let rect = CGRect(x: x(value) - dot / 2, y: midY - dot / 2, width: dot, height: dot)
                context.fill(Path(ellipseIn: rect),
                             with: .color(isBad ? theme.colors.danger.color : theme.colors.inkPrimary.color))
            }
        }
        .accessibilityHidden(true)
    }
}

/// A row that opens something: a title, a value, a chevron, on its own card.
struct ToolLinkRow<Value: Hashable>: View {
    let title: String
    let detail: String?
    let value: Value

    var body: some View {
        NavigationLink(value: value) {
            ToolLinkLabel(title: title, detail: detail)
        }
        .buttonStyle(TilePressStyle())
    }
}

/// A row that runs an action rather than pushing a page.
struct ToolButtonRow: View {
    let title: String
    let detail: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ToolLinkLabel(title: title, detail: detail)
        }
        .buttonStyle(TilePressStyle())
    }
}

struct ToolLinkLabel: View {
    let title: String
    let detail: String?

    @Environment(\.somaTheme) private var theme

    var body: some View {
        SomaCard {
            HStack(spacing: theme.metrics.moveRowGap) {
                Text(title)
                    .somaFont(theme.typography.body)
                    .foregroundStyle(theme.colors.inkPrimary.color)
                Spacer(minLength: 0)
                if let detail {
                    Text(detail)
                        .somaFont(theme.typography.rowValue)
                        .foregroundStyle(theme.colors.inkSecondary.color)
                }
                Image(systemName: "chevron.right")
                    .somaFont(theme.typography.caption)
                    .foregroundStyle(theme.colors.inkSecondary.color)
            }
        }
        .contentShape(.rect)
    }
}

/// The one next thing a tool offers, with the aspect's mini orb beside it.
struct ToolNextCard: View {
    let eyebrow: String
    let aspect: SomaAspect
    let title: String
    let detail: String?
    let actionTitle: String?
    let action: (() -> Void)?

    @Environment(\.somaTheme) private var theme

    var body: some View {
        SomaActionCard(eyebrow: eyebrow, title: title, detail: detail,
                       actionTitle: actionTitle, action: action) {
            PulseMiniOrb(aspect: aspect, diameter: theme.metrics.checkDiameter * 1.6)
        }
    }
}

/// A card that waits on data: what it is, a dash, and what fills it.
struct ToolEmptyCard: View {
    let eyebrow: String
    let message: String

    var body: some View {
        SomaChartCard(eyebrow: eyebrow, value: nil, note: message) { EmptyView() }
    }
}
