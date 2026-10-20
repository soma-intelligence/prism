//
//  LabParts.swift
//  Prism
//
//  The pieces the Body lab pages share: a card of measures against their
//  band (a rail, the band in an aspect's hue, the value's dot), a small
//  capital heading over a group, a list of rows that open or say something,
//  and the primary button a sheet ends on.
//
//  Built from the theme alone, like every SomaUI component, and kept in this
//  folder because only the lab draws them.
//

import SwiftUI
import SomaUI

// MARK: - Measures against a band

/// One line of a band card: what it is, the line under it, the value, and
/// the rail with the band and the dot.
struct LabBandItem: Identifiable {
    let id: String
    var title: String
    var detail: String?
    /// Nil renders a dash.
    var value: String?
    /// The band on the rail, 0 to 1. Nil draws the rail alone.
    var band: ClosedRange<Double>?
    /// Where the value sits, 0 to 1. Nil draws no dot.
    var position: Double?
    /// Worse than it should be: the value and the dot turn to danger.
    var isFlagged = false
    /// A route the line opens, when it opens one.
    var route: LabRoute?
}

/// A card of measures against their band: the Figma's "rows" card.
struct LabBandCard: View {
    let title: String
    var eyebrow: String?
    var aspect: SomaAspect = .body
    let items: [LabBandItem]

    @Environment(\.somaTheme) private var theme

    var body: some View {
        SomaCard {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .somaFont(theme.typography.body)
                        .foregroundStyle(theme.colors.inkPrimary.color)
                        .accessibilityAddTraits(.isHeader)
                    if let eyebrow {
                        LabEyebrow(eyebrow)
                    }
                }
                .padding(.bottom, 4)
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 {
                        Rectangle()
                            .fill(theme.colors.inkPrimary.color.opacity(theme.metrics.browseSeparatorOpacity))
                            .frame(height: 0.5)
                    }
                    if let route = item.route {
                        NavigationLink(value: route) { LabBandLine(item: item, aspect: aspect) }
                            .buttonStyle(.plain)
                    } else {
                        LabBandLine(item: item, aspect: aspect)
                    }
                }
            }
        }
    }
}

struct LabBandLine: View {
    let item: LabBandItem
    let aspect: SomaAspect

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let colors = theme.colors
        let status = self.status
        HStack(alignment: .center, spacing: theme.metrics.cardSpacing) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .somaFont(theme.typography.body)
                    .foregroundStyle(colors.inkPrimary.color)
                HStack(spacing: 5) {
                    if let status {
                        Text(status.word).foregroundStyle(status.color)
                        Text(verbatim: "·").foregroundStyle(colors.inkSecondary.color)
                    }
                    Text(item.value ?? "-")
                        .somaFont(theme.typography.rowValue)
                        .foregroundStyle(colors.inkPrimary.color)
                }
                .somaFont(theme.typography.caption)
                .lineLimit(1)
                if let detail = item.detail {
                    Text(detail)
                        .somaFont(theme.typography.caption)
                        .foregroundStyle(colors.inkSecondary.color)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            LabRail(band: item.band, position: item.position, aspect: aspect, isFlagged: item.isFlagged)
                .frame(width: theme.metrics.aspectChartWidth, height: theme.metrics.chartRingDiameter + 6)
        }
        .padding(.vertical, 10)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(item.title))
        .accessibilityValue(Text([item.value ?? "Not measured", item.detail].compactMap { $0 }.joined(separator: ", ")))
    }

    /// Where the value sits against its band, as a word and a colour.
    private var status: (word: LocalizedStringResource, color: Color)? {
        guard let position = item.position, let band = item.band else {
            return item.isFlagged ? ("Out of range", theme.colors.statusOut.color) : nil
        }
        if item.isFlagged || !band.contains(position) {
            // The lab's own reference range, not the person's usual: said
            // as the lab's, never as a clinical "normal".
            return (position > band.upperBound ? "Above the lab’s range" : "Below the lab’s range", theme.colors.statusOut.color)
        }
        return ("Within the lab’s range", theme.colors.statusNormal.color)
    }
}

