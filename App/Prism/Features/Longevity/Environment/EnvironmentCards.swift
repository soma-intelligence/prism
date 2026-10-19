//
//  EnvironmentCards.swift
//  Prism
//

import SwiftUI
import Charts
import SomaUI

/// Everything the Environment lens draws, without the scroll view around
/// it: the weather pill, the three stats, then light, air, sound and sleep.
/// Every card is a button; the lens decides what each one opens.
struct EnvironmentLensContent: View {
    let report: EnvironmentReport
    let sky: EnvironmentSky
    let bedroom: EnvironmentBedroom
    var here = EnvironmentHere(access: .denied, place: nil, isHere: false)
    var sleepPlaces: [EnvironmentSleepPlace] = []
    var open: (EnvironmentMeasure) -> Void = { _ in }
    var openBedroom: () -> Void = {}
    var openPlaces: () -> Void = {}
    var requestLocation: () -> Void = {}

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics
        let colors = theme.colors

        VStack(alignment: .leading, spacing: metrics.leadSpacing) {
            VStack(alignment: .leading, spacing: metrics.leadSpacing) {
                Button { open(.temperature) } label: {
                    SomaWeatherPill(symbol: report.outside?.symbol ?? "cloud.sun.fill",
                                    value: report.outside?.temperature.map { "\(Int($0.rounded()))°C" },
                                    place: here.place?.name ?? (here.place == nil ? nil : "Here"))
                }
                .buttonStyle(.somaGlassPress)

                SomaStatRow(stats) { stat in
                    switch stat.id {
                    case "Air quality": open(.air)
                    case "UV now": open(.uv)
                    default: open(.daylight)
                    }
                }
            }
            .padding(.top, metrics.heroTopPadding)

            EnvironmentSection("Where you are") {
                EnvironmentWhereCard(here: here, report: report, sky: sky, open: open, requestLocation: requestLocation)
            }

            EnvironmentSection("Light") {
                EnvironmentTap { open(.daylight) } label: {
                    EnvironmentDaylightCard(report: report, sky: sky)
                }
                EnvironmentTap { open(.uv) } label: {
                    EnvironmentScaleCard(measure: .uv, report: report)
                }
            }

            EnvironmentSection("Air") {
                EnvironmentTap { open(.air) } label: {
                    EnvironmentScaleCard(measure: .air, report: report)
                }
                EnvironmentTap { open(.temperature) } label: {
                    SomaThermometerPill(now: report.outside?.temperature, low: report.outside?.low, high: report.outside?.high)
                }
            }

            EnvironmentSection("Sound") {
                EnvironmentSoundCard(report: report, open: open)
            }

            EnvironmentSection("Sleep") {
                EnvironmentBedroomCard(bedroom: bedroom, open: openBedroom, openPlaces: openPlaces)
                EnvironmentSleepPlacesCard(places: sleepPlaces, open: openPlaces)
            }

            EnvironmentSection("Days outside") {
                EnvironmentTap { open(.daylight) } label: {
                    SomaChartCard(eyebrow: "This year", value: report.daysOutside, unit: "days",
                                  note: "\(Int(EnvironmentReport.outsideMinutes)) min or more") {
                        PulseYearGridView(grid: report.grid, style: .squares, levels: [1, 15, EnvironmentReport.outsideMinutes, 60])
                            .accessibilityElement()
                            .accessibilityLabel("Days outside this year")
                            .accessibilityValue(report.daysOutside.map { "\($0) days" } ?? "-")
                    }
                }
            }
        }
        .foregroundStyle(colors.inkPrimary.color)
    }

    private var stats: [SomaStat] {
        let uvStatus = EnvironmentMeasure.uv.status(EnvironmentMeasure.uv.current(report), report: report, colors: theme.colors)
        let daylightStatus = EnvironmentMeasure.daylight.status(report.daylight, report: report, colors: theme.colors)
        let uv = EnvironmentMeasure.uv.current(report)
        let aqi = report.outside?.aqi
        let airStatus = EnvironmentMeasure.air.status(aqi, report: report, colors: theme.colors)
        return [
            SomaStat("Air quality", value: aqi.map(EnvironmentMeasure.air.format),
                     cue: airStatus.map { LocalizedStringResource(stringLiteral: $0.word) },
                     cueTone: (aqi ?? 0) > 100 ? .watch : (aqi == nil ? .neutral : .good)),
            SomaStat("UV now", value: uv.map(EnvironmentMeasure.uv.format),
                     cue: uvStatus.map { LocalizedStringResource(stringLiteral: $0.word) },
                     cueTone: (uv ?? 0) >= 6 ? .watch : .neutral),
            SomaStat("Daylight", value: report.daylight.map(EnvironmentMeasure.daylight.format), unit: "min",
                     trend: report.isDaylightLow ? .down : nil,
                     cue: daylightStatus.map { LocalizedStringResource(stringLiteral: $0.word) },
                     cueTone: report.isDaylightLow ? .watch : (daylightStatus == nil ? .neutral : .good)),
        ]
    }
}

