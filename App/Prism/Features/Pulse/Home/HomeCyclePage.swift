//
//  HomeCyclePage.swift
//  Prism
//

import SwiftUI
import SomaUI
import HealthExportCore

/// Where the person is in their cycle, pushed from Today's cycle card: the
/// day and the phase from the flow Apple Health holds, what the phase moves
/// against the usual, the next period, and a feeling to log.
///
/// Cycle tracking is sensitive: it is asked for here, when this page opens,
/// and never at launch.
struct HomeCyclePage: View {
    @Environment(HealthDashboard.self) private var health
    @Environment(\.somaTheme) private var theme
    @State private var cycle: HomeCycle?
    @State private var periodDays = 0
    @State private var markers: [HomeMarker: HomeMarkerSeries] = [:]
    @State private var isRead = false
    @State private var sheet: HomeSheetRoute?

    private let calendar = Calendar.current

    var body: some View {
        HomePage("Cycle") {
            SomaPageHero(eyebrow: eyebrow, title: title, reason: reason)
                .padding(.bottom, theme.metrics.cardSpacing)

            SomaChartCard(
                eyebrow: "Cycle",
                value: cycle.map { "\($0.day)" },
                unit: cycle?.length.map { "of \($0) days" } ?? "days in",
                note: chartNote
            ) {
                if let cycle {
                    HomeCycleTrack(cycle: cycle, periodDays: periodDays)
                        .padding(.top, 8)
                }
            }

            HomeRowsCard("What this phase moves", caption: "Against your usual") {
                ForEach([HomeMarker.restingHeartRate, .wristTemperature, .breathing, .hrv]) { marker in
                    HomeMeasureRow(
                        name: marker.title,
                        unit: marker.unit,
                        decimals: marker.decimals,
                        latest: markers[marker]?.latest,
                        band: markers[marker]?.band,
                        higherIsWorse: marker.higherIsWorse
                    )
                }
            }

            SomaCard {
                VStack(alignment: .leading, spacing: theme.metrics.moveRowSpacing) {
                    HomeValueRow(name: "Next period", value: cycle?.nextStart.map { "About \($0.formatted(.dateTime.day().month(.abbreviated)))" })
                    HomeHairline()
                    HomeValueRow(name: "Cycle length", value: cycle?.length.map { "\($0) days" })
                    HomeHairline()
                    HomeValueRow(
                        name: "Past cycles",
                        value: cycle.flatMap { $0.lengths.isEmpty ? nil : $0.lengths.suffix(4).map(String.init).joined(separator: ", ") }
                    )
                }
            }

            HomeActionCard(
                eyebrow: "Today",
                aspect: .body,
                title: "Log how today feels",
                detail: "Symptoms and energy help Soma tell your cycle from a cold coming on.",
                actionTitle: "Log it"
            ) { sheet = .checkIn }
        }
        .task { await read() }
        .homeSheets($sheet)
    }

    private var eyebrow: String {
        guard let cycle else { return "Cycle" }
        var text = "Day \(cycle.day)"
        if let length = cycle.length { text += " of \(length)" }
        if let phase = cycle.phase { text += " · \(phase.title)" }
        return text
    }

    private var title: String {
        guard isRead else { return "Reading your cycle." }
        switch cycle?.phase {
        case .menstrual: return "The first days of your cycle."
        case .follicular: return "The cooler half of your cycle."
        case .ovulatory: return "Around ovulation."
        case .luteal: return "The warmer half of your cycle."
        case nil: return cycle == nil ? "No cycle on record yet." : "One period on record."
        }
    }

    private var reason: String {
        guard isRead else { return "Asking Apple Health for cycle tracking, which only this page reads." }
        guard let cycle else {
            return "Log periods in Apple Health’s Cycle Tracking, or allow Soma to read them, and your phase shows here."
        }
        switch cycle.phase {
        case .luteal:
            let days = cycle.nextStart.flatMap { calendar.dateComponents([.day], from: calendar.startOfDay(for: Date()), to: $0).day }
            let when = days.map { " in about \($0) days" } ?? ""
            return "Resting heart rate, temperature and breathing all run a little higher now. That is usual after ovulation, and it eases when your period starts\(when). Soma reads this week’s numbers with that in mind."
        case .follicular:
            return "Resting heart rate and temperature sit at their lowest in this half. Harder training tends to feel easier now."
        case .ovulatory:
            return "Temperature turns upward around now. A small rise over the next days is expected, not a sign of illness."
        case .menstrual:
            return "Energy can dip in the first days. Soma keeps the plan gentler while your period runs."
        case nil:
            return "Two periods on record give Soma your cycle length; the phase and the next period follow from it."
        }
    }

    private var chartNote: String {
        guard let cycle else { return "Fills in from the periods logged in Apple Health." }
        guard let next = cycle.nextStart else { return "Day \(cycle.day) since your last period started." }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: Date()), to: next).day ?? 0
        let phase = cycle.phase.map { "\($0.title) phase. " } ?? ""
        return days >= 0 ? "\(phase)Period expected in about \(days) days." : "\(phase)Your period is \(-days) days later than your usual."
    }

    private func read() async {
        let wanted = [HomeMetric.menstrualFlow, HomeMetric.respiratoryRate, HomeMetric.wristTemperature]
        guard !isRead, let source = await health.prepare(wanted) else {
            isRead = true
            return
        }
        let now = Date()
        // Value 5 is "none": a day logged without flow.
        let flow = await source.home(HomeMetric.menstrualFlow, days: 400, now: now, calendar: calendar)
            .filter { Int($0.value) != 5 }
        cycle = HomeCycle.make(flowDays: flow.map(\.start), today: now, calendar: calendar)
        if let start = cycle?.starts.last {
            periodDays = Set(flow.filter { $0.start >= start }.map { calendar.startOfDay(for: $0.start) }).count
        }
        for marker in [HomeMarker.restingHeartRate, .wristTemperature, .breathing, .hrv] {
            let readings = await source.home(marker.identifier, days: 40, now: now, calendar: calendar)
            markers[marker] = HomeMarkerSeries.make(readings, days: 14, today: now, calendar: calendar, aggregate: marker.aggregate)
        }
        isRead = true
    }
}
