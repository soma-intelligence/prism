//
//  HomeTodayCards.swift
//  Prism
//

import SwiftUI
import SomaUI
import HealthExportCore

/// The cards Edit Today can add to Today, hidden until the person shows them:
/// nutrition, stand hours and the cycle.
struct HomeTodayExtraCard: View {
    let card: HomeTodayCard
    let open: (HomeSheetRoute) -> Void

    var body: some View {
        switch card {
        case .nutrition:
            TileLink(value: HomeRoute.nutrition) { HomeNutritionCard() }
        case .stand:
            Button { open(.stand) } label: { HomeStandCard() }
                .buttonStyle(TilePressStyle())
        case .cycle:
            TileLink(value: HomeRoute.cycle) { HomeCycleCard() }
        default:
            EmptyView()
        }
    }
}

extension HomeTodayCard {
    /// Whether the card belongs under "Your aspects" rather than at the top.
    var isAspect: Bool {
        switch self {
        case .tonight, .energy, .today: false
        default: true
        }
    }
}

/// Today's food as a card: calories so far and the protein in them.
private struct HomeNutritionCard: View {
    private var log: TrackLogStore { .shared }

    var body: some View {
        let meals = log.meals(on: Date())
        let kcal = meals.isEmpty ? nil : meals.reduce(0) { $0 + $1.kilocalories }
        let protein = HomeFormat.whole(meals.reduce(0) { $0 + $1.proteinEaten })
        SomaAspectCard(
            aspect: .gut,
            value: kcal.map { HomeFormat.whole($0) },
            unit: "kcal so far",
            summary: meals.isEmpty
                ? "Nothing logged yet today. Hold the orb to add a meal, water or coffee."
                : "\(meals.count == 1 ? "One meal" : "\(meals.count) meals"), \(protein) g of protein."
        ) {
            EmptyView()
        }
    }
}

/// Stand hours as a card, read from the watch when the card is on the page.
private struct HomeStandCard: View {
    @Environment(HealthDashboard.self) private var health
    @State private var stood: Int?

    private var log: HomeLog { .shared }

    var body: some View {
        SomaAspectCard(
            aspect: .activity,
            value: stood.map(String.init),
            unit: "of \(log.standGoal) hours stood",
            summary: stood == nil ? "Apple Watch counts an hour once you stand and move for a minute in it." : "Tap for the day hour by hour."
        ) {
            EmptyView()
        }
        .task {
            guard let source = await health.prepare([HomeMetric.standHour]) else { return }
            let now = Date()
            let samples = await source.home(HomeMetric.standHour, days: 0, now: now)
            let hours = HomeStandHour.day(samples, now: now, calendar: .current)
            stood = samples.isEmpty ? nil : hours.filter { $0 == .stood }.count
        }
    }
}

/// The cycle as a card. Cycle tracking is read only when its page opens, so
/// the card says where to look rather than asking from Today.
private struct HomeCycleCard: View {
    var body: some View {
        SomaAspectCard(
            aspect: .heart,
            value: nil,
            unit: "cycle day",
            summary: "Day and phase from Apple Health’s Cycle Tracking. Open it to read them."
        ) {
            EmptyView()
        }
    }
}

/// The two rows at Today's foot: Edit Today and All categories.
struct HomeTodayFoot: View {
    let open: (HomeSheetRoute) -> Void

    private struct Row: Identifiable {
        var id: String { title }
        var title: String
        var route: HomeSheetRoute
    }

    var body: some View {
        SomaBrowseGroup([Row(title: "Edit Today", route: .editToday), Row(title: "All categories", route: .allCategories)], hasGlyphs: false) { row in
            SomaBrowseRow(title: row.title) { open(row.route) }
        }
    }
}
