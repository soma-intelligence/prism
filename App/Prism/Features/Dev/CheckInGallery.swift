//
//  CheckInGallery.swift
//  Prism
//

import SwiftUI
import SomaUI
import SomaUIPreviewSupport

/// The "Soma asks" pieces in the component gallery: the progress, the stack
/// and each kind of answer, fed from the shared question fixtures. Tapping an
/// answer moves the stack on, so the motion can be judged here too.
struct CheckInGallery: View {
    @Environment(\.somaTheme) private var theme
    @State private var index = 0
    @State private var count = 7
    @State private var yes: Bool?
    @State private var step: Int?

    private var questions: [SomaPreviewSamples.Question] { SomaPreviewSamples.questions }

    var body: some View {
        VStack(spacing: 12) {
            Text("Soma asks: SomaStepProgress, SomaQuestionStack, SomaQuestionPrompt, SomaYesNoPills, SomaScaleOrbs, SomaCountStepper, SomaQuietButton")
                .somaFont(theme.typography.eyebrow)
                .textCase(.uppercase)
                .foregroundStyle(theme.colors.inkSecondary.color)
                .frame(maxWidth: .infinity, alignment: .leading)

            SomaStepProgress(
                count: questions.count, current: index,
                label: SomaPreviewSamples.questionProgress(index, of: questions.count)
            )
            SomaQuestionStack(index: index) {
                if questions.indices.contains(index) {
                    card(questions[index])
                } else {
                    SomaQuestionPrompt(SomaPreviewSamples.questionDone) {
                        SomaActionButton(SomaPreviewSamples.questionClose) { index = 0 }
                    }
                }
            }
            .frame(minHeight: theme.metrics.questionSheetHeight * 0.55)
            HStack(spacing: 0) {
                SomaQuietButton(SomaPreviewSamples.questionSkip) { advance() }
                SomaQuietButton(SomaPreviewSamples.questionLater) { index = 0 }
            }
        }
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private func card(_ question: SomaPreviewSamples.Question) -> some View {
        switch question.kind {
        case .yesNo:
            SomaQuestionPrompt(question.text) {
                SomaYesNoPills(yes: SomaPreviewSamples.questionYes, no: SomaPreviewSamples.questionNo, aspect: question.aspect, chosen: yes) {
                    yes = $0
                    advance()
                }
            }
        case .scale(let low, let high, let tone):
            SomaQuestionPrompt(question.text) {
                SomaScaleOrbs(chosen: step, low: low, high: high, tone: tone) {
                    step = $0
                    advance()
                }
            }
        case .count(let range, _, let unit):
            SomaQuestionPrompt(question.text) {
                VStack(spacing: theme.metrics.cardSpacing) {
                    SomaCountStepper(value: $count, in: range, unit: unit, decrementLabel: SomaPreviewSamples.questionLess, incrementLabel: SomaPreviewSamples.questionMore)
                    SomaActionButton(SomaPreviewSamples.questionNext) { advance() }
                }
            }
        }
    }

    private func advance() {
        index += 1
        yes = nil
        step = nil
    }
}

#Preview("Soma asks") {
    ScrollView {
        CheckInGallery()
            .padding(.vertical)
    }
    .background(SomaPreviewSamples.backdrop())
}
