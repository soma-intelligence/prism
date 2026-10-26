//
//  MindAssessmentSheet.swift
//  Prism
//

import SwiftUI
import SomaUI

/// A questionnaire, one item a screen: the question every item answers, the
/// item, and its answers as full width pills. A tap answers and moves on.
///
/// Every answer is kept as it is given (`MindStore` drafts), so a sheet
/// closed half way opens again on the item it stopped at, and nothing is
/// scored until the last item is answered. PHQ-9 item 9 answered above "Not
/// at all" opens the support lines (`MindCrisisSheet`) before any score is
/// shown; the results wait under it until it is closed.
struct MindAssessmentSheet: View {
    /// Answered in this order, each saved as its own questionnaire.
    let instruments: [MindInstrument]
    var onFinish: () -> Void = {}

    @Environment(\.somaTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var position = 0
    @State private var current: MindAssessment?
    @State private var finished: [MindAssessment] = []
    @State private var showsResults = false
    @State private var showsCrisis = false

    var body: some View {
        MindSheetFrame(title: showsResults ? "Your answers" : "Questionnaire", closeTitle: showsResults ? "Close" : "Cancel") {
            if showsResults {
                results
            } else if let current, let item = current.nextItem {
                question(current, item: item)
            }
        } footer: {
            if showsResults {
                MindWideButton(title: "Done") { close() }
            } else {
                // Back steps within the questionnaire under way: one already
                // finished is kept as answered.
                MindQuietButton(title: "Back") { back() }
                    .opacity(current?.answers.isEmpty ?? true ? 0 : 1)
                    .disabled(current?.answers.isEmpty ?? true)
            }
        }
        .onAppear { if current == nil { start(at: 0) } }
        .sheet(isPresented: $showsCrisis, onDismiss: advance) {
            MindCrisisSheet(distress: .indirect)
        }
    }

    // MARK: Screens

    private func question(_ assessment: MindAssessment, item: Int) -> some View {
        let type = theme.typography
        let colors = theme.colors
        let instrument = assessment.instrument

        return VStack(alignment: .leading, spacing: theme.metrics.leadSpacing) {
            VStack(alignment: .leading, spacing: theme.metrics.cardHeaderSpacing) {
                Text("\(instrument.title), \(item + 1) of \(instrument.items.count)")
                    .somaFont(type.captionValue)
                    .foregroundStyle(colors.inkSecondary.color)
                Text(instrument.stem)
                    .somaFont(type.caption)
                    .foregroundStyle(colors.inkSecondary.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(instrument.items[item])
                .somaFont(type.title)
                .foregroundStyle(colors.inkPrimary.color)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: theme.metrics.cardSpacing) {
                ForEach(Array(instrument.options.enumerated()), id: \.offset) { index, option in
                    MindAnswerPill(title: option) { answer(index) }
                }
            }
        }
        .padding(.top, theme.metrics.cardSpacing)
        .id("\(instrument.rawValue).\(item)")
    }

    private var results: some View {
        VStack(alignment: .leading, spacing: theme.metrics.cardSpacing) {
            ForEach(finished) { assessment in
                MindAssessmentResultCard(assessment: assessment)
            }
            if finished.contains(where: \.needsCrisisCare) {
                MindSupportLinesButton()
            }
            MindAssessmentFootnote()
        }
        .padding(.top, theme.metrics.cardSpacing)
    }

    // MARK: Flow

    private func start(at index: Int) {
        position = index
        let instrument = instruments[index]
        current = MindStore.shared.draft(instrument) ?? MindAssessment(instrument: instrument, date: Date(), answers: [])
    }

    private func answer(_ option: Int) {
        guard var assessment = current else { return }
        assessment.answers.append(option)
        assessment.date = Date()
        current = assessment
        MindStore.shared.save(assessment)
        guard assessment.isComplete else { return }
        finished.append(assessment)
        if assessment.needsCrisisCare {
            // The support lines first; `advance` runs when they close.
            showsCrisis = true
        } else {
            advance()
        }
    }

    private func advance() {
        if position + 1 < instruments.count {
            start(at: position + 1)
        } else {
            showsResults = true
        }
    }

    private func back() {
        guard var assessment = current, !assessment.answers.isEmpty else { return }
        assessment.answers.removeLast()
        current = assessment
        MindStore.shared.save(assessment)
    }

    private func close() {
        onFinish()
        dismiss()
    }
}

/// One answer, a full width pill that answers on tap.
struct MindAnswerPill: View {
    let title: String
    let action: () -> Void

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let colors = theme.colors
        Button(action: action) {
            Text(title)
                .somaFont(theme.typography.body)
                .foregroundStyle(colors.inkPrimary.color)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, minHeight: theme.metrics.minimumTapTarget + theme.metrics.spaceS, alignment: .leading)
                .padding(.horizontal, theme.metrics.cardPadding)
                .background(Capsule().fill(colors.surface.color))
                .contentShape(.capsule)
        }
        .buttonStyle(SomaGlassPressStyle())
    }
}

