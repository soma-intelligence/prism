//
//  GlucosePage.swift
//  Prism
//

import SwiftUI
import SomaUI
import HealthExportCore

/// A continuous glucose monitor's fortnight: any low under 54 first, then the
/// time in each range as one stacked bar, the last 24 hours against 70 to 180,
/// the ambulatory profile hour by hour, and what each meal logged in Track
/// did over the two hours after it.
///
/// Drawn inside `BloodGlucosePage`, which reads Health once and owns the
/// navigation title: it opens this page when most of the readings are a
/// monitor's, and `LabRoute.cgm` opens it whatever the readings. Every
/// number is written in the unit chosen in Settings.
struct GlucosePage: View {
    /// Fourteen days of readings, any order.
    let samples: [HealthReading]
    /// False until Health has answered, so the empty state does not flash.
    var isLoaded = true

    @Environment(\.somaTheme) private var theme
    @State private var settings = GlobalSettings.shared
    @State private var log = TrackLogStore.shared

    var body: some View {
        let now = Date.now
        let unit = settings.units.glucose
        let summary = GlucoseSummary.make(samples: samples, meals: meals(now: now), unit: unit, now: now)
        TabPartScaffold(
            aspect: nil,
            eyebrow: summary.isContinuous ? eyebrow(summary) : nil,
            title: title(summary),
            reason: reason(summary),
            stats: [
                SomaStat("In range", value: summary.timeInRange.map(Self.percent), unit: "%"),
                SomaStat("GMI", value: summary.gmi.map { LabMath.format($0, decimals: 1) ?? "-" }, unit: "%"),
                SomaStat("Variation", value: summary.cv.map { LabMath.format($0, decimals: 0) ?? "-" }, unit: "%"),
            ]
        ) {
            if let note = summary.urgentNote {
                SomaExplainerSection("Low glucose") {
                    SomaExplainerRow(symbol: "exclamationmark.triangle.fill", hue: .symptoms,
                                     term: "Under \(unit.label(milligrams: GlucoseRange.veryLow))", line: note)
                }
            }
            if summary.isContinuous {
                SomaChartCard(
                    eyebrow: "Time in range",
                    value: summary.timeInRange.map(Self.percent),
                    unit: "%",
                    note: "\(unit.label(milligrams: GlucoseRange.low)) to \(unit.label(milligrams: GlucoseRange.high)). The consensus aims for more than 70%."
                ) {
                    GlucoseRangeBar(summary: summary)
                }
                LabRowGroup(heading: "By range", rows: ranges(summary))
                let day = lastDay(now: now)
                SomaChartCard(
                    eyebrow: "Last 24 hours",
                    value: day.last.map { unit.text(milligrams: $0.value) },
                    unit: unit.title,
                    note: "The band is \(unit.text(milligrams: GlucoseRange.low)) to \(unit.label(milligrams: GlucoseRange.high))."
                ) {
                    GlucoseDayChart(readings: day, meals: meals(now: now).filter { $0.date >= now.addingTimeInterval(-86_400) },
                                    unit: unit, now: now)
                }
                SomaChartCard(
                    eyebrow: "By hour, \(Int(summary.daysCovered.rounded())) days",
                    value: summary.averageMilligrams.map { unit.text(milligrams: $0) },
                    unit: "\(unit.title) on average",
                    note: "The line is the median at each hour, the bands hold half and four fifths of the readings."
                ) {
                    GlucoseProfileChart(profile: summary.profile, unit: unit)
                }
                mealRows(summary)
                LabFootnote("Informative, not a diagnosis. Targets from the 2019 international consensus on time in range; yours may differ, so ask your doctor.")
            }
        }
    }

    // MARK: Words

    private static func percent(_ share: Double) -> String {
        LabMath.format(share * 100, decimals: 0) ?? "-"
    }

    private func eyebrow(_ summary: GlucoseSummary) -> String {
        let days = max(1, Int(summary.daysCovered.rounded()))
        return "Last \(days) \(days == 1 ? "day" : "days") · \(summary.readingCount) readings"
    }

    private func title(_ summary: GlucoseSummary) -> String {
        if summary.urgentNote != nil { return "A low under \(summary.unit.label(milligrams: GlucoseRange.veryLow))." }
        guard summary.isContinuous, let inRange = summary.timeInRange else {
            return isLoaded ? "No monitor yet." : "Reading Health."
        }
        let share = Self.percent(inRange)
        return inRange >= GlucoseRange.targetInRange ? "In range \(share)% of the time." : "In range \(share)% of the time, under the aim."
    }

