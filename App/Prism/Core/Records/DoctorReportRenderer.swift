//
//  DoctorReportRenderer.swift
//  Prism
//
//  The doctor report laid out on paper: A4 or US Letter, a header and a
//  numbered footer on every page, the sections as tables, and a PDF whose
//  text is text. Each page is a SwiftUI view drawn by `ImageRenderer` into a
//  Core Graphics PDF context, which keeps the glyphs as glyphs, so a reader
//  can select and search them; the same views are the in-app preview.
//
//  The page is laid out in the theme's own roles and spacing, then scaled
//  down so the theme's body role prints at ``DoctorReportPaper/bodyPoints``:
//  the type is the app's, at the size of a printed page.
//

import CoreGraphics
import Foundation
import SomaUI
import SwiftUI

// MARK: - Paper

nonisolated enum DoctorReportPaper: String, CaseIterable, Identifiable, Sendable {
    case a4, letter

    var id: String { rawValue }

    var title: String {
        switch self {
        case .a4: "A4"
        case .letter: "US Letter"
        }
    }

    /// In PDF points, 72 to the inch: ISO 216 A4 is 210 by 297 mm, ANSI A
    /// Letter is 8.5 by 11 inches.
    var size: CGSize {
        switch self {
        case .a4: CGSize(width: 595.28, height: 841.89)
        case .letter: CGSize(width: 612, height: 792)
        }
    }

    /// The regions that print on Letter, from CLDR's paper size data.
    static let letterRegions: Set<String> = ["US", "CA", "MX", "PH", "CL", "CO", "VE", "PR", "GT", "SV", "CR", "PA", "NI", "BZ"]

    static func forLocale(_ locale: Locale) -> DoctorReportPaper {
        guard let region = locale.region?.identifier else { return .a4 }
        return letterRegions.contains(region) ? .letter : .a4
    }

    /// The page's margin in points, about 14 mm.
    static let margin: CGFloat = 40
    /// The point size the theme's body role prints at. Every other role
    /// keeps its proportion to it.
    static let bodyPoints: CGFloat = 10
}

// MARK: - Pieces

/// One unbreakable piece of a page. Tables break between rows, and a table
/// that runs onto the next page repeats its column titles there.
enum DoctorReportPiece {
    case title(DoctorReport)
    case heading(title: String, note: String?)
    case fact(DoctorReportFact)
    case caption(String)
    case header(DoctorReportTable)
    case row(DoctorReportTable, DoctorReportRow)
    case line(String)
    case disclaimer(String)

    /// A heading, a caption and a table's column titles never end a page.
    var keepsWithNext: Bool {
        switch self {
        case .heading, .caption, .header: true
        default: false
        }
    }

    static func pieces(of report: DoctorReport) -> [DoctorReportPiece] {
        var pieces: [DoctorReportPiece] = [.title(report)]
        for section in report.sections {
            pieces.append(.heading(title: section.title, note: section.note))
            for block in section.blocks {
                switch block {
                case .facts(let facts):
                    pieces += facts.map(DoctorReportPiece.fact)
                case .lines(let lines):
                    pieces += lines.map(DoctorReportPiece.line)
                case .table(let table):
                    if let caption = table.caption { pieces.append(.caption(caption)) }
                    pieces.append(.header(table))
                    pieces += table.rows.map { .row(table, $0) }
                }
            }
        }
        pieces.append(.disclaimer(report.disclaimer))
        return pieces
    }
}

// MARK: - Layout and PDF

@MainActor
enum DoctorReportRenderer {
    /// The pages, each a run of pieces, in the page's own units.
    struct Layout {
        var report: DoctorReport
        var paper: DoctorReportPaper
        /// Theme points to one paper point.
        var scale: CGFloat
        var pages: [[DoctorReportPiece]]

        /// The page in the theme's points.
        var pageSize: CGSize { CGSize(width: paper.size.width * scale, height: paper.size.height * scale) }
        var margin: CGFloat { DoctorReportPaper.margin * scale }
        var contentWidth: CGFloat { pageSize.width - margin * 2 }
    }

