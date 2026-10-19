//
//  EveningClosePage.swift
//  Prism
//

import SwiftUI
import SomaUI

/// Evening Close: a closing time for work, two hours before the sleep window,
/// and a record of the evenings it was kept.
///
/// Closing apps and sites needs the Screen Time (FamilyControls) entitlement,
/// which this build does not have, so this keeps the part that needs none:
/// the closing time placed from your sleep, a note when it comes if you want
/// one, and the evenings counted. The page says plainly that nothing is
/// blocked.
struct EveningClosePage: View {
    @Environment(HealthDashboard.self) private var health
    @Environment(\.somaTheme) private var theme
    @State private var settings = false
    @State private var reminded = false

    private var model: ToolsModel { .shared }
    private var store: ToolsStore { .shared }

    var body: some View {
        let prefs = store.record.evening
        let day = ToolDay(inputs: model.current, cups: TrackLogStore.shared.caffeineCups, sleepNeedHours: health.scores?.sleepNeedHours)
        let reading = EveningCloseReading(prefs: prefs, day: day, calendar: .current)

        ToolPage(ToolKind.eveningClose.title) {
            ToolHero(eyebrow: reading.isClosed ? "Closed · opens at \(reading.opensLabel)" : "Open · closes at \(reading.closesLabel)",
                     headline: reading.isClosed ? "Work is closed until \(reading.opensLabel)." : "Work closes at \(reading.closesLabel).",
                     lead: "The evening starts when work stops.",
                     rest: stressLine)

            SomaChartCard(eyebrow: "Tonight",
                          value: reading.isClosed ? ToolFormat.span(hours: reading.hoursUntilOpen) : ToolFormat.span(hours: reading.hoursUntilClose),
                          unit: reading.isClosed ? "until it opens" : "until it closes",
                          note: reading.coverNote) {
                ToolSpanRows(aspect: .mind, rows: reading.rows, axis: 18...32, ticks: [18, 21, 24, 27, 30])
            }

            ToolRowsCard(aspect: .mind, rows: [
                ToolRow(title: "Closed on time", detail: "Last 7 evenings", value: reading.onTime.map { "\($0) of 7" }),
                ToolRow(title: "Opened early", detail: "Each exit is written down", value: "\(reading.openedEarly)"),
            ])

            ToolButtonRow(title: "Settings", detail: nil) { settings = true }

            ToolNextCard(eyebrow: reading.isClosed ? "Closed" : "Slow the evening down", aspect: .mind,
                         title: reading.isClosed ? "Closed for tonight" : "Close work now",
                         detail: reading.isClosed ? "It opens again at \(reading.opensLabel)." : "It opens again at \(reading.opensLabel).",
                         actionTitle: reading.isClosed ? "Open early" : "Close now",
                         action: { reading.isClosed ? openEarly() : closeNow(onTime: false) })
            ToolLinkRow(title: "About Evening Close", detail: nil, value: ToolRoute.intro(.eveningClose))
        }
        .sheet(isPresented: $settings) { EveningCloseSettingsSheet() }
        .task {
            store.markOpened(.eveningClose)
            await model.load(health)
            if prefs.noteWhenCloses, prefs.closesByItself, !reminded {
                reminded = await ToolNotifier.remind(id: "evening-close", title: "Work closes now",
                                                     body: "The evening starts here. It opens again at \(reading.opensLabel).",
                                                     at: reading.nextClose)
            }
        }
    }

    private var stressLine: String? {
        guard let stress = health.scores?.stress else { return "Closing early is always allowed." }
        return stress >= 60 ? "Today ran hot, so closing early is a good idea." : "Closing early is always allowed."
    }

    private func closeNow(onTime: Bool) {
        let today = Calendar.current.startOfDay(for: Date())
        store.update { record in
            record.evening.evenings.removeAll { $0.day == today }
            record.evening.evenings.append(EveningEntry(day: today, closedOnTime: true, openedEarly: false))
        }
    }

    private func openEarly() {
        let today = Calendar.current.startOfDay(for: Date())
        store.update { record in
            if let index = record.evening.evenings.firstIndex(where: { $0.day == today }) {
                record.evening.evenings[index].openedEarly = true
            } else {
                record.evening.evenings.append(EveningEntry(day: today, closedOnTime: true, openedEarly: true))
            }
        }
    }
}