/// A thin rail from 0 to 1 with the normal band on it in faint green and a
/// hollow ring where the value sits.
struct LabRail: View {
    let band: ClosedRange<Double>?
    let position: Double?
    var aspect: SomaAspect = .body
    var isFlagged = false

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let pen = SomaPen(theme)
        let track = theme.metrics.chartThinBarWidth * 0.75
        let colors = theme.colors
        let band = band
        let position = position
        let outside = isFlagged || (position.map { value in band.map { !$0.contains(value) } ?? false } ?? false)
        let ringColor = outside ? colors.statusOut.color : (band == nil ? theme.aspects[aspect].identity.color : colors.statusNormal.color)

        Canvas { context, size in
            let inset = pen.ring / 2 + 1
            let width = size.width - inset * 2
            let rail = CGRect(x: inset, y: (size.height - track) / 2, width: width, height: track)
            context.fill(Path(roundedRect: rail, cornerRadius: track / 2), with: .color(pen.grid))
            if let band {
                let rect = CGRect(x: inset + width * band.lowerBound, y: rail.minY,
                                  width: max(width * (band.upperBound - band.lowerBound), track), height: track)
                context.fill(Path(roundedRect: rect, cornerRadius: track / 2), with: .color(pen.normal.opacity(0.45)))
            }
            if let position {
                pen.ring(context, at: CGPoint(x: inset + width * min(max(position, 0), 1), y: size.height / 2), color: ringColor)
            }
        }
        .accessibilityHidden(true)
    }
}

extension LabBandItem {
    /// A blood marker as a band line: its range as the band, the value's dot,
    /// and the reading before it in the line under the name.
    init(marker value: BloodMarkerValue, previous: (date: Date, value: BloodMarkerValue)?, route: LabRoute? = nil) {
        let reading = LabMath.reading(value)
        let definition = BloodMarkerCatalog.definition(for: value)
        var detail = reading.rangeText ?? "no reference range"
        if let previous {
            let before = LabMath.reading(previous.value)
            let number = LabMath.format(before.value, decimals: LabMath.decimals(for: before.value)) ?? "-"
            detail += " · \(number) in \(previous.date.formatted(.dateTime.month(.wide)))"
        }
        let band: ClosedRange<Double>? = (reading.low != nil || reading.high != nil)
            ? reading.position(reading.low ?? reading.domain.lowerBound)...reading.position(reading.high ?? reading.domain.upperBound)
            : nil
        self.init(id: value.key, title: definition.name, detail: detail, value: reading.text, band: band,
                  position: reading.position(reading.value), isFlagged: reading.isOutside, route: route)
    }
}

// MARK: - Headings and rows

/// Small capitals over a group: "Entries", "Two inputs missing".
struct LabEyebrow: View {
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

/// One row of a lab list: a title, the value on the right, and what it does.
struct LabRow: Identifiable {
    let id: String
    var title: String
    var detail: String?
    var route: LabRoute?
    var action: (() -> Void)?

    init(_ title: String, detail: String? = nil, route: LabRoute? = nil, action: (() -> Void)? = nil) {
        self.id = title
        self.title = title
        self.detail = detail
        self.route = route
        self.action = action
    }
}

/// A group of lab rows under an optional small capital heading.
struct LabRowGroup: View {
    var heading: String?
    let rows: [LabRow]

    @Environment(\.somaTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.metrics.browseHeadingSpacing) {
            if let heading {
                LabEyebrow(heading)
            }
            SomaBrowseGroup(rows, hasGlyphs: false) { row in
                if let route = row.route {
                    NavigationLink(value: route) {
                        SomaBrowseRow(title: row.title, detail: row.detail)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                } else {
                    SomaBrowseRow(title: row.title, detail: row.detail, opensSomething: row.action != nil, action: row.action)
                }
            }
        }
    }
}

/// The line under a page that says what a number is not.
struct LabFootnote: View {
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

/// Short explanations as explainer rows: a glyph, the heading in bold, the
/// text in grey under it.
struct LabExplainCard: View {
    let sections: [(heading: String, text: String)]

