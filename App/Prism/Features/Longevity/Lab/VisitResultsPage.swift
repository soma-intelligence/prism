//
//  VisitResultsPage.swift
//  Prism
//

import SwiftUI
import SomaUI

/// A Soma visit's results: fitness age, lean mass and body fat, the fitness
/// age plot and what moved since the visit before.
///
/// Every number here comes from a visit, and no visit has a source yet, so
/// the page keeps its frame, says what fills it and offers the booking. Your
/// age comes from Health, so the line the plot is read against is already
/// drawn.
struct VisitResultsPage: View {
    @Environment(HealthDashboard.self) private var health

    @State private var age: Int?
    @State private var isBooking = false

    var body: some View {
        TabPartScaffold(
            aspect: nil,
            eyebrow: "Soma visit",
            title: "No visit yet.",
            reason: "Fitness age, lean mass by region, body fat and grip come from a Soma visit, which is optional. The results land here the same day.",
            stats: [
                SomaStat("Fitness age", value: nil),
                SomaStat("Lean mass", value: nil, unit: "kg"),
                SomaStat("Body fat %", value: nil),
            ]
        ) {
            SomaChartCard(
                eyebrow: "Fitness age",
                value: nil,
                unit: "give or take",
                note: "Your first visit draws this, and every visit after narrows the band."
            ) {
                BodyFitnessAgeFrame(age: age)
            }
            LabRowGroup(heading: "Since your last visit", rows: [
                LabRow("Lean mass", detail: "-"),
                LabRow("Body fat", detail: "-"),
                LabRow("Grip", detail: "-"),
                LabRow("Trunk lean mass", detail: "-"),
                LabRow("Bone density", detail: "-"),
            ])
            SomaActionCard(
                eyebrow: "Next visit",
                title: "No visit booked",
                detail: "Twenty minutes at a Soma studio.",
                actionTitle: "Book",
                action: { isBooking = true }
            ) {
                SomaOrb(aspect: .body, scale: .mini)
            }
        }
        .navigationTitle("Visit")
        .task { await load() }
        .sheet(isPresented: $isBooking) {
            NotWiredPage(
                eyebrow: "Next visit",
                title: "Book a visit",
                message: "Booking a Soma visit isn’t connected yet. When it is, this is where you pick a time."
            )
        }
    }

    private func load() async {
        guard let source = await health.prepare([LabMetric.dateOfBirth]) else { return }
        age = await LabHealth.age(in: source)
    }
}

#Preview("Visit results") {
    NavigationStack {
        VisitResultsPage()
    }
    .environment(HealthDashboard())
}
