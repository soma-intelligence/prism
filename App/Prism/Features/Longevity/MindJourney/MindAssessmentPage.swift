//
//  MindAssessmentPage.swift
//  Prism
//

import SwiftUI
import SomaUI

/// Questionnaires: PHQ-9 for mood and GAD-7 for anxiety. The latest of each
/// with its band and its sentence, every total since as a line across the
/// bands, the way to take them again, the two week reminder, and the
/// history.
///
/// Everything here is on the phone (`MindStore`); nothing is sent. A latest
/// PHQ-9 with item 9 above "Not at all" keeps the support lines at the top.
struct MindAssessmentPage: View {
    @Environment(\.somaTheme) private var theme

    @State private var notifications = SomaNotifications.shared
    @State private var isTaking = false

    private let instruments: [MindInstrument] = [.phq9, .gad7]

    var body: some View {
        @Bindable var notifications = notifications
        let store = MindStore.shared
        let latest = instruments.compactMap { store.latest($0) }
        let hasDraft = instruments.contains { store.draft($0) != nil }
        let history = store.assessments.filter { instruments.contains($0.instrument) }.reversed()

        MindPage(navigationTitle: "Questionnaires", title: "Mood and anxiety") {
            if store.latest(.phq9)?.needsCrisisCare == true {
                MindSupportLinesButton()
            }

            if latest.isEmpty {
                MindTextCard(
                    title: "No answers yet",
                    text: "PHQ-9 and GAD-7 are the questionnaires doctors use for mood and anxiety. 16 questions, about two minutes."
                )
            }

            ForEach(instruments) { instrument in
                if let last = store.latest(instrument) {
                    MindAssessmentResultCard(assessment: last)
                    let scores = store.history(instrument)
                    if scores.count > 1 {
                        SomaCard {
                            VStack(alignment: .leading, spacing: theme.metrics.cardHeaderSpacing) {
                                SomaCardHeader("\(instrument.title) over time", caption: "Lines mark where each band begins")
                                MindScoreHistoryChart(assessments: scores)
                            }
                        }
                    }
                }
            }

            MindWideButton(title: hasDraft ? "Pick up where you left off" : (latest.isEmpty ? "Take a 2 minute check" : "Take them again")) {
                isTaking = true
            }

            MindReminderCard(
                title: "Every two weeks",
                detail: "A reminder at \(MindQuestionnaireReminders.morning.text), two weeks after the last time",
                isOn: $notifications.schedule.assessmentReminders
            )

            if !history.isEmpty {
                MindRowsCard(title: "History", rows: Array(history)) { assessment in
                    MindAssessmentRow(assessment: assessment)
                }
            }

            MindAssessmentFootnote()
            Text("PHQ-9 and GAD-7 were developed by Drs. Robert L. Spitzer, Janet B. W. Williams, Kurt Kroenke and colleagues, with an educational grant from Pfizer Inc.")
                .somaFont(theme.typography.caption)
                .foregroundStyle(theme.colors.inkSecondary.color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .sheet(isPresented: $isTaking, onDismiss: {
            Task { await MindQuestionnaireReminders.sync() }
        }) {
            MindEntryGate { MindAssessmentSheet(instruments: instruments) }
        }
        .onChange(of: notifications.schedule.assessmentReminders) { _, isOn in
            Task { await MindQuestionnaireReminders.sync(asking: isOn) }
        }
        .task { await MindQuestionnaireReminders.sync() }
    }
}

/// A reminder switch with its name and when it comes.
struct MindReminderCard: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool

    @Environment(\.somaTheme) private var theme

    var body: some View {
        SomaCard {
            HStack(spacing: theme.metrics.moveRowGap) {
                VStack(alignment: .leading, spacing: theme.metrics.spaceXS) {
                    Text(title)
                        .somaFont(theme.typography.body)
                        .foregroundStyle(theme.colors.inkPrimary.color)
                    Text(detail)
                        .somaFont(theme.typography.caption)
                        .foregroundStyle(theme.colors.inkSecondary.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: theme.metrics.spaceS)
                SettingsSwitch(title: title, isOn: $isOn)
            }
        }
    }
}

/// One questionnaire in the history: its name and day, and the total with
/// its band.
struct MindAssessmentRow: View {
    let assessment: MindAssessment

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let type = theme.typography
        let colors = theme.colors

        HStack(alignment: .center, spacing: theme.metrics.moveRowGap) {
            VStack(alignment: .leading, spacing: theme.metrics.spaceXS) {
                Text(assessment.instrument.title)
                    .somaFont(type.body)
                    .foregroundStyle(colors.inkPrimary.color)
                Text(MindAssessmentFormat.day(assessment.date))
                    .somaFont(type.caption)
                    .foregroundStyle(colors.inkSecondary.color)
            }
            Spacer(minLength: theme.metrics.spaceS)
            SomaNumber(assessment.reading.map { "\($0.value) \($0.unit), \($0.word.localizedLowercase)" }, type.rowValue)
                .foregroundStyle(colors.inkPrimary.color)
        }
        .padding(.vertical, theme.metrics.browseRowVerticalPadding)
        .accessibilityElement(children: .combine)
    }
}

/// Every total of one questionnaire, oldest on the left, on the
/// questionnaire's whole scale, with a dashed rule where each band begins.
struct MindScoreHistoryChart: View {
    let assessments: [MindAssessment]

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let hue = theme.aspects[.mind].identity.color
        let points = assessments.compactMap { assessment in assessment.score.map { (assessment.date, Double($0)) } }
        let instrument = assessments.first?.instrument ?? .phq9
        let cuts = instrument.cutPoints.map(Double.init)
        let labels = points.indices.map { index in
            index == 0 || index == points.count - 1 ? MindAssessmentFormat.day(points[index].0) : ""
        }

        SomaPlot(scale: SomaPlotScale(domain: Double(instrument.minScore)...Double(instrument.maxScore), ticks: [Double(instrument.minScore)] + cuts),
                 xLabels: labels,
                 height: theme.metrics.chartCompactPlotHeight) { context, space, pen in
            for cut in cuts {
                pen.rule(context, y: space.y(cut), in: space.plot)
            }
            let line = points.indices.map { CGPoint(x: space.x($0, of: points.count), y: space.y(points[$0].1)) }
            pen.line(context, line, color: hue)
            for (index, point) in line.enumerated() {
                if index == line.count - 1 {
                    pen.ring(context, at: point, color: hue)
                } else {
                    pen.dot(context, at: point, color: hue, filled: true)
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("\(instrument.title) totals, \(points.count) times")
    }
}

#if DEBUG
#Preview("Questionnaires") {
    NavigationStack { MindAssessmentPage() }
        .somaTheme(.standard)
}
#endif
