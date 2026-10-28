//
//  PulseAroundYouCard.swift
//  Prism
//

import SwiftUI
import SomaUI

/// The last card on Today: what surrounds you, in the shape of the aspect
/// cards above it but with no aspect of its own, so its dot is ink rather
/// than a hue. Minutes of daylight lead, the day's track sits at the trailing
/// edge, and the line under the value names the sound around you.
///
/// Reads the same ``EnvironmentInputs`` and ``EnvironmentReport`` as the
/// Environment lens, without the year of daylight the lens's grid needs.
struct PulseAroundYouCard: View {
    @Environment(HealthDashboard.self) private var health
    @Environment(\.somaTheme) private var theme
    @State private var report: EnvironmentReport?

    var body: some View {
        let metrics = theme.metrics
        let type = theme.typography
        let colors = theme.colors
        let report = self.report ?? EnvironmentReport.make(from: EnvironmentInputs(now: Date()))

        SomaCard {
            HStack(alignment: .center, spacing: metrics.cardSpacing) {
                VStack(alignment: .leading, spacing: theme.metrics.spaceS) {
                    HStack(spacing: metrics.identityDotSpacing) {
                        Circle()
                            .fill(colors.inkSecondary.color)
                            .frame(width: metrics.identityDotDiameter, height: metrics.identityDotDiameter)
                        Text("Around you")
                            .somaFont(type.eyebrow)
                            .foregroundStyle(colors.inkSecondary.color)
                    }

                    SomaNumber(report.daylight.map { "\(Int($0.rounded()))" }, type.metricCompact,
                               unit: String(localized: "min of daylight"))
                        .foregroundStyle(colors.inkPrimary.color)
                    .lineLimit(1)

                    Text(report.summary)
                        .somaFont(type.caption)
                        .foregroundStyle(colors.inkSecondary.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)

                EnvironmentDayTrack(spans: report.daylightSpans, now: report.now,
                                    firstLabel: report.firstOutside, lastLabel: report.lastOutside)
                    .frame(width: metrics.aspectChartWidth)
            }
        }
        .task { await load() }
    }

    private func load() async {
        let calendar = Calendar.current
        let now = Date()
#if DEBUG
        if EnvironmentReport.usesPreview {
            report = EnvironmentReport.preview
            return
        }
#endif
        guard let source = await health.prepare(EnvironmentInputs.metrics) else {
            report = EnvironmentReport.make(from: EnvironmentInputs(now: now), calendar: calendar)
            return
        }
        let inputs = await EnvironmentInputs.read(from: source, now: now, calendar: calendar, wholeYear: false)
        report = EnvironmentReport.make(from: inputs, calendar: calendar)
    }
}
