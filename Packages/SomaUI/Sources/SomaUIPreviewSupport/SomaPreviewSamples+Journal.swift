//
//  SomaPreviewSamples+Journal.swift
//  SomaUIPreviewSupport
//

import SwiftUI
import SomaUI

/// A journal day for the gallery and the previews: the quick add tiles, a
/// few habits with every kind of trailing mark, and a chosen feeling.
public extension SomaPreviewSamples {
    struct JournalTile: Identifiable, Sendable {
        public let id: String
        public let glyph: SomaTrackGlyph.Kind
        public let tone: SomaTrackTone
    }

    struct JournalHabit: Identifiable, Sendable {
        public let id: String
        public let glyph: SomaTrackGlyph.Kind
        public let tone: SomaTrackTone
        public let detail: String?
        public let mark: SomaHabitMark.State
    }

    static let journalTiles: [JournalTile] = [
        JournalTile(id: "Drink", glyph: .drink, tone: .tide),
        JournalTile(id: "Meal", glyph: .meal, tone: .sage),
        JournalTile(id: "Fast", glyph: .fast, tone: .sand),
        JournalTile(id: "Weight", glyph: .weight, tone: .stone),
        JournalTile(id: "Mood", glyph: .mood, tone: .rose),
        JournalTile(id: "Breathe", glyph: .breathe, tone: .sage),
        JournalTile(id: "Sauna", glyph: .sauna, tone: .clay),
        JournalTile(id: "Cold plunge", glyph: .cold, tone: .tide),
    ]

    static let journalHabits: [JournalHabit] = [
        JournalHabit(id: "Alcohol", glyph: .alcohol, tone: .dusk, detail: nil, mark: .on),
        JournalHabit(id: "Late meal", glyph: .lateMeal, tone: .dusk, detail: nil, mark: .off),
        JournalHabit(id: "8,000 steps", glyph: .steps, tone: .moss, detail: "5,412", mark: .progress(0.68)),
        JournalHabit(id: "7 h of sleep", glyph: .sleep, tone: .dusk, detail: "7 h 24", mark: .met),
        JournalHabit(id: "Daylight", glyph: .daylight, tone: .sand, detail: nil, mark: .missing),
    ]

    struct JournalQuestion: Identifiable, Sendable {
        public let id: String
        public let glyph: SomaTrackGlyph.Kind
        public let tone: SomaTrackTone
        public let answer: Bool?
    }

    /// An evening's yes or no questions: one yes, one no, one unanswered.
    static let journalQuestions: [JournalQuestion] = [
        JournalQuestion(id: "Alcohol", glyph: .alcohol, tone: .dusk, answer: true),
        JournalQuestion(id: "Late meal", glyph: .lateMeal, tone: .dusk, answer: false),
        JournalQuestion(id: "Screens in bed", glyph: .screens, tone: .dusk, answer: nil),
    ]

    struct JournalQuantity: Identifiable, Sendable {
        public let id: String
        public let glyph: SomaTrackGlyph.Kind
        public let tone: SomaTrackTone
        public let value: String?
        public let unit: String
    }

    /// Two things a day counts rather than answers: one logged, one not.
    static let journalQuantities: [JournalQuantity] = [
        JournalQuantity(id: "Caffeine", glyph: .coffee, tone: .sand, value: "160", unit: "mg"),
        JournalQuantity(id: "Drinks", glyph: .drink, tone: .tide, value: nil, unit: "ml"),
    ]

    struct RitualStep: Identifiable, Sendable {
        public let id: String
        public let glyph: SomaTrackGlyph.Kind
        public let isDone: Bool
    }

    /// A morning ritual, two of its three steps done.
    static let ritualSteps: [RitualStep] = [
        RitualStep(id: "Daylight, 10 minutes", glyph: .daylight, isDone: true),
        RitualStep(id: "A glass of water", glyph: .drink, isDone: true),
        RitualStep(id: "Stretch", glyph: .stretch, isDone: false),
    ]

    /// Two weeks of a ritual, oldest first: the share of its steps done each
    /// day, today last.
    static let ritualDays: [Double?] = [nil, 1, 0.67, 0, 1, 0.33, 1, 1, 1, 0.67, 1, 1, 1, 0.67]

    /// The share of the sample day that is logged, and its count.
    static let journalProgress = (fraction: 0.6, count: 6)
}

#Preview("Journal parts") {
    @Previewable @State var feeling: Int? = 5
    let theme = SomaTheme.standard

    ScrollView {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Text("6 entries").somaFont(theme.typography.title)
                Spacer()
                SomaProgressRing(fraction: SomaPreviewSamples.journalProgress.fraction) {
                    Text("\(SomaPreviewSamples.journalProgress.count)")
                        .somaFont(theme.typography.rowValue)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4)) {
                ForEach(SomaPreviewSamples.journalTiles) { tile in
                    SomaGlyphTile(tile.id, glyph: tile.glyph, tone: tile.tone) {}
                }
            }
            SomaBrowseGroup(SomaPreviewSamples.journalHabits) { habit in
                SomaHabitRow(glyph: habit.glyph, title: habit.id, detail: habit.detail,
                             tone: habit.tone, mark: habit.mark) {}
            }
            SomaHabitStack(SomaPreviewSamples.journalQuantities) { quantity in
                SomaHabitRow(glyph: quantity.glyph, title: quantity.id, tone: quantity.tone,
                             value: quantity.value, unit: quantity.unit) {}
            }
            SomaHabitStack(SomaPreviewSamples.journalQuestions) { question in
                SomaHabitRow(glyph: question.glyph, title: question.id, tone: question.tone,
                             answer: .constant(question.answer))
            }
            SomaFeelingScale(value: $feeling, names: SomaPreviewSamples.feelingNames)
            SomaRitualDays(shares: SomaPreviewSamples.ritualDays, tone: .sand)
            ForEach(SomaPreviewSamples.ritualSteps) { step in
                SomaRitualStep(step.id, glyph: step.glyph, tone: .sand, isDone: step.isDone) {}
            }
        }
        .padding()
    }
    .background(SomaPreviewSamples.backdrop(theme))
}
