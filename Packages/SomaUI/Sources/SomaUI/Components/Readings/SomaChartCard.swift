//
//  SomaChartCard.swift
//  SomaUI
//

import SwiftUI

/// A card about one number and the chart that explains it: the name as the
/// card's title, the value large with its unit,
/// and the chart under them.
///
/// The note is not drawn (owner, 2026-10-03: fewer words, the chart says it).
/// VoiceOver still reads it, as the card's hint, because a chart alone tells a
/// listener nothing. A missing value reads as a dash.
public struct SomaChartCard<Chart: View>: View {
    private let eyebrow: String
    private let value: String?
    private let unit: String?
    private let note: String?
    private let chart: Chart

    @Environment(\.somaTheme) private var theme

    public init(
        eyebrow: String,
        value: String?,
        unit: String? = nil,
        note: String?,
        @ViewBuilder chart: () -> Chart
    ) {
        self.eyebrow = eyebrow
        self.value = value
        self.unit = unit
        self.note = note
        self.chart = chart()
    }

    public var body: some View {
        let type = theme.typography
        let colors = theme.colors

        SomaCard {
            VStack(alignment: .leading, spacing: theme.metrics.spaceS) {
                Text(eyebrow)
                    .somaFont(type.cardTitle)
                    .foregroundStyle(colors.inkPrimary.color)

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    SomaNumber(value, type.metric)
                        .foregroundStyle(colors.inkPrimary.color)
                        .somaRollingNumber(value, holdsWidth: unit != nil)
                    if let unit, value != nil {
                        Text(unit)
                            .somaFont(type.callout)
                            .foregroundStyle(colors.inkSecondary.color)
                    }
                }
                .accessibilityElement(children: .combine)

                chart
                    .padding(.top, theme.metrics.chartLabelGap * 2)
            }
        }
        .accessibilityHint(note.map { Text($0) } ?? Text(verbatim: ""))
    }
}

#Preview("Chart card") {
    ZStack {
        SomaPreviewBackdrop()
        SomaChartCard(eyebrow: "Mindful minutes", value: "12", unit: "min today",
                      note: "On days with ten minutes or more, your evening HRV comes back sooner.") {
            SomaNightBars(aspect: .mind, values: [4, 0, 14, 5, 8, 0, 12])
        }
        .padding()
    }
}
