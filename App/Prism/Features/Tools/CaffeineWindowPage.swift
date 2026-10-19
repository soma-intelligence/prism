//
//  CaffeineWindowPage.swift
//  Prism
//

import SwiftUI
import SomaUI
import HealthExportCore

/// Caffeine Window: when the last cup can still leave bedtime under 25 mg,
/// what is on board now, and what each cup of the day leaves at bedtime.
///
/// A two layer caffeine model: first-order elimination with a five hour
/// half-life, and the last call solved against the headroom the day's real
/// doses left, not against one typical cup. Doses come from Apple Health's
/// dietary caffeine and from the drinks logged in ``TrackLogStore`` (here, on
/// Pulse or in Track), a cup Soma also wrote to Health counted once.
struct CaffeineWindowPage: View {
    @Environment(HealthDashboard.self) private var health
    @Environment(\.somaTheme) private var theme
    @State private var logging = false

    private var model: ToolsModel { .shared }
    private var store: ToolsStore { .shared }

    var body: some View {
        let day = ToolDay(inputs: model.current, cups: TrackLogStore.shared.caffeineCups, sleepNeedHours: health.scores?.sleepNeedHours)
        let reading = day.caffeine

        ToolPage(ToolKind.caffeineWindow.title) {
            if let reading {
                ToolHero(eyebrow: eyebrow(reading),
                         headline: headline(reading),
                         lead: lead(reading, day: day),
                         rest: "This plan keeps you under 25 mg at bedtime, so your first deep sleep is not cut short.")
                ToolStats([
                    SomaStat("On board", value: "\(Int(reading.onBoardNowMg.rounded()))", unit: "mg"),
                    SomaStat("At bedtime", value: "\(Int(reading.atBedtimeMg.rounded()))", unit: "mg",
                             trend: reading.atBedtimeMg > SomaTools.CaffeineModel.bedtimeThresholdMg ? .down : nil),
                    SomaStat("Today", value: "\(Int(todayTotal(day).rounded()))", unit: "mg"),
                ])
                curveCard(reading, day: day)
                cupsCard(reading, day: day)
            } else {
                ToolHero(eyebrow: "No bedtime yet",
                         headline: "The window needs your bedtime.",
                         lead: "It is read from your recent nights in Apple Health, and none are recorded yet.",
                         rest: "Cups you log still count once it can.")
                ToolStats([
                    SomaStat("On board", value: nil, unit: "mg"),
                    SomaStat("At bedtime", value: nil, unit: "mg"),
                    SomaStat("Today", value: day.doses.isEmpty ? nil : "\(Int(todayTotal(day).rounded()))", unit: "mg"),
                ])
            }

            ToolFootnote(habitLine(day))
            ToolLinkRow(title: "How the window is set", detail: nil, value: ToolRoute.intro(.caffeineWindow))
            ToolNextCard(eyebrow: "Log", aspect: .gut, title: "Log a cup", detail: "The window follows what you really drink.",
                         actionTitle: "Log", action: { logging = true })
        }
        .sheet(isPresented: $logging) { CaffeineLogSheet() }
        .task {
            store.markOpened(.caffeineWindow)
            await model.load(health)
        }
    }

    // MARK: - Pieces

    private func curveCard(_ reading: SomaTools.CaffeineWindowEngine.Reading, day: ToolDay) -> some View {
        let start = day.calendar.date(bySettingHour: 6, minute: 0, second: 0, of: day.inputs.now) ?? day.inputs.now
        let end = max(reading.bedtime, start.addingTimeInterval(18 * 3600))
        let curve = SomaTools.CaffeineWindowEngine.curve(doses: day.doses, from: start, to: end)
        let top = max(150, ((curve.max() ?? 0) / 50).rounded(.up) * 50)
        let nowFraction = day.inputs.now.timeIntervalSince(start) / end.timeIntervalSince(start)
        return SomaChartCard(eyebrow: "Caffeine on board", value: "\(Int(reading.onBoardNowMg.rounded()))", unit: "mg now",
                             note: "Each cup halves about every five hours. The flat line is the 25 mg this plan aims for at bedtime.") {
            ToolCurveChart(aspect: .gut, values: curve.map { Optional($0) }, top: top,
                           threshold: SomaTools.CaffeineModel.bedtimeThresholdMg, now: nowFraction,
                           xLabels: axisLabels(start: start, end: end),
                           yLabels: ["\(Int(top))", "\(Int(top / 2))", "0"])
        }
    }

