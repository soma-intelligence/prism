//
//  SomaAspectTile.swift
//  SomaUI
//

import SwiftUI

/// One aspect as a small square tile: its glyph on a tinted badge at the top,
/// its name at the foot, and when there is one, the value that sums it up
/// across from the badge.
///
/// Set three to a row they make the grid of aspects at the foot of Today. The
/// tile draws no chevron: the whole tile is the door, and the page zooms out
/// of it.
public struct SomaAspectTile: View {
    private let aspect: SomaAspect
    private let value: String?

    @Environment(\.somaTheme) private var theme

    /// - Parameter value: today's score or reading, set small at the top
    ///   trailing corner. Nil draws nothing there.
    public init(aspect: SomaAspect, value: String? = nil) {
        self.aspect = aspect
        self.value = value
    }

    public var body: some View {
        let metrics = theme.metrics
        let type = theme.typography
        let colors = theme.colors

        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                SomaAspectGlyph(aspect, style: .badge)
                Spacer(minLength: 0)
                if let value {
                    Text(verbatim: value)
                        .somaFont(type.captionValue)
                        .foregroundStyle(colors.inkSecondary.color)
                }
            }
            Spacer(minLength: metrics.aspectTileSpacing)
            Text(aspect.title)
                .somaFont(type.callout)
                .foregroundStyle(colors.inkPrimary.color)
                .lineLimit(1)
        }
        .padding(metrics.cardPadding - 2)
        .frame(maxWidth: .infinity, minHeight: metrics.aspectTileHeight, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: metrics.cardCornerRadius, style: .continuous)
                .fill(colors.surface.color)
        )
        .overlay(
            RoundedRectangle(cornerRadius: metrics.cardCornerRadius, style: .continuous)
                .strokeBorder(colors.inkPrimary.color.opacity(metrics.hairlineOpacity), lineWidth: 0.5)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(aspect.title))
        .accessibilityValue(Text(verbatim: value ?? ""))
    }
}

/// A quiet control set under a section: a glyph and a few words on a recessed
/// capsule, for the things a page offers but never pushes (customise the page,
/// browse everything).
public struct SomaQuietPill: View {
    private let title: LocalizedStringResource
    private let systemImage: String

    @Environment(\.somaTheme) private var theme

    public init(_ title: LocalizedStringResource, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }

    public var body: some View {
        let metrics = theme.metrics
        let colors = theme.colors

        HStack(spacing: metrics.identityDotSpacing + 2) {
            Image(systemName: systemImage)
                .foregroundStyle(colors.inkSecondary.color)
                .imageScale(.small)
            Text(title)
                .foregroundStyle(colors.inkPrimary.color)
        }
        .somaFont(theme.typography.callout)
        .lineLimit(1)
        .padding(.horizontal, metrics.quietPillPadding)
        .frame(minHeight: metrics.quietPillHeight)
        .background(Capsule().fill(colors.surfaceRecessed.color))
        .contentShape(Capsule())
    }
}

#Preview("Aspect tiles") {
    ZStack {
        SomaPreviewBackdrop()
        VStack(spacing: 16) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(SomaAspect.allCases) { aspect in
                    SomaAspectTile(aspect: aspect, value: aspect == .sleep ? "87" : nil)
                }
            }
            HStack(spacing: 10) {
                SomaQuietPill("Edit Today", systemImage: "slider.horizontal.3")
                SomaQuietPill("All measures", systemImage: "magnifyingglass")
            }
        }
        .padding()
    }
}
