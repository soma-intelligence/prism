//
//  DoctorReportPaperViews.swift
//  Prism
//
//  The views `DoctorReportRenderer` draws onto paper, and the in-app preview
//  draws too: a page, its header and footer, and each piece.
//

import CoreGraphics
import Foundation
import SomaUI
import SwiftUI

// MARK: - Page

/// One page at its size in the theme's points: header, pieces, footer.
struct DoctorReportPageView: View {
    let layout: DoctorReportRenderer.Layout
    let index: Int

    @Environment(\.somaTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DoctorReportPageHeader(report: layout.report)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(layout.pages[index].enumerated()), id: \.offset) { _, piece in
                    DoctorReportPieceView(piece: piece, width: layout.contentWidth)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            DoctorReportPageFooter(report: layout.report, number: index + 1, count: layout.pages.count)
        }
        .padding(layout.margin)
        .frame(width: layout.pageSize.width, height: layout.pageSize.height, alignment: .topLeading)
        .background(theme.colors.surface.color)
    }
}

/// The line over every page: what it is, and whose.
struct DoctorReportPageHeader: View {
    let report: DoctorReport

    @Environment(\.somaTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.metrics.spaceXS) {
            HStack(alignment: .firstTextBaseline, spacing: theme.metrics.spaceS) {
                Text(verbatim: "Soma \u{00B7} \(report.title)")
                    .somaFont(theme.typography.eyebrow)
                    .foregroundStyle(theme.colors.inkSecondary.color)
                Spacer(minLength: theme.metrics.spaceS)
                Text(verbatim: ([report.patientName] + [report.patientLine].compactMap { $0 }).joined(separator: ", "))
                    .somaFont(theme.typography.caption)
                    .foregroundStyle(theme.colors.inkSecondary.color)
            }
            Divider()
        }
        .padding(.bottom, theme.metrics.spaceM)
    }
}

/// The line under every page: when it was made, what it is not, the page.
struct DoctorReportPageFooter: View {
    let report: DoctorReport
    let number: Int
    let count: Int

    @Environment(\.somaTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.metrics.spaceXS) {
            Divider()
            HStack(alignment: .firstTextBaseline, spacing: theme.metrics.spaceS) {
                Text(verbatim: "Prepared \(report.generated). For information, not a diagnosis.")
                Spacer(minLength: theme.metrics.spaceS)
                Text(verbatim: "Page \(number) of \(count)")
            }
            .somaFont(theme.typography.caption)
            .foregroundStyle(theme.colors.inkSecondary.color)
        }
        .padding(.top, theme.metrics.spaceM)
    }
}

// MARK: - Pieces

struct DoctorReportPieceView: View {
    let piece: DoctorReportPiece
    let width: CGFloat

    @Environment(\.somaTheme) private var theme

    /// The share of a table's width the flag and trend columns take, and the
    /// facts' label column.
    static let flagShare: CGFloat = 0.08
    static let trendShare: CGFloat = 0.12
    static let labelShare: CGFloat = 0.3

    var body: some View {
        let colors = theme.colors
        let type = theme.typography
        switch piece {
        case .title(let report):
            VStack(alignment: .leading, spacing: theme.metrics.spaceXS) {
                Text(verbatim: report.title)
                    .somaFont(type.display)
                    .foregroundStyle(colors.inkPrimary.color)
                Text(verbatim: "For a visit with a doctor, from the patient's own records on their phone.")
                    .somaFont(type.callout)
                    .foregroundStyle(colors.inkSecondary.color)
            }
            .frame(width: width, alignment: .leading)
            .padding(.bottom, theme.metrics.spaceS)

        case .heading(let title, let note):
            VStack(alignment: .leading, spacing: theme.metrics.spaceXS) {
                Text(verbatim: title)
                    .somaFont(type.title)
                    .foregroundStyle(colors.inkPrimary.color)
                if let note {
                    Text(verbatim: note)
                        .somaFont(type.caption)
                        .foregroundStyle(colors.inkSecondary.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(width: width, alignment: .leading)
            .padding(.top, theme.metrics.spaceL)
            .padding(.bottom, theme.metrics.spaceS)

        case .fact(let fact):
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(verbatim: fact.label)
                    .somaFont(type.caption)
                    .foregroundStyle(colors.inkSecondary.color)
                    .frame(width: width * Self.labelShare, alignment: .leading)
                    .padding(.trailing, theme.metrics.spaceS)
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: fact.value)
                    .somaFont(type.callout)
                    .foregroundStyle(colors.inkPrimary.color)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: theme.metrics.spaceS)
                flag(fact.flag)
            }
            .frame(width: width, alignment: .leading)
            .padding(.vertical, theme.metrics.spaceXS)

        case .caption(let caption):
            Text(verbatim: caption)
                .somaFont(type.cardTitle)
                .foregroundStyle(colors.inkPrimary.color)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: width, alignment: .leading)
                .padding(.top, theme.metrics.spaceS)
                .padding(.bottom, theme.metrics.spaceXS)

        case .header(let table):
            columns(table, cells: table.columns.map(\.title), font: type.eyebrow, ink: colors.inkSecondary.color,
                    flagTitle: "Flag", trend: nil)
                .padding(.vertical, theme.metrics.spaceXS)
                .overlay(alignment: .bottom) { Divider() }

        case .row(let table, let row):
            VStack(alignment: .leading, spacing: theme.metrics.scoreLabelSpacing) {
                columns(table, cells: row.cells, font: type.callout, ink: colors.inkPrimary.color, flag: row.flag,
                        trend: row.trend)
                if let note = row.note {
                    Text(verbatim: note)
                        .somaFont(type.caption)
                        .foregroundStyle(colors.inkSecondary.color)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: width, alignment: .leading)
                }
            }
            .padding(.vertical, theme.metrics.spaceXS)
            .overlay(alignment: .bottom) { Divider() }