    static func layout(_ report: DoctorReport, paper: DoctorReportPaper, theme: SomaTheme) -> Layout {
        let scale = theme.typography.body.size / DoctorReportPaper.bodyPoints
        var layout = Layout(report: report, paper: paper, scale: scale, pages: [])
        let width = layout.contentWidth

        func height(_ view: some View) -> CGFloat {
            let renderer = ImageRenderer(content: printed(view.frame(width: width).fixedSize(horizontal: false, vertical: true), theme: theme))
            renderer.proposedSize = ProposedViewSize(width: width, height: nil)
            var measured: CGFloat = 0
            renderer.render { size, _ in measured = size.height }
            return measured
        }

        let chrome = height(DoctorReportPageHeader(report: report))
            + height(DoctorReportPageFooter(report: report, number: 1, count: 1))
        let available = layout.pageSize.height - layout.margin * 2 - chrome
        let pieces = DoctorReportPiece.pieces(of: report)
        let heights = pieces.map { height(DoctorReportPieceView(piece: $0, width: width)) }

        var pages: [[DoctorReportPiece]] = []
        var current: [DoctorReportPiece] = []
        var used: CGFloat = 0
        var header: (piece: DoctorReportPiece, height: CGFloat)?
        // The caption of the table under way, said again over its rest.
        var caption: String?

        for index in pieces.indices {
            let piece = pieces[index]
            // A heading, caption or column titles carry the pieces they keep
            // with into the space they need.
            var needed = heights[index]
            var next = index
            while pieces[next].keepsWithNext, next + 1 < pieces.count {
                next += 1
                needed += heights[next]
            }
            if used + needed > available, !current.isEmpty {
                pages.append(current)
                current = []
                used = 0
                if case .row = piece, let header {
                    if let caption {
                        let again = DoctorReportPiece.caption("\(caption), continued")
                        current.append(again)
                        used += height(DoctorReportPieceView(piece: again, width: width))
                    }
                    current.append(header.piece)
                    used += header.height
                }
            }
            switch piece {
            case .header:
                header = (piece, heights[index])
                if index > 0, case .caption(let text) = pieces[index - 1] { caption = text } else { caption = nil }
            case .heading:
                header = nil
                caption = nil
            default: break
            }
            current.append(piece)
            used += heights[index]
        }
        if !current.isEmpty { pages.append(current) }
        layout.pages = pages
        return layout
    }

    /// The report as a PDF: one page per laid out page, its text selectable.
    static func pdf(_ report: DoctorReport, paper: DoctorReportPaper, theme: SomaTheme) -> Data {
        pdf(layout(report, paper: paper, theme: theme), theme: theme)
    }

    static func pdf(_ layout: Layout, theme: SomaTheme) -> Data {
        let data = NSMutableData()
        var box = CGRect(origin: .zero, size: layout.paper.size)
        let info = [
            kCGPDFContextTitle as String: layout.report.title,
            kCGPDFContextCreator as String: "Soma",
        ] as CFDictionary
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &box, info) else { return Data() }
        for index in layout.pages.indices {
            let renderer = ImageRenderer(content: printed(page(layout, index), theme: theme))
            renderer.proposedSize = ProposedViewSize(layout.pageSize)
            renderer.render { size, draw in
                context.beginPDFPage(nil)
                context.saveGState()
                context.scaleBy(x: box.width / size.width, y: box.height / size.height)
                draw(context)
                context.restoreGState()
                context.endPDFPage()
            }
        }
        context.closePDF()
        return data as Data
    }

    static func page(_ layout: Layout, _ index: Int) -> DoctorReportPageView {
        DoctorReportPageView(layout: layout, index: index)
    }

    /// Paper is light whatever the phone's appearance.
    private static func printed(_ view: some View, theme: SomaTheme) -> some View {
        view.somaTheme(theme).environment(\.colorScheme, .light)
    }
}
