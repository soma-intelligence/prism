//
//  SocialJetlagPage.swift
//  Prism
//

import SwiftUI
import SomaUI

/// Social Jetlag: how much later the body sleeps on free nights than on work
/// nights, measured from the middle of each night (Roenneberg's MCTQ).
struct SocialJetlagPage: View {
    @Environment(HealthDashboard.self) private var health
    @Environment(\.somaTheme) private var theme
    @State private var showAlarm = false

    private var model: ToolsModel { .shared }
    private var store: ToolsStore { .shared }

    var body: some View {
        let day = ToolDay(inputs: model.current, cups: TrackLogStore.shared.caffeineCups, sleepNeedHours: health.scores?.sleepNeedHours)
        let week = weekComparison(day)
        let series = SomaTools.CircadianTrends.socialJetlagSeries(bedHours: longSeries(day).bed, wakeHours: longSeries(day).wake,
                                                                 endingOn: day.inputs.now, weeks: 12)
        let known = series.compactMap { $0 }
        let usual = known.count >= 3 ? (known.min() ?? 0)...(known.max() ?? 0) : nil
        let gap = week?.signedGapHours

        ToolPage(ToolKind.socialJetlag.title) {
            ToolHero(eyebrow: "This week",
                     headline: headline(gap),
                     lead: week.map { "Mid-sleep falls at \(ToolFormat.clock(hour: $0.workdayMidSleepHour)) on work nights and at \(ToolFormat.clock(hour: $0.freeDayMidSleepHour)) on free nights." }
                        ?? "It needs at least one work night and two free nights to compare.",
                     rest: week == nil ? "\(day.nightCount) nights recorded in the last eight weeks." : "Under two hours is healthy.")
            ToolStats([
                SomaStat("Weekdays", value: week.map { ToolFormat.clock(hour: $0.workdayMidSleepHour) }),
                SomaStat("Weekends", value: week.map { ToolFormat.clock(hour: $0.freeDayMidSleepHour) }),
                SomaStat("Drift", value: week.map { ToolFormat.hoursMinutes($0.gapHours) }),
            ])

            if let week {
                SomaChartCard(eyebrow: "Your nights this week", value: nil,
                              note: "Each bar is a typical night; the white mark is its middle, the moment the body clock is read from.") {
                    ToolSpanRows(aspect: .sleep, rows: nightRows(day, week: week), axis: 21...35, ticks: [22, 25, 28, 31, 34])
                }
            }

            SomaChartCard(eyebrow: "Social jetlag", value: gap.map { ToolFormat.hoursMinutes(abs($0)) }, unit: "this week",
                          note: usual.map { "12 weeks. Usually \(ToolFormat.hoursMinutes($0.lowerBound)) to \(ToolFormat.hoursMinutes($0.upperBound)); under 2:00 is healthy." }
                            ?? "12 weeks. Each week needs two free nights to count.") {
                ToolHistoryChart(aspect: .sleep, values: series, band: usual, firstLabel: "12 weeks ago")
            }

            ToolLinkRow(title: "How the drift is measured", detail: nil, value: ToolRoute.intro(.socialJetlag))

            if let week, week.gapHours >= 0.5 {
                let target = week.workdayMidSleepHour + 0.5
                ToolNextCard(eyebrow: "This weekend", aspect: .sleep,
                             title: "Keep mid-sleep near \(ToolFormat.clock(hour: target)) on Saturday",
                             detail: "Rising within an hour of a work day brings the drift down.",
                             actionTitle: "Set alarm", action: { showAlarm = true })
            }
        }
        .navigationDestination(isPresented: $showAlarm) { SmartAlarmPage() }
        .task {
            store.markOpened(.socialJetlag)
            await model.load(health)
        }
    }

    private func longSeries(_ day: ToolDay) -> (bed: [Double?], wake: [Double?]) {
        day.inputs.series(days: ToolsInputs.nightDays, calendar: day.calendar)
    }

    /// The comparison over the last four weeks, which is what a week's figure
    /// needs to hold two free nights.
    private func weekComparison(_ day: ToolDay) -> SomaTools.SocialJetlag.Comparison? {
        let recent = day.inputs.series(days: 28, calendar: day.calendar)
        return SomaTools.SocialJetlag.compare(bedHours: recent.bed, wakeHours: recent.wake, today: day.inputs.now)
    }

    private func headline(_ gap: Double?) -> String {
        guard let gap else { return "Not enough nights to compare yet." }
        let span = ToolFormat.span(hours: abs(gap))
        if abs(gap) < 0.25 { return "Weekends keep the same time as weekdays." }
        return gap > 0 ? "Weekends run \(span) later than weekdays." : "Weekends run \(span) earlier than weekdays."
    }

    private func nightRows(_ day: ToolDay, week: SomaTools.SocialJetlag.Comparison) -> [ToolSpanRows.Row] {
        func axis(_ hour: Double) -> Double { hour < 12 ? hour + 24 : hour }
        let durations = day.nights.map { SomaTools.ChronotypeEstimator.sleepDuration(bedHour: $0.bedHour, wakeHour: $0.wakeHour) }
        let half = (durations.isEmpty ? 7.5 : durations.reduce(0, +) / Double(durations.count)) / 2
        let work = axis(week.workdayMidSleepHour), free = axis(week.freeDayMidSleepHour)
        return [
            ToolSpanRows.Row(label: "Work nights", start: work - half, end: work + half, mark: work),
            ToolSpanRows.Row(label: "Free nights", start: free - half, end: free + half, mark: free, strength: 0.6),
        ]
    }
}