        case .line(let line):
            Text(verbatim: line)
                .somaFont(type.callout)
                .foregroundStyle(colors.inkPrimary.color)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: width, alignment: .leading)
                .padding(.vertical, theme.metrics.spaceXS)

        case .disclaimer(let text):
            Text(verbatim: text)
                .somaFont(type.caption)
                .foregroundStyle(colors.inkSecondary.color)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: width, alignment: .leading)
                .padding(.top, theme.metrics.spaceL)
        }
    }

    /// A row of cells at the table's column widths, then the flag and the
    /// trend when the table has them.
    private func columns(_ table: DoctorReportTable, cells: [String], font: SomaFontSpec, ink: Color,
                         flag: DoctorReportFlag = .none, flagTitle: String? = nil, trend: [Double?]?) -> some View {
        let flagWidth = table.showsFlags ? width * Self.flagShare : 0
        let trendWidth = table.showsTrend ? width * Self.trendShare : 0
        let dataWidth = width - flagWidth - trendWidth
        let total = max(table.columns.map(\.share).reduce(0, +), .ulpOfOne)
        return HStack(alignment: .firstTextBaseline, spacing: 0) {
            ForEach(Array(table.columns.enumerated()), id: \.offset) { index, column in
                Text(verbatim: cells.indices.contains(index) ? cells[index] : "-")
                    .somaFont(column.isNumber && flagTitle == nil ? theme.typography.rowValue : font)
                    .foregroundStyle(ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.trailing, theme.metrics.spaceS)
                    .frame(width: dataWidth * column.share / total, alignment: .leading)
            }
            if table.showsFlags {
                Group {
                    if let flagTitle {
                        Text(verbatim: flagTitle)
                            .somaFont(font)
                            .foregroundStyle(ink)
                    } else {
                        self.flag(flag)
                    }
                }
                .frame(width: flagWidth, alignment: .leading)
            }
            if table.showsTrend {
                Text(verbatim: flagTitle == nil ? " " : "Trend")
                    .somaFont(flagTitle == nil ? theme.typography.rowValue : font)
                    .foregroundStyle(ink)
                    .frame(width: trendWidth, alignment: .leading)
                    .overlay {
                        if let trend {
                            DoctorReportTrendLine(values: trend)
                                .stroke(theme.colors.inkSecondary.color)
                        }
                    }
            }
        }
        .frame(width: width, alignment: .leading)
    }

    @ViewBuilder
    private func flag(_ flag: DoctorReportFlag) -> some View {
        if flag != .none {
            Text(verbatim: flag.word)
                .somaFont(theme.typography.eyebrow)
                .foregroundStyle((flag == .attention ? theme.colors.statusAlert : theme.colors.statusOut).color)
        }
    }
}

/// A small line through a row's daily values, scaled to its own range. A
/// gap in the days is bridged; one value or none draws nothing.
struct DoctorReportTrendLine: Shape {
    let values: [Double?]

    /// At most this many points: a year of days is drawn as weeks or so,
    /// the shape of the period rather than its noise.
    static let points = 30

    func path(in rect: CGRect) -> Path {
        let size = max(1, Int((Double(values.count) / Double(Self.points)).rounded(.up)))
        let buckets = stride(from: 0, to: values.count, by: size).map { start in
            let present = values[start..<min(start + size, values.count)].compactMap { $0 }
            return present.isEmpty ? nil : present.reduce(0, +) / Double(present.count)
        }
        let present = buckets.enumerated().compactMap { index, value in value.map { (index, $0) } }
        guard present.count > 1, let low = present.map(\.1).min(), let high = present.map(\.1).max() else { return Path() }
        let step = rect.width / CGFloat(max(buckets.count - 1, 1))
        var path = Path()
        for (n, point) in present.enumerated() {
            let y = high > low ? rect.maxY - CGFloat((point.1 - low) / (high - low)) * rect.height : rect.midY
            let location = CGPoint(x: rect.minX + CGFloat(point.0) * step, y: y)
            if n == 0 { path.move(to: location) } else { path.addLine(to: location) }
        }
        return path
    }
}
