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
        public let symbol: String
        public let hue: SomaHealthHue
    }

    struct JournalHabit: Identifiable, Sendable {
        public let id: String
        public let symbol: String
        public let hue: SomaHealthHue
        public let detail: String?
        public let mark: SomaHabitMark.State
    }

    static let journalTiles: [JournalTile] = [
        JournalTile(id: "Drink", symbol: "drop.fill", hue: .medications),
        JournalTile(id: "Meal", symbol: "fork.knife", hue: .nutrition),
        JournalTile(id: "Fast", symbol: "timer", hue: .mobility),
        JournalTile(id: "Weight", symbol: "scalemass.fill", hue: .body),
        JournalTile(id: "Mood", symbol: "face.smiling", hue: .symptoms),
        JournalTile(id: "Breathe", symbol: "wind", hue: .mind),
        JournalTile(id: "Sauna", symbol: "flame.fill", hue: .vitals),
        JournalTile(id: "Cold plunge", symbol: "snowflake", hue: .hearing),
    ]

    static let journalHabits: [JournalHabit] = [
        JournalHabit(id: "Alcohol", symbol: "wineglass.fill", hue: .sleep, detail: nil, mark: .on),
        JournalHabit(id: "Late meal", symbol: "fork.knife", hue: .sleep, detail: nil, mark: .off),
        JournalHabit(id: "8,000 steps", symbol: "figure.walk", hue: .activity, detail: "5,412", mark: .progress(0.68)),
        JournalHabit(id: "7 h of sleep", symbol: "bed.double.fill", hue: .sleep, detail: "7 h 24", mark: .met),
        JournalHabit(id: "Daylight", symbol: "sun.max.fill", hue: .mobility, detail: nil, mark: .missing),
    ]

    struct JournalQuestion: Identifiable, Sendable {
        public let id: String
        public let symbol: String
        public let hue: SomaHealthHue
        public let answer: Bool?
    }

    /// An evening's yes or no questions: one yes, one no, one unanswered.
    static let journalQuestions: [JournalQuestion] = [
        JournalQuestion(id: "Alcohol", symbol: "wineglass.fill", hue: .sleep, answer: true),
        JournalQuestion(id: "Late meal", symbol: "fork.knife", hue: .sleep, answer: false),
        JournalQuestion(id: "Screens in bed", symbol: "iphone", hue: .sleep, answer: nil),
    ]

    struct JournalQuantity: Identifiable, Sendable {
        public let id: String
        public let symbol: String
        public let hue: SomaHealthHue
        public let value: String?
        public let unit: String
    }

    /// Two things a day counts rather than answers: one logged, one not.
    static let journalQuantities: [JournalQuantity] = [
        JournalQuantity(id: "Caffeine", symbol: "cup.and.saucer.fill", hue: .mobility, value: "160", unit: "mg"),
        JournalQuantity(id: "Drinks", symbol: "drop.fill", hue: .medications, value: nil, unit: "ml"),
    ]

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
                    SomaGlyphTile(tile.id, symbol: tile.symbol, hue: tile.hue) {}
                }
            }
            SomaBrowseGroup(SomaPreviewSamples.journalHabits) { habit in
                SomaHabitRow(symbol: habit.symbol, title: habit.id, detail: habit.detail,
                             hue: habit.hue, mark: habit.mark) {}
            }
            SomaHabitStack(SomaPreviewSamples.journalQuantities) { quantity in
                SomaHabitRow(symbol: quantity.symbol, title: quantity.id, hue: quantity.hue,
                             value: quantity.value, unit: quantity.unit) {}
            }
            SomaHabitStack(SomaPreviewSamples.journalQuestions) { question in
                SomaHabitRow(symbol: question.symbol, title: question.id, hue: question.hue,
                             answer: .constant(question.answer))
            }
            SomaFeelingScale(value: $feeling, names: SomaPreviewSamples.feelingNames)
        }
        .padding()
    }
    .background(SomaPreviewSamples.backdrop(theme))
}
