//
//  NapArchitectPage.swift
//  Prism
//

import SwiftUI
import SomaUI
import SomaWidgetKit

/// Nap Architect: the afternoon window where a short nap helps, how long it
/// should be, and the cutoff after which a nap takes from tonight.
///
/// The nap engine runs over a SAFTE alertness curve built from last night: the
/// dip is the curve's afternoon low, the cutoff sits six hours before the
/// expected bedtime, and the length follows sleep pressure (twenty minutes, or
/// a full cycle when pressure is heavy).
struct NapArchitectPage: View {
    @Environment(HealthDashboard.self) private var health
    @Environment(JournalStore.self) private var journal
    @Environment(\.somaTheme) private var theme
    @State private var napping = SomaLiveActivities.shared.isRunning(.nap)

    private var model: ToolsModel { .shared }
    private var store: ToolsStore { .shared }

    var body: some View {
        let day = ToolDay(inputs: model.current, cups: TrackLogStore.shared.caffeineCups, sleepNeedHours: health.scores?.sleepNeedHours)
        let night = day.inputs.lastNight(calendar: day.calendar)
        let cbt = day.phase?.cbtMinHours ?? SomaTools.SAFTEEngine.Chronotype.intermediate.seedCBTminHour
        let plan = night.flatMap { SomaTools.NapArchitectEngine.plan(lastNightBed: $0.bed, wake: $0.wake, now: day.inputs.now,
                                                                      cbtMinHour: cbt, calendar: day.calendar) }
        let debt = health.scores?.sleepDebtHours

        ToolPage(ToolKind.napArchitect.title) {
            if let plan {
                let band = SomaTools.NapArchitectEngine.PressureBand(pressure: plan.currentPressure)
                ToolHero(eyebrow: eyebrow(plan), headline: headline(plan), lead: lead(plan), rest: rest(plan, debt: debt))
                ToolStats([
                    SomaStat("Nap for", value: plan.recommendedMinutes > 0 ? "\(plan.recommendedMinutes)" : nil, unit: "min"),
                    SomaStat("Cutoff", value: ToolFormat.clock(hour: plan.hardCutoffHour)),
                    SomaStat("Pressure", value: "\(Int(plan.currentPressure.rounded()))"),
                ])
                ToolRowsCard(title: "Sleep pressure", eyebrow: "Against the bands", aspect: .sleep, rows: [
                    ToolRow(title: "Pressure now", detail: "light under 26, heavy above 34",
                            value: "\(Int(plan.currentPressure.rounded())), \(band.rawValue)",
                            tone: band == .heavy ? .danger : .plain,
                            band: ToolBand(range: 0...50, usual: 18...26, value: plan.currentPressure)),
                    ToolRow(title: "Sleep debt", detail: "over recent nights", value: debt.map { ToolFormat.span(hours: $0) },
                            band: ToolBand(range: 0...3, usual: 0...1, value: debt)),
                ])
            } else {
                ToolHero(eyebrow: "No night yet",
                         headline: "The nap window needs last night.",
                         lead: "It builds your day’s alertness curve from when you slept, and no night since yesterday is recorded.",
                         rest: "With a watch on overnight, the window appears in the morning.")
                ToolStats([SomaStat("Nap for", value: nil, unit: "min"), SomaStat("Cutoff", value: nil), SomaStat("Pressure", value: nil)])
            }

            energyCard

            if let plan, plan.hasWindow {
                ToolNoteCard(title: "Why \(ToolFormat.clock(hour: plan.windowStartHour)) to \(ToolFormat.clock(hour: plan.hardCutoffHour))",
                             lead: "It sits on your afternoon dip, where sleep pressure and your body clock line up.",
                             rest: "Twenty minutes clears fatigue without reaching deep sleep, so you wake sharp rather than groggy.")
            }
            if let plan, plan.recommendedMinutes > 0, SomaLiveActivities.shared.isAvailable {
                ToolButtonRow(title: napping ? "End the nap" : "Start a \(plan.recommendedMinutes) minute nap",
                              detail: napping ? "On your lock screen" : "Counts down on your lock screen, rings at the end") {
                    if napping {
                        NapTimer.cancel()
                        napping = false
                    } else {
                        if !napLogged { journal.toggle("nap", on: Date()) }
                        napping = true
                        Task { await NapTimer.start(minutes: plan.recommendedMinutes) }
                    }
                }
            }
            ToolButtonRow(title: "Naps today", detail: napLogged ? "One logged" : "None logged") {
                journal.toggle("nap", on: Date())
            }
            ToolLinkRow(title: "About Nap Architect", detail: nil, value: ToolRoute.intro(.napArchitect))
        }
        .task {
            store.markOpened(.napArchitect)
            await model.load(health)
        }
    }

    private var napLogged: Bool {
        journal.day(Date()).tags.contains("nap")
    }

    @ViewBuilder
    private var energyCard: some View {
        let curve = health.scores?.energyCurve ?? []
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let end = start.addingTimeInterval(24 * 3600)
        // The curve on a fixed day axis: one slot per half hour, nil where
        // the energy model has no point.
        let slots: [Double?] = (0..<48).map { index in
            let from = start.addingTimeInterval(Double(index) * 1800)
            let inside = curve.filter { $0.date >= from && $0.date < from.addingTimeInterval(1800) }.map(\.level)
            return inside.isEmpty ? nil : inside.reduce(0, +) / Double(inside.count)
        }
        let now = health.scores?.energy
        SomaChartCard(eyebrow: "Energy today", value: now.map { "\($0)" }, unit: "of 100",
                      note: curve.isEmpty ? "The energy curve fills in as the watch records the day." : "Pressure builds as energy falls.") {
            ToolCurveChart(aspect: .mind, values: slots, top: 100,
                           now: Date().timeIntervalSince(start) / end.timeIntervalSince(start),
                           xLabels: ["00", "06", "12", "18", "24"], yLabels: ["100", "50", "0"])
        }
    }

    private func eyebrow(_ plan: SomaTools.NapArchitectEngine.Plan) -> String {
        if !plan.hasWindow { return "No window today" }
        if plan.pastCutoff { return "Past the cutoff" }
        return plan.isOpenNow ? "Open now" : "Opens at \(ToolFormat.clock(hour: plan.windowStartHour))"
    }

    private func headline(_ plan: SomaTools.NapArchitectEngine.Plan) -> String {
        if !plan.hasWindow { return "No room for a nap today." }
        if plan.pastCutoff { return "Too late for a nap today." }
        if plan.isOpenNow { return "A \(plan.recommendedMinutes) minute nap fits now." }
        return "Nap at \(ToolFormat.clock(hour: plan.windowStartHour)) for \(plan.recommendedMinutes) minutes."
    }

    private func lead(_ plan: SomaTools.NapArchitectEngine.Plan) -> String {
        "The window runs from \(ToolFormat.clock(hour: plan.windowStartHour)) and closes for good at \(ToolFormat.clock(hour: plan.hardCutoffHour))."
    }

    private func rest(_ plan: SomaTools.NapArchitectEngine.Plan, debt: Double?) -> String? {
        guard plan.pastCutoff else { return nil }
        if let debt, debt > 0.5 {
            return "A nap now would take from tonight; with \(ToolFormat.span(hours: debt)) of sleep debt, an early night pays back more."
        }
        return "A nap now would take from tonight."
    }
}
