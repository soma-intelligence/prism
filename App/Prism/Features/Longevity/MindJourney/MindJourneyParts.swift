//
//  MindJourneyParts.swift
//  Prism
//
//  The pieces Mind's deeper pages share: a value on its usual range, a card
//  of such rows, a chip, a wide button and a sheet's frame.
//

import SwiftUI
import SomaUI

/// A value against its usual range: the range as a band on a track, the
/// value as a dot, in the danger ink when it sits on the side that costs.
struct MindUsualTrack: View {
    let value: Double?
    let usual: ClosedRange<Double>?
    var isCost = false
    /// Clock hours to mark with ticks instead of a dot, over a 24 hour track.
    var marks: [Double] = []

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics
        let colors = theme.colors
        let hue = theme.aspects[.mind].identity.color

        GeometryReader { proxy in
            let width = proxy.size.width
            let scale = scale
            let midY = proxy.size.height / 2
            let track = metrics.chartTrackHeight
            let x: (Double) -> CGFloat = { v in
                width * CGFloat((min(max(v, scale.lowerBound), scale.upperBound) - scale.lowerBound) / max(scale.upperBound - scale.lowerBound, 0.0001))
            }
            ZStack(alignment: .topLeading) {
                Capsule().fill(colors.surfaceRecessed.color)
                    .frame(width: width, height: track)
                    .offset(y: midY - track / 2)
                if let usual {
                    Capsule().fill(hue.opacity(metrics.chartSpreadOpacity + 0.3))
                        .frame(width: max(x(usual.upperBound) - x(usual.lowerBound), track), height: track)
                        .offset(x: x(usual.lowerBound), y: midY - track / 2)
                }
                ForEach(Array(marks.enumerated()), id: \.offset) { _, hour in
                    Capsule().fill(hue)
                        .frame(width: metrics.chartMarkerWidth, height: metrics.chartMarkerHeight)
                        .offset(x: x(hour) - metrics.chartMarkerWidth / 2, y: midY - metrics.chartMarkerHeight / 2)
                }
                if marks.isEmpty, let value {
                    let dot = metrics.chartEstimateDiameter
                    Circle()
                        .fill(isCost ? colors.danger.color : colors.inkPrimary.color)
                        .frame(width: dot, height: dot)
                        .background(Circle().fill(colors.surface.color).padding(-2))
                        .offset(x: x(value) - dot / 2, y: midY - dot / 2)
                }
            }
        }
        .frame(height: metrics.chartEstimateDiameter + 4)
        .accessibilityHidden(true)
    }

    /// The span shown: the usual range and the value, with room either side.
    private var scale: ClosedRange<Double> {
        if !marks.isEmpty { return 0...24 }
        let points = [value, usual?.lowerBound, usual?.upperBound].compactMap { $0 }
        guard let low = points.min(), let high = points.max() else { return 0...1 }
        let pad = max((high - low) * 0.6, abs(high) * 0.05, 0.5)
        return (low - pad)...(high + pad)
    }
}

/// One signal row: title and its usual, the value, and the track.
struct MindSignalRowView: View {
    let row: MindSignalRow

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let type = theme.typography
        let colors = theme.colors

        HStack(alignment: .center, spacing: theme.metrics.moveRowGap) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .somaFont(type.body)
                    .foregroundStyle(colors.inkPrimary.color)
                if let detail = row.detail {
                    Text(detail)
                        .somaFont(type.caption)
                        .foregroundStyle(colors.inkSecondary.color)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: theme.metrics.spaceS) {
                SomaNumber(row.value, type.rowValue)
                    .foregroundStyle(row.isCost ? colors.danger.color : colors.inkPrimary.color)
                if row.usual != nil || !row.marks.isEmpty {
                    MindUsualTrack(value: row.number, usual: row.usual, isCost: row.isCost, marks: row.marks)
                        .frame(width: theme.metrics.aspectChartWidth)
                }
            }
        }
        .padding(.vertical, theme.metrics.browseRowVerticalPadding)
        .accessibilityElement(children: .combine)
    }
}

/// A card of rows under a header, with hairlines between them.
struct MindRowsCard<Row: Identifiable, RowView: View>: View {
    let title: LocalizedStringResource
    var caption: LocalizedStringResource?
    let rows: [Row]
    @ViewBuilder let row: (Row) -> RowView

    @Environment(\.somaTheme) private var theme

    var body: some View {
        SomaCard {
            VStack(alignment: .leading, spacing: theme.metrics.cardHeaderSpacing + 4) {
                SomaCardHeader(title, caption: caption)
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { MindHairline() }
                        row(item)
                    }
                }
            }
        }
    }
}

struct MindHairline: View {
    @Environment(\.somaTheme) private var theme

    var body: some View {
        Rectangle()
            .fill(theme.colors.inkPrimary.color.opacity(theme.metrics.hairlineOpacity))
            .frame(height: 0.5)
    }
}