// MARK: - Light

/// Today's minutes in daylight as a ring against the usual band, the usual
/// and what is left of the sun beside it, and the sun's path under both.
private struct EnvironmentDaylightCard: View {
    let report: EnvironmentReport
    let sky: EnvironmentSky

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics
        let type = theme.typography
        let colors = theme.colors
        let words = PulseWording(calendar: .current, locale: .current)
        let status = EnvironmentMeasure.daylight.status(report.daylight, report: report, colors: colors)

        EnvironmentCardFrame(title: "Daylight", status: status) {
            HStack(alignment: .center, spacing: metrics.cardSpacing) {
                SomaArcGauge(scale: .daylight, value: report.daylight, band: report.daylightUsual) {
                    VStack(spacing: 0) {
                        Text(verbatim: report.daylight.map(EnvironmentMeasure.daylight.format) ?? "-")
                            .somaFont(type.metric)
                            .foregroundStyle(colors.inkPrimary.color)
                        Text("min")
                            .somaFont(type.caption)
                            .foregroundStyle(colors.inkSecondary.color)
                    }
                }
                VStack(alignment: .leading, spacing: metrics.cardSpacing) {
                    EnvironmentFigure(label: "Usual", value: report.daylightUsual.map {
                        "\(Int($0.lowerBound)) to \(Int($0.upperBound))"
                    }, unit: "min")
                    EnvironmentFigure(label: "Sun left", value: sky.left, unit: nil)
                    EnvironmentFigure(label: "Outside", value: report.firstOutside.map { first in
                        report.lastOutside.map { "\(first) to \($0)" } ?? first
                    }, unit: nil)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            SomaSunPath(progress: sky.progress, rise: sky.rise(words), set: sky.set(words))
                .padding(.top, 4)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Daylight")
        .accessibilityValue(report.daylight.map { "\(Int($0.rounded())) minutes" } ?? "-")
    }
}

/// A measure on its coloured scale: the value large, its word in its colour,
/// the scale bar under it.
private struct EnvironmentScaleCard: View {
    let measure: EnvironmentMeasure
    let report: EnvironmentReport

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let colors = theme.colors
        let value = measure.current(report)
        let status = measure.status(value, report: report, colors: colors)

        EnvironmentCardFrame(title: measure.title, status: status) {
            EnvironmentValue(text: value.map(measure.format), unit: measure.unit,
                             tint: value.map { measure.scale.value(at: $0).color })
            SomaScaleBar(scale: measure.scale, value: value, style: measure.barStyle,
                         limit: measure.limit, ticks: measure.ticks)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: measure.title))
        .accessibilityValue(Text(verbatim: value.map(measure.format) ?? "-"))
    }
}

// MARK: - Sound

/// The sound around you and in your headphones, each a level against its
/// limit, and the two over the week as lines against the same limits.
private struct EnvironmentSoundCard: View {
    let report: EnvironmentReport
    let open: (EnvironmentMeasure) -> Void

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics

        SomaCard {
            VStack(alignment: .leading, spacing: metrics.cardSpacing) {
                ForEach([EnvironmentMeasure.sound, .headphones]) { measure in
                    Button { open(measure) } label: {
                        EnvironmentLevelRow(measure: measure, report: report).contentShape(.rect)
                    }
                    .buttonStyle(.somaGlassPress)
                }
                EnvironmentSoundWeek(report: report)
                    .frame(height: metrics.chartSparkHeight * 2.4)
                    .padding(.top, 4)
            }
        }
    }
}

private struct EnvironmentLevelRow: View {
    let measure: EnvironmentMeasure
    let report: EnvironmentReport

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let type = theme.typography
        let colors = theme.colors
        let value = measure.current(report)
        let status = measure.status(value, report: report, colors: colors)

        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Circle()
                    .fill(EnvironmentSoundWeek.hue(measure))
                    .frame(width: theme.metrics.chartPointDiameter, height: theme.metrics.chartPointDiameter)
                Text(verbatim: measure.title)
                    .somaFont(type.body)
                    .foregroundStyle(colors.inkPrimary.color)
                if measure == .headphones {
                    Text("7 days")
                        .somaFont(type.caption)
                        .foregroundStyle(colors.inkSecondary.color)
                }
                Spacer(minLength: 0)
                if let status {
                    Text(verbatim: status.word)
                        .somaFont(type.caption)
                        .foregroundStyle(status.color)
                }
                Text(verbatim: value.map { "\(measure.format($0)) dB" } ?? "-")
                    .somaFont(type.rowValue)
                    .foregroundStyle(value == nil ? colors.inkSecondary.color : colors.inkPrimary.color)
            }
            SomaScaleBar(scale: measure.scale, value: value, style: .level, limit: measure.limit)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: measure.title))
        .accessibilityValue(Text(verbatim: value.map { "\(measure.format($0)) decibels" } ?? "-"))
    }
}