    private func reason(_ summary: GlucoseSummary) -> String? {
        guard summary.isContinuous else {
            return isLoaded ? "A continuous glucose monitor that writes to Health, a Dexcom or a Libre, fills this page." : nil
        }
        let unit = summary.unit
        var text = "Average \(unit.text(milligrams: summary.averageMilligrams)) \(unit.title)"
        if let below = summary.timeBelow70 {
            text += ", \(Self.percent(below))% under \(unit.label(milligrams: GlucoseRange.low))"
        }
        text += "."
        if summary.daysCovered < 10 {
            text += " GMI firms up after 14 days of wear."
        }
        return text
    }

    private func ranges(_ summary: GlucoseSummary) -> [LabRow] {
        let unit = summary.unit
        func row(_ title: String, _ share: Double?, aim: String) -> LabRow {
            LabRow(title, detail: share.map { "\(Self.percent($0))%, aim \(aim)" } ?? "-")
        }
        let veryHigh = summary.timeAbove250
        let high = summary.timeAbove180.map { $0 - (veryHigh ?? 0) }
        let veryLow = summary.timeBelow54
        let low = summary.timeBelow70.map { $0 - (veryLow ?? 0) }
        return [
            row("Over \(unit.text(milligrams: GlucoseRange.veryHigh))", veryHigh, aim: "under 5%"),
            row("\(unit.text(milligrams: GlucoseRange.high)) to \(unit.text(milligrams: GlucoseRange.veryHigh))", high, aim: "under 20%"),
            row("\(unit.text(milligrams: GlucoseRange.low)) to \(unit.text(milligrams: GlucoseRange.high))", summary.timeInRange, aim: "over 70%"),
            row("\(unit.text(milligrams: GlucoseRange.veryLow)) to \(unit.text(milligrams: GlucoseRange.low))", low, aim: "under 3%"),
            row("Under \(unit.text(milligrams: GlucoseRange.veryLow))", veryLow, aim: "under 1%"),
        ]
    }

    @ViewBuilder
    private func mealRows(_ summary: GlucoseSummary) -> some View {
        let unit = summary.unit
        let rows = summary.meals.prefix(7).map { response in
            let peak = "\(LabMath.format(response.peakMinutes, decimals: 0) ?? "-") min"
            let rise = unit.text(milligrams: response.rise)
            let day = response.date.formatted(.dateTime.weekday(.abbreviated))
            return LabRow("\(response.name) · \(day) \(ScoreMath.clock(response.date))",
                          detail: "+\(rise) \(unit.title), \(peak)")
        }
        if rows.isEmpty {
            LabFootnote("Meals logged in Track show their peak here, read over the two hours after.")
        } else {
            LabRowGroup(heading: "After meals", rows: rows)
        }
    }

    // MARK: Data

    private func meals(now: Date) -> [TrackMealEntry] {
        #if DEBUG && targetEnvironment(simulator)
        if FixtureGlucose.isOn { return FixtureGlucose.meals(now: now) }
        #endif
        return log.meals
    }

    private func lastDay(now: Date) -> [HealthReading] {
        samples.filter { $0.start >= now.addingTimeInterval(-86_400) && $0.start <= now }.sorted { $0.start < $1.start }
    }
}

// MARK: - Charts

/// The fortnight's time in each range as one bar: very low and low in the
/// alert hue, in range in the normal green, high and very high in the out hue,
/// the milder band of each pair faded.
private struct GlucoseRangeBar: View {
    let summary: GlucoseSummary

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let colors = theme.colors
        let metrics = theme.metrics
        let veryLow = summary.timeBelow54 ?? 0
        let low = (summary.timeBelow70 ?? 0) - veryLow
        let veryHigh = summary.timeAbove250 ?? 0
        let high = (summary.timeAbove180 ?? 0) - veryHigh
        let parts: [(Double, Color)] = [
            (veryLow, colors.statusAlert.color),
            (low, colors.statusAlert.color.opacity(metrics.chartSpreadOpacity)),
            (summary.timeInRange ?? 0, colors.statusNormal.color),
            (high, colors.statusOut.color.opacity(metrics.chartSpreadOpacity)),
            (veryHigh, colors.statusOut.color),
        ]
        Canvas { context, size in
            var x: CGFloat = 0
            context.clip(to: Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: metrics.chartBarCornerRadius))
            for (share, color) in parts where share > 0 {
                let width = size.width * CGFloat(share)
                context.fill(Path(CGRect(x: x, y: 0, width: width, height: size.height)), with: .color(color))
                x += width
            }
        }
        .frame(height: metrics.chartBarWidth)
        .accessibilityHidden(true)
    }
}