/// A word to tap: a feeling, a theme, an answer.
struct MindChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let colors = theme.colors
        Button(action: action) {
            Text(title)
                .somaFont(theme.typography.body)
                .foregroundStyle(isSelected ? colors.accent.color : colors.inkPrimary.color)
                .padding(.horizontal, theme.metrics.cardPadding - 4)
                .frame(minHeight: theme.metrics.minimumTapTarget)
                .background(Capsule().fill(isSelected ? colors.inkPrimary.color.opacity(theme.metrics.selectionFillOpacity) : colors.surface.color))
                .contentShape(.capsule)
        }
        .buttonStyle(SomaGlassPressStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Chips that wrap onto as many lines as they need.
struct MindChipFlow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(proposal.width ?? .infinity, subviews)
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(bounds.width, subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(_ width: CGFloat, _ subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = rows[rows.count - 1].indices.isEmpty ? size.width : rows[rows.count - 1].width + spacing + size.width
            if needed > width, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            let current = rows[rows.count - 1]
            rows[rows.count - 1].width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            rows[rows.count - 1].height = max(current.height, size.height)
            rows[rows.count - 1].indices.append(index)
        }
        return rows
    }
}

/// A full width capsule button. The primary one is the screen's one filled
/// accent shape.
struct MindWideButton: View {
    let title: String
    var isPrimary = true
    var isEnabled = true
    let action: () -> Void

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let colors = theme.colors
        let metrics = theme.metrics
        Button(action: action) {
            Text(title)
                .somaFont(theme.typography.body)
                .foregroundStyle(isPrimary ? colors.onAccent.color : colors.inkPrimary.color)
                .frame(maxWidth: .infinity, minHeight: metrics.minimumTapTarget + 8)
                .background(Capsule().fill(isPrimary ? colors.accent.color : colors.surface.color))
                .opacity(isEnabled ? 1 : 0.4)
                .contentShape(.capsule)
        }
        .buttonStyle(SomaGlassPressStyle())
        .disabled(!isEnabled)
    }
}

/// A plain text button: "Not now", "Write instead".
struct MindQuietButton: View {
    let title: String
    let action: () -> Void

    @Environment(\.somaTheme) private var theme

    var body: some View {
        Button(action: action) {
            Text(title)
                .somaFont(theme.typography.body)
                .foregroundStyle(theme.colors.inkSecondary.color)
                .frame(maxWidth: .infinity, minHeight: theme.metrics.minimumTapTarget)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

/// An eyebrow set above a group of cards.
struct MindEyebrow: View {
    let text: String

    @Environment(\.somaTheme) private var theme

    var body: some View {
        Text(text)
            .somaFont(theme.typography.eyebrow)
            .foregroundStyle(theme.colors.inkSecondary.color)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A sheet's frame: its own navigation bar with a way out, the canvas under
/// it, and the content scrolling.
struct MindSheetFrame<Content: View, Footer: View>: View {
    let title: String
    var closeTitle = "Cancel"
    @ViewBuilder let content: () -> Content
    @ViewBuilder let footer: () -> Footer

    @Environment(\.somaTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            SomaPageScroll {
                VStack(alignment: .leading, spacing: theme.metrics.leadSpacing) {
                    content()
                }
                .padding(.horizontal, theme.metrics.pagePadding)
                .padding(.bottom, theme.metrics.pagePadding)
                .frame(maxWidth: theme.metrics.pageMaxWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .softScrollEdges()
            .safeAreaInset(edge: .bottom) {
                footer()
                    .padding(.horizontal, theme.metrics.pagePadding)
                    .padding(.bottom, theme.metrics.cardSpacing)
                    .frame(maxWidth: theme.metrics.pageMaxWidth)
                    .frame(maxWidth: .infinity)
                    // The page's ground under the buttons, fading in above
                    // them, so what scrolls behind never shows through.
                    .background {
                        LinearGradient(stops: [
                            .init(color: theme.colors.canvas.color.opacity(0), location: 0),
                            .init(color: theme.colors.canvas.color, location: 0.3),
                        ], startPoint: .top, endPoint: .bottom)
                        .padding(.top, -theme.metrics.cardSpacing * 2)
                        .ignoresSafeArea(edges: .bottom)
                    }
            }
            .background(theme.colors.canvas.color.ignoresSafeArea())
            .navigationTitle(title)
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(closeTitle) { dismiss() }
                }
            }
            .tint(theme.colors.inkPrimary.color)
        }
    }
}

/// A pushed page's frame: the Mind weather behind the head, a short status
/// headline when the page has one, the stats, then the cards. A thin wrapper
/// so every deeper page reads alike and names its bar.
struct MindPage<Cards: View>: View {
    let navigationTitle: String
    var title: String? = nil
    var stats: [SomaStat] = []
    @ViewBuilder let cards: () -> Cards

    var body: some View {
        scaffold
            .navigationTitle(navigationTitle)
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
    }

    @ViewBuilder private var scaffold: some View {
        if let title {
            TabPartScaffold(aspect: .mind, eyebrow: nil, title: title, reason: nil, stats: stats, cards: cards)
        } else {
            TabPartScaffold(aspect: .mind, stats: stats, cards: cards)
        }
    }
}

enum MindFormat {
    static func whole(_ value: Double?) -> String? {
        value.map { Int($0.rounded()).formatted() }
    }

    /// Minutes as hours and minutes: 2 h 30, 45 min.
    static func duration(_ minutes: Double) -> String {
        let whole = Int(minutes.rounded())
        if whole < 60 { return "\(whole) min" }
        return whole % 60 == 0 ? "\(whole / 60) h" : "\(whole / 60) h " + String(format: "%02d", whole % 60)
    }
}
