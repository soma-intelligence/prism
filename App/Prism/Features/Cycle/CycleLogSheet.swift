//
//  CycleLogSheet.swift
//  Prism
//

import SwiftUI
import SomaUI
import HealthExportCore

/// The cycle log: today's or yesterday's flow, whether it opens a period,
/// the symptoms of the day as yes or no chips, and a note. Flow and
/// symptoms go to Apple Health, the note stays on the phone.
///
/// Opened from the cycle page and from Track's Period tile. Opening it asks
/// Health for the cycle types, as the cycle page does: they are sensitive,
/// so the launch sheet never named them.
struct CycleLogSheet: View {
    @Environment(HealthDashboard.self) private var health
    @Environment(\.somaTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    /// Today, or yesterday.
    @State private var isYesterday = false
    @State private var flow: CycleFlow?
    /// Nil until the flow days are read: then the default (a first day when
    /// no flow came in the ten days before).
    @State private var startsPeriod: Bool?
    @State private var symptoms: Set<CycleSymptom> = []
    @State private var note = ""
    @State private var recentFlow: [Date] = []
    @State private var problem: String?
    @State private var isSaving = false

    private let calendar = Calendar.current
    private var store: CycleStore { .shared }

    private var day: Date {
        let today = calendar.startOfDay(for: .now)
        return isYesterday ? (calendar.date(byAdding: .day, value: -1, to: today) ?? today) : today
    }

    var body: some View {
        let metrics = theme.metrics
        let type = theme.typography
        let colors = theme.colors

        TrackEntryPage(title: "Cycle") {
            HStack(spacing: metrics.spaceS) {
                SomaChoiceChip("Today", isOn: !isYesterday) { isYesterday = false }
                SomaChoiceChip("Yesterday", isOn: isYesterday) { isYesterday = true }
            }

            SomaCard {
                VStack(alignment: .leading, spacing: metrics.spaceM) {
                    TrackEyebrow("Flow")
                    HStack(spacing: metrics.spaceS) {
                        ForEach(CycleFlow.allCases) { level in
                            SomaChoiceChip(level.title, isOn: flow == level) {
                                flow = flow == level ? nil : level
                            }
                        }
                    }
                    if flow != nil {
                        TrackHairline()
                        Text("First day of your period?")
                            .somaFont(type.body)
                            .foregroundStyle(colors.inkPrimary.color)
                        HStack(spacing: metrics.spaceS) {
                            SomaChoiceChip("Yes", isOn: isFirstDay) { startsPeriod = true }
                            SomaChoiceChip("No", isOn: !isFirstDay) { startsPeriod = false }
                        }
                    }
                }
            }

            SomaCard {
                VStack(alignment: .leading, spacing: metrics.spaceM) {
                    TrackEyebrow("Symptoms")
                    TrackFlowLayout(spacing: metrics.spaceS) {
                        ForEach(CycleSymptom.allCases) { symptom in
                            SomaTopicChip(symptom.title, tone: .rose, isOn: symptoms.contains(symptom)) {
                                if symptoms.contains(symptom) { symptoms.remove(symptom) } else { symptoms.insert(symptom) }
                            }
                        }
                    }
                }
            }

            HomeTextField(title: "Note", text: $note, prompt: "A note for the day, kept on this iPhone")

            TrackNote(lead: problem ?? "Flow and symptoms go to Apple Health, where Cycle Tracking reads them too. The note stays on this iPhone.")
        } footer: {
            SomaActionButton(isSaving ? "Saving" : "Save") {
                Task { await save() }
            }
            .disabled(isSaving || (flow == nil && symptoms.isEmpty && note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
        }
        .task { await prepare() }
        .onChange(of: isYesterday) { note = store.note(on: day, calendar: calendar) ?? "" }
    }

    private var isFirstDay: Bool {
        startsPeriod ?? Self.opensPeriod(day: day, recentFlow: recentFlow, calendar: calendar)
    }

    /// A day of flow opens a period when no flow came in the days before it
    /// that would still count as the same period (`HomeCycle.gapDays`).
    static func opensPeriod(day: Date, recentFlow: [Date], calendar: Calendar) -> Bool {
        let start = calendar.startOfDay(for: day)
        return !recentFlow.contains { flowDay in
            let gap = calendar.dateComponents([.day], from: calendar.startOfDay(for: flowDay), to: start).day ?? Int.max
            return gap > 0 && gap < HomeCycle.gapDays
        }
    }

    private func prepare() async {
        note = store.note(on: day, calendar: calendar) ?? ""
        #if DEBUG && targetEnvironment(simulator)
        if FixtureCycle.isOn {
            recentFlow = FixtureCycle.flowDays()
            return
        }
        #endif
        let wanted = [HomeMetric.menstrualFlow] + CycleSymptom.allCases.map(\.identifier)
        guard let source = await health.prepare(wanted) else { return }
        recentFlow = await source.home(HomeMetric.menstrualFlow, days: HomeCycle.gapDays + 1, now: .now, calendar: calendar)
            .filter { $0.code != 5 }
            .map(\.start)
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let log = CycleLog(writer: HealthKitCycleWriter(), isAsked: { [health] in health.hasAsked(HomeMetric.menstrualFlow) })
        var outcomes: [CycleLog.Outcome] = []
        if let flow {
            outcomes.append(await log.write(flow: flow, on: day, startsPeriod: isFirstDay, calendar: calendar))
            store.markFlowSeen(day)
        }
        for symptom in CycleSymptom.allCases where symptoms.contains(symptom) {
            outcomes.append(await log.write(symptom: symptom, on: day, calendar: calendar))
        }
        store.setNote(note, on: day, calendar: calendar)

        if let failure = outcomes.first(where: { $0 != .saved }) {
            switch failure {
            case .notAsked: problem = "Allow Soma to write cycle tracking in Apple Health, then save again. The note is kept."
            case .notWritten: problem = "Apple Health is not on this device, so only the note was kept."
            case .failed(let message): problem = "Not saved to Apple Health. \(message)"
            case .saved: break
            }
            return
        }
        dismiss()
    }
}

#if DEBUG
#Preview("Cycle log") {
    NavigationStack { CycleLogSheet() }
        .environment(HealthDashboard())
}
#endif
