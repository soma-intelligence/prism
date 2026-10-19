//
//  SmartAlarmPage.swift
//  Prism
//

import SwiftUI
import SomaUI
import HealthScoring

/// Smart Alarm: one ring inside a window that ends at the "never after" time,
/// at the lightest moment the night is expected to offer.
///
/// The smart wake engine picks the moment: the window's latest edge is a
/// hard bound, and inside it the ring lands at the end of a predicted sleep
/// cycle from tonight's expected onset, pulled later by debt and a low HRV.
/// Without a watch the moment is predicted and never adjusted overnight.
struct SmartAlarmPage: View {
    @Environment(HealthDashboard.self) private var health
    @Environment(\.somaTheme) private var theme
    @State private var settings = false
    @State private var setKind: ToolAlarmScheduler.Kind?
    @State private var reminded = false

    private var model: ToolsModel { .shared }
    private var store: ToolsStore { .shared }

    var body: some View {
        let prefs = store.record.alarm
        let day = ToolDay(inputs: model.current, cups: TrackLogStore.shared.caffeineCups, sleepNeedHours: health.scores?.sleepNeedHours)
        let plan = SmartAlarmReading.make(prefs: prefs, day: day, scores: health.scores)
        let last = day.inputs.lastNight(calendar: day.calendar)

        ToolPage(ToolKind.smartAlarm.title) {
            if let plan {
                ToolHero(eyebrow: "\(plan.dayLabel)",
                         headline: "Up between \(ToolFormat.clock(plan.window.lowerBound)) and \(ToolFormat.clock(plan.window.upperBound)).",
                         lead: prefs.isOn ? "Capped at \(ToolFormat.clock(plan.window.upperBound)), the time you set." : "The alarm is off; this is what it would do.",
                         rest: "It wakes you at the lightest moment in that half hour. Expected at \(ToolFormat.clock(plan.ring)).")
                ToolStats([
                    SomaStat("Lights out", value: plan.lightsOut.map { ToolFormat.clock($0) }),
                    SomaStat("Window", value: "\(prefs.window)", unit: "min"),
                    SomaStat("Wake by", value: ToolFormat.clock(plan.window.upperBound)),
                ])
            } else {
                ToolHero(eyebrow: "No days set", headline: "Pick the days it rings.", lead: "Open the settings to choose days and a time.")
            }

            SomaChartCard(eyebrow: "Last night", value: last.map { ToolFormat.hoursMinutes($0.asleep) }, unit: "asleep",
                          note: last == nil ? "No night recorded since yesterday." : "The kind of light stretches it waits for.") {
                if let last { ToolHypnogram(night: last) }
            }

            ToolEyebrow("Limits")
            ToolRowsCard(rows: [
                ToolRow(title: ToolAlarmScheduler.alarmKitAllowed ? "It lives in Soma" : "A notification, for now",
                        detail: ToolAlarmScheduler.alarmKitAllowed
                            ? "It breaks through silent mode and Focus, and never shows in the Clock app."
                            : "Soma cannot set a true alarm yet, so it rings as a notification, which silent mode can hush.",
                        value: ""),
                ToolRow(title: "A watch refines it", detail: "Without one, the moment is predicted and never adjusted overnight.", value: ""),
            ])
            ToolButtonRow(title: "Alarm settings", detail: prefs.isOn ? "On" : "Off") { settings = true }

            if let plan, let lightsOut = plan.lightsOut {
                let windDown = lightsOut.addingTimeInterval(-Double(prefs.remindBefore) * 60)
                ToolNextCard(eyebrow: "Tonight", aspect: .sleep, title: "Wind down at \(ToolFormat.clock(windDown))",
                             detail: "Lights out by \(ToolFormat.clock(lightsOut)) keeps your sleep need.",
                             actionTitle: reminded ? "Reminder set" : "Remind me",
                             action: {
                                 Task {
                                     reminded = await ToolNotifier.remind(id: "alarm-winddown", title: "Wind down",
                                                                          body: "Lights out by \(ToolFormat.clock(lightsOut)).", at: windDown)
                                 }
                             })
            }
            if let setKind {
                ToolFootnote(setKind == .alarm ? "Alarm set." : setKind == .notification ? "Set as a notification." : "Nothing could be set: notifications are off for Soma.")
            }
            ToolLinkRow(title: "About Smart Alarm", detail: nil, value: ToolRoute.intro(.smartAlarm))
        }
        .sheet(isPresented: $settings, onDismiss: { Task { await apply() } }) { SmartAlarmSettingsSheet() }
        .task {
            store.markOpened(.smartAlarm)
            await model.load(health)
        }
    }

