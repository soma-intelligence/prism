//
//  SomaColumns.swift
//  SomaUI
//

import SwiftUI

// MARK: - Span

/// How much of a ``SomaCardColumns`` row a child takes.
public enum SomaColumnSpan: Sendable, Equatable {
    /// One column: the child goes to whichever column is shortest.
    case one
    /// Every column: the child starts below everything above it, and what
    /// follows starts below it. For a control, a status line or a footnote,
    /// which belong to the page rather than to one column of it.
    case full
}

private struct SomaColumnSpanKey: LayoutValueKey {
    static let defaultValue = SomaColumnSpan.one
}

public extension View {
    /// Sets how much of a ``SomaCardColumns`` row this child takes. Outside the
    /// columns it does nothing.
    func somaColumnSpan(_ span: SomaColumnSpan) -> some View {
        layoutValue(key: SomaColumnSpanKey.self, value: span)
    }
}

// MARK: - Layout

/// Cards in as many columns as the width holds, each card under the shortest
/// column so far, the way an iPad page tiles them.
///
/// The column count is read from the width the layout is offered, never from
/// the device: a phone gets one column, the inner screen of a foldable and an
/// iPad get two, and a window resized across the line reflows live without
/// rebuilding a single card, so nothing inside one loses its state.
///
/// A page with a single card never leaves an empty column beside it: the
/// count is capped at the number of cards that take one column.
public struct SomaColumnsLayout: Layout {
    public var minColumnWidth: CGFloat
    public var spacing: CGFloat
    public var maxColumns: Int

    public init(minColumnWidth: CGFloat, spacing: CGFloat, maxColumns: Int) {
        self.minColumnWidth = minColumnWidth
        self.spacing = spacing
        self.maxColumns = maxColumns
    }

    /// How many columns a width holds, at least one and at most `maxColumns`.
    public static func columnCount(
        width: CGFloat,
        minColumnWidth: CGFloat,
        spacing: CGFloat,
        maxColumns: Int
    ) -> Int {
        guard width.isFinite, width > 0, minColumnWidth > 0 else { return 1 }
        let fit = Int(((width + spacing) / (minColumnWidth + spacing)).rounded(.down))
        return max(1, min(max(1, maxColumns), fit))
    }

    /// The arrangements already worked out in this layout pass, by the width
    /// they were worked out for.
    ///
    /// SwiftUI asks a layout for its size several times a pass (once per
    /// proposal, then once more to place), and every answer measures every
    /// child. The children here are whole columns of cards, so on the Journal
    /// that was hundreds of milliseconds each time a sheet opened over it.
    /// The system empties the cache whenever a child changes.
    public struct Cache {
        var arrangements: [CGFloat?: (frames: [CGRect], size: CGSize)] = [:]
    }

    public func makeCache(subviews: Subviews) -> Cache { Cache() }

    public func updateCache(_ cache: inout Cache, subviews: Subviews) {
        cache.arrangements.removeAll(keepingCapacity: true)
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        arrangement(width: proposal.width, subviews: subviews, cache: &cache).size
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        let arrangement = arrangement(width: bounds.width, subviews: subviews, cache: &cache)
        for (index, frame) in arrangement.frames.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: frame.width, height: frame.height)
            )
        }
    }

    /// The arrangement for `width`, worked out once per width per pass.
    private func arrangement(width: CGFloat?, subviews: Subviews, cache: inout Cache) -> (frames: [CGRect], size: CGSize) {
        let key = width.flatMap { $0.isFinite ? $0 : nil }
        if let known = cache.arrangements[key] { return known }
        let made = arrange(width: width, subviews: subviews)
        cache.arrangements[key] = made
        return made
    }

    /// Every child's frame, and the size of the whole, for one width.
    private func arrange(width proposed: CGFloat?, subviews: Subviews) -> (frames: [CGRect], size: CGSize) {
        // No width offered: one column at the widest child's own width.
        let width = proposed.flatMap { $0.isFinite ? $0 : nil }
            ?? subviews.map { $0.sizeThatFits(.unspecified).width }.max()
            ?? 0
        let singles = subviews.filter { $0[SomaColumnSpanKey.self] == .one }.count
        let count = min(
            Self.columnCount(width: width, minColumnWidth: minColumnWidth, spacing: spacing, maxColumns: maxColumns),
            max(1, singles)
        )
        let columnWidth = count > 1 ? (width - spacing * CGFloat(count - 1)) / CGFloat(count) : width

        // The next free y in each column, gap included.
        var next = Array(repeating: CGFloat.zero, count: count)
        var frames: [CGRect] = []
        frames.reserveCapacity(subviews.count)

        for subview in subviews {
            let spansAll = count == 1 || subview[SomaColumnSpanKey.self] == .full
            if spansAll {
                let y = next.max() ?? 0
                let height = subview.sizeThatFits(ProposedViewSize(width: width, height: nil)).height
                frames.append(CGRect(x: 0, y: y, width: width, height: height))
                // A child that draws nothing takes no gap either.
                let end = height > 0 ? y + height + spacing : y
                next = Array(repeating: end, count: count)
            } else {
                // The shortest column, the leading one when two tie.
                let lowest = next.min() ?? 0
                let column = next.firstIndex { $0 <= lowest + 0.5 } ?? 0
                let y = next[column]
                let height = subview.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil)).height
                let x = CGFloat(column) * (columnWidth + spacing)
                frames.append(CGRect(x: x, y: y, width: columnWidth, height: height))
                if height > 0 { next[column] = y + height + spacing }
            }
        }

        // The lowest child that draws anything, with no gap after it.
        let height = frames.filter { $0.height > 0 }.map(\.maxY).max() ?? 0
        return (frames, CGSize(width: width, height: height))
    }
}

