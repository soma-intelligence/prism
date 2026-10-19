//
//  SoundExposurePage.swift
//  Prism
//

import SwiftUI
import SomaUI
import HealthExportCore

/// The sound around you, or the sound in your headphones: fourteen days of
/// levels against the 80 dB line, the last seven days in rows, and the change
/// over seven, thirty and ninety days.
///
/// One page for both, because both are a level held over time and read the
/// same way. What differs is the words and, for headphones, the share of a
/// safe listening week they used.
struct SoundExposurePage: View {
    enum Kind {
        case environment, headphones

        var identifier: String {
            switch self {
            case .environment: EnvironmentInputs.Metric.sound
            case .headphones: EnvironmentInputs.Metric.headphones
            }
        }

        var title: String {
            switch self {
            case .environment: "Environmental sound"
            case .headphones: "Headphone audio"
            }
        }
    }

    let kind: Kind

    @Environment(HealthDashboard.self) private var health
    @Environment(\.somaTheme) private var theme
    @State private var report: SoundReport?

    var body: some View {
        let report = self.report ?? SoundReport.make(kind: kind, readings: [], now: .now)
        let lead = MetricLead.override(health.status)

        TabPartScaffold(
            aspect: nil,
            eyebrow: report.eyebrow,
            title: lead?.title ?? (self.report == nil ? "Reading Apple Health." : report.headline),
            reason: lead?.reason ?? report.reason,
            stats: []
        ) {
            SomaChartCard(eyebrow: kind.title, value: report.value, unit: report.unit, note: report.note) {
                MetricDailyBars(
                    values: report.days,
                    usual: report.usual,
                    limit: SoundExposure.limit,
                    floor: 40,
                    aspect: .mind,
                    leadingLabel: report.axis.0,
                    middleLabel: report.axis.1,
                    trailingLabel: report.axis.2
                )
            }
            MetricRowsCard(eyebrow: "Last 7 days", rows: report.week)
            MetricRowsCard(eyebrow: "By period", rows: report.periods)
            SomaActionCard(eyebrow: report.tipEyebrow, title: report.tipTitle, detail: report.tipDetail) {
                PulseMiniOrb(aspect: .mind, diameter: theme.metrics.miniOrbDiameter)
            }
            if kind == .environment {
                MetricRowsCard(rows: [MetricRowItem("Headphone audio", detail: "Levels in your ears, and a safe week", route: .headphoneAudio)])
            } else {
                MetricRowsCard(rows: [MetricRowItem("Environmental sound", detail: "The sound around you, day by day", route: .environmentalSound)])
            }
        }
        .navigationTitle(kind == .environment ? "Environmental sound" : "Headphone audio")
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        let now = Date()
        guard let source = await health.prepare([kind.identifier]),
              let metric = HealthMetricCatalog.metric(for: kind.identifier) else {
            report = SoundReport.make(kind: kind, readings: [], now: now)
            return
        }
        let start = Calendar.current.date(byAdding: .day, value: -180, to: now) ?? now
        let readings = (try? await source.samples(metric, from: start, to: now, limit: 0)) ?? []
        report = SoundReport.make(kind: kind, readings: readings, now: now)
    }
}

/// The sound pages' words and numbers.
struct SoundReport {
    var eyebrow: String
    var headline: String
    var reason: String
    var value: String?
    var unit: String
    var note: String
    var days: [Double?]
    var usual: ClosedRange<Double>?
    var axis: (String?, String?, String?)
    var week: [MetricRowItem]
    var periods: [MetricRowItem]
    var tipEyebrow: String
    var tipTitle: String
    var tipDetail: String

    static let shownDays = 14