/// The last 24 hours as a line over the 70 to 180 band, each meal a dashed
/// hairline with its name over the plot.
private struct GlucoseDayChart: View {
    let readings: [HealthReading]
    let meals: [TrackMealEntry]
    let unit: GlucoseUnit
    let now: Date

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let hue = theme.aspects[.gut].identity.color
        let start = now.addingTimeInterval(-86_400)
        let unit = unit
        let readings = readings
        let mealTimes = meals.map(\.date)
        let low = unit.value(milligrams: GlucoseRange.low)
        let high = unit.value(milligrams: GlucoseRange.high)
        let scale = SomaPlotScale(values: readings.map { unit.value(milligrams: $0.value) }, including: [low, high])
        let marks = meals.map { SomaPlot.Mark(fraction: $0.date.timeIntervalSince(start) / 86_400, label: $0.meal.title) }
        SomaPlot(scale: scale, marks: marks, xLabels: labels(start: start), height: theme.metrics.chartCompactPlotHeight) { context, space, pen in
            func x(_ date: Date) -> CGFloat { space.x(fraction: date.timeIntervalSince(start) / 86_400) }
            pen.band(context, top: space.y(high), bottom: space.y(low), in: space.plot)
            for time in mealTimes {
                pen.vertical(context, x: x(time), height: space.size.height, color: pen.inkSecondary, dashed: true)
            }
            let points = readings.map { CGPoint(x: x($0.start), y: space.y(unit.value(milligrams: $0.value))) }
            pen.line(context, points, color: hue)
            if let latest = points.last { pen.ring(context, at: latest, color: hue) }
        }
        .accessibilityHidden(true)
    }

    private func labels(start: Date) -> [String] {
        (0...4).map { ScoreMath.clock(start.addingTimeInterval(Double($0) * 6 * 3600)) }
    }
}

/// The ambulatory profile: for each hour, the 10th to 90th percentile as a
/// faint band, the 25th to 75th over it, and the median as the line.
private struct GlucoseProfileChart: View {
    let profile: [GlucoseProfileHour]
    let unit: GlucoseUnit

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let hue = theme.aspects[.gut].identity.color
        let unit = unit
        let profile = profile
        let low = unit.value(milligrams: GlucoseRange.low)
        let high = unit.value(milligrams: GlucoseRange.high)
        let scale = SomaPlotScale(values: profile.flatMap { [$0.p10, $0.p90] }.map { unit.value(milligrams: $0) },
                                  including: [low, high])
        SomaPlot(scale: scale, xLabels: ["00:00", "06:00", "12:00", "18:00", "24:00"]) { context, space, pen in
            func x(_ hour: Int) -> CGFloat { space.x(fraction: (Double(hour) + 0.5) / 24) }
            func points(_ value: KeyPath<GlucoseProfileHour, Double>) -> [CGPoint] {
                profile.map { CGPoint(x: x($0.hour), y: space.y(unit.value(milligrams: $0[keyPath: value]))) }
            }
            pen.rule(context, y: space.y(low), in: space.plot)
            pen.rule(context, y: space.y(high), in: space.plot)
            pen.band(context, upper: points(\.p90), lower: points(\.p10), color: hue)
            pen.band(context, upper: points(\.p75), lower: points(\.p25), color: hue)
            pen.line(context, points(\.median), color: hue)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Reading

extension HealthDashboard {
    /// Fourteen days of glucose from Health, through the same once-per-set
    /// request as every page, for this page and the Body's Glucose tile.
    /// Empty when Health is not there or the read threw. On a simulator,
    /// `-health.cgm YES` hands back the made up monitor instead.
    func glucoseFortnight(now: Date = .now) async -> [HealthReading] {
        #if DEBUG && targetEnvironment(simulator)
        if FixtureGlucose.isOn { return FixtureGlucose.readings(now: now) }
        #endif
        guard let source = await prepare([LabMetric.glucose]),
              let metric = HealthMetricCatalog.metric(for: LabMetric.glucose),
              let start = Calendar.current.date(byAdding: .day, value: -14, to: now) else { return [] }
        return (try? await source.samples(metric, from: start, to: now, limit: 0)) ?? []
    }
}
