//
//  TrackFoodView.swift
//  Prism
//

import SwiftUI
import SomaUI

/// Food log: a meal as a ring in proportion. The person names it and sets
/// what one portion holds; the ring's arcs are each part's share of the
/// energy, and the energy is worked out from the grams (four kilocalories a
/// gram of protein or carbohydrate, nine of fat) rather than guessed.
///
/// A name logged before fills its grams back in. Soma has no food database or
/// photo reading in this build, so nothing is filled from a picture. Saved to
/// Apple Health as dietary energy, protein, carbohydrates and fat, and kept in
/// ``TrackLogStore``.
struct TrackFoodView: View {
    @Environment(\.somaTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var protein = 0.0
    @State private var carbs = 0.0
    @State private var fat = 0.0
    @State private var portions = 1.0
    @State private var meal = TrackMeal.at(hour: Calendar.current.component(.hour, from: .now))

    private let log = TrackLogStore.shared
    private static let portionChoices: [(Double, String)] = [(0.5, "Half"), (1, "One portion"), (1.5, "One and a half")]
    private static let gramStep = 5.0

    var body: some View {
        let metrics = theme.metrics
        let type = theme.typography
        let colors = theme.colors
        let energy = TrackMealEntry.kilocalories(protein: protein, carbs: carbs, fat: fat) * portions

        TrackEntryPage(title: meal.title) {
            TextField("What did you eat?", text: $name)
                .somaFont(type.body)
                .foregroundStyle(colors.inkPrimary.color)
                .padding(.horizontal, metrics.cardPadding)
                .frame(minHeight: metrics.minimumTapTarget + metrics.cardSpacing)
                .background(RoundedRectangle(cornerRadius: metrics.cardCornerRadius, style: .continuous).fill(colors.surface.color))
                .submitLabel(.done)
                .onSubmit(recall)

            SomaMacroRing(parts: [
                SomaMacroPart(title: "Protein", detail: grams(protein), weight: protein * 4),
                SomaMacroPart(title: "Carbs", detail: grams(carbs), weight: carbs * 4),
                SomaMacroPart(title: "Fat", detail: grams(fat), weight: fat * 9),
            ]) {
                SomaReadout(energy > 0 ? "\(Int(energy.rounded()))" : nil, caption: "kcal")
            }

            SomaCard {
                VStack(alignment: .leading, spacing: metrics.cardSpacing * 0.5) {
                    TrackEyebrow("One portion holds")
                    stepper("Protein", value: $protein)
                    TrackHairline()
                    stepper("Carbs", value: $carbs)
                    TrackHairline()
                    stepper("Fat", value: $fat)
                }
            }

            HStack(spacing: metrics.cardSpacing * 0.5) {
                ForEach(Self.portionChoices, id: \.0) { choice in
                    SomaChoiceChip(choice.1, isOn: portions == choice.0) { portions = choice.0 }
                }
            }

            TrackNote(lead: timingLine)
        } footer: {
            SomaActionButton("Log \(meal.title.lowercased())") { save() }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || energy <= 0)
        }
    }

    private func grams(_ value: Double) -> String { "\(Int((value * portions).rounded())) g" }

    private func stepper(_ title: String, value: Binding<Double>) -> some View {
        let metrics = theme.metrics
        let colors = theme.colors
        return HStack {
            Text(title)
                .somaFont(theme.typography.body)
                .foregroundStyle(colors.inkPrimary.color)
            Spacer()
            Text("\(Int(value.wrappedValue)) g")
                .somaFont(theme.typography.rowValue)
                .foregroundStyle(colors.inkSecondary.color)
            HStack(spacing: 0) {
                stepButton("minus", label: "Less \(title.lowercased())") { value.wrappedValue = max(0, value.wrappedValue - Self.gramStep) }
                stepButton("plus", label: "More \(title.lowercased())") { value.wrappedValue += Self.gramStep }
            }
            .background(Capsule().fill(colors.surfaceRecessed.color))
            .padding(.leading, metrics.cardSpacing)
        }
        .frame(minHeight: metrics.minimumTapTarget)
    }

    private func stepButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        let metrics = theme.metrics
        return Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: metrics.browseChevronSize, weight: .semibold))
                .foregroundStyle(theme.colors.inkPrimary.color)
                .frame(width: metrics.minimumTapTarget, height: metrics.minimumTapTarget * 0.8)
                .contentShape(.rect)
        }
        .buttonStyle(.somaGlassPress)
        .accessibilityLabel(Text(label))
    }

    /// Where this meal sits against the same meal over the last week.
    private var timingLine: String {
        let now = Date.now
        let calendar = Calendar.current
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        let earlier = log.meals.filter { $0.meal == meal && $0.date >= weekAgo && !calendar.isDate($0.date, inSameDayAs: now) }
        guard earlier.count >= 2 else {
            return "Name it, set what one portion holds, and Soma keeps the rest."
        }
        let minutes = { (date: Date) -> Int in calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date) }
        let times = earlier.map { minutes($0.date) }
        let nowMinutes = minutes(now)
        if nowMinutes < times.min() ?? nowMinutes {
            return "\(meal.title) at \(TrackClock.time(now)) would be your earliest this week."
        }
        if nowMinutes > times.max() ?? nowMinutes {
            return "\(meal.title) at \(TrackClock.time(now)) would be your latest this week."
        }
        return "\(meal.title) at \(TrackClock.time(now)), inside your usual hours this week."
    }

    private func recall() {
        guard let last = log.lastMeal(named: name) else { return }
        protein = last.protein
        carbs = last.carbs
        fat = last.fat
    }

    private func save() {
        let now = Date.now
        let entry = TrackMealEntry(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            meal: meal, protein: protein, carbs: carbs, fat: fat, portions: portions, date: now
        )
        log.addMeal(entry)
        Task {
            await TrackHealthWriter.save([
                .energy(kilocalories: entry.kilocalories),
                .protein(grams: protein * portions),
                .carbohydrates(grams: carbs * portions),
                .fat(grams: fat * portions),
            ], at: now)
        }
        dismiss()
    }
}

#if DEBUG
#Preview("Food") {
    NavigationStack { TrackFoodView() }
}
#endif
