//
//  SomaReadingRow.swift
//  SomaUI
//

import SwiftUI

/// One reading as a quiet row, the way a score page lists what it reads and a
/// category lists its measures: the name in the ink with when it was last
/// read under it, the week as a small line in the aspect's tone, then the
/// latest value with its unit, and a chevron when the row opens its page.
///
/// Sits in a ``SomaBrowseGroup`` (built without glyphs) so the rows share one
/// card with hairlines between them. A reading with nothing this week keeps
/// its name and shows a dash, never a zero.
///
/// Given a status (even `.none`), the line under the name leads with its
/// word in the status's colour ("Within your usual"), then the caption; the name
/// holds one line and that line is kept even when empty, so rows in a group
/// share one height.
public struct SomaReadingRow: View {
    private let title: String
    private let caption: String?
    private let value: String?
    private let unit: String?
    private let week: [Double?]
    private let aspect: SomaAspect?
    private let opensSomething: Bool
    private let status: SomaReadingStatus?

    @Environment(\.somaTheme) private var theme

    /// - Parameters:
    ///   - caption: when it was last read: "Today", "Oct 19".
    ///   - week: the last seven days, oldest first; fewer than two readings
    ///     draws no line.
    ///   - aspect: whose tone the line takes; nil keeps it in the ink.
    public init(
        title: String,
        caption: String? = nil,
        value: String?,
        unit: String? = nil,
        week: [Double?] = [],
        aspect: SomaAspect? = nil,
        opensSomething: Bool = true,
        status: SomaReadingStatus? = nil
    ) {
        self.status = status
        self.title = title
        self.caption = caption
        self.value = value
        self.unit = unit
        self.week = week
        self.aspect = aspect
        self.opensSomething = opensSomething
    }

    public var body: some View {
        let metrics = theme.metrics
        let colors = theme.colors
        let type = theme.typography
        let tint = aspect.map { theme.aspects[$0].identity.color } ?? colors.inkSecondary.color

        HStack(spacing: metrics.browseRowSpacing) {
            VStack(alignment: .leading, spacing: metrics.readingRowLineGap) {
                if status == nil {
                    Text(title)
                        .somaFont(type.body)
                        .foregroundStyle(colors.inkPrimary.color)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if let caption {
                        Text(caption)
                            .somaFont(type.caption)
                            .foregroundStyle(colors.inkSecondary.color)
                    }
                } else {
                    Text(title)
                        .somaFont(type.body)
                        .foregroundStyle(colors.inkPrimary.color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    statusLine
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if week.compactMap({ $0 }).count > 1 {
                SomaSparkline(week, tint: tint, filled: false)
                    .frame(width: metrics.readingRowSparkWidth, height: metrics.readingRowSparkHeight)
            }

            // Value and unit in a trailing column of one width, so the week's
            // lines before it share a left edge down the group.
            HStack(alignment: .firstTextBaseline, spacing: metrics.metricHeroSpacing) {
                SomaNumber(value, type.rowValue)
                    .foregroundStyle(colors.inkPrimary.color)
                if let unit, value != nil {
                    Text(unit)
                        .somaFont(type.caption)
                        .foregroundStyle(colors.inkSecondary.color)
                }
            }
            .fixedSize()
            .frame(minWidth: metrics.readingRowValueWidth, alignment: .trailing)

            if opensSomething {
                Image(systemName: "chevron.right")
                    .font(.system(size: metrics.browseChevronSize, weight: .semibold))
                    .foregroundStyle(colors.inkSecondary.color)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, metrics.browseRowPadding)
        .padding(.vertical, metrics.browseRowVerticalPadding)
        .frame(minHeight: metrics.browseRowMinHeight)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    /// The status word in its colour, then the caption, on one line held
    /// even when both are missing.
    private var statusLine: some View {
        let colors = theme.colors
        let word = status?.word
        return HStack(spacing: 5) {
            if let word, let status {
                // The word whole; a caption beside it gives way first.
                Text(word)
                    .foregroundStyle(status.color(colors))
                    .fixedSize()
                    .layoutPriority(1)
            }
            if let caption {
                if word != nil {
                    Text(verbatim: "·").foregroundStyle(colors.inkSecondary.color)
                }
                Text(caption).foregroundStyle(colors.inkSecondary.color)
            }
            if word == nil, caption == nil {
                Text(verbatim: " ").accessibilityHidden(true)
            }
        }
        .somaFont(theme.typography.caption)
        .lineLimit(1)
    }
}

#Preview("Reading rows") {
    struct Row: Identifiable {
        let id: String
        let caption: String?
        let value: String?
        let unit: String?
        let week: [Double?]
    }
    let rows = [
        Row(id: "Resting heart rate", caption: "Today", value: "58", unit: "bpm", week: [58, 57, 59, nil, 56, 61, 64]),
        Row(id: "Heart rate variability", caption: "Today", value: "42", unit: "ms", week: [44, 47, 40, 41, 43, 39, 42]),
        Row(id: "Cardio fitness", caption: "Oct 12", value: "41.2", unit: "VO2 max", week: []),
        Row(id: "Heart rate recovery", caption: nil, value: nil, unit: nil, week: []),
    ]
    return ScrollView {
        SomaBrowseGroup(rows, hasGlyphs: false) { row in
            SomaReadingRow(title: row.id, caption: row.caption, value: row.value, unit: row.unit,
                           week: row.week, aspect: .heart)
        }
        .padding()
    }
    .background(SomaTheme.standard.colors.canvas.color)
}
