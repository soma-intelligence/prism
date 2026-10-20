//
//  SomaTopicChip.swift
//  SomaUI
//

import SwiftUI

/// A filter capsule for one topic, led by a dot in the topic's calm tone.
///
/// Chosen, any chip takes the accent the way the rest of the app marks a
/// selection, and its dot steps aside: the tone names the topic, the accent
/// says it is chosen. A chip without a tone is "All".
public struct SomaTopicChip: View {
    private let title: String
    private let tone: SomaTrackTone?
    private let isOn: Bool
    private let action: () -> Void

    @Environment(\.somaTheme) private var theme

    public init(_ title: String, tone: SomaTrackTone?, isOn: Bool, action: @escaping () -> Void) {
        self.title = title
        self.tone = tone
        self.isOn = isOn
        self.action = action
    }

    public var body: some View {
        let metrics = theme.metrics

        Button(action: action) {
            HStack(spacing: metrics.articleChipDot * 0.75) {
                if let tone, !isOn {
                    Circle()
                        .fill(tone.color)
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
        return isOn ? colors.onAccent.color : colors.inkPrimary.color
    }

    private var fill: Color {
        let colors = theme.colors
        guard isOn else { return colors.surface.color }
        return colors.accent.color
    }
}

#Preview("Topic chips") {
    HStack(spacing: 8) {
        SomaTopicChip("All", tone: nil, isOn: false) {}
        SomaTopicChip("Sleep", tone: .dusk, isOn: false) {}
        SomaTopicChip("Heart", tone: .rose, isOn: true) {}
        SomaTopicChip("Mind", tone: .sage, isOn: false) {}
    }
    .padding()
}
