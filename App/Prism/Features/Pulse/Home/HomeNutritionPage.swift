//
//  HomeNutritionPage.swift
//  Prism
//

import SwiftUI
import SomaUI
import HealthExportCore

/// Today's food, pushed from Today's nutrition card: what was eaten so far,
/// the macros against what this person usually has, the rise after each meal
/// when a glucose monitor writes to Apple Health, the meals, water and
/// caffeine, and dinner to log.
struct HomeNutritionPage: View {
    @Environment(HealthDashboard.self) private var health
    @Environment(\.somaTheme) private var theme
    @State private var glucose: [HealthReading] = []
    @State private var sheet: HomeSheetRoute?

    private var log: TrackLogStore { .shared }
    private let calendar = Calendar.current

    var body: some View {
        let now = Date()
        let meals = log.meals(on: now)
        let responses = meals.map { HomeMealResponse.make(meal: $0.date, glucose: glucose) }
        let measured = responses.compactMap { $0 }
        let lastIndex = measured.indices.last

        HomePage("Nutrition") {
            SomaPageHero(eyebrow: "Today so far", title: headline(meals), reason: reason(meals))
                .padding(.bottom, theme.metrics.cardSpacing)

            HomeRowsCard("Macros", caption: "Against your usual day") {
                macroRow("Protein", meals, \.proteinEaten)
                macroRow("Carbohydrate", meals, \.carbsEaten)
                macroRow("Fat", meals, \.fatEaten)
            }

            SomaChartCard(
                eyebrow: "After meals",
                value: measured.last.map { "+\(Int($0.rise.rounded()))" },
                unit: "mg/dL peak",
                note: glucoseNote(measured)
            ) {
                if !measured.isEmpty {
                    HomeMealCurves(responses: measured, highlighted: lastIndex)
                        .padding(.top, theme.metrics.spaceS)
                }
            }

            HomeEyebrow("Meals today")
                .padding(.top, theme.metrics.cardSpacing)
            if meals.isEmpty {
                HomeNote("Nothing logged today")
            } else {
                SomaCard {
                    VStack(alignment: .leading, spacing: theme.metrics.moveRowSpacing) {
                        ForEach(Array(zip(meals, responses).enumerated()), id: \.offset) { index, pair in
                            if index > 0 { HomeHairline() }
                            HomeValueRow(
                                name: pair.0.name.isEmpty ? pair.0.meal.title : pair.0.name,
                                detail: "\(pair.0.meal.title) · \(HomeFormat.clock(pair.0.date)) · \(HomeFormat.whole(pair.0.kilocalories)) kcal",
                                value: pair.1.map { "+\(Int($0.rise.rounded())) mg/dL" },
                                isWorse: (pair.1?.rise ?? 0) >= 40
                            )
                        }
                    }
                }
            }

            SomaCard {
                VStack(alignment: .leading, spacing: theme.metrics.moveRowSpacing) {
                    HomeValueRow(
                        name: "Water",
                        value: log.waterMl(on: now).map { "\(HomeFormat.litres($0)) of \(HomeFormat.litres(log.waterGoalMl))" }
                    )
                    HomeHairline()
                    HomeValueRow(name: "Caffeine", value: caffeineLine(now))
                }
            }

            HomeActionCard(
                eyebrow: "Tonight",
                aspect: .gut,
                title: meals.contains { $0.meal == .dinner } ? "Dinner logged" : "Log dinner",
                detail: "Protein and greens first, then the starch: the rise tends to be gentler.",
                actionTitle: "Log it"
            ) { sheet = .foodLog }
        }
        .task {
            guard let source = await health.prepare([HomeMetric.bloodGlucose]) else { return }
            glucose = await source.home(HomeMetric.bloodGlucose, days: 1, now: Date(), calendar: calendar)
        }
        .homeSheets($sheet)
    }

    private func macroRow(_ name: String, _ meals: [TrackMealEntry], _ value: KeyPath<TrackMealEntry, Double>) -> some View {
        let total = meals.isEmpty ? nil : meals.reduce(0) { $0 + $1[keyPath: value] }
        let band = usualBand(value)
        return HomeMeasureRow(name: name, unit: "g", latest: total, band: band, higherIsWorse: false)
    }

    /// The middle half of the daily totals of the days logged before today.
    private func usualBand(_ value: KeyPath<TrackMealEntry, Double>) -> ClosedRange<Double>? {
        let today = calendar.startOfDay(for: Date())
        var byDay: [Date: Double] = [:]
        for meal in log.meals where meal.date < today {
            byDay[calendar.startOfDay(for: meal.date), default: 0] += meal[keyPath: value]
        }
        guard byDay.count >= 5,
              let low = PulseSignals.percentile(Array(byDay.values), 0.25),
              let high = PulseSignals.percentile(Array(byDay.values), 0.75) else { return nil }
        return low...max(low, high)
    }

    private func headline(_ meals: [TrackMealEntry]) -> String {
        guard !meals.isEmpty else { return "Nothing logged yet." }
        let kcal = HomeFormat.whole(meals.reduce(0) { $0 + $1.kilocalories })
        return meals.contains { $0.meal == .dinner } ? "\(kcal) kcal today." : "\(kcal) kcal, with dinner to come."
    }

    private func reason(_ meals: [TrackMealEntry]) -> String {
        guard !meals.isEmpty else {
            return "Log what you eat and Soma sets it against your usual day. With a glucose monitor in Apple Health, each meal shows its rise."
        }
        let protein = HomeFormat.whole(meals.reduce(0) { $0 + $1.proteinEaten })
        if let band = usualBand(\.proteinEaten), meals.reduce(0, { $0 + $1.proteinEaten }) < band.lowerBound {
            return "Protein is the one to catch up on: \(protein) g so far. Dinner with protein first keeps tonight calm."
        }
        return "\(meals.count == 1 ? "One meal" : "\(meals.count) meals") logged, \(protein) g of protein. The macros read against your own days once five are logged."
    }

    private func glucoseNote(_ measured: [HomeMealResponse]) -> String {
        guard let last = measured.last else {
            return "Needs a glucose monitor writing to Apple Health, with a reading before and two after a meal."
        }
        let higher = measured.dropLast().filter { $0.rise < last.rise }.count
        var note = "The latest meal rose \(Int(last.rise.rounded())) mg/dL"
        if let back = last.backToBaseline { note += ", back in \(SomaFormat.duration(back))" }
        note += "."
        if measured.count > 1 { note += " More than \(higher) of today’s other \(measured.count - 1)." }
        return note
    }

    private func caffeineLine(_ now: Date) -> String? {
        guard let mg = log.caffeineMg(on: now) else { return nil }
        if let last = log.lastCaffeine(on: now) {
            return "\(HomeFormat.whole(mg)) mg, the last at \(HomeFormat.clock(last))"
        }
        return "\(HomeFormat.whole(mg)) mg"
    }
}
