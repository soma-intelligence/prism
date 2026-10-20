//
//  SomaFactStrip.swift
//  SomaUI
//

import SwiftUI

/// One compact fact under a metric's chart: what it is, the value, and a few
/// quiet words under it. A tone other than neutral colours the value
/// ("Up 4%" in the good tone), never the words.
public struct SomaFact: Identifiable, Equatable, Sendable {
    public var id: String { label }
    public var label: String
    /// Nil for a dash.
    public var value: String?
    public var detail: String?
    public var tone: SomaCueTone

    public init(_ label: String, value: String?, detail: String? = nil, tone: SomaCueTone = .neutral) {
        self.label = label
        self.value = value
        self.detail = detail
        self.tone = tone
    }
}

/// Up to three facts side by side on one quiet card, split by hairlines:
/// enough to read a metric at a glance without a table.
///
/// Numbers roll when they change; under Reduce Motion they change in place.
public struct SomaFactStrip: View {
    private let facts: [SomaFact]

    @Environment(\.somaTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Only the first three are shown.
    public init(_ facts: [SomaFact]) {
        self.facts = Array(facts.prefix(3))
    }

    public var body: some View {
        let colors = theme.colors
        let metrics = theme.metrics

        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(facts.enumerated()), id: \.element.id) { index, fact in
                if index > 0 {
                    Rectangle()
                        .fill(colors.inkPrimary.color.opacity(metrics.hairlineOpacity))
                        .frame(width: 0.5)
                        .padding(.vertical, metrics.metricFactSpacing * 2)
                }
                VStack(alignment: .leading, spacing: metrics.metricFactSpacing) {
                    Text(fact.label)
                        .somaFont(theme.typography.caption)
                        .foregroundStyle(colors.inkSecondary.color)
                        .lineLimit(1)
                    Text(fact.value ?? "-")
                        .somaFont(theme.typography.metricFact)
                        .foregroundStyle(fact.tone == .neutral ? colors.inkPrimary.color : fact.tone.color(colors))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .contentTransition(reduceMotion ? .identity : .numericText())
                    if let detail = fact.detail {
                        Text(detail)
                            .somaFont(theme.typography.caption)
                            .foregroundStyle(colors.inkSecondary.color)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, metrics.cardPadding)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.vertical, metrics.cardPadding)
        .background(colors.surface.color, in: .rect(cornerRadius: metrics.cardCornerRadius, style: .continuous))
        .animation(reduceMotion ? nil : theme.motion.numberRoll, value: facts)
    }
}

#Preview("Fact strip") {
    VStack(spacing: 16) {
        SomaFactStrip([
            SomaFact("Your usual", value: "7.1k to 9.4k"),
            SomaFact("30 day trend", value: "Up 4%", detail: "From 7,950", tone: .good),
            SomaFact("Usual days", value: "21 of 30"),
        ])
        SomaFactStrip([SomaFact("Typical", value: "95 to 100 %"), SomaFact("30 day trend", value: nil)])
    }
    .padding()
}
