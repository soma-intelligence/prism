//
//  SomaChoiceChip.swift
//  SomaUI
//

import SwiftUI

/// A capsule a person taps: a tag, a choice, a thing to add.
///
/// Off, a chip is quiet: the outline style is a hairline capsule, the filled
/// and tinted styles sit on the raised surface. On, every style fills with
/// ink and its label turns to the ground's colour, the way a selected
/// segment does in the system: one strong, plain mark of selection, never a
/// coloured wash. The outline style adds a check when on. A tinted chip keeps
/// its feeling's colour on its glyph alone. A chip with a symbol is an
/// action: "+ Drink".
public struct SomaChoiceChip: View {
    public enum Style: Sendable, Equatable {
        case outline
        case filled
        case tinted(SomaAspect)
    }

    private let title: String
    private let symbol: String?
    private let isOn: Bool
    private let style: Style
    private let action: () -> Void

    @Environment(\.somaTheme) private var theme

    public init(_ title: String, symbol: String? = nil, isOn: Bool = false, style: Style = .filled, action: @escaping () -> Void) {
        self.title = title
        self.symbol = symbol
        self.isOn = isOn
        self.style = style
        self.action = action
    }

    public var body: some View {
        let metrics = theme.metrics
        let colors = theme.colors
        let glyph = isOn && style == .outline ? "checkmark" : symbol
        let ink: Color = isOn ? colors.onAccent.color : colors.inkPrimary.color
        let glyphInk: Color = switch style {
        case .tinted(let aspect): isOn ? SomaMoodScale.glow(aspect, theme: theme) : colors.inkSecondary.color
        default: isOn ? colors.onAccent.color : colors.inkSecondary.color
        }

        Button(action: action) {
            HStack(spacing: metrics.spaceXS) {
                if let glyph {
                    Image(systemName: glyph)
                        .font(.system(size: metrics.browseChevronSize, weight: .medium))
                        .foregroundStyle(glyphInk)
                }
                Text(title)
                    .somaFont(theme.typography.callout)
                    .foregroundStyle(ink)
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.horizontal, metrics.spaceM + metrics.spaceXS)
            .frame(minHeight: metrics.minimumTapTarget * 0.84)
            .background(Capsule().fill(fill))
            .overlay {
                if style == .outline && !isOn {
                    Capsule().strokeBorder(colors.inkPrimary.color.opacity(metrics.inputTickFaint), lineWidth: metrics.inputHairline)
                }
            }
            .contentShape(.capsule)
        }
        .buttonStyle(.somaGlassPress)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private var fill: Color {
        let colors = theme.colors
        if isOn { return colors.inkPrimary.color }
        return style == .outline ? .clear : colors.surface.color
    }
}

/// The one primary action at the foot of a screen: a full width capsule in
/// the accent. The secondary style is the quiet choice beside it, "Skip".
public struct SomaActionButton: View {
    public enum Role: Sendable {
        case primary
        case secondary
    }

    private let title: String
    private let role: Role
    private let action: () -> Void

    @Environment(\.somaTheme) private var theme
    @Environment(\.isEnabled) private var isEnabled

    public init(_ title: String, role: Role = .primary, action: @escaping () -> Void) {
        self.title = title
        self.role = role
        self.action = action
    }

    public var body: some View {
        let metrics = theme.metrics
        let colors = theme.colors

        Button(action: action) {
            Text(title)
                .somaFont(theme.typography.body)
                .foregroundStyle(role == .primary ? colors.onAccent.color : colors.inkPrimary.color)
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: metrics.minimumTapTarget + metrics.cardSpacing)
                .background(Capsule().fill(role == .primary ? colors.accent.color : colors.surface.color))
                .opacity(isEnabled ? 1 : 0.4)
                .contentShape(.capsule)
        }
        .buttonStyle(.somaGlassPress)
    }
}

#Preview("Chips and action") {
    ZStack {
        SomaPreviewBackdrop()
        VStack(spacing: 20) {
            HStack {
                SomaChoiceChip("Coffee after 14:00", isOn: true, style: .outline) {}
                SomaChoiceChip("Alcohol", style: .outline) {}
            }
            HStack {
                SomaChoiceChip("Drink", symbol: "plus") {}
                SomaChoiceChip("One bowl", isOn: true) {}
            }
            HStack {
                SomaChoiceChip("Calm", isOn: true, style: .tinted(.gut)) {}
                SomaChoiceChip("Work", symbol: "briefcase", isOn: true, style: .tinted(.gut)) {}
                SomaChoiceChip("Family", symbol: "house", style: .tinted(.gut)) {}
            }
            SomaActionButton("Save") {}
            SomaActionButton("Skip", role: .secondary) {}
        }
        .padding()
    }
}
