//
//  SomaActionCard.swift
//  SomaUI
//

import SwiftUI

/// The one next thing a part offers: an eyebrow, a leading picture, what it is,
/// and the action that does it.
///
/// The detail line is not drawn (owner, 2026-10-03: fewer words); VoiceOver
/// reads it as the title's hint.
///
/// The action is the screen's primary one, so it is the one place the accent
/// fills a shape. A card that has nothing to offer yet passes a nil action and
/// shows its words alone.
public struct SomaActionCard<Leading: View>: View {
    private let eyebrow: String
    private let title: String
    private let detail: String?
    private let actionTitle: String?
    private let action: (() -> Void)?
    private let leading: Leading

    @Environment(\.somaTheme) private var theme

    public init(
        eyebrow: String,
        title: String,
        detail: String?,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil,
        @ViewBuilder leading: () -> Leading
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.detail = detail
        self.actionTitle = actionTitle
        self.action = action
        self.leading = leading()
    }

    public var body: some View {
        let metrics = theme.metrics
        let type = theme.typography
        let colors = theme.colors

        SomaCard {
            VStack(alignment: .leading, spacing: theme.metrics.spaceM) {
                Text(eyebrow)
                    .somaFont(type.eyebrow)
                    .foregroundStyle(colors.inkSecondary.color)

                HStack(alignment: .center, spacing: metrics.moveRowGap) {
                    leading

                    Text(title)
                        .somaFont(type.body)
                        .foregroundStyle(colors.inkPrimary.color)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityHint(detail.map { Text($0) } ?? Text(verbatim: ""))

                    if let actionTitle, let action {
                        Button(action: action) {
                            Text(actionTitle)
                                .somaFont(type.body)
                                .foregroundStyle(colors.onAccent.color)
                                .padding(.horizontal, theme.metrics.spaceL)
                                .frame(minHeight: metrics.chromeCapsuleHeight)
                                .background(Capsule().fill(colors.accent.color))
                                .contentShape(.capsule)
                        }
                        .buttonStyle(SomaGlassPressStyle())
                    }
                }
            }
        }
    }
}

#Preview("Action card") {
    ZStack {
        SomaPreviewBackdrop()
        SomaActionCard(eyebrow: "A ritual for tonight", title: "Breathe for 10 minutes",
                       detail: "Brings your HRV back toward 48 ms.", actionTitle: "Start", action: {}) {
            SomaOrb(aspect: .mind, scale: .mini)
        }
        .padding()
    }
}
