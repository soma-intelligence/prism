//
//  SomaMetricHero.swift
//  SomaUI
//

import SwiftUI

/// The head of a metric's page: when the number is from, the number large
/// and light with its unit, and one plain line on what it means, led by a dot
/// in that line's tone ("Above your usual").
///
/// The number rolls to a new value rather than blinking; under Reduce Motion
/// it changes in place. A missing value is a dash, and the line under it says
/// what the page is waiting for.
public struct SomaMetricHero: View {
    private let caption: String?
    private let value: String?
    private let unit: String?
    private let meaning: String?
    private let tone: SomaCueTone

    @Environment(\.somaTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameters:
    ///   - caption: when the number is from: "Today so far", "Last night".
    ///   - meaning: one plain line, never a sentence with a full stop.
    public init(caption: String?, value: String?, unit: String?, meaning: String?, tone: SomaCueTone = .neutral) {
        self.caption = caption
        self.value = value
        self.unit = unit
        self.meaning = meaning
        self.tone = tone
    }

    public var body: some View {
        let colors = theme.colors
        let metrics = theme.metrics

        VStack(alignment: .leading, spacing: metrics.metricHeroSpacing) {
            if let caption {
                Text(caption)
                    .somaFont(theme.typography.eyebrow)
                    .foregroundStyle(colors.inkSecondary.color)
            }
            HStack(alignment: .firstTextBaseline, spacing: metrics.metricHeroSpacing * 1.5) {
                if let value {
                    Text(value)
                        .somaFont(theme.typography.metricHero)
                        .foregroundStyle(colors.inkPrimary.color)
                        .contentTransition(reduceMotion ? .identity : .numericText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    if let unit {
                        Text(unit)
                            .somaFont(theme.typography.metricHeroUnit)
                            .foregroundStyle(colors.inkSecondary.color)
                    }
                } else {
                    SomaMissingValue(theme.typography.metricHero)
                }
            }
            if let meaning {
                HStack(spacing: metrics.metricHeroSpacing * 2) {
                    Circle()
                        .fill(tone.color(colors))
                        .frame(width: metrics.metricMeaningDot, height: metrics.metricMeaningDot)
                    Text(meaning)
                        .somaFont(theme.typography.callout)
                        .foregroundStyle(colors.inkPrimary.color)
                        .contentTransition(.opacity)
                }
            }
        }
        .animation(reduceMotion ? nil : theme.motion.numberRoll, value: value)
        .animation(reduceMotion ? nil : theme.motion.numberRoll, value: meaning)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

#Preview("Metric hero") {
    VStack(alignment: .leading, spacing: 32) {
        SomaMetricHero(caption: "Today so far", value: "6,557", unit: nil, meaning: "531 more for a usual day", tone: .neutral)
        SomaMetricHero(caption: "Last night", value: "7h 54m", unit: nil, meaning: "Within your usual", tone: .good)
        SomaMetricHero(caption: "Today", value: "97.5", unit: "%", meaning: "In the typical range", tone: .good)
        SomaMetricHero(caption: nil, value: nil, unit: "bpm", meaning: "Waiting for a first reading")
    }
    .padding()
}