/// Seven days of both levels as lines, the 70 and 80 dB limits as dashed
/// rules behind them.
private struct EnvironmentSoundWeek: View {
    let report: EnvironmentReport

    @Environment(\.somaTheme) private var theme

    static func hue(_ measure: EnvironmentMeasure) -> Color {
        measure == .headphones ? SomaHealthHue.cycle.color : SomaHealthHue.hearing.color
    }

    private struct Point: Identifiable {
        var id: String { "\(series.rawValue)\(day)" }
        let series: EnvironmentMeasure
        let day: Int
        let value: Double
    }

    var body: some View {
        let colors = theme.colors
        let points = [EnvironmentMeasure.sound, .headphones].flatMap { measure in
            measure.days(report).suffix(7).enumerated().compactMap { index, value in
                value.map { Point(series: measure, day: index, value: $0) }
            }
        }

        Chart {
            ForEach([70.0, 80.0], id: \.self) { line in
                RuleMark(y: .value("Limit", line))
                    .foregroundStyle(colors.inkSecondary.color.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(position: .top, alignment: .leading, spacing: 1) {
                        Text(verbatim: "\(Int(line))")
                            .somaFont(theme.typography.captionValue)
                            .foregroundStyle(colors.inkSecondary.color)
                    }
            }
            ForEach(points) { point in
                LineMark(x: .value("Day", point.day), y: .value("dB", point.value),
                         series: .value("Series", point.series.rawValue))
                    .foregroundStyle(Self.hue(point.series))
                    .lineStyle(StrokeStyle(lineWidth: theme.metrics.chartStroke, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.catmullRom)
                PointMark(x: .value("Day", point.day), y: .value("dB", point.value))
                    .foregroundStyle(Self.hue(point.series))
                    .symbolSize(point.day == 6 ? 30 : 0)
            }
        }
        .chartXScale(domain: 0...6)
        .chartYScale(domain: 40...95)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .accessibilityHidden(true)
    }
}

// MARK: - Sleep

/// The bedroom as the Sleep environment sheet keeps it: last night's noise,
/// the room's temperature, whether it was dark, and where you slept.
private struct EnvironmentBedroomCard: View {
    let bedroom: EnvironmentBedroom
    let open: () -> Void
    let openPlaces: () -> Void

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics
        let colors = theme.colors
        let sleep = SomaHealthHue.sleep.color

        SomaCard {
            VStack(alignment: .leading, spacing: metrics.cardSpacing) {
                Button(action: open) {
                    VStack(alignment: .leading, spacing: metrics.cardSpacing) {
                        HStack {
                            Text("Sleep environment")
                                .somaFont(theme.typography.cardTitle)
                                .foregroundStyle(colors.inkPrimary.color)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .somaFont(theme.typography.caption)
                                .foregroundStyle(colors.inkSecondary.color)
                        }
                        HStack(alignment: .top, spacing: 0) {
                            EnvironmentBedroomFact(symbol: "ear.fill", label: "Noise",
                                                   value: bedroom.noise.map { "\(Int($0.rounded())) dB" },
                                                   tint: bedroom.noise.map { SomaDataScale.soundLevel.value(at: $0).color } ?? sleep)
                            EnvironmentBedroomFact(symbol: "thermometer.medium", label: "Room",
                                                   value: bedroom.temperature.map { "\(ScoreMath.number($0, decimals: 1))°" },
                                                   tint: bedroom.temperature.map { SomaDataScale.temperature.value(at: $0).color } ?? sleep)
                            EnvironmentBedroomFact(symbol: "cloud.moon.fill", label: "Outside",
                                                   value: bedroom.outdoor.map { "\(Int($0.rounded()))°" },
                                                   tint: bedroom.outdoor.map { SomaDataScale.temperature.value(at: $0).color } ?? sleep)
                            EnvironmentBedroomFact(symbol: "moon.fill", label: "Dark",
                                                   value: bedroom.isDark.map { $0 ? "Yes" : "No" },
                                                   tint: sleep)
                        }
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.somaGlassPress)

                Rectangle()
                    .fill(colors.inkPrimary.color.opacity(metrics.hairlineOpacity))
                    .frame(height: 0.5)

                Button(action: openPlaces) {
                    HStack(spacing: 8) {
                        Image(systemName: "mappin.and.ellipse")
                            .foregroundStyle(sleep)
                        Text("Last night")
                            .foregroundStyle(colors.inkSecondary.color)
                        Spacer(minLength: 0)
                        Text(verbatim: bedroom.place ?? "-")
                            .foregroundStyle(colors.inkPrimary.color)
                        Image(systemName: "chevron.right")
                            .foregroundStyle(colors.inkSecondary.color)
                    }
                    .somaFont(theme.typography.caption)
                    .contentShape(.rect)
                }
                .buttonStyle(.somaGlassPress)
            }
        }
    }
}

private struct EnvironmentBedroomFact: View {
    let symbol: String
    let label: LocalizedStringResource
    let value: String?
    let tint: Color

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let colors = theme.colors
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .somaFont(theme.typography.body)
                .foregroundStyle(tint)
                .frame(width: theme.metrics.environmentPillDisc, height: theme.metrics.environmentPillDisc)
                .background(Circle().fill(tint.opacity(0.16)))
            Text(verbatim: value ?? "-")
                .somaFont(theme.typography.rowValue)
                .foregroundStyle(value == nil ? colors.inkSecondary.color : colors.inkPrimary.color)
            Text(label)
                .somaFont(theme.typography.caption)
                .foregroundStyle(colors.inkSecondary.color)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Pieces

/// A titled group on the lens, the way the Body lens heads its sections.
private struct EnvironmentSection<Content: View>: View {
    let title: LocalizedStringResource
    let content: Content

    @Environment(\.somaTheme) private var theme

    init(_ title: LocalizedStringResource, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.metrics.cardSpacing) {
            Text(title)
                .somaFont(theme.typography.headline)
                .foregroundStyle(theme.colors.inkPrimary.color)
                .accessibilityAddTraits(.isHeader)
            content
        }
    }
}

/// A card that opens something.
private struct EnvironmentTap<Label: View>: View {
    let action: () -> Void
    @ViewBuilder let label: Label

    var body: some View {
        Button(action: action) { label.contentShape(.rect) }
            .buttonStyle(.somaGlassPress)
    }
}

/// A card's frame: its title, the status word in its colour on the trailing
/// edge, then what it draws.
private struct EnvironmentCardFrame<Content: View>: View {
    let title: String
    let status: (word: String, color: Color)?
    @ViewBuilder let content: Content

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let colors = theme.colors
        SomaCard {
            VStack(alignment: .leading, spacing: theme.metrics.cardSpacing) {
                HStack(alignment: .firstTextBaseline) {
                    Text(verbatim: title)
                        .somaFont(theme.typography.cardTitle)
                        .foregroundStyle(colors.inkPrimary.color)
                    Spacer(minLength: 0)
                    if let status {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(status.color)
                                .frame(width: theme.metrics.chartPointDiameter, height: theme.metrics.chartPointDiameter)
                            Text(verbatim: status.word)
                                .somaFont(theme.typography.caption)
                                .foregroundStyle(status.color)
                        }
                    }
                    Image(systemName: "chevron.right")
                        .somaFont(theme.typography.caption)
                        .foregroundStyle(colors.inkSecondary.color)
                }
                content
            }
        }
    }
}

