//
//  HomeMarkerSheet.swift
//  Prism
//

import SwiftUI
import SomaUI
import HealthExportCore

/// A marker Today can raise: a measure read against its own usual.
enum HomeMarker: String, CaseIterable, Identifiable, Hashable, Sendable {
    case restingHeartRate, hrv, breathing, wristTemperature

    var id: String { rawValue }

    var title: String {
        switch self {
        case .restingHeartRate: "Resting heart rate"
        case .hrv: "HRV"
        case .breathing: "Breathing"
        case .wristTemperature: "Wrist temperature"
        }
    }

    var chip: String {
        switch self {
        case .restingHeartRate: "Resting HR"
        case .hrv: "HRV"
        case .breathing: "Breathing"
        case .wristTemperature: "Wrist temp"
        }
    }

    var identifier: String {
        switch self {
        case .restingHeartRate: PulseInputs.Metric.restingHeartRate
        case .hrv: PulseInputs.Metric.heartRateVariability
        case .breathing: HomeMetric.respiratoryRate
        case .wristTemperature: HomeMetric.wristTemperature
        }
    }

    var unit: String {
        switch self {
        case .restingHeartRate: "bpm"
        case .hrv: "ms"
        case .breathing: "/min"
        case .wristTemperature: "°C"
        }
    }

    var decimals: Int {
        switch self {
        case .restingHeartRate, .hrv: 0
        case .breathing, .wristTemperature: 1
        }
    }

    /// A change this size over a period counts as moving.
    var step: Double {
        switch self {
        case .restingHeartRate: 1
        case .hrv: 3
        case .breathing: 0.4
        case .wristTemperature: 0.2
        }
    }

    /// Whether a value above the usual is the worse side.
    var higherIsWorse: Bool { self != .hrv }

    /// What the reading is, in a few words, then how to read it.
    var about: (term: String, line: String, symbol: String, hue: SomaHealthHue) {
        switch self {
        case .restingHeartRate:
            ("Your heart at its calmest, awake.", "It moves slowly: a beat or two held for days is worth a look.",
             "heart.fill", .heart)
        case .hrv:
            ("How much the time between beats varies.", "Higher is usually rested. Read against your own month.",
             "waveform.path.ecg", .heart)
        case .breathing:
            ("Counted while you sleep.", "One breath a minute up for a few nights often comes before a cold.",
             "lungs.fill", .respiratory)
        case .wristTemperature:
            ("Asleep, against your own baseline.", "A little higher after ovulation and when something is coming on.",
             "thermometer.medium", .vitals)
        }
    }

    /// How a day's readings become one value: the median of a resting rate,
    /// the mean of the rest.
    func aggregate(_ values: [Double]) -> Double? {
        switch self {
        case .restingHeartRate: PulseSignals.median(values)
        default: values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
        }
    }

    func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(decimals)))
    }
}

/// How far back the chart reads.
enum HomeMarkerRange: Int, CaseIterable, Hashable {
    case month = 30, quarter = 91, half = 182, year = 365

    var title: String {
        switch self {
        case .month: "30 days"
        case .quarter: "3 months"
        case .half: "6 months"
        case .year: "1 year"
        }
    }
}

/// A marker Home raises, in a sheet: today's value against the usual, the
/// line over the range chosen, how it moved by period, a check in, and what
/// the measure is.
struct HomeMarkerSheet: View {
    let initial: HomeMarker

    @Environment(HealthDashboard.self) private var health
    @Environment(\.somaTheme) private var theme
    @State private var marker: HomeMarker
    @State private var range: HomeMarkerRange = .month
    @State private var readings: [HomeMarker: [HealthReading]] = [:]
    @State private var sheet: HomeSheetRoute?

    init(initial: HomeMarker) {
        self.initial = initial
        _marker = State(initialValue: initial)
    }

