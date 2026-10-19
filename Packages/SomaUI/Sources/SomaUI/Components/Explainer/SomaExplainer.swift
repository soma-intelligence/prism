//
//  SomaExplainer.swift
//  SomaUI
//

import SwiftUI

/// The sheet behind an info button: a picture first (the score's ring, or its parts as a donut),
/// a short bold title and one line under it, then a few compact sections:
/// rows of a coloured glyph, a bold term and one short line; what moved the
/// number today; the ranges as coloured bands.
///
/// Words are kept to the minimum on purpose. Anything that can be drawn is
/// drawn, and a paragraph is never the answer.
///
/// Pass `onClose` when the explainer is a sheet: it adds the close button and
/// the grabber. Leave it out for an explainer pushed onto a stack, which has
/// the stack's own back button.
public struct SomaExplainer<Hero: View, Content: View>: View {
    private let eyebrow: String?
    private let title: String
    private let summary: String?
    private let aspect: SomaAspect?
    private let onClose: (() -> Void)?
    private let hero: Hero
    private let content: Content

    @Environment(\.somaTheme) private var theme

    /// - Parameters:
    ///   - eyebrow: small capitals over the title, or nil.
    ///   - title: two or three words.
    ///   - summary: one line under the title, or nil.
    ///   - aspect: the aspect whose colour washes the top of the sheet.
    ///   - onClose: dismisses the sheet; nil when the explainer is pushed.
    public init(eyebrow: String? = nil, title: String, summary: String? = nil,
                aspect: SomaAspect? = nil, onClose: (() -> Void)? = nil,
                @ViewBuilder hero: () -> Hero, @ViewBuilder content: () -> Content) {
        self.eyebrow = eyebrow
        self.title = title
        self.summary = summary
        self.aspect = aspect
        self.onClose = onClose
        self.hero = hero()
        self.content = content()
    }

