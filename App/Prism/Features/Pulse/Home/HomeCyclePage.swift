//
//  HomeCyclePage.swift
//  Prism
//

import SwiftUI
import SomaUI
import HealthExportCore

/// Where the person is in their cycle, pushed from Today's cycle card and
/// from Body: the day and the phase from the flow Apple Health holds, the
/// month with its period and the next one expected, the symptoms of this
/// cycle, what the phase moves against the usual, the next period, signs of
/// the menopause transition when there are any, and the log. the earlier app's cycle
/// detail, drawn as Soma.
///
/// Cycle tracking and the symptoms logged against it are sensitive: they are
/// asked for here, when this page opens, and never at launch.
struct HomeCyclePage: View {
    @Environment(HealthDashboard.self) private var health
    @Environment(\.somaTheme) private var theme
    @State private var cycle: HomeCycle?
    @State private var periodDays = 0
    @State private var markers: [HomeMarker: HomeMarkerSeries] = [:]
    @State private var isRead = false
    @State private var sheet: HomeSheetRoute?
    /// Every day with flow, at its start.
    @State private var flowDays: [Date] = []
    /// Days each symptom was logged on, over the same year as the flow.
    @State private var symptoms: [CycleSymptom: [Date]] = [:]
    @State private var assessment = PerimenopauseAssessment(stage: nil, signs: [])
    @State private var isLogging = false

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
                        .padding(.top, theme.metrics.spaceS)
                }
            }

            CycleCalendarCard(
                month: Date(),
                periodDays: Set(flowDays),
                expectedDays: expectedDays,
                symptomDays: Set(symptoms.values.flatMap { $0 }.map { calendar.startOfDay(for: $0) })
            )

            HomeRowsCard("Symptoms this cycle", caption: cycle == nil ? "Logged in Apple Health" : "Since day 1") {
                if tally.isEmpty {
                    HomeValueRow(name: "None logged", detail: "Log cramps, hot flashes and the rest below. They go to Apple Health.", value: nil)
                } else {
                    ForEach(tally, id: \.symptom) { item in
                        HomeValueRow(name: item.symptom.title, value: item.days == 1 ? "1 day" : "\(item.days) days")
                    }
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

            if PerimenopauseCard.shows(assessment) {
                PerimenopauseCard(assessment: assessment)
            }

            HomeActionCard(
                eyebrow: "Today",
                aspect: .body,
                title: "Log your cycle",
                detail: "Flow and symptoms go to Apple Health, and help Soma tell your cycle from a cold coming on.",
                actionTitle: "Log it"
            ) { isLogging = true }

            LabFootnote("Informative, not a diagnosis. Predictions come from your own past cycles. Pain, very heavy bleeding or bleeding between periods is for a clinician.")
        }
        .task { await read() }
        .homeSheets($sheet)
        .sheet(isPresented: $isLogging, onDismiss: { Task { await read(force: true) } }) {
            NavigationStack { CycleLogSheet() }
                .environment(\.trackInSheet, true)
                .presentationDragIndicator(.visible)
        }
#if DEBUG
        .task {
            // `-cycle.log YES` opens the log over the page, for screenshots.
            if UserDefaults.standard.bool(forKey: "cycle.log") {
                try? await Task.sleep(for: .seconds(theme.motion.settleDelay))
                isLogging = true
            }
        }
#endif
    }

    /// The days the next period is expected: as many days as the last
    /// finished period ran, from the predicted start.
    private var expectedDays: Set<Date> {
        guard let next = cycle?.nextStart else { return [] }
        let length = CycleHistory.periods(flowDays: flowDays, today: Date(), calendar: calendar)
            .compactMap(\.days).last ?? 5
        return Set((0..<length).compactMap { calendar.date(byAdding: .day, value: $0, to: next) })
    }

    private var tally: [CycleSymptomTally] {
        guard let start = cycle?.starts.last else { return [] }
        return CycleSymptomTally.make(symptoms: symptoms, since: start, now: Date(), calendar: calendar)
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

    private func read(force: Bool = false) async {
        guard force || !isRead else { return }
        let now = Date()
        #if DEBUG && targetEnvironment(simulator)
        if FixtureCycle.isOn {
            let wrist = FixtureCycle.wristTemperature(now: now, calendar: calendar)
            apply(flow: FixtureCycle.flowDays(now: now, calendar: calendar),
                  symptoms: FixtureCycle.symptoms(now: now, calendar: calendar),
                  wrist: wrist, age: FixtureCycle.age, now: now)
            markers[.wristTemperature] = HomeMarkerSeries.make(wrist, days: 14, today: now, calendar: calendar,
                                                               aggregate: HomeMarker.wristTemperature.aggregate)
            isRead = true
            return
        }
        #endif
        // The flow and the symptoms are sensitive: naming them here is what
        // asks for them, on this page and nowhere at launch.
        let wanted = [HomeMetric.menstrualFlow, HomeMetric.respiratoryRate, HomeMetric.wristTemperature]
            + CycleSymptom.allCases.map(\.identifier)
        guard let source = await health.prepare(wanted) else {
            isRead = true
            return
        }
        // Value 5 is "none": a day logged without flow.
        let flow = await source.home(HomeMetric.menstrualFlow, days: 400, now: now, calendar: calendar)
            .filter { $0.code != 5 }
            .map(\.start)
        var logged: [CycleSymptom: [Date]] = [:]
        for symptom in CycleSymptom.allCases {
            let days = await source.home(symptom.identifier, days: 400, now: now, calendar: calendar)
                .filter { $0.code != CycleSymptom.notPresentCode }
                .map(\.start)
            if !days.isEmpty { logged[symptom] = days }
        }
        let wrist = await source.home(HomeMetric.wristTemperature, days: 40, now: now, calendar: calendar)
        apply(flow: flow, symptoms: logged, wrist: wrist, age: SomaProfileStore.shared.profile.age(on: now, calendar: calendar), now: now)
        // What tells Body and Track that this person tracks a cycle.
        if let last = flowDays.last { CycleStore.shared.markFlowSeen(last) }
        for marker in [HomeMarker.restingHeartRate, .wristTemperature, .breathing, .hrv] {
            let readings = marker == .wristTemperature ? wrist : await source.home(marker.identifier, days: 40, now: now, calendar: calendar)
            markers[marker] = HomeMarkerSeries.make(readings, days: 14, today: now, calendar: calendar, aggregate: marker.aggregate)
        }
        isRead = true
    }

    /// Everything the page draws from the flow days, the symptoms and the
    /// wrist: the cycle, the month, the tally and the transition signs.
    private func apply(flow: [Date], symptoms logged: [CycleSymptom: [Date]], wrist: [HealthReading], age: Int?, now: Date) {
        flowDays = Set(flow.map { calendar.startOfDay(for: $0) }).sorted()
        symptoms = logged
        cycle = HomeCycle.make(flowDays: flowDays, today: now, calendar: calendar)
        if let start = cycle?.starts.last {
            periodDays = flowDays.filter { $0 >= start }.count
        }
        assessment = PerimenopauseSignal.assess(
            cycles: CycleHistory.periods(flowDays: flowDays, today: now, calendar: calendar),
            symptoms: logged, wristTemperature: wrist, now: now, calendar: calendar, age: age
        )
    }
}