/// A finished questionnaire: the total with its scale and its band in a
/// word, and the sentence that goes with the band. The score never stands
/// alone.
struct MindAssessmentResultCard: View {
    let assessment: MindAssessment

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let type = theme.typography
        let colors = theme.colors
        let reading = assessment.reading
        let instrument = assessment.instrument
        let title = instrument == .phq9 || instrument == .gad7
            ? "\(instrument.title), \(instrument.subject.localizedLowercase)"
            : instrument.title

        SomaCard {
            VStack(alignment: .leading, spacing: theme.metrics.spaceS) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .somaFont(type.cardTitle)
                        .foregroundStyle(colors.inkPrimary.color)
                    Spacer(minLength: theme.metrics.spaceS)
                    Text(MindAssessmentFormat.day(assessment.date))
                        .somaFont(type.caption)
                        .foregroundStyle(colors.inkSecondary.color)
                }
                HStack(alignment: .firstTextBaseline, spacing: theme.metrics.spaceS) {
                    Text(reading?.value ?? "-")
                        .somaFont(type.metric)
                        .foregroundStyle(colors.inkPrimary.color)
                    if let reading {
                        Text(reading.unit)
                            .somaFont(type.callout)
                            .foregroundStyle(colors.inkSecondary.color)
                        Text(reading.word)
                            .somaFont(type.callout)
                            .foregroundStyle(colors.inkPrimary.color)
                    }
                }
                .accessibilityElement(children: .combine)
                if let reading {
                    Text(reading.detail)
                        .somaFont(type.body)
                        .foregroundStyle(colors.inkSecondary.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// The way back to the support lines, after they were shown once.
struct MindSupportLinesButton: View {
    @State private var isOpen = false

    var body: some View {
        MindWideButton(title: "Support lines", isPrimary: false) { isOpen = true }
            .sheet(isPresented: $isOpen) { MindCrisisSheet(distress: .indirect) }
    }
}

/// What the questionnaires are and are not, and whose they are.
struct MindAssessmentFootnote: View {
    @Environment(\.somaTheme) private var theme

    var body: some View {
        Text("These are screening questionnaires, not a diagnosis. If something here worries you, talk it over with a doctor. Your answers stay on this phone.")
            .somaFont(theme.typography.caption)
            .foregroundStyle(theme.colors.inkSecondary.color)
            .fixedSize(horizontal: false, vertical: true)
    }
}

enum MindAssessmentFormat {
    /// 12 Oct, or 12 Oct 2025 outside this year.
    static func day(_ date: Date, calendar: Calendar = .current) -> String {
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: Date())
        return sameYear
            ? date.formatted(.dateTime.day().month(.abbreviated))
            : date.formatted(.dateTime.day().month(.abbreviated).year())
    }
}

#if DEBUG
#Preview("Questionnaire") {
    MindAssessmentSheet(instruments: [.phq9, .gad7])
        .somaTheme(.standard)
}
#endif
