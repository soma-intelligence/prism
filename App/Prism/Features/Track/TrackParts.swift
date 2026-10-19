//
//  TrackParts.swift
//  Prism
//

import SwiftUI
import SomaUI

/// Rows of views that wrap to the next line when the width runs out, the way
/// words do. The Journal's tags are chips of different lengths, and a grid
/// would leave holes where a short one sits under a long one.
struct TrackFlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(width: bounds.width, subviews: subviews)
        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row {
        var indices: [Int] = []
        var y: CGFloat = 0
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width, !current.indices.isEmpty {
                rows.append(current)
                current = Row(y: current.y + current.height + spacing)
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}

/// Where a tag sits in the Journal and the picture it wears: a section of
/// the day and an SF Symbol. The section gives the colour: evening indigo,
/// daytime orange, training green, a person's own habits violet.
///
/// The starter tags each have their own; a tag of the person's own goes under
/// Habits with a plain tag glyph.
struct TrackTagStyle: Equatable {
    enum Section: Int, CaseIterable, Identifiable, Comparable {
        case evening, daytime, training, habits

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .daytime: "Daytime"
            case .training: "Training"
            case .evening: "Evening"
            case .habits: "Habits"
            }
        }

        static func < (lhs: Section, rhs: Section) -> Bool { lhs.rawValue < rhs.rawValue }

        var hue: SomaHealthHue {
            switch self {
            case .daytime: .mobility
            case .training: .nutrition
            case .evening: .sleep
            case .habits: .symptoms
            }
        }
    }

    var section: Section
    var symbol: String

    var hue: SomaHealthHue { section.hue }

    static func of(_ tagID: String) -> TrackTagStyle {
        switch tagID {
        case "coffee-late": TrackTagStyle(section: .daytime, symbol: "cup.and.saucer.fill")
        case "meditation": TrackTagStyle(section: .daytime, symbol: "wind")
        case "travel": TrackTagStyle(section: .daytime, symbol: "airplane")
        case "nap": TrackTagStyle(section: .daytime, symbol: "powersleep")
        case "supplements": TrackTagStyle(section: .daytime, symbol: "pills.fill")
        case "hard-training": TrackTagStyle(section: .training, symbol: "figure.run")
        case "sauna": TrackTagStyle(section: .training, symbol: "flame.fill")
        case "alcohol": TrackTagStyle(section: .evening, symbol: "wineglass.fill")
        case "late-meal": TrackTagStyle(section: .evening, symbol: "fork.knife")
        case "screens-in-bed": TrackTagStyle(section: .evening, symbol: "iphone")
        default: TrackTagStyle(section: .habits, symbol: "tag.fill")
        }
    }
}

/// A small capitals label over a group or inside a card: TAGS, HOW YOU FEEL.
struct TrackEyebrow: View {
    let text: String

    @Environment(\.somaTheme) private var theme

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .somaFont(theme.typography.eyebrow)
            .textCase(.uppercase)
            .foregroundStyle(theme.colors.inkSecondary.color)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A line whose first sentence is ink and the rest grey, the way every reason
/// on the pages reads.
struct TrackLeadText: View {
    let lead: String
    let rest: String?

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let colors = theme.colors
        let rest = rest.map { Text(" \($0)").foregroundStyle(colors.inkSecondary.color) } ?? Text("")
        (Text(lead).foregroundStyle(colors.inkPrimary.color) + rest)
            .somaFont(theme.typography.body)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The hairline between two parts of a card.
struct TrackHairline: View {
    @Environment(\.somaTheme) private var theme

    var body: some View {
        Rectangle()
            .fill(theme.colors.inkPrimary.color.opacity(theme.metrics.browseSeparatorOpacity))
            .frame(height: 0.5)
    }
}
