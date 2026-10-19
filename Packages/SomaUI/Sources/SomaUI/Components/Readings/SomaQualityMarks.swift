//
//  SomaQualityMarks.swift
//  SomaUI
//

import SwiftUI

/// How much weight a reading can bear, as a short row of dots: the filled ones
/// in ink, the rest recessed.
///
/// Ink and not the accent: a grade is a fact about a reading, not something a
/// person chose, and a screen of records would otherwise be speckled with the
/// one colour that means "act here". Zero filled marks is a grade too, the one
/// that says the source was not recognised.
public struct SomaQualityMarks: View {
    private let filled: Int
    private let total: Int

    @Environment(\.somaTheme) private var theme

    /// - Parameters:
    ///   - filled: how many marks to fill, clamped to `0...total`.
    ///   - total: how many marks the scale has.
    public init(filled: Int, of total: Int) {
        self.total = max(1, total)
        self.filled = min(max(0, filled), self.total)
    }

    public var body: some View {
        let metrics = theme.metrics
        let ink = theme.colors.inkPrimary.color

        HStack(spacing: metrics.identityDotSpacing / 2) {
            ForEach(0..<total, id: \.self) { index in
                Circle()
                    .fill(index < filled ? ink.opacity(metrics.energyFullOpacity) : ink.opacity(metrics.hairlineOpacity))
                    .frame(width: metrics.timelineDotDiameter, height: metrics.timelineDotDiameter)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(filled) of \(total)"))
    }
}

#Preview("Quality marks") {
    ZStack {
        SomaPreviewBackdrop()
        VStack(spacing: 16) {
            ForEach(0..<5, id: \.self) { level in
                SomaQualityMarks(filled: level, of: 4)
            }
        }
        .padding()
    }
}
