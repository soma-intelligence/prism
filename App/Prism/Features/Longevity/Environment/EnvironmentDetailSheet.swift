//
//  EnvironmentDetailSheet.swift
//  Prism
//

import SwiftUI
import SomaUI
import HealthExportCore

/// One measure of the Environment lens up close: the value on its scale, the
/// last 7 or 30 days as a chart over the usual band, the low, average and
/// high, and, for a Health reading, every record in the Vault.
struct EnvironmentDetailSheet: View {
    let measure: EnvironmentMeasure
    let report: EnvironmentReport

    var body: some View {
        ScoreSheet(eyebrow: "Environment", title: LocalizedStringResource(stringLiteral: measure.title)) {
            if measure == .temperature {
                EnvironmentTemperatureBody(report: report)
            } else {
                EnvironmentDetailBody(measure: measure, report: report)
            }
        }
    }
}

/// What the sheet holds, below its title.
struct EnvironmentDetailBody: View {
    let measure: EnvironmentMeasure
    let report: EnvironmentReport

    @State private var span = 7
    @Environment(\.somaTheme) private var theme

    private struct VaultLink: Identifiable {
        let id = "records"
        let type: BodyDataType
    }

    var body: some View {
        let metrics = theme.metrics
        let colors = theme.colors
        let value = measure.current(report)
        let status = measure.status(value, report: report, colors: colors)
        let points = points(span)
        let values = points.map(\.value)
        let average = PulseTrends.mean(values)

        VStack(alignment: .leading, spacing: metrics.cardSpacing) {
            SomaCard {
                VStack(alignment: .leading, spacing: metrics.cardSpacing) {
                    HStack(alignment: .firstTextBaseline) {
                        EnvironmentValue(text: value.map(measure.format), unit: measure.unit,
                                         tint: value.map { measure.scale.value(at: $0).color })
                        Spacer(minLength: 0)
                        if let status {
                            Text(verbatim: status.word)
                                .somaFont(theme.typography.caption)
                                .foregroundStyle(status.color)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(status.color.opacity(0.16)))
                        }
                    }
                    SomaScaleBar(scale: measure.scale, value: value, style: measure.barStyle,
                                 limit: measure.limit, ticks: measure.ticks)
                }
            }
            .navigationDestination(for: VaultRoute.self) { $0.page }

            Picker("Period", selection: $span) {
                Text("7D").tag(7)
                Text("30D").tag(30)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            SomaCard {
                if points.count > 1 {
                    SomaRangeChart(points, band: measure.band(report), average: average,
                                   format: { $0.formatted(.number.precision(.fractionLength(0))) })
                        .frame(height: 200)
                } else {
                    Text(verbatim: "-")
                        .somaFont(theme.typography.metric)
                        .foregroundStyle(colors.inkSecondary.color)
                        .frame(maxWidth: .infinity, minHeight: 200)
                }
            }

            SomaStatRow([
                SomaStat("Low", value: values.min().map(measure.format), unit: unit),
                SomaStat("Average", value: average.map(measure.format), unit: unit),
                SomaStat("High", value: values.max().map(measure.format), unit: unit),
            ])
            .padding(.vertical, 4)

            if let metric = measure.metric {
                SomaBrowseGroup([VaultLink(type: BodyDataType(metric))], hasGlyphs: false) { link in
                    NavigationLink(value: VaultRoute.dataType(link.type)) {
                        SomaBrowseRow(title: "All records", detail: nil)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var unit: LocalizedStringResource? {
        measure.unit.isEmpty ? nil : LocalizedStringResource(stringLiteral: measure.unit)
    }

    /// The last `count` days that hold a value, each on its date.
    private func points(_ count: Int) -> [SomaChartPoint] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: report.today)
        let days = measure.days(report)
        return days.suffix(count).enumerated().compactMap { index, value in
            let offset = min(count, days.count) - 1 - index
            guard let value, let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return SomaChartPoint(date: date, value: value)
        }
    }
}