    public var body: some View {
        let metrics = theme.metrics
        let type = theme.typography
        let colors = theme.colors

        ScrollView {
            VStack(alignment: .leading, spacing: metrics.explainerSectionSpacing) {
                hero
                    .frame(maxWidth: .infinity)
                    .padding(.top, metrics.explainerHeroTopPadding)

                VStack(alignment: .leading, spacing: metrics.explainerTitleSpacing) {
                    if let eyebrow {
                        Text(eyebrow)
                            .somaFont(type.eyebrow)
                            .textCase(.uppercase)
                            .foregroundStyle(colors.inkSecondary.color)
                    }
                    Text(title)
                        .somaFont(type.explainerTitle)
                        .foregroundStyle(colors.inkPrimary.color)
                        .accessibilityAddTraits(.isHeader)
                    if let summary {
                        Text(summary)
                            .somaFont(type.callout)
                            .foregroundStyle(colors.inkPrimary.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                content
            }
            .padding(.horizontal, metrics.pagePadding)
            .padding(.bottom, metrics.leadSpacing * 2)
            .frame(maxWidth: metrics.explainerMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(alignment: .top) {
            ZStack(alignment: .top) {
                colors.canvas.color
                if let aspect {
                    LinearGradient(colors: [theme.aspects[aspect].identity.color.opacity(metrics.explainerWashOpacity),
                                            colors.canvas.color.opacity(0)],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: metrics.explainerHeroDiameter * 2.4)
                }
            }
            .ignoresSafeArea()
        }
        .overlay(alignment: .topTrailing) {
            if let onClose {
                SomaIconButton(symbol: "xmark", accessibilityLabel: "Close", action: onClose)
                    .padding(metrics.pagePadding)
            }
        }
        .presentationDragIndicator(onClose == nil ? .hidden : .visible)
#if os(macOS)
        .frame(minWidth: onClose == nil ? nil : metrics.explainerSheetWidth,
               minHeight: onClose == nil ? nil : metrics.explainerSheetHeight)
#endif
    }
}

// MARK: - Sections

/// A group of rows under a quiet heading, on one surface: "How it's built",
/// "What moves it", "Ranges".
public struct SomaExplainerSection<Content: View>: View {
    private let title: String?
    private let content: Content

    @Environment(\.somaTheme) private var theme

    public init(_ title: String?, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    public var body: some View {
        let metrics = theme.metrics
        let colors = theme.colors
        let shape = RoundedRectangle(cornerRadius: metrics.cardCornerRadius, style: .continuous)

        VStack(alignment: .leading, spacing: 0) {
            if let title {
                Text(title)
                    .somaFont(theme.typography.caption)
                    .foregroundStyle(colors.inkSecondary.color)
                    .padding(.horizontal, metrics.explainerRowPadding)
                    .padding(.vertical, metrics.explainerSectionHeaderPadding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(colors.surfaceRecessed.color)
                    .accessibilityAddTraits(.isHeader)
            }
            VStack(alignment: .leading, spacing: 0) {
                Group(subviews: content) { rows in
                    ForEach(rows) { row in
                        row
                        if row.id != rows.last?.id {
                            Rectangle()
                                .fill(colors.inkPrimary.color.opacity(metrics.hairlineOpacity))
                                .frame(height: 0.5)
                                .padding(.leading, metrics.explainerRowPadding)
                        }
                    }
                }
            }
        }
        .background(colors.surface.color)
        .clipShape(shape)
        .overlay(shape.strokeBorder(colors.inkPrimary.color.opacity(metrics.hairlineOpacity), lineWidth: 0.5))
    }
}

// MARK: - Rows

/// One thing the score is built from: a coloured glyph, a bold term, one
/// short line, and the part's weight at the trailing edge when it has one.
public struct SomaExplainerRow: View {
    private let symbol: String
    private let hue: SomaHealthHue
    private let term: String
    private let line: String?
    private let trailing: String?

    @Environment(\.somaTheme) private var theme

    public init(symbol: String, hue: SomaHealthHue, term: String, line: String? = nil, trailing: String? = nil) {
        self.symbol = symbol
        self.hue = hue
        self.term = term
        self.line = line
        self.trailing = trailing
    }

    /// The row of one part of the donut, its weight as a percent.
    public init(_ part: SomaExplainerPart, showsWeight: Bool = true) {
        self.init(symbol: part.symbol, hue: part.hue, term: part.title, line: part.line,
                  trailing: showsWeight ? "\(Int(part.weight.rounded()))%" : nil)
    }

    public var body: some View {
        let metrics = theme.metrics
        let type = theme.typography
        let colors = theme.colors

        HStack(alignment: .top, spacing: metrics.explainerRowGap) {
            SomaExplainerGlyph(symbol: symbol, hue: hue)
            VStack(alignment: .leading, spacing: metrics.explainerLineSpacing) {
                Text(term)
                    .somaFont(type.explainerTerm)
                    .foregroundStyle(colors.inkPrimary.color)
                if let line {
                    Text(line)
                        .somaFont(type.callout)
                        .foregroundStyle(colors.inkSecondary.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let trailing {
                Text(trailing)
                    .somaFont(type.rowValue)
                    .foregroundStyle(hue.color)
            }
        }
        .padding(metrics.explainerRowPadding)
        .accessibilityElement(children: .combine)
    }
}

/// A glyph in a disc of its hue.
public struct SomaExplainerGlyph: View {
    private let symbol: String
    private let hue: SomaHealthHue

    @Environment(\.somaTheme) private var theme

    public init(symbol: String, hue: SomaHealthHue) {
        self.symbol = symbol
        self.hue = hue
    }

    public var body: some View {
        let metrics = theme.metrics
        Image(systemName: symbol)
            .font(.system(size: metrics.explainerGlyphSize, weight: .semibold))
            .foregroundStyle(hue.color)
            .frame(width: metrics.explainerGlyphDiameter, height: metrics.explainerGlyphDiameter)
            .background(Circle().fill(hue.color.opacity(metrics.explainerGlyphTint)))
            .accessibilityHidden(true)
    }
}

/// The small print at the foot of an explainer.
public struct SomaExplainerNote: View {
    private let text: String

    @Environment(\.somaTheme) private var theme

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text)
            .somaFont(theme.typography.caption)
            .foregroundStyle(theme.colors.inkSecondary.color)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, theme.metrics.explainerRowPadding)
    }
}