    var body: some View {
        let series = HomeMarkerSeries.make(
            readings[marker] ?? [], days: range.rawValue, today: Date(), calendar: .current,
            aggregate: marker.aggregate
        )

        HomeSheet(eyebrow: "Heart · Monitor", title: marker.title) {
            VStack(alignment: .leading, spacing: 8) {
                HomeValue(value: series.latest.map(marker.format), unit: "\(marker.unit), latest")
                HomeReason(reason(series))
            }

            // Every marker in lines that wrap, never a row that scrolls sideways.
            SomaFlowLayout(spacing: 8) {
                ForEach(HomeMarker.allCases) { option in
                    HomeChip(title: option.chip, isOn: option == marker) { marker = option }
                }
            }

            HomeSegments(options: HomeMarkerRange.allCases.map { ($0, $0.title) }, selection: $range)

            SomaChartCard(
                eyebrow: marker.title,
                value: series.latest.map(marker.format),
                unit: marker.unit,
                note: note(series)
            ) {
                HomeTrendChart(
                    values: series.days,
                    band: series.band,
                    aspect: .heart,
                    axis: axis,
                    decimals: marker.decimals
                )
                .padding(.top, theme.metrics.spaceS)
            }

            trendCard(series)

            HomeActionCard(
                eyebrow: "Tonight",
                aspect: .heart,
                title: "Check in before bed",
                detail: "If you feel run down, Soma keeps tomorrow’s plan easy.",
                actionTitle: "Check in"
            ) { sheet = .checkIn }

            ScoreAbout(lead: marker.about.term, rest: marker.about.line,
                       symbol: marker.about.symbol, hue: marker.about.hue)
        }
        .task(id: marker) { await read(marker) }
        .homeSheets($sheet)
    }

    private func trendCard(_ series: HomeMarkerSeries) -> some View {
        let type = theme.typography
        let colors = theme.colors

        return HomeRowsCard("Trend", caption: "Against the week before") {
            HStack {
                Text("Period").frame(maxWidth: .infinity, alignment: .leading)
                Text("Change").frame(maxWidth: .infinity, alignment: .trailing)
                Text("Direction").frame(maxWidth: .infinity, alignment: .trailing)
            }
            .somaFont(type.caption)
            .foregroundStyle(colors.inkSecondary.color)

            ForEach(series.changes) { change in
                let direction = HomeMarkerSeries.direction(change.change, step: marker.step)
                let worse = direction == (marker.higherIsWorse ? "Rising" : "Falling")
                HStack {
                    Text("\(change.days) days").frame(maxWidth: .infinity, alignment: .leading)
                    Text(change.change.map { HomeFormat.signed($0, max(marker.decimals, 1)) } ?? "-")
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .foregroundStyle(worse ? colors.danger.color : colors.inkPrimary.color)
                    Text(direction)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .foregroundStyle(worse ? colors.danger.color : colors.inkSecondary.color)
                }
                .somaFont(type.rowValue)
                .foregroundStyle(colors.inkPrimary.color)
                .accessibilityElement(children: .combine)
            }

        }
    }

    private var axis: [String] {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -(range.rawValue - 1), to: Date()) ?? Date()
        let middle = calendar.date(byAdding: .day, value: -(range.rawValue / 2), to: Date()) ?? Date()
        let style = Date.FormatStyle().day().month(.abbreviated)
        return [start.formatted(style), middle.formatted(style), "Today"]
    }

    private func note(_ series: HomeMarkerSeries) -> String {
        if let band = series.band {
            return "\(range.title). Usually \(marker.format(band.lowerBound)) to \(marker.format(band.upperBound))."
        }
        return series.latest == nil
            ? "Nothing recorded yet. Your watch fills this as it measures."
            : "\(range.title). The usual band appears after five days of readings."
    }

    private func reason(_ series: HomeMarkerSeries) -> String {
        guard let latest = series.latest else {
            return "No reading yet. Apple Watch records this on its own; the line fills in as it does."
        }
        guard let band = series.band, let usual = series.usual else {
            return "Soma needs five days of readings to know your usual."
        }
        let range = "Your usual is \(marker.format(band.lowerBound)) to \(marker.format(band.upperBound))."
        let running = series.days.reversed().prefix { value in
            guard let value else { return false }
            return value > band.upperBound
        }.count
        if latest > band.upperBound {
            let run = running >= 2 ? ", \(running) days running" : ""
            return "Above your usual\(run). \(range) Short nights and hard afternoons add to it."
        }
        if latest < band.lowerBound {
            return "Below your usual. \(range)"
        }
        return "Close to your usual \(marker.format(usual)). \(range)"
    }

    private func read(_ marker: HomeMarker) async {
        guard readings[marker] == nil,
              let source = await health.prepare([marker.identifier]) else { return }
        readings[marker] = await source.home(marker.identifier, days: 365 + 97, now: Date())
    }
}
