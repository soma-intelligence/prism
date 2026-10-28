//
//  SomaBrowseList.swift
//  SomaUI
//

import SwiftUI

/// One line in a browse list: a glyph, what it is called, and a chevron saying
/// it opens something.
///
/// The glyph sits in a fixed column rather than at its intrinsic width. Glyphs
/// carry different amounts of ink, and titles that each start at a different x
/// read as a ragged pile instead of a column.
///
/// What a row is for, which decides what colour it wears.
///
/// A role and not a colour: a component reads the theme rather than being handed
/// one, so a call site cannot invent a shade, and the two roles here can be
/// restyled in one place when the scale changes.
public enum SomaRowRole: Sendable {
    /// Opens something, changes something, says something. Almost every row.
    case standard
    /// Destroys something. Deletion, withdrawal, a wipe.
    ///
    /// It takes the whole row rather than only the glyph, which is the one place
    /// the house rule about a single accent gives way: an accent marks what a
    /// person chooses, and this marks what they cannot take back.
    case destructive

    func glyph(_ theme: SomaTheme) -> Color {
        switch self {
        case .standard: theme.colors.accent.color
        case .destructive: theme.colors.danger.color
        }
    }

    func title(_ theme: SomaTheme) -> Color {
        switch self {
        case .standard: theme.colors.inkPrimary.color
        case .destructive: theme.colors.danger.color
        }
    }
}

public struct SomaBrowseRow<Trailing: View>: View {
    private let symbol: String?
    private let title: String
    private let detail: String?
    private let opensSomething: Bool
    private let role: SomaRowRole
    private let action: (() -> Void)?
    private let trailing: Trailing

    @Environment(\.somaTheme) private var theme

    public init(
        symbol: String? = nil,
        title: String,
        detail: String? = nil,
        opensSomething: Bool = true,
        role: SomaRowRole = .standard,
        action: (() -> Void)? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.symbol = symbol
        self.title = title
        self.detail = detail
        self.opensSomething = opensSomething
        self.role = role
        self.action = action
        self.trailing = trailing()
    }

    public var body: some View {
        if let action {
            Button(action: action) { line }
                .buttonStyle(SomaBrowseRowStyle())
        } else {
            line
        }
    }

    /// The row itself, which is the same whether or not it is a button.
    private var line: some View {
        HStack(spacing: theme.metrics.browseRowSpacing) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: theme.metrics.browseGlyphSize))
                    .foregroundStyle(role.glyph(theme))
                    .frame(width: theme.metrics.browseGlyphColumn)
            }

            Text(title)
                .somaFont(theme.typography.body)
                .foregroundStyle(role.title(theme))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: theme.metrics.browseRowSpacing)

            if let detail {
                Text(detail)
                    .somaFont(theme.typography.rowValue)
                    .foregroundStyle(theme.colors.inkSecondary.color)
            }

            trailing

            if opensSomething {
                Image(systemName: "chevron.right")
                    .font(.system(size: theme.metrics.browseChevronSize, weight: .semibold))
                    .foregroundStyle(theme.colors.inkSecondary.color)
            }
        }
        .padding(.horizontal, theme.metrics.browseRowPadding)
        .padding(.vertical, theme.metrics.browseRowVerticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: theme.metrics.browseRowMinHeight)
        .contentShape(.rect)
    }
}

public extension SomaBrowseRow where Trailing == EmptyView {
    /// A row with nothing between its title and its chevron.
    init(
        symbol: String? = nil,
        title: String,
        detail: String? = nil,
        opensSomething: Bool = true,
        role: SomaRowRole = .standard,
        action: (() -> Void)? = nil
    ) {
        self.init(
            symbol: symbol,
            title: title,
            detail: detail,
            opensSomething: opensSomething,
            role: role,
            action: action
        ) { EmptyView() }
    }
}

