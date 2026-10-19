//
//  MindHabitsPage.swift
//  Prism
//

import SwiftUI
import SomaUI

/// Insights · Recovery and Insights · Sleep: what each habit does to the next
/// morning's recovery, or to that night's sleep score.
///
/// Habits are the Journal's tags and ten minute breathing sessions from Apple
/// Health; scores are `SomaScores`' last thirty days. Each effect is
/// `EffectMath` on the person's own days, sorted into clear, not enough days
/// yet, and no effect.
struct MindHabitsPage: View {
    @State var lens: MindHabitLens

    @Environment(HealthDashboard.self) private var health
    @Environment(JournalStore.self) private var journal
    @Environment(\.somaTheme) private var theme

    @State private var inputs: MindInputs?

    var body: some View {
        let calendar = Calendar.current
        let now = Date()
        let scores = health.scores
        let today = calendar.startOfDay(for: now)
        let series = lens == .recovery ? scores?.recoverySeries : scores?.sleepSeries
        let outcome = MindHabitEffects.keyedByDayBefore(series ?? [], today: today, calendar: calendar)
        let model = MindHabitEffects.make(lens: lens, habits: habits(calendar: calendar), outcome: outcome)
        let score = lens == .recovery ? scores?.recovery : scores?.sleep

        MindPage(
            navigationTitle: "Insights"
        ) {
            SomaSegmentedControl(
                segments: MindHabitLens.allCases.map { SomaSegment(id: $0, title: LocalizedStringResource(stringLiteral: $0.title)) },
                selection: $lens
            )
            .frame(maxWidth: .infinity)

            if !model.clear.isEmpty {
                card("Clear effect", caption: "\(lens.when.capitalized), in points", rows: model.clear, strong: true)
            }
            if !model.needsMore.isEmpty {
                card("Needs more days", caption: "Fewer than \(MindHabitEffects.clearDays) days so far", rows: model.needsMore, strong: false)
            }
            if !model.none.isEmpty {
                card("No effect", caption: "Enough days, no change", rows: model.none, strong: true)
            }
            if model.clear.isEmpty && model.needsMore.isEmpty && model.none.isEmpty {
                MindTextCard(title: "Nothing measured yet")
            }

            if let cost = model.clear.first(where: \.isCost), let delta = cost.delta {
                let recent = recentCount(cost.id, calendar: calendar)
                SomaActionCard(
                    eyebrow: "Tonight",
                    title: "A day without \(cost.title.localizedLowercase)",
                    detail: "It was on \(recent) of the last 4 days. A day without it is worth about \(MindHabitEffects.points(delta)) \(lens.when)."
                ) {
                    SomaOrb(aspect: lens == .recovery ? .mind : .sleep, scale: .mini)
                }
            }
        }
        .task {
            await health.loadScores()
            inputs = await MindLoad.inputs(health)
        }
    }

    private func card(_ title: LocalizedStringResource, caption: String, rows: [MindHabitEffects.Habit], strong: Bool) -> some View {
        let window = max(outcomeWindow, 1)
        let largest = max(rows.compactMap { $0.delta.map(abs) }.max() ?? 1, 5)
        return MindRowsCard(title: title, caption: LocalizedStringResource(stringLiteral: caption), rows: rows) { habit in
            MindHabitRow(habit: habit, window: window, largest: largest, clearDays: strong ? nil : MindHabitEffects.clearDays, aspect: lens == .recovery ? .mind : .sleep)
        }
    }

    private var outcomeWindow: Int {
        (lens == .recovery ? health.scores?.recoverySeries : health.scores?.sleepSeries)?.compactMap { $0 }.count ?? 0
    }

    private func habits(calendar: Calendar) -> [(id: String, title: String, days: Set<Date>)] {
        var result = journal.tags.map { tag in
            (id: tag.id, title: tag.title, days: journal.dates(tagged: tag.id))
        }
        if let inputs {
            let minutes = MindDaily.minutesByDay(inputs.mindful, calendar: calendar)
            result.append((id: "breathe", title: "Breathe, 10 minutes", days: Set(minutes.filter { $0.value >= 10 }.keys)))
        }
        return result.filter { !$0.days.isEmpty }
    }

    private func recentCount(_ id: String, calendar: Calendar) -> Int {
        let days = habits(calendar: calendar).first { $0.id == id }?.days ?? []
        let today = calendar.startOfDay(for: Date())
        return (0..<4).filter { offset in
            days.contains(calendar.date(byAdding: .day, value: -offset, to: today) ?? today)
        }.count
    }
}

/// One habit: how often it happened, the points, and the bar from the centre.
struct MindHabitRow: View {
    let habit: MindHabitEffects.Habit
    let window: Int
    let largest: Double
    /// When set, the row says how many days are still to go.
    let clearDays: Int?
    let aspect: SomaAspect

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let type = theme.typography
        let colors = theme.colors
        let togo = clearDays.map { max(0, $0 - habit.days) } ?? 0
        let detail = "on \(habit.days) of \(window) days" + (togo > 0 ? ", \(togo) more to go" : "")

        HStack(alignment: .center, spacing: theme.metrics.moveRowGap) {
            VStack(alignment: .leading, spacing: 2) {
                Text(habit.title)
                    .somaFont(type.body)
                    .foregroundStyle(colors.inkPrimary.color)
                Text(detail)
                    .somaFont(type.caption)
                    .foregroundStyle(colors.inkSecondary.color)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                Text(value)
                    .somaFont(type.rowValue)
                    .foregroundStyle(habit.isCost ? colors.danger.color : colors.inkPrimary.color)
                SomaEffectBar(fraction: habit.delta.map { $0 / largest }, aspect: aspect, isCost: habit.isCost)
                    .frame(width: theme.metrics.aspectChartWidth)
                    .opacity(clearDays == nil ? 1 : 0.6)
            }
        }
        .padding(.vertical, theme.metrics.browseRowVerticalPadding)
        .accessibilityElement(children: .combine)
    }

    private var value: String {
        guard let delta = habit.delta else { return "-" }
        let whole = Int(delta.rounded())
        if abs(delta) < MindHabitEffects.noEffectPoints, clearDays == nil { return "No effect" }
        return (whole > 0 ? "+\(whole)" : "\(whole)") + " pts"
    }
}
