//
//  AFibBurdenPage.swift
//  Prism
//

import SwiftUI
import SomaUI
import HealthExportCore

/// AFib History from Apple Watch: the share of each week spent in atrial
/// fibrillation, how it moved, what the number means, and the way to an ECG
/// and to the rhythm notifications.
///
/// AFib History is only switched on by people already diagnosed with AFib,
/// so the page reads as a log to share with a doctor, never as a finding.
struct AFibBurdenPage: View {
    @Environment(HealthDashboard.self) private var health
    @Environment(\.somaTheme) private var theme

    @State private var readings: RhythmMobilityReadings?

    private var words: MetricWords { MetricWords() }
    /// Weeks drawn as bars: three months, enough to see a direction.
    static let shownWeeks = 13

    var body: some View {
        let now = Date.now
        let summary = (readings ?? RhythmMobilityReadings()).rhythm(now: now)
        let lead = MetricLead.override(health.status)
        let slots = Self.slots(summary.weeks, count: Self.shownWeeks, now: now, calendar: .current)

        TabPartScaffold(
            aspect: .heart,
            eyebrow: summary.weeks.last.map { "Week of \(words.short($0.start))" } ?? "AFib History",
            title: lead?.title ?? headline(summary),
            reason: lead?.reason ?? reason(summary),
            stats: [
                SomaStat("Latest week", value: summary.latestBurden.map { _ in HeartRhythmSummary.burdenText(summary.latestBurden) }),
                SomaStat("Change", value: summary.change.map(changeText)),
                SomaStat("Notifications", value: readings == nil ? nil : "\(summary.events.count)"),
            ]
        ) {
            SomaChartCard(
                eyebrow: "Time in AFib, by week",
                value: summary.latestBurden.map { _ in HeartRhythmSummary.burdenText(summary.latestBurden) },
                unit: "of the week",
                note: summary.weeks.isEmpty
                    ? "Switch on AFib History in the Heart settings of the Health app. Each week then lands here."
                    : "\(Self.shownWeeks) weeks. A week without a bar was not read: the watch needs to be worn most of the week."
            ) {
                MetricDailyBars(
                    values: slots.map { $0.map { $0 * 100 } },
                    aspect: .heart,
                    leadingLabel: slots.isEmpty ? nil : Self.weekStart(Self.shownWeeks - 1, now: now, calendar: .current).map(words.short),
                    trailingLabel: "This week"
                )
            }
            MetricTextCard(
                eyebrow: "What it means",
                lead: "AFib History estimates how much of each week your heart spent in atrial fibrillation, from the pulse readings your watch takes through the day.",
                rest: "A lower share is better, and what helps is the same as for the heart in general: sleep, less alcohol, moving most days, and a weight and blood pressure in range. It is not a diagnosis; bring the weeks to your doctor."
            )
            MetricRowsCard(eyebrow: "More on your rhythm", rows: [
                MetricRowItem("ECG", detail: "Record one when you feel a flutter or a skipped beat.", route: .ecg),
                MetricRowItem("Rhythm notifications", detail: summary.events.first.map { "Last on \(words.day($0.date))" } ?? "None this year",
                              route: .rhythmEvents),
            ])
            MetricTextCard(
                eyebrow: "When to get help",
                lead: "Chest pain, pressure, fainting or breathlessness are not something to wait out: call emergency services.",
                rest: "AFib History cannot detect a heart attack or a stroke."
            )
        }
        .task { await load() }
        .somaRefreshable { await load() }
    }

    private func load() async {
        readings = await health.rhythmMobility()
    }

    private func headline(_ summary: HeartRhythmSummary) -> String {
        guard readings != nil else { return "Reading your AFib History." }
        guard let latest = summary.latestBurden else { return "No AFib History yet." }
        return "\(HeartRhythmSummary.burdenText(latest)) of the latest week in AFib."
    }

    private func reason(_ summary: HeartRhythmSummary) -> String {
        guard readings != nil else { return "Asking Health for your weekly estimates. They're read on this device only." }
        guard summary.latestBurden != nil else {
            return "AFib History needs an Apple Watch and a diagnosis of AFib, switched on in the Health app."
        }
        guard let change = summary.change else { return "One week read so far. The next ones show the direction." }
        if abs(change) < 0.01 { return "About the same as the week before." }
        return change > 0 ? "Up \(changeText(change)) on the week before." : "Down \(changeText(abs(change))) on the week before."
    }

    private func changeText(_ change: Double) -> String {
        let points = Int((change * 100).rounded())
        return points > 0 ? "+\(points) pts" : "\(points) pts"
    }

    /// The first day of the week `weeksAgo` weeks before this one.
    static func weekStart(_ weeksAgo: Int, now: Date, calendar: Calendar) -> Date? {
        guard let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start else { return nil }
        return calendar.date(byAdding: .weekOfYear, value: -weeksAgo, to: thisWeek)
    }

    /// One slot a week, oldest first, nil where no burden was read.
    static func slots(_ weeks: [AFibWeek], count: Int, now: Date, calendar: Calendar) -> [Double?] {
        guard !weeks.isEmpty else { return [] }
        let byStart = Dictionary(weeks.map { ($0.start, $0.burden) }, uniquingKeysWith: { first, _ in first })
        return (0..<count).reversed().map { weeksAgo in
            weekStart(weeksAgo, now: now, calendar: calendar).flatMap { byStart[$0] }
        }
    }
}

// MARK: - Reading

extension HealthDashboard {
    /// The rhythm and mobility readings of the last year, through the same
    /// once-per-set request as every page. Empty when Health is not there or
    /// the request threw; the page then keeps its dashes and ``MetricLead``
    /// says why.
    func rhythmMobility(now: Date = .now) async -> RhythmMobilityReadings {
        guard let source = await prepare(RhythmMobilityReadings.identifiers) else { return RhythmMobilityReadings() }
        return await RhythmMobilityReadings.read(from: source, now: now, calendar: .current)
    }
}

#Preview("AFib History") {
    NavigationStack { AFibBurdenPage() }
        .environment(HealthDashboard())
}
