//
//  ShiftWorkPage.swift
//  Prism
//

import SwiftUI
import SomaUI

/// Shift Work Reset: tell it the shift, and it prints the plan for light,
/// sleep, a nap and caffeine, and the way back to your usual window.
///
/// The shift plan engine: a new roster moves the wake time the way a flight
/// moves the clock, so the jet lag model does the re-entrainment arithmetic.
/// Nothing is planned until a shift is set.
struct ShiftWorkPage: View {
    @Environment(HealthDashboard.self) private var health
    @Environment(\.somaTheme) private var theme
    @State private var editing = false

    private var model: ToolsModel { .shared }
    private var store: ToolsStore { .shared }

    var body: some View {
        let shift = store.record.shift
        let day = ToolDay(inputs: model.current, cups: TrackLogStore.shared.caffeineCups, sleepNeedHours: health.scores?.sleepNeedHours)
        let wakeHour = shift.usualWake.map { Double($0) / 60 } ?? day.habitualWakeHour
        let sleepHour = day.habitualSleepHour ?? SomaTools.ShiftSchedule.habitualSleepHour
        let plan: SomaTools.ShiftPlan? = shift.starts.flatMap { starts in
            SomaTools.ShiftSchedule.plan(
                shiftStartHour: Double(starts) / 60,
                usualWakeHour: wakeHour ?? SomaTools.ShiftSchedule.defaultUsualWakeHour,
                daysSinceChange: SomaTools.ShiftSchedule.daysSinceChange(rosterDate: shift.firstNight, now: model.current.now),
                recentDaylightMin: model.current.daylightToday ?? SomaTools.ShiftSchedule.recentDaylightMin,
                habitualSleepHour: sleepHour)
        }

        ToolPage(ToolKind.shiftWork.title) {
            if let plan, let starts = shift.starts {
                ToolHero(eyebrow: "\(shift.kind?.rawValue ?? "Shift") · starts \(ToolFormat.clock(hour: Double(starts) / 60))",
                         headline: plan.state.daysLeft > 0
                            ? "\(ToolFormat.capitalized(ToolFormat.words(plan.state.daysLeft))) days to settle into the shift."
                            : "Your clock has caught up with the shift.",
                         lead: "Your wake moves \(ToolFormat.span(hours: abs(plan.shiftHours))) \(plan.shiftHours > 0 ? "earlier" : "later").",
                         rest: plan.state.direction == .advance ? "Morning light pulls the clock earlier; keep the evening dim." : "Evening light pushes the clock later; keep the early morning dim.")
                ToolStats(stats(shift: shift, wake: wakeHour, plan: plan))
                ToolEyebrow("Today’s plan")
                ToolRowsCard(aspect: .sleep, rows: plan.actions.map { action in
                    ToolRow(title: action.title, detail: action.detail,
                            value: action.endHour.map { "\(ToolFormat.clock(hour: action.startHour)) to \(ToolFormat.clock(hour: $0))" }
                                ?? "by \(ToolFormat.clock(hour: action.startHour))")
                })
                ToolFootnote("Not medical advice.")
                ToolNextCard(eyebrow: "Your shift", aspect: .sleep, title: "Change the shift",
                             detail: "The plan follows the times you set.", actionTitle: "Edit", action: { editing = true })
            } else {
                ToolHero(eyebrow: "No shift set",
                         headline: "Tell it your shift, and it prints the plan.",
                         lead: "Set when a shift starts and when you usually wake.",
                         rest: "It then times light, sleep and a nap around the first nights, and the way back to your usual window.")
                ToolStats(stats(shift: shift, wake: wakeHour, plan: nil))
                ToolEyebrow("What the plan covers")
                ToolRowsCard(rows: [
                    ToolRow(title: "Light", detail: "When to seek it, and when to block it on the way home."),
                    ToolRow(title: "Sleep", detail: "An anchor block that stays put, and a nap before the first night."),
                    ToolRow(title: "Caffeine", detail: "A cutoff six hours before the sleep you plan after a shift."),
                    ToolRow(title: "The way back", detail: "How many days to return to your window, and what each asks of you."),
                ].map { var row = $0; row.value = ""; return row })
                ToolNextCard(eyebrow: "Start", aspect: .sleep, title: "Working nights or early starts?",
                             detail: "Two times are enough to begin.", actionTitle: "Set shift", action: { editing = true })
            }
            ToolLinkRow(title: "About Shift Work Reset", detail: nil, value: ToolRoute.intro(.shiftWork))
        }
        .sheet(isPresented: $editing) { ShiftSheet(habitualWake: day.habitualWakeHour) }
        .task {
            store.markOpened(.shiftWork)
            await model.load(health)
        }
    }

    private func stats(shift: ShiftPrefs, wake: Double?, plan: SomaTools.ShiftPlan?) -> [SomaStat] {
        [
            SomaStat("Shift", value: shift.starts.map { ToolFormat.clock(hour: Double($0) / 60) }),
            SomaStat("Usual wake", value: wake.map { ToolFormat.clock(hour: $0) }),
            SomaStat("First night", value: shift.firstNight.map { $0.formatted(.dateTime.day().month(.abbreviated)) }),
        ]
    }
}

/// The shift sheet: the kind of shift and its times.
struct ShiftSheet: View {
    let habitualWake: Double?

    @Environment(\.dismiss) private var dismiss

    private var store: ToolsStore { .shared }

    var body: some View {
        let shift = store.record.shift
        NavigationStack {
            ListScaffold(eyebrow: "Shift Work Reset", title: "Your shift") {
                ToolEyebrow("Kind of shift")
                ToolSettingsGroup(rows: ShiftPrefs.Kind.allCases.map { kind in
                    .choice(kind.rawValue, shift.kind == kind, { store.update { $0.shift.kind = kind } })
                })
                ToolEyebrow("Times")
                ToolSettingsGroup(rows: [
                    .time("Shift starts", Binding(get: { shift.starts ?? 22 * 60 }, set: { v in store.update { $0.shift.starts = v } })),
                    .time("Usual wake", Binding(get: { shift.usualWake ?? Int(((habitualWake ?? 7) * 60).rounded()) },
                                                set: { v in store.update { $0.shift.usualWake = v } })),
                    .date("First night", Binding(get: { shift.firstNight }, set: { v in store.update { $0.shift.firstNight = v } })),
                ])
                if shift.starts != nil {
                    ToolButtonRow(title: "Clear the shift", detail: nil) {
                        store.update { $0.shift = ShiftPrefs() }
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
