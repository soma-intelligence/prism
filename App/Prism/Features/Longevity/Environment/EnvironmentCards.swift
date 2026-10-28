//
//  EnvironmentCards.swift
//  Prism
//

import SwiftUI
import Charts
import SomaUI

/// Everything the Environment lens draws, without the scroll view around
/// it: the weather pill, the three stats, then light, air and pollen, sound,
/// sleep and the week. Every card that opens something is a button; the lens
/// decides what each one opens.
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
    /// Whether the morning pollen alert is on, and the way to turn it.
    var pollenAlerts = false
    var setPollenAlerts: (Bool) -> Void = { _ in }

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics
        let colors = theme.colors
        let week = (report.week ?? .empty(now: sky.now)).laying(report.outside)

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

            // The sections in one column on a phone and two where the width
            // holds them; the year of days outside runs under both.
            SomaCardColumns(gap: .sections) {
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
                    EnvironmentPollenCard(peak: week.pollenPeak, counts: report.outside?.pollen,
                                          hasForecast: report.outside != nil,
                                          alerts: pollenAlerts, setAlerts: setPollenAlerts)
                        .id("pollen")
                }

                EnvironmentSection("Sound") {
                    EnvironmentSoundCard(report: report, open: open)
                }

                EnvironmentSection("Sleep") {
                    EnvironmentBedroomCard(bedroom: bedroom, open: openBedroom, openPlaces: openPlaces)
                    EnvironmentSleepPlacesCard(places: sleepPlaces, open: openPlaces)
                }

                EnvironmentSection("This week") {
                    EnvironmentTap { open(.daylight) } label: {
                        EnvironmentWeekCard(week: week)
                    }
                }
                .id("week")

                EnvironmentSection("Days outside") {
                    EnvironmentTap { open(.daylight) } label: {
                        SomaChartCard(eyebrow: "This year", value: report.daysOutside, unit: "days",
                                      note: "\(Int(EnvironmentReport.outsideMinutes)) min or more") {
                            PulseYearGridView(grid: report.grid, style: .squares, levels: [1, 15, EnvironmentReport.outsideMinutes, 60])
                                .accessibilityElement()
                                .accessibilityLabel("Days outside this year")
                                .accessibilityValue(report.daysOutside.map { "\($0) days" } ?? SomaFormat.notMeasured)
                        }
                    }
                }
                .somaColumnSpan(.full)
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
                        SomaNumber(report.daylight.map(EnvironmentMeasure.daylight.format), type.metric)
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
                .padding(.top, theme.metrics.spaceXS)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Daylight")
        .accessibilityValue(report.daylight.map { "\(Int($0.rounded())) minutes" } ?? SomaFormat.notMeasured)
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
        .accessibilityValue(Text(verbatim: value.map(measure.format) ?? SomaFormat.notMeasured))
    }
}

// MARK: - Pollen

/// Today's strongest pollen where you are, large and in its level's colour,
/// the six kinds under it, and the switch for a morning alert when it is
/// high. Without a place, or outside the forecast's map, one sentence says
/// why it is empty.
private struct EnvironmentPollenCard: View {
    let peak: PollenPeak?
    let counts: [PollenKind: Double]?
    let hasForecast: Bool
    let alerts: Bool
    let setAlerts: (Bool) -> Void

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics
        let type = theme.typography
        let colors = theme.colors
        let status = peak.map { (word: $0.level.word, color: Self.color($0.level)) }