/// A run of browse rows on one surface, hairlines between them.
///
/// Data driven rather than a free `ViewBuilder`: where the separators go, and
/// which row does without one, is the group's job. A builder would hand that
/// back to every call site, and a list whose last row carries a stray line is
/// exactly the defect this shape rules out.
///
/// The separator is inset to where the titles start, so the column of titles
/// reads as the left edge of the list and the glyphs hang outside it.
public struct SomaBrowseGroup<Data: RandomAccessCollection, Row: View>: View
where Data.Element: Identifiable {
    private let data: Data
    private let hasGlyphs: Bool
    private let row: (Data.Element) -> Row

    @Environment(\.somaTheme) private var theme

    public init(
        _ data: Data,
        hasGlyphs: Bool = true,
        @ViewBuilder row: @escaping (Data.Element) -> Row
    ) {
        self.data = data
        self.hasGlyphs = hasGlyphs
        self.row = row
    }

    /// Where a separator starts: past the padding and the glyph column, so it
    /// begins under the first letter of the title above it.
    private var separatorInset: CGFloat {
        guard hasGlyphs else { return theme.metrics.browseRowPadding }
        return theme.metrics.browseRowPadding
            + theme.metrics.browseGlyphColumn
            + theme.metrics.browseRowSpacing
    }

    public var body: some View {
        VStack(spacing: 0) {
            ForEach(data) { element in
                row(element)

                if element.id != data.last?.id {
                    Rectangle()
                        .fill(theme.colors.inkPrimary.color.opacity(theme.metrics.browseSeparatorOpacity))
                        .frame(height: 0.5)
                        .padding(.leading, separatorInset)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: theme.metrics.browseGroupCornerRadius, style: .continuous)
                .fill(theme.colors.surface.color)
        )
        .clipShape(
            RoundedRectangle(cornerRadius: theme.metrics.browseGroupCornerRadius, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: theme.metrics.browseGroupCornerRadius, style: .continuous)
                .strokeBorder(
                    theme.colors.inkPrimary.color.opacity(theme.metrics.hairlineOpacity),
                    lineWidth: 0.5
                )
        )
    }
}

/// The heading over a browse group.
///
/// Set in the title role and in the primary ink, not as a small grey kicker:
/// on a screen that is nothing but lists, the heading is the only thing that
/// tells one list from the next.
public struct SomaBrowseHeading: View {
    private let text: String

    @Environment(\.somaTheme) private var theme

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text)
            .somaFont(theme.typography.title)
            .foregroundStyle(theme.colors.inkPrimary.color)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A browse heading and its group, spaced as a section.
public struct SomaBrowseSection<Data: RandomAccessCollection, Row: View>: View
where Data.Element: Identifiable {
    private let heading: String?
    private let data: Data
    private let hasGlyphs: Bool
    private let row: (Data.Element) -> Row

    @Environment(\.somaTheme) private var theme

    public init(
        _ heading: String? = nil,
        items: Data,
        hasGlyphs: Bool = true,
        @ViewBuilder row: @escaping (Data.Element) -> Row
    ) {
        self.heading = heading
        self.data = items
        self.hasGlyphs = hasGlyphs
        self.row = row
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: theme.metrics.browseHeadingSpacing) {
            if let heading {
                SomaBrowseHeading(heading)
            }

            SomaBrowseGroup(data, hasGlyphs: hasGlyphs, row: row)
        }
    }
}

/// What a browse row does under a finger: a wash across the whole row, edge to
/// edge, the way a list row highlights.
///
/// Not ``SomaGlassPressStyle``: that one scales and dims a floating control, and
/// a row scaling inside a group would slide out from under the hairlines that
/// bound it. Public as `.somaBrowseRow`, for a `NavigationLink` or a `Button`
/// that wraps a ``SomaBrowseRow`` outside ``SomaBrowseGroup``'s own button.
public struct SomaBrowseRowStyle: ButtonStyle {
    @Environment(\.somaTheme) private var theme

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                configuration.isPressed
                    ? theme.colors.inkPrimary.color.opacity(theme.metrics.browsePressOpacity)
                    : Color.clear
            )
    }
}

public extension ButtonStyle where Self == SomaBrowseRowStyle {
    /// A list row's press: a wash across the whole row, edge to edge.
    static var somaBrowseRow: SomaBrowseRowStyle { SomaBrowseRowStyle() }
}

#Preview("Browse List") {
    struct Item: Identifiable {
        let id: String
        let symbol: String
        let detail: String?
    }

    let categories = [
        Item(id: "Activity", symbol: "flame.fill", detail: nil),
        Item(id: "Heart", symbol: "heart.fill", detail: nil),
        Item(id: "Sleep", symbol: "bed.double.fill", detail: nil),
    ]
    let readings = [
        Item(id: "Resting Heart Rate", symbol: "heart", detail: "58 bpm"),
        Item(id: "Walking Heart Rate", symbol: "figure.walk", detail: "94 bpm"),
    ]

    return ZStack {
        SomaPreviewBackdrop()

        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                SomaBrowseSection("Health Categories", items: categories) { item in
                    SomaBrowseRow(symbol: item.symbol, title: item.id) {}
                }

                SomaBrowseSection("Heart", items: readings) { item in
                    SomaBrowseRow(symbol: item.symbol, title: item.id, detail: item.detail) {}
                }
            }
            .padding(20)
        }
    }
}