    static func make(
        kind: SoundExposurePage.Kind,
        readings: [HealthReading],
        now: Date,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> SoundReport {
        let words = MetricWords(calendar: calendar, locale: locale)
        let today = calendar.startOfDay(for: now)
        let days = SoundExposure.daily(readings, days: shownDays, now: now, calendar: calendar)
        let usual = EnvironmentReport.usual(days.dropLast().compactMap { $0 }, roundedTo: 1)
        let weekStart = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        let week = readings.filter { $0.start >= weekStart }
        let byDay = Dictionary(grouping: week) { calendar.startOfDay(for: $0.start) }.compactMapValues(SoundExposure.mean)
        let usualText = usual.map { "\(words.whole($0.lowerBound)) to \(words.whole($0.upperBound))" }

        let periods = [7, 30, 90].map { span in
            MetricRowItem("\(span) days", value: SoundExposure.changeText(SoundExposure.change(readings, days: span, now: now)))
        }

        switch kind {
        case .environment:
            let todayLevel = days.last ?? nil
            let above = SoundExposure.timeAbove(SoundExposure.limit, in: week)
            let loudest = byDay.max { $0.value < $1.value }
            let quietest = byDay.min { $0.value < $1.value }
            let peak = week.filter { $0.value >= SoundExposure.limit }.max { $0.value < $1.value }

            var headline = "Nothing measured around you yet."
            var reason = "Apple Watch listens for how loud it is around you, never to what is said, and writes the level to Health."
            if let todayLevel {
                headline = "\(words.whole(todayLevel)) dB: \(todayLevel < 65 ? "an ordinary, quiet day." : todayLevel < 80 ? "a busy day around you." : "a loud day around you.")"
                reason = "Your surroundings averaged \(words.whole(todayLevel)) dB"
                reason += usualText.map { ", against your usual \($0)." } ?? "."
                reason += above > 0
                    ? " Sound harms hearing when it stays above 80 dB for hours; in the last seven days it passed 80 for \(SoundExposure.duration(above))."
                    : " Sound harms hearing when it stays above 80 dB for hours; it didn’t pass 80 in the last seven days."
            }

            return SoundReport(
                eyebrow: "Today, average so far",
                headline: headline,
                reason: reason,
                value: todayLevel.map(words.whole),
                unit: "dB today",
                note: "Daily averages, the last 14 days." + (usualText.map { " Usually \($0)." } ?? ""),
                days: days,
                usual: usual,
                axis: words.axis(days: shownDays, now: now),
                week: [
                    MetricRowItem("Time above 80 dB", detail: peak.map { "Peak \(words.whole($0.value)) dB, \(words.day($0.start))" },
                                  value: week.isEmpty ? nil : SoundExposure.duration(above)),
                    MetricRowItem("Loudest day", detail: loudest.map { words.day($0.key) }, value: loudest.map { "\(words.whole($0.value)) dB" }),
                    MetricRowItem("Quietest day", detail: quietest.map { words.day($0.key) }, value: quietest.map { "\(words.whole($0.value)) dB" }),
                ],
                periods: periods,
                tipEyebrow: "Noise",
                tipTitle: "Tell me when it’s loud",
                tipDetail: "In the Noise app on Apple Watch, turn on notifications and it nudges you when your surroundings stay above 80 dB for three minutes."
            )

        case .headphones:
            let average = SoundExposure.mean(week)
            let listening = SoundExposure.listening(week)
            let dose = SoundExposure.weeklyDose(week)
            let loudest = week.max { $0.value < $1.value }
            let dosePercent = Int((dose * 100).rounded())

            var headline = "No headphone listening recorded."
            var reason = "iPhone measures the level of what plays through AirPods and other supported headphones, and writes it to Health."
            if let average {
                headline = "\(words.whole(average)) dB: \(average < SoundExposure.limit ? "comfortably under the line." : "over the line this week.")"
                reason = "\(SoundExposure.duration(listening)) of listening in the last seven days used about \(dosePercent)% of a safe week. A safe week is 80 dB for 40 hours; every 3 dB louder halves the time."
            }

            return SoundReport(
                eyebrow: "7 day average",
                headline: headline,
                reason: reason,
                value: average.map(words.whole),
                unit: "dB, 7 day average",
                note: "Daily levels, the last 14 days." + (usualText.map { " Usually \($0)." } ?? ""),
                days: days,
                usual: usual,
                axis: words.axis(days: shownDays, now: now),
                week: [
                    MetricRowItem("Listening time", value: week.isEmpty ? nil : SoundExposure.duration(listening)),
                    MetricRowItem("Loudest session", detail: loudest.map { words.day($0.start) }, value: loudest.map { "\(words.whole($0.value)) dB" }),
                    MetricRowItem("Share of a safe week", detail: "Against 80 dB for 40 hours", value: week.isEmpty ? nil : "about \(dosePercent)%"),
                ],
                periods: periods,
                tipEyebrow: "Headphones",
                tipTitle: "Cap loud audio at 80 dB",
                tipDetail: "In Settings, Sounds and Haptics, Headphone Safety, Reduce Loud Audio turns down anything louder, so a loud track never reaches your ears."
            )
        }
    }
}

#Preview("Environmental sound") {
    NavigationStack { SoundExposurePage(kind: .environment) }
        .environment(HealthDashboard())
}