    var body: some View {
        SomaExplainerSection(nil) {
            ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                SomaExplainerRow(symbol: Self.symbol(section.heading), hue: .other, term: section.heading, line: section.text)
            }
        }
    }

    /// A glyph for the two headings the lab pages use, a plain one for any
    /// other.
    private static func symbol(_ heading: String) -> String {
        switch heading {
        case "What it means": "text.magnifyingglass"
        case "What moves it": "arrow.up.arrow.down"
        default: "info.circle.fill"
        }
    }
}

/// Text whose first sentence reads in ink and the rest in grey.
struct LabLeadText: View {
    let text: String

    @Environment(\.somaTheme) private var theme

    init(_ text: String) { self.text = text }

    var body: some View {
        let parts = split
        let lead = Text(parts.lead).foregroundStyle(theme.colors.inkPrimary.color)
        let rest = Text(parts.rest).foregroundStyle(theme.colors.inkSecondary.color)
        Text("\(lead)\(rest)")
            .somaFont(theme.typography.body)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var split: (lead: String, rest: String) {
        guard let end = text.range(of: ". ") else { return (text, "") }
        return (String(text[..<end.upperBound]), String(text[end.upperBound...]))
    }
}

// MARK: - Sheets

/// The one primary action a sheet ends on: a full width capsule in the accent.
struct LabPrimaryButton: View {
    let title: String
    var isEnabled = true
    let action: () -> Void

    @Environment(\.somaTheme) private var theme

    var body: some View {
        Button(action: action) {
            Text(title)
                .somaFont(theme.typography.body)
                .foregroundStyle(theme.colors.onAccent.color)
                .frame(maxWidth: .infinity, minHeight: theme.metrics.minimumTapTarget + 12)
                .background(Capsule().fill(theme.colors.accent.color.opacity(isEnabled ? 1 : 0.4)))
                .contentShape(.capsule)
        }
        .buttonStyle(SomaGlassPressStyle())
        .disabled(!isEnabled)
    }
}

/// The secondary action beside it: an outlined capsule.
struct LabSecondaryButton: View {
    let title: String
    let action: () -> Void

    @Environment(\.somaTheme) private var theme

    var body: some View {
        Button(action: action) {
            Text(title)
                .somaFont(theme.typography.body)
                .foregroundStyle(theme.colors.inkPrimary.color)
                .frame(maxWidth: .infinity, minHeight: theme.metrics.minimumTapTarget + 12)
                .background(Capsule().strokeBorder(theme.colors.inkPrimary.color.opacity(theme.metrics.hairlineOpacity * 2)))
                .contentShape(.capsule)
        }
        .buttonStyle(SomaGlassPressStyle())
    }
}

/// A sheet's page shape: eyebrow, title, the reason, then the content, in a
/// scroll view with the sheet's own Done.
struct LabSheet<Content: View>: View {
    let eyebrow: String
    let title: String
    var reason: String?
    var doneTitle = "Done"
    let content: Content

    @Environment(\.somaTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    init(eyebrow: String, title: String, reason: String? = nil, doneTitle: String = "Done", @ViewBuilder content: () -> Content) {
        self.eyebrow = eyebrow
        self.title = title
        self.reason = reason
        self.doneTitle = doneTitle
        self.content = content()
    }

    var body: some View {
        NavigationStack {
            SomaPageScroll {
                VStack(alignment: .leading, spacing: theme.metrics.leadSpacing) {
                    SomaPageHero(eyebrow: eyebrow, title: title, reason: reason)
                    VStack(alignment: .leading, spacing: theme.metrics.cardSpacing) {
                        content
                    }
                }
                .padding(.horizontal, theme.metrics.pagePadding)
                .padding(.bottom, theme.metrics.pagePadding)
                .frame(maxWidth: theme.metrics.pageMaxWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(theme.colors.canvas.color.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(doneTitle) { dismiss() }
                }
            }
        }
    }
}

// MARK: - Dates

extension Date {
    /// "28 August", the way a lab page names a day.
    var labDay: String { formatted(.dateTime.day().month(.wide)) }
    /// "Wed 9 Sep".
    var labShortDay: String { formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)) }
}
