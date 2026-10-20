//
//  StepsPage.swift
//  Prism
//

import SwiftUI
import SomaUI

/// Daily steps: today on the metric stage with thirty days of bars against
/// the usual day, the last four weeks, and the month so far against the one
/// before.
///
/// Every number is a daily total from Health's own statistics, so a phone and
/// a watch that both counted a walk count it once.
struct StepsPage: View {
    @Environment(HealthDashboard.self) private var health
    @State private var report = StepsReport.make(totals: [:], now: .now)

    var body: some View {
        let lead = MetricLead.override(health.status)

        TabPartScaffold(
            aspect: .activity,
            eyebrow: report.eyebrow,
            title: lead?.title ?? report.headline,
            reason: lead?.reason ?? report.reason,
            stats: []
        ) {
            AspectStage(
                aspect: .activity,
                lead: .days(report.stage, caption: "Today, so far", value: report.today, unit: "steps",
                            higherIsBetter: true, format: MetricWords().whole),
                values: report.stage,
                unit: "steps",
                scale: nil,
                format: { MetricWords().whole($0) }
            )
            MetricRowsCard(eyebrow: "Week by week", rows: report.weeks.isEmpty
                ? [MetricRowItem("No steps yet", detail: "Your phone and watch count them as you move.")]
                : report.weeks)
            SomaChartCard(eyebrow: report.monthTitle, value: report.monthTotal, unit: "steps", note: report.monthNote) {
                MetricBandChart(values: report.monthCurve, aspect: .activity)
            }
            MetricRowsCard(rows: [
                MetricRowItem("Activity summary", detail: "Sessions, the Move ring and time by type", route: .activitySummary),
                MetricRowItem("Territory", detail: "Where your walks and runs went", route: .territory),
            ])
        }
        .navigationTitle("Steps")
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        let now = Date()
        guard let source = await health.prepare([FitnessHistory.Metric.steps]) else { return }
        let totals = await FitnessHistory.dailyTotals(FitnessHistory.Metric.steps, days: 62, now: now, source: source, calendar: .current)
        report = StepsReport.make(totals: totals, now: now)
    }
}

/// The Steps page's words and numbers.
struct StepsReport {
    var eyebrow: String
    var headline: String
    var reason: String
    var today: String?
    var usual: ClosedRange<Double>?
    var usualNote: String
    var days: [Double?]
    /// The stage's days, the last thirty, today last.
    var stage: [Double?]
    var axis: (String?, String?, String?)
    var weeks: [MetricRowItem]
    var monthTitle: String
    var monthTotal: String?
    var monthNote: String
    var monthCurve: [Double]

    static let shownDays = 14
    static let stageDays = 30

    static func make(totals: [Date: Double], now: Date, calendar: Calendar = .current, locale: Locale = .current) -> StepsReport {
        let words = MetricWords(calendar: calendar, locale: locale)
        let today = calendar.startOfDay(for: now)
        let days: [Double?] = (0..<shownDays).map { index in
            calendar.date(byAdding: .day, value: index - (shownDays - 1), to: today).flatMap { totals[$0] }
        }
        let past = days.dropLast().compactMap { $0 }
        let usual = EnvironmentReport.usual(past, roundedTo: 100)
        let todaySteps = totals[today]

        var headline = "No steps recorded yet."
        var reason = "Your iPhone counts steps in your pocket and Apple Watch counts them on your wrist. Both fill this page."
        if let todaySteps {
            let count = words.whole(todaySteps)
            if let usual {
                let range = "\(words.whole(usual.lowerBound)) to \(words.whole(usual.upperBound))"
                if todaySteps > usual.upperBound {
                    headline = "\(count) steps, already past a usual day."
                    reason = "A usual day runs \(range). Today went beyond it before it ended."
                } else if todaySteps >= usual.lowerBound {
                    headline = "\(count) steps, inside a usual day."
                    reason = "A usual day runs \(range), and today is already in it."
                } else {
                    headline = "\(count) steps so far."
                    reason = "A usual day runs \(range). The rest of today decides where this one lands."
                }
            } else {
                headline = "\(count) steps so far today."
                reason = "A usual day needs a week of days counted. Keep your phone or watch on you and it draws itself."
            }
        }

        let weeks = StepsMath.weeks(totals, count: 4, now: now, calendar: calendar)
        let rows: [MetricRowItem] = weeks.enumerated().map { index, week in
            let title = "\(words.short(week.start)) to \(week.isCurrent ? words.short(week.end) + ", so far" : words.short(week.end))"
            var detail: String?
            if index + 1 < weeks.count {
                let before = weeks[index + 1].perDay
                let change = before > 0 ? (week.perDay - before) / before : 0
                let percent = Int((abs(change) * 100).rounded())
                detail = percent < 2 ? "Level with the week before" : "\(change > 0 ? "Up" : "Down") \(percent)% on the week before"
            }
            return MetricRowItem(title, detail: detail, value: "\(StepsMath.thousands(week.perDay, locale: locale)) a day", id: "\(week.start)")
        }

        let curve = StepsMath.monthToDate(totals, now: now, calendar: calendar)
        let monthName = now.formatted(Date.FormatStyle(locale: locale, calendar: calendar).month(.wide))
        let hasMonth = totals.keys.contains { calendar.isDate($0, equalTo: now, toGranularity: .month) }
        var monthNote = "Steps add up here day by day from the first of the month."
        if hasMonth, let total = curve.last, let before = StepsMath.lastMonthToSameDay(totals, now: now, calendar: calendar) {
            let gap = total - before
            let lastMonth = (calendar.date(byAdding: .month, value: -1, to: now) ?? now)
                .formatted(Date.FormatStyle(locale: locale, calendar: calendar).month(.wide))
            monthNote = "\(words.whole(abs(gap))) \(gap >= 0 ? "ahead of" : "behind") \(lastMonth) on the same day."
        }

        return StepsReport(
            eyebrow: "Today, so far at \(words.time(now))",
            headline: headline,
            reason: reason,
            today: todaySteps.map(words.whole),
            usual: usual,
            usualNote: usual.map { "Usually \(words.whole($0.lowerBound)) to \(words.whole($0.upperBound)) a day. The last 14 days." }
                ?? "The last 14 days. A usual day shows once a week is counted.",
            days: days,
            stage: (0..<stageDays).map { index in
                calendar.date(byAdding: .day, value: index - (stageDays - 1), to: today).flatMap { totals[$0] }
            },
            axis: words.axis(days: shownDays, now: now),
            weeks: rows,
            monthTitle: "\(monthName) so far",
            monthTotal: hasMonth ? curve.last.map(words.whole) : nil,
            monthNote: monthNote,
            monthCurve: hasMonth ? curve : []
        )
    }
}

#Preview("Steps") {
    NavigationStack { StepsPage() }
        .environment(HealthDashboard())
}