        EnvironmentCardFrame(title: "Pollen", status: status, opens: false) {
            EnvironmentValue(text: peak.map { "\(Int($0.grains.rounded()))" }, unit: "grains/m³", tint: status?.color)
            Text(verbatim: note)
                .somaFont(type.caption)
                .foregroundStyle(colors.inkSecondary.color)
                .fixedSize(horizontal: false, vertical: true)
            if let counts {
                Grid(alignment: .leading, horizontalSpacing: metrics.cardSpacing, verticalSpacing: metrics.spaceS) {
                    ForEach(Array(stride(from: 0, to: PollenKind.allCases.count, by: 3)), id: \.self) { row in
                        GridRow {
                            ForEach(PollenKind.allCases[row..<min(row + 3, PollenKind.allCases.count)], id: \.self) { kind in
                                kindCell(kind, grains: counts[kind])
                            }
                        }
                    }
                }
            }
            HStack(spacing: metrics.spaceS) {
                Image(systemName: alerts ? "bell.fill" : "bell")
                    .foregroundStyle(alerts ? colors.accent.color : colors.inkSecondary.color)
                Text("Morning alert when high")
                    .foregroundStyle(colors.inkPrimary.color)
                Spacer(minLength: 0)
                SettingsSwitch(title: String(localized: "Morning pollen alert"),
                               isOn: Binding(get: { alerts }, set: setAlerts))
            }
            .somaFont(type.caption)
            .padding(.top, metrics.spaceXS)
        }
        .accessibilityElement(children: .contain)
    }

    /// One kind: its name, and its level in the level's colour.
    private func kindCell(_ kind: PollenKind, grains: Double?) -> some View {
        let level = grains.map { PollenLevel.level(kind, grains: $0) }
        return VStack(alignment: .leading, spacing: theme.metrics.spaceXXS) {
            Text(verbatim: kind.title)
                .somaFont(theme.typography.caption)
                .foregroundStyle(theme.colors.inkSecondary.color)
            SomaNumber(level?.word, theme.typography.rowValue)
                .foregroundStyle(level.map(Self.color) ?? theme.colors.inkSecondary.color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// The one line under the value: what is highest, or why nothing is.
    private var note: String {
        if let peak { return "\(peak.kind.title) is the highest today." }
        return hasForecast ? "Pollen forecasts cover Europe only." : "Pollen needs where you are."
    }

    static func color(_ level: PollenLevel) -> Color {
        SomaDataScale.pollen.value(at: Double(level.rawValue)).color
    }
}

// MARK: - Week

/// The last seven days: daylight as bars against the 30 to 120 minute goal,
/// then the loud days, the headphone dose against the WHO's week, the UV
/// added up and the days of unhealthy air.
private struct EnvironmentWeekCard: View {
    let week: EnvironmentWeek

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics
        let type = theme.typography
        let colors = theme.colors
        let hasDaylight = week.daylightTotal != nil

        SomaCard {
            VStack(alignment: .leading, spacing: metrics.cardSpacing) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Daylight")
                        .somaFont(type.cardTitle)
                        .foregroundStyle(colors.inkPrimary.color)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .somaFont(type.caption)
                        .foregroundStyle(colors.inkSecondary.color)
                }
                EnvironmentValue(text: hasDaylight ? "\(week.daylightDaysReached) of \(EnvironmentWeek.days)" : nil,
                                 unit: "days at \(Int(EnvironmentWeek.daylightTarget.lowerBound)) min or more")
                if !hasDaylight {
                    Text("Time in daylight from your watch fills the week.")
                        .somaFont(type.caption)
                        .foregroundStyle(colors.inkSecondary.color)
                }
                EnvironmentWeekDaylight(minutes: week.daylightMinutes)
                    .frame(height: metrics.chartCompactPlotHeight)
                HStack(alignment: .top, spacing: 0) {
                    EnvironmentBedroomFact(symbol: "ear.fill", label: "Loud days",
                                           value: week.loudDays.map { "\($0)" },
                                           tint: SomaHealthHue.hearing.color)
                    EnvironmentBedroomFact(symbol: "headphones", label: "Headphones",
                                           value: week.headphoneDoseShare.map { "\(Int(($0 * 100).rounded()))%" },
                                           tint: (week.headphoneDoseShare ?? 0) > 1 ? colors.statusOut.color : SomaHealthHue.cycle.color)
                    EnvironmentBedroomFact(symbol: "sun.max.fill", label: "UV added",
                                           value: week.uvTotal.map { "\(Int($0.rounded()))" },
                                           tint: SomaDataScale.uvIndex.value(at: (week.uvTotal ?? 0) / Double(EnvironmentWeek.days)).color)
                    EnvironmentBedroomFact(symbol: "aqi.medium", label: "Poor air",
                                           value: week.unhealthyAirDays.map { "\($0)" },
                                           tint: SomaDataScale.airQuality.value(at: week.airPeak ?? 0).color)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("This week")
        .accessibilityValue(hasDaylight
            ? "\(week.daylightDaysReached) of \(EnvironmentWeek.days) days with \(Int(EnvironmentWeek.daylightTarget.lowerBound)) minutes of daylight or more"
            : SomaFormat.notMeasured)
    }
}

/// Seven bars of minutes in daylight, the goal band shaded behind them and a
/// missing day left empty.
private struct EnvironmentWeekDaylight: View {
    let minutes: [Double?]

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics
        let colors = theme.colors
        let target = EnvironmentWeek.daylightTarget
        let top = max(target.upperBound, minutes.compactMap { $0 }.max() ?? 0)

        Chart {
            RectangleMark(xStart: .value("Start", -0.5), xEnd: .value("End", Double(minutes.count) - 0.5),
                          yStart: .value("Low", target.lowerBound), yEnd: .value("High", target.upperBound))
                .foregroundStyle(SomaDataScale.daylight.value(at: target.upperBound).color.opacity(metrics.chartBandOpacity))
            ForEach(Array(minutes.enumerated()), id: \.offset) { index, value in
                if let value {
                    BarMark(x: .value("Day", Double(index)), y: .value("Minutes", value), width: .ratio(0.55))
                        .foregroundStyle(SomaDataScale.daylight.value(at: value).color)
                        .cornerRadius(metrics.chartThinBarRadius)
                }
            }
        }
        .chartXScale(domain: -0.5...(Double(minutes.count) - 0.5))
        .chartYScale(domain: 0...top)
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(values: [target.lowerBound, target.upperBound]) { value in
                AxisValueLabel {
                    if let minutes = value.as(Double.self) {
                        Text(verbatim: "\(Int(minutes))")
                            .somaFont(theme.typography.captionValue)
                            .foregroundStyle(colors.inkSecondary.color)
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Sound

/// The sound around you and in your headphones side by side, each its level
/// large over a fine meter with its limit marked, and the two over the week
/// as lines under them. Two stacked bars with heavy markers read as a form
/// (owner, 2026-10-24).
private struct EnvironmentSoundCard: View {
    let report: EnvironmentReport
    let open: (EnvironmentMeasure) -> Void

    @Environment(\.somaTheme) private var theme
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let metrics = theme.metrics

        SomaCard {
            VStack(alignment: .leading, spacing: metrics.cardSpacing) {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(Array([EnvironmentMeasure.sound, .headphones].enumerated()), id: \.element) { index, measure in
                        if index > 0 {
                            Rectangle()
                                .fill(theme.colors.inkPrimary.color.opacity(metrics.hairlineOpacity))
                                .frame(width: 1 / displayScale)
                                .padding(.horizontal, metrics.cardSpacing)
                        }
                        Button { open(measure) } label: {
                            EnvironmentLevelRow(measure: measure, report: report).contentShape(.rect)
                        }
                        .buttonStyle(.somaGlassPress)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                EnvironmentSoundWeek(report: report)
                    .frame(height: metrics.chartSparkHeight * 2.2)
                    .padding(.top, theme.metrics.spaceS)
            }
        }
    }
}

/// One source of sound: its name with its line's colour, the level large,
/// the word for it, and a fine meter from 30 to 100 dB with the limit as a
/// short tick.
private struct EnvironmentLevelRow: View {
    let measure: EnvironmentMeasure
    let report: EnvironmentReport

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics
        let type = theme.typography
        let colors = theme.colors
        let value = measure.current(report)
        let status = measure.status(value, report: report, colors: colors)
        let hue = EnvironmentSoundWeek.hue(measure)

        VStack(alignment: .leading, spacing: metrics.spaceS) {
            HStack(spacing: metrics.spaceXS + 2) {
                Circle().fill(hue).frame(width: 6, height: 6)
                Text(verbatim: measure.title)
                    .somaFont(type.caption)
                    .foregroundStyle(colors.inkSecondary.color)
                    .lineLimit(1)
            }
            HStack(alignment: .firstTextBaseline, spacing: metrics.spaceXS) {
                SomaNumber(value.map(measure.format), type.metricCompact)
                    .foregroundStyle(colors.inkPrimary.color)
                if value != nil {
                    Text("dB")
                        .somaFont(type.caption)
                        .foregroundStyle(colors.inkSecondary.color)
                }
            }
            Text(verbatim: status?.word ?? (measure == .headphones ? "7 day average" : "Now"))
                .somaFont(type.caption)
                .foregroundStyle(status?.color ?? colors.inkSecondary.color)
            GeometryReader { proxy in
                let width = proxy.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(colors.inkPrimary.color.opacity(metrics.hairlineOpacity))
                        .frame(height: 3)
                    if let value {
                        Capsule().fill(hue).frame(width: max(3, width * share(value)), height: 3)
                    }
                    if let limit = measure.limit {
                        Capsule().fill(colors.inkPrimary.color.opacity(0.6))
                            .frame(width: 1.5, height: 9)
                            .offset(x: width * share(limit) - 0.75)
                    }
                }
                .frame(height: 9)
            }
            .frame(height: 9)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: measure.title))
        .accessibilityValue(Text(verbatim: value.map { "\(measure.format($0)) decibels" } ?? SomaFormat.notMeasured))
    }

    /// Where a level sits on the meter, which runs from 30 to 100 dB.
    private func share(_ db: Double) -> CGFloat {
        CGFloat(min(max((db - 30) / 70, 0), 1))
    }
}

/// Seven days of both levels as lines, the 80 dB limit as one dashed rule
/// behind them.
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
            ForEach([80.0], id: \.self) { line in
                RuleMark(y: .value("Limit", line))
                    .foregroundStyle(colors.inkSecondary.color.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 0.75, dash: [2, 3]))
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
                        Text(verbatim: bedroom.place ?? String(localized: "Unnamed place"))
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
        VStack(spacing: theme.metrics.spaceS) {
            Image(systemName: symbol)
                .somaFont(theme.typography.body)
                .foregroundStyle(tint)
                .frame(width: theme.metrics.environmentPillDisc, height: theme.metrics.environmentPillDisc)
            SomaNumber(value, theme.typography.rowValue)
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
    /// Whether the card opens something, and so wears a chevron.
    var opens = true
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
                        HStack(spacing: theme.metrics.spaceXS) {
                            Circle()
                                .fill(status.color)
                                .frame(width: theme.metrics.chartPointDiameter, height: theme.metrics.chartPointDiameter)
                            Text(verbatim: status.word)
                                .somaFont(theme.typography.caption)
                                .foregroundStyle(status.color)
                        }
                    }
                    if opens {
                        Image(systemName: "chevron.right")
                            .somaFont(theme.typography.caption)
                            .foregroundStyle(colors.inkSecondary.color)
                    }
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
            SomaNumber(text, theme.typography.metric)
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
                .foregroundStyle(colors.inkSecondary.color)
            HStack(alignment: .firstTextBaseline, spacing: theme.metrics.spaceXS) {
                SomaNumber(value, theme.typography.rowValue)
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
