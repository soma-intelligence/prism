//
//  SomaPageHero.swift
//  SomaUI
//

import SwiftUI

/// The head of a page: an eyebrow and the one line the page is about.
///
/// The reason is not drawn (owner, 2026-10-03: fewer words, the numbers under
/// the head say it); VoiceOver reads it as the headline's hint.
public struct SomaPageHero: View {
    private let eyebrow: String?
    private let title: String
    private let reason: String?

    @Environment(\.somaTheme) private var theme

    /// - Parameters:
    ///   - eyebrow: set in small capitals above: "Lean mass · eight weeks".
    ///   - title: the headline: "Your legs carried the change."
    ///   - reason: one or more sentences explaining it.
    public init(eyebrow: String?, title: String, reason: String?) {
        self.eyebrow = eyebrow
        self.title = title
        self.reason = reason
    }

    public var body: some View {
        let type = theme.typography
        let colors = theme.colors

        VStack(alignment: .leading, spacing: 8) {
            if let eyebrow {
                Text(eyebrow)
                    .somaFont(type.eyebrow)
                    .textCase(.uppercase)
                    .foregroundStyle(colors.inkSecondary.color)
            }

            Text(title)
                .somaFont(type.headline)
                .foregroundStyle(colors.inkPrimary.color)
                .accessibilityAddTraits(.isHeader)
                .accessibilityHint(reason.map { Text($0) } ?? Text(verbatim: ""))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview("Page hero") {
    ZStack {
        SomaPreviewBackdrop()
        SomaPageHero(
            eyebrow: "Lean mass · eight weeks",
            title: "You’ve built lean mass.",
            reason: "Lean mass rose 1.5 kg in eight weeks, read by your smart scale through Apple Health."
        )
        .padding()
    }
}