// MARK: - Cards in columns

/// A page's cards in one column on a phone and two where there is room.
///
/// The widths come from the theme: a column is never narrower than
/// `cardColumnMinWidth`, and there are never more than `cardColumnLimit`. Mark
/// a child that belongs to the whole page with `.somaColumnSpan(.full)`.
public struct SomaCardColumns<Content: View>: View {
    /// Which of the theme's gaps sits between two children.
    public enum Gap: Sendable {
        /// The gap between two cards.
        case cards
        /// The gap between two titled sections, each a heading over its cards.
        case sections
    }

    private let gap: Gap
    private let content: Content

    @Environment(\.somaTheme) private var theme

    public init(gap: Gap = .cards, @ViewBuilder content: () -> Content) {
        self.gap = gap
        self.content = content()
    }

    public var body: some View {
        let metrics = theme.metrics
        SomaColumnsLayout(
            minColumnWidth: metrics.cardColumnMinWidth,
            spacing: gap == .cards ? metrics.cardSpacing : metrics.leadSpacing,
            maxColumns: metrics.cardColumnLimit
        ) {
            content
        }
    }
}

// MARK: - Readable width

public extension View {
    /// Holds a column of prose, a form or a conversation to the theme's
    /// readable width, centred in whatever room is left. Narrower than that,
    /// it takes the whole width.
    func somaReadableWidth(alignment: HorizontalAlignment = .leading) -> some View {
        modifier(SomaReadableWidth(alignment: alignment))
    }
}

private struct SomaReadableWidth: ViewModifier {
    let alignment: HorizontalAlignment

    @Environment(\.somaTheme) private var theme

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: theme.metrics.readableMaxWidth, alignment: Alignment(horizontal: alignment, vertical: .center))
            .frame(maxWidth: .infinity)
    }
}

// MARK: - Width class

/// Whether the room a view is given holds two panes side by side.
///
/// Unlike the size class it is read off the view's own width, so a sheet, a
/// Split View third and an iPhone on its side each answer for the room they
/// actually have.
public enum SomaWidthClass: Sendable, Equatable {
    /// One pane: a list pushes its detail, a lead sits above its cards.
    case compact
    /// Two panes side by side.
    case regular

    public init(width: CGFloat, metrics: SomaMetrics) {
        self = width >= metrics.twoPaneMinWidth ? .regular : .compact
    }
}

public extension View {
    /// Reports this view's ``SomaWidthClass`` into `widthClass` whenever its
    /// width crosses the theme's line, and only then.
    func somaWidthClass(_ widthClass: Binding<SomaWidthClass>) -> some View {
        modifier(SomaWidthClassReader(widthClass: widthClass))
    }
}

private struct SomaWidthClassReader: ViewModifier {
    @Binding var widthClass: SomaWidthClass

    @Environment(\.somaTheme) private var theme

    func body(content: Content) -> some View {
        let metrics = theme.metrics
        content.onGeometryChange(for: SomaWidthClass.self) { proxy in
            SomaWidthClass(width: proxy.size.width, metrics: metrics)
        } action: { value in
            widthClass = value
        }
    }
}

// MARK: - Previews

#Preview("Card columns") {
    SomaColumnsPreview()
}

#Preview("Card columns, narrow", traits: .fixedLayout(width: 360, height: 760)) {
    SomaColumnsPreview()
}

private struct SomaColumnsPreview: View {
    @Environment(\.somaTheme) private var theme
    @State private var widthClass = SomaWidthClass.compact

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.metrics.leadSpacing) {
                Text(widthClass == .regular ? "Two panes fit" : "One pane")
                    .somaFont(theme.typography.eyebrow)
                    .foregroundStyle(theme.colors.inkSecondary.color)

                SomaCardColumns {
                    ForEach(Array(["Sleep", "Recovery with a longer line that wraps onto a second line", "Strain", "Stress", "Energy"].enumerated()), id: \.offset) { index, title in
                        SomaCard {
                            VStack(alignment: .leading, spacing: theme.metrics.cardHeaderSpacing) {
                                Text(title)
                                    .somaFont(theme.typography.cardTitle)
                                ForEach(0..<(index % 3 + 1), id: \.self) { _ in
                                    Text("A line of the card.")
                                        .somaFont(theme.typography.caption)
                                        .foregroundStyle(theme.colors.inkSecondary.color)
                                }
                            }
                        }
                    }
                    Text("A footnote spans every column.")
                        .somaFont(theme.typography.caption)
                        .foregroundStyle(theme.colors.inkSecondary.color)
                        .somaColumnSpan(.full)
                }

                Text("Prose stays at a readable width, however wide the page grows, so a line is easy to follow back to its start.")
                    .somaFont(theme.typography.body)
                    .somaReadableWidth()
            }
            .padding(theme.metrics.pagePadding)
            .somaWidthClass($widthClass)
        }
        .background(theme.colors.canvas.color)
    }
}
