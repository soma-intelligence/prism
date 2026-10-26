//
//  OnboardingScaffold.swift
//  Prism
//

import SwiftUI
import SomaUI

/// An action at the foot of a step.
struct OnboardingButton {
    let title: String
    var isEnabled = true
    let action: () -> Void

    init(_ title: String, isEnabled: Bool = true, action: @escaping () -> Void) {
        self.title = title
        self.isEnabled = isEnabled
        self.action = action
    }
}

/// A sentence in ink followed by the rest in grey, as one paragraph.
struct OnboardingLead: View {
    var lead: String?
    var rest: String?

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let colors = theme.colors
        let first = Text(lead ?? "").foregroundStyle(colors.inkPrimary.color)
        let second = Text(rest ?? "").foregroundStyle(colors.inkSecondary.color)
        let space = lead != nil && rest != nil ? " " : ""

        Text("\(first)\(space)\(second)")
            .somaFont(theme.typography.callout)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The footnote, the accent button and the quiet second choice.
struct OnboardingFooter: View {
    var footnote: String?
    let primary: OnboardingButton
    var secondary: OnboardingButton?

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics

        VStack(spacing: 12) {
            if let footnote {
                Text(footnote)
                    .somaFont(theme.typography.caption)
                    .foregroundStyle(theme.colors.inkSecondary.color)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            OnboardingPrimaryButton(button: primary)
            if let secondary {
                OnboardingQuietButton(button: secondary)
            }
        }
        .padding(.horizontal, metrics.pagePadding)
        .padding(.top, theme.metrics.spaceS)
        .padding(.bottom, theme.metrics.spaceM)
        .frame(maxWidth: metrics.pageMaxWidth)
        .frame(maxWidth: .infinity)
    }
}

/// The accent capsule: the one primary action on a step.
struct OnboardingPrimaryButton: View {
    let button: OnboardingButton

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let colors = theme.colors

        Button(action: button.action) {
            Text(button.title)
                .somaFont(theme.typography.body)
                .foregroundStyle(colors.onAccent.color)
                .frame(maxWidth: .infinity, minHeight: theme.metrics.minimumTapTarget + 4)
                .background(Capsule().fill(colors.accent.color))
                .contentShape(.capsule)
        }
        .buttonStyle(.somaGlassPress)
        .disabled(!button.isEnabled)
        .opacity(button.isEnabled ? 1 : 0.4)
    }
}

/// A second choice set as a plain line in grey: Later, Skip.
struct OnboardingQuietButton: View {
    let button: OnboardingButton

    @Environment(\.somaTheme) private var theme

    var body: some View {
        Button(action: button.action) {
            Text(button.title)
                .somaFont(theme.typography.callout)
                .foregroundStyle(theme.colors.inkSecondary.color)
                .frame(minHeight: theme.metrics.minimumTapTarget)
                .padding(.horizontal, theme.metrics.cardPadding)
                .contentShape(.rect)
        }
        .buttonStyle(.somaGlassPressDim)
    }
}

/// A capsule outlined with the hairline: a second way in, never the accent.
struct OnboardingOutlineButton<Label: View>: View {
    let action: () -> Void
    @ViewBuilder var label: () -> Label

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let colors = theme.colors

        Button(action: action) {
            label()
                .somaFont(theme.typography.body)
                .foregroundStyle(colors.inkPrimary.color)
                .frame(maxWidth: .infinity, minHeight: theme.metrics.minimumTapTarget + 4)
                .overlay(
                    Capsule().strokeBorder(colors.inkPrimary.color.opacity(theme.metrics.hairlineOpacity * 2), lineWidth: 1)
                )
                .contentShape(.capsule)
        }
        .buttonStyle(.somaGlassPress)
    }
}

/// One row of a screen's card: a lead mark, a title, a grey line, and an
/// optional control at the trailing edge.
struct OnboardingRow<Lead: View, Trailing: View>: View {
    let title: String
    let detail: String
    @ViewBuilder var lead: () -> Lead
    @ViewBuilder var trailing: () -> Trailing

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let colors = theme.colors
        let type = theme.typography

        HStack(alignment: .center, spacing: theme.metrics.spaceM) {
            lead()
                .frame(width: theme.metrics.miniOrbDiameter)
            VStack(alignment: .leading, spacing: theme.metrics.spaceXS) {
                Text(title)
                    .somaFont(type.callout)
                    .foregroundStyle(colors.inkPrimary.color)
                Text(detail)
                    .somaFont(type.caption)
                    .foregroundStyle(colors.inkSecondary.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            trailing()
        }
    }
}

extension OnboardingRow where Trailing == EmptyView {
    init(title: String, detail: String, @ViewBuilder lead: @escaping () -> Lead) {
        self.init(title: title, detail: detail, lead: lead, trailing: { EmptyView() })
    }
}

/// A card of rows with hairlines between them.
struct OnboardingRowsCard<Item: Identifiable, Row: View>: View {
    let items: [Item]
    @ViewBuilder var row: (Item) -> Row

    @Environment(\.somaTheme) private var theme

    var body: some View {
        SomaCard {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 {
                        Rectangle()
                            .fill(theme.colors.inkPrimary.color.opacity(theme.metrics.browseSeparatorOpacity))
                            .frame(height: 0.5)
                            .padding(.vertical, theme.metrics.spaceM)
                    }
                    row(item)
                }
            }
        }
    }
}

/// An SF Symbol set at the size a row's lead mark takes.
struct OnboardingGlyph: View {
    let symbol: String

    @Environment(\.somaTheme) private var theme

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: theme.metrics.browseGlyphSize))
            .foregroundStyle(theme.colors.inkPrimary.color)
            .frame(height: theme.metrics.miniOrbDiameter * 0.7)
            .accessibilityHidden(true)
    }
}

/// A plain note in a card: the declined states and the honest "not
/// connected yet" lines.
struct OnboardingNote: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        SomaCard {
            OnboardingRow(title: title, detail: detail) {
                OnboardingGlyph(symbol: symbol)
            }
        }
    }
}

/// Answer chips that wrap onto as many lines as they need.
struct OnboardingChipFlow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = rows[rows.count - 1].indices.isEmpty ? size.width : rows[rows.count - 1].width + spacing + size.width
            if needed > width, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows.filter { !$0.indices.isEmpty }
    }
}

/// One answer as a capsule. Chosen is a tonal step with the accent on the
/// words, never an accent fill.
struct OnboardingChip: View {
    let title: String
    let isOn: Bool
    /// Stretches to share a row evenly with its neighbours instead of
    /// hugging its words.
    var fills = false
    let action: () -> Void

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let colors = theme.colors
        let metrics = theme.metrics

        Button(action: action) {
            Text(title)
                .somaFont(theme.typography.callout)
                .foregroundStyle(isOn ? colors.accent.color : colors.inkPrimary.color)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, metrics.spaceM)
                .frame(maxWidth: fills ? .infinity : nil, minHeight: metrics.minimumTapTarget * 0.9)
                .background(Capsule().fill(isOn ? colors.surface.color : Color.clear))
                .overlay(
                    Capsule().strokeBorder(
                        colors.inkPrimary.color.opacity(isOn ? metrics.hairlineOpacity : metrics.browseSeparatorOpacity),
                        lineWidth: 1
                    )
                )
                .contentShape(.capsule)
        }
        .buttonStyle(.somaGlassPress)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
