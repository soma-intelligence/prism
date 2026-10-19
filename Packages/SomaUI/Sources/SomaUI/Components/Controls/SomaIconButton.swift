//
//  SomaIconButton.swift
//  SomaUI
//

import SwiftUI

/// How an icon button sits on its ground.
public enum SomaIconButtonStyle: Sendable, Equatable, CaseIterable {
    /// A glass disc. For floating chrome only: a bar, an overlay, a toolbar.
    case glass
    /// No material of its own. For a button inside a surface that already has
    /// one, such as a sidebar: glass laid on glass is decoration, and the rule
    /// is that glass is floating chrome or nothing.
    case plain
}

/// A round button carrying one glyph.
public struct SomaIconButton: View {
    private let symbol: String
    private let style: SomaIconButtonStyle
    private let accessibilityLabel: LocalizedStringResource
    private let action: () -> Void

    public init(
        symbol: String,
        style: SomaIconButtonStyle = .glass,
        accessibilityLabel: LocalizedStringResource,
        action: @escaping () -> Void
    ) {
        self.symbol = symbol
        self.style = style
        self.accessibilityLabel = accessibilityLabel
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            SomaIconLabel(symbol: symbol, style: style)
        }
        .buttonStyle(.somaGlassPress)
        .somaIconMaterial(style)
        .accessibilityLabel(Text(accessibilityLabel))
    }
}

/// The inside of a ``SomaIconButton``, for controls that bring their own button:
/// a `ShareLink`, a `Menu`, a `NavigationLink`.
///
/// Wrap it with `.buttonStyle(.somaGlassPress)` and `.somaIconMaterial(style)`
/// so one glyph never looks unlike the next.
public struct SomaIconLabel: View {
    private let symbol: String
    private let style: SomaIconButtonStyle

    @Environment(\.somaTheme) private var theme

    public init(symbol: String, style: SomaIconButtonStyle = .glass) {
        self.symbol = symbol
        self.style = style
    }

    private var size: CGFloat {
        max(theme.metrics.iconButtonDiameter, theme.metrics.minimumTapTarget)
    }

    public var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.42, weight: .medium))
            .foregroundStyle(
                style == .glass
                    ? theme.colors.inkPrimary.color
                    : theme.colors.inkSecondary.color
            )
            .frame(width: size, height: size)
            .contentShape(.circle)
    }
}

public extension View {
    /// The material an icon button of this style sits on.
    @ViewBuilder
    func somaIconMaterial(_ style: SomaIconButtonStyle) -> some View {
        switch style {
        case .glass: somaGlass(.regular, in: .circle)
        case .plain: self
        }
    }
}

#Preview("Icon Button") {
    ZStack {
        SomaPreviewBackdrop()

        VStack(spacing: 20) {
            HStack(spacing: 12) {
                SomaIconButton(symbol: "square.and.arrow.up", accessibilityLabel: "Share") {}
                SomaIconButton(symbol: "gearshape", accessibilityLabel: "Settings") {}
            }
            HStack(spacing: 12) {
                SomaIconButton(symbol: "square.and.arrow.up", style: .plain,
                               accessibilityLabel: "Share") {}
                SomaIconButton(symbol: "gearshape", style: .plain,
                               accessibilityLabel: "Settings") {}
            }
        }
    }
}
