//
//  SomaTopicChip.swift
//  SomaUI
//

import SwiftUI

/// A filter capsule for one topic, led by a dot in the topic's Health hue.
///
/// Chosen, the capsule fills with the hue and its label turns to the near
/// black that Health sets on its tiles, which clears 4.5:1 on every hue. A
/// chip without a hue is "All": chosen, it takes the accent, the way the
/// rest of the app marks a selection.
public struct SomaTopicChip: View {
    private let title: String
    private let hue: SomaHealthHue?
    private let isOn: Bool
    private let action: () -> Void

    @Environment(\.somaTheme) private var theme

    public init(_ title: String, hue: SomaHealthHue?, isOn: Bool, action: @escaping () -> Void) {
        self.title = title
        self.hue = hue
        self.isOn = isOn
        self.action = action
    }

    public var body: some View {
        let metrics = theme.metrics

        Button(action: action) {
            HStack(spacing: metrics.articleChipDot * 0.75) {
                if let hue, !isOn {
                    Circle()
                        .fill(hue.color)
                        .frame(width: metrics.articleChipDot, height: metrics.articleChipDot)
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
            .contentShape(.capsule)
        }
        .buttonStyle(.somaGlassPress)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private var ink: Color {
        let colors = theme.colors
        guard isOn else { return colors.inkPrimary.color }
        return hue == nil ? colors.onAccent.color : SomaHealthHue.ink.color
    }

    private var fill: Color {
        let colors = theme.colors
        guard isOn else { return colors.surface.color }
        return hue?.color ?? colors.accent.color
    }
}

#Preview("Topic chips") {
    HStack(spacing: 8) {
        SomaTopicChip("All", hue: nil, isOn: true) {}
        SomaTopicChip("Sleep", hue: .sleep, isOn: false) {}
        SomaTopicChip("Heart", hue: .heart, isOn: true) {}
        SomaTopicChip("Mind", hue: .mind, isOn: false) {}
    }
    .padding()
}