/// What the Evening Close page shows, worked out from the settings and the day.
struct EveningCloseReading {
    let closes: Double
    let opens: Double
    let now: Date
    let nextClose: Date
    let isClosed: Bool
    let hoursUntilClose: Double
    let hoursUntilOpen: Double
    let sleepStart: Double?
    let sleepEnd: Double?
    let onTime: Int?
    let openedEarly: Int

    init(prefs: EveningPrefs, day: ToolDay, calendar: Calendar) {
        let now = day.inputs.now
        let closes = Double(prefs.closes) / 60
        let opens = Double(prefs.opens) / 60
        self.now = now
        self.closes = closes
        self.opens = opens
        let nowHour = day.nowHour
        let closedSpan = (opens - closes + 24).truncatingRemainder(dividingBy: 24)
        let sinceClose = (nowHour - closes + 24).truncatingRemainder(dividingBy: 24)
        let closedToday = prefs.evenings.contains { $0.day == calendar.startOfDay(for: now) && !$0.openedEarly }
        isClosed = (prefs.closesByItself && sinceClose < closedSpan) || (closedToday && sinceClose < closedSpan)
        hoursUntilClose = (closes - nowHour + 24).truncatingRemainder(dividingBy: 24)
        hoursUntilOpen = (opens - nowHour + 24).truncatingRemainder(dividingBy: 24)
        nextClose = SomaTools.CaffeineWindowEngine.nextOccurrence(ofHour: closes, after: now, calendar: calendar)
        sleepStart = day.habitualSleepHour
        sleepEnd = day.habitualWakeHour
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: calendar.startOfDay(for: now)) ?? now
        let week = prefs.evenings.filter { $0.day > weekAgo }
        onTime = week.isEmpty ? nil : week.filter { $0.closedOnTime && !$0.openedEarly }.count
        openedEarly = week.filter(\.openedEarly).count
    }

    var closesLabel: String { ToolFormat.clock(hour: closes) }
    var opensLabel: String { ToolFormat.clock(hour: opens) }

    var coverNote: String {
        let span = (opens - closes + 24).truncatingRemainder(dividingBy: 24)
        var note = "Closed from \(closesLabel) to \(opensLabel), \(ToolFormat.span(hours: span)) in all."
        if let sleepStart {
            let lead = (sleepStart - closes + 24).truncatingRemainder(dividingBy: 24)
            note += " It covers the \(ToolFormat.span(hours: lead)) before your sleep window."
        }
        return note
    }

    var rows: [ToolSpanRows.Row] {
        func axis(_ hour: Double) -> Double { hour < 12 ? hour + 24 : hour }
        var rows = [ToolSpanRows.Row(label: "Closed", start: axis(closes), end: axis(opens))]
        if let sleepStart, let sleepEnd {
            rows.append(ToolSpanRows.Row(label: "Sleep", start: axis(sleepStart), end: axis(sleepEnd), strength: 0.5))
        }
        return rows
    }
}

/// Evening Close's settings sheet.
struct EveningCloseSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.somaTheme) private var theme

    private var store: ToolsStore { .shared }

    var body: some View {
        let prefs = store.record.evening
        NavigationStack {
            ListScaffold(eyebrow: "Evening Close", title: "Settings") {
                ToolEyebrow("Every evening")
                ToolSettingsGroup(rows: [
                    .toggle("Close by itself", Binding(get: { prefs.closesByItself }, set: { v in store.update { $0.evening.closesByItself = v } })),
                    .time("Closes", Binding(get: { prefs.closes }, set: { v in store.update { $0.evening.closes = v } })),
                    .time("Opens", Binding(get: { prefs.opens }, set: { v in store.update { $0.evening.opens = v } })),
                    .toggle("A note when it closes", Binding(get: { prefs.noteWhenCloses }, set: { v in store.update { $0.evening.noteWhenCloses = v } })),
                ])
                ToolEyebrow("Getting out")
                ToolSettingsGroup(rows: [
                    .value("Early exits", "Written down"),
                    .value("History", "\(prefs.evenings.count) evenings"),
                ])
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
