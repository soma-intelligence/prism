//
//  SomaChoiceChip.swift
//  SomaUI
//

import SwiftUI

/// A capsule a person taps: a tag, a choice, a thing to add.
///
/// The outline style is a tag that can be on or off; on, it takes the raised
/// surface and a check in the accent. The filled style is one choice among a
/// few (a portion, a preset, a word); chosen, its label turns to the accent.
/// A chip with a symbol is an action: "+ Drink". The tinted style is one of
/// several picks that wear a colour: chosen, it fills with a wash of the
/// aspect's bright orb colour and its glyph takes the aspect's hue, the way a mood's words take the
/// colour of the feeling.
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
        let ink: Color = switch style {
        case .outline: isOn ? colors.inkPrimary.color : colors.inkSecondary.color
        case .filled: isOn ? colors.accent.color : colors.inkPrimary.color
        case .tinted: colors.inkPrimary.color
        }
        let glyphInk: Color = switch style {
        case .tinted(let aspect): isOn ? theme.aspects[aspect].identity.color : colors.inkSecondary.color
        default: isOn ? colors.accent.color : colors.inkPrimary.color
        }

        Button(action: action) {
            HStack(spacing: metrics.scoreLabelSpacing * 3) {
                if let glyph {
                    Image(systemName: glyph)
                        .font(.system(size: metrics.browseChevronSize, weight: .semibold))
                        .foregroundStyle(glyphInk)
                }
                Text(title)
                    .somaFont(theme.typography.callout)
                    .foregroundStyle(ink)
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.horizontal, metrics.cardPadding * 0.875)
            .frame(minHeight: metrics.minimumTapTarget * 0.84)
            .background(Capsule().fill(fill))
            .overlay {
                switch style {
                case .outline:
                    Capsule().strokeBorder(
                        colors.inkPrimary.color.opacity(isOn ? metrics.hairlineOpacity : metrics.browseSeparatorOpacity),
                        lineWidth: 1
                    )
                case .tinted(let aspect) where isOn:
                    Capsule().strokeBorder(SomaMoodScale.glow(aspect, theme: theme).opacity(metrics.chipTintRimOpacity), lineWidth: 1)
                default:
                    EmptyView()
                }
            }
            .contentShape(.capsule)
        }
        .buttonStyle(.somaGlassPress)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private var fill: Color {
        let colors = theme.colors
        let metrics = theme.metrics
        switch style {
        case .outline: return isOn ? colors.surface.color : .clear
        case .filled: return isOn ? colors.surfaceRecessed.color : colors.surface.color
        case .tinted(let aspect):
            return isOn ? SomaMoodScale.glow(aspect, theme: theme).opacity(metrics.chipTintOpacity) : colors.surface.color
        }
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