    private func cupsCard(_ reading: SomaTools.CaffeineWindowEngine.Reading, day: ToolDay) -> some View {
        let today = day.doses.filter { day.calendar.isDate($0.time, inSameDayAs: day.inputs.now) }
        let threshold = SomaTools.CaffeineModel.bedtimeThresholdMg
        var rows: [ToolRow] = today.map { dose in
            let left = SomaTools.CaffeineModel.residual(doses: [dose], at: reading.bedtime)
            let late = reading.lastCall.map { dose.time > $0 } ?? false
            return ToolRow(title: "Cup, \(ToolFormat.clock(dose.time))",
                           detail: "\(Int(dose.mg.rounded())) mg when you drank it",
                           value: "\(Int(left.rounded())) mg", tone: late ? .danger : .plain)
        }
        if today.count > 1 {
            rows.append(ToolRow(title: "Together", detail: "aim under \(Int(threshold)) mg",
                                value: "\(Int(reading.atBedtimeMg.rounded())) mg",
                                tone: reading.atBedtimeMg > threshold ? .danger : .plain,
                                band: ToolBand(range: 0...(threshold * 3), usual: 0...threshold, value: reading.atBedtimeMg)))
        }
        return Group {
            if rows.isEmpty {
                ToolNoteCard(title: "What each cup leaves at \(ToolFormat.clock(reading.bedtime))", lead: "No caffeine logged today.",
                             rest: "Coffee, tea and energy drinks logged in Apple Health or here show up with what each leaves at bedtime.")
            } else {
                ToolRowsCard(title: "What each cup leaves at \(ToolFormat.clock(reading.bedtime))", aspect: .gut, rows: rows)
            }
        }
    }

    // MARK: - Words

    private func eyebrow(_ reading: SomaTools.CaffeineWindowEngine.Reading) -> String {
        guard let lastCall = reading.lastCall else { return "Closed for today" }
        return reading.lastCallHasPassed ? "Closed since \(ToolFormat.clock(lastCall))" : "Open until \(ToolFormat.clock(lastCall))"
    }

    private func headline(_ reading: SomaTools.CaffeineWindowEngine.Reading) -> String {
        guard let lastCall = reading.lastCall else { return "No more caffeine today." }
        return reading.lastCallHasPassed
            ? "Your caffeine window closed at \(ToolFormat.clock(lastCall))."
            : "Your last cup is by \(ToolFormat.clock(lastCall))."
    }

    private func lead(_ reading: SomaTools.CaffeineWindowEngine.Reading, day: ToolDay) -> String {
        guard reading.doseCount > 0 else {
            return "Nothing logged today; a \(Int(reading.nextDoseMg.rounded())) mg cup fits until then."
        }
        return "What you drank will still be about \(Int(reading.atBedtimeMg.rounded())) mg at your \(ToolFormat.clock(reading.bedtime)) bedtime."
    }

    private func todayTotal(_ day: ToolDay) -> Double {
        day.doses.filter { day.calendar.isDate($0.time, inSameDayAs: day.inputs.now) }.reduce(0) { $0 + $1.mg }
    }

    private func habitLine(_ day: ToolDay) -> String {
        let all = ToolDay.merged(health: day.inputs.caffeine.map { SomaTools.CaffeineModel.Dose(mg: $0.value, time: $0.start) },
                                 logged: TrackLogStore.shared.caffeineCups)
        let byDay = SomaTools.CaffeineDayBuckets.byDay(all, days: 30, endingOn: day.inputs.now, calendar: day.calendar)
        let logged = byDay.filter { !$0.isEmpty }
        guard !logged.isEmpty else { return "Last 30 days: nothing logged. A day without a log is left empty, not counted as zero." }
        let mean = logged.map { $0.reduce(0) { $0 + $1.mg } }.reduce(0, +) / Double(logged.count)
        return "Last 30 days: \(Int(mean.rounded())) mg a day on average, across \(logged.count) logged days. A day without a log is left empty, not counted as zero."
    }

    private func axisLabels(start: Date, end: Date) -> [String] {
        (0...4).map { step in
            ToolFormat.hourLabel(Double(Calendar.current.component(.hour, from: start.addingTimeInterval(end.timeIntervalSince(start) * Double(step) / 4))))
        }
    }
}

/// Logging a cup: what it was, and when.
struct CaffeineLogSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.somaTheme) private var theme
    @State private var kind = 0
    @State private var time = Date()

    /// Typical caffeine per serving, the drink it is logged as, and its volume.
    private static let kinds: [(name: String, mg: Double, drink: TrackDrink, ml: Double)] = [
        ("Coffee", 95, .coffee, 250), ("Espresso", 64, .coffee, 30), ("Tea", 47, .tea, 250),
        ("Cola", 34, .water, 330), ("Energy drink", 80, .water, 250),
    ]

    var body: some View {
        NavigationStack {
            ListScaffold(eyebrow: "Caffeine Window", title: "Log a cup") {
                ToolSettingsGroup(rows: Self.kinds.enumerated().map { index, item in
                    .choice("\(item.name), \(Int(item.mg)) mg", kind == index, { kind = index })
                })
                SomaCard {
                    DatePicker(selection: $time, in: ...Date(), displayedComponents: .hourAndMinute) {
                        Text("When")
                            .somaFont(theme.typography.body)
                            .foregroundStyle(theme.colors.inkPrimary.color)
                    }
                }
                ToolFootnote("Kept on this phone.")
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Log") {
                        let item = Self.kinds[kind]
                        let entry = TrackLogStore.shared.addDrink(item.drink, ml: item.ml, caffeineMg: item.mg, at: time)
                        Task { await TrackHealthWriter.saveDrink(entry) }
                        dismiss()
                    }
                }
            }
        }
    }
}