    /// Sets or clears the ring after the settings change.
    private func apply() async {
        let prefs = store.record.alarm
        guard prefs.isOn else {
            ToolAlarmScheduler.cancel()
            setKind = nil
            return
        }
        let day = ToolDay(inputs: model.current, cups: TrackLogStore.shared.caffeineCups, sleepNeedHours: health.scores?.sleepNeedHours)
        guard let plan = SmartAlarmReading.make(prefs: prefs, day: day, scores: health.scores) else { return }
        setKind = await ToolAlarmScheduler.set(plan.ring, tint: theme.colors.accent.color)
    }
}

/// The next ring, worked out from the settings and the nights.
struct SmartAlarmReading {
    var ring: Date
    var window: ClosedRange<Date>
    var lightsOut: Date?
    var dayLabel: String

    static func make(prefs: AlarmPrefs, day: ToolDay, scores: SomaScores?) -> SmartAlarmReading? {
        let calendar = day.calendar
        let now = day.inputs.now
        // The next ringing day: tomorrow at the earliest, on a chosen weekday.
        var latest: Date?
        for offset in 1...7 {
            guard let date = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)) else { continue }
            if prefs.days.contains(calendar.component(.weekday, from: date)) {
                latest = calendar.date(byAdding: .minute, value: prefs.neverAfter, to: date)
                break
            }
        }
        guard let latest else { return nil }
        let earliest = latest.addingTimeInterval(-Double(prefs.window) * 60)
        let need = (scores?.sleepNeedHours ?? day.sleepNeedHours) * 3600
        let onset = day.nextBedtime
        let spans = day.inputs.lastNight(calendar: calendar)?.stages.map {
            SomaTools.SleepCycleModel.StageSpan(stage: $0.stage, seconds: $0.end.timeIntervalSince($0.start))
        } ?? []
        let inputs = SomaTools.SmartWakeEngine.Inputs(
            earliest: earliest, latest: latest,
            anchorWakeHour: day.habitualWakeHour, regularity: day.alignment?.regularity.map { Double($0.score) / 100 },
            cbtMinHour: day.phase?.cbtMinHours, sleepNeedSeconds: Int(need),
            debtHours: scores?.sleepDebtHours ?? 0, hrvRatio: 1, strainRatio: 1,
            onset: onset, onsetLatencySeconds: 15 * 60,
            meanCycleSeconds: SomaTools.SleepCycleModel.meanCycleSeconds(spans),
            observedSpans: [], observedOnset: nil, calendar: calendar)
        let plan = SomaTools.SmartWakeEngine.plan(inputs)
        let lightsOut = plan.ring.addingTimeInterval(-need - 15 * 60)
        return SmartAlarmReading(ring: plan.ring, window: plan.window,
                                 lightsOut: lightsOut > now ? lightsOut : nil,
                                 dayLabel: ToolFormat.day(latest, weekday: true))
    }
}

/// Last night's stages: a lane per stage, each stretch a
/// block in its shade of the sleep hue, joined by thin steps.
struct ToolHypnogram: View {
    let night: ToolNight

    var body: some View {
        SomaHypnogram(
            runs: night.stages.compactMap { run in
                SomaSleepStage(name: run.stage).map { SomaStageRun(stage: $0, start: run.start, end: run.end) }
            },
            xLabels: [ToolFormat.clock(night.bed), ToolFormat.clock(night.wake)]
        )
        .accessibilityHidden(true)
    }
}

/// The Smart Alarm's settings sheet.
struct SmartAlarmSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss

    private var store: ToolsStore { .shared }

    var body: some View {
        let prefs = store.record.alarm
        func bind<T>(_ key: WritableKeyPath<AlarmPrefs, T>) -> Binding<T> {
            Binding(get: { store.record.alarm[keyPath: key] }, set: { v in store.update { $0.alarm[keyPath: key] = v } })
        }
        return NavigationStack {
            ListScaffold(eyebrow: "Smart Alarm", title: "Alarm settings") {
                ToolEyebrow("The alarm")
                ToolSettingsGroup(rows: [
                    .toggle("Smart Alarm", bind(\.isOn)),
                    .time("Never after", bind(\.neverAfter)),
                    .toggle("Weekends too", Binding(get: { prefs.days.contains(1) && prefs.days.contains(7) },
                                                    set: { on in store.update { if on { $0.alarm.days.formUnion([1, 7]) } else { $0.alarm.days.subtract([1, 7]) } } })),
                ])
                ToolEyebrow("Picking the moment")
                ToolSettingsGroup(rows: [
                    .minutes("Window", bind(\.window), [10, 20, 30, 45], "min"),
                    .minutes("Time to get ready", bind(\.readyMinutes), [15, 30, 45, 60, 90], "min"),
                ])
                ToolEyebrow("The evening before")
                ToolSettingsGroup(rows: [
                    .toggle("Bedtime reminder", bind(\.bedtimeReminder)),
                    .minutes("Remind me", bind(\.remindBefore), [15, 30, 45, 60], "min before"),
                ])
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