/// A value large with its unit small, tinted where the scale says.
struct EnvironmentValue: View {
    let text: String?
    let unit: String
    var tint: Color? = nil

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let colors = theme.colors
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(verbatim: text ?? "-")
                .somaFont(theme.typography.metric)
                .foregroundStyle(text == nil ? colors.inkSecondary.color : (tint ?? colors.inkPrimary.color))
            if text != nil, !unit.isEmpty {
                Text(verbatim: unit)
                    .somaFont(theme.typography.caption)
                    .foregroundStyle(colors.inkSecondary.color)
            }
        }
    }
}

/// A small label over a number: the figures beside the daylight ring.
private struct EnvironmentFigure: View {
    let label: LocalizedStringResource
    let value: String?
    let unit: String?

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let colors = theme.colors
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .somaFont(theme.typography.eyebrow)
                .textCase(.uppercase)
                .foregroundStyle(colors.inkSecondary.color)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(verbatim: value ?? "-")
                    .somaFont(theme.typography.rowValue)
                    .foregroundStyle(value == nil ? colors.inkSecondary.color : colors.inkPrimary.color)
                if let unit, value != nil {
                    Text(verbatim: unit)
                        .somaFont(theme.typography.caption)
                        .foregroundStyle(colors.inkSecondary.color)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
    }
}
