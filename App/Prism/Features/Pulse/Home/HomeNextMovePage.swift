//
//  HomeNextMovePage.swift
//  Prism
//

import SwiftUI
import SomaUI
import HealthExportCore

/// The move behind the orb, pushed from Today: what to do now and the number
/// that asks for it, the day's energy with its stress peaks, why this move
/// against the usual, one Start, and the other doors. Moves are ranked by the
/// rules in `Core/NextMove`.
struct HomeNextMovePage: View {
    @Environment(HealthDashboard.self) private var health
    @Environment(\.somaTheme) private var theme
    @State private var day: HomeDay?
    @State private var sheet: HomeSheetRoute?

    private var log: HomeLog { .shared }

    var body: some View {
        let move = day?.cue

        HomePage("Next move") {
            SomaPageHero(
                eyebrow: "Now · \(HomeFormat.clock(day?.now ?? NextMoveClock.now()))",
                title: move?.title ?? (day == nil ? "Reading your day." : "Nothing presses right now."),
                reason: move?.message ?? (day == nil
                    ? "Asking Apple Health for last night, today and the month before."
                    : "Sleep, heart, stress and what you logged sit close to your usual. The next move appears here when a number asks for one.")
            )
            .padding(.bottom, theme.metrics.cardSpacing)

            SomaChartCard(
                eyebrow: "Energy",
                value: day?.scores?.energy.map(String.init),
                unit: "of 100",
                note: energyNote
            ) {
                MindEnergyChart(slots: day?.slots ?? [], curve: day?.curve ?? [])
                    .padding(.top, 8)
            }

            if let move, !(move.evidence.isEmpty && move.why.isEmpty) {
                HomeRowsCard(caption: "Why this move") {
                    if !move.why.isEmpty {
                        HomeWhyLine(text: move.why)
                    }
                    ForEach(Array(move.evidence.enumerated()), id: \.offset) { _, evidence in
                        HomeValueRow(name: evidence.label, value: evidence.value)
                    }
                    if let context = day?.context {
                        whyRows(context, move: move)
                    }
                }

                HomeActionCard(
                    eyebrow: "The move",
                    aspect: move.aspect,
                    title: move.title,
                    detail: move.message,
                    actionTitle: move.actionTitle
                ) { open(move.door) }
            }

            HomeEyebrow("Or instead")
                .padding(.top, theme.metrics.cardSpacing)
            SomaBrowseGroup(alternatives) { row in
                if row.id == "medical" {
                    NavigationLink(value: HomeRoute.medicalCard) {
                        SomaBrowseRow(title: row.title, detail: row.detail)
                    }
                    .buttonStyle(.plain)
                } else {
                    SomaBrowseRow(title: row.title, detail: row.detail) { row.action() }
                }
            }

            if let rest = day?.moves.filter({ $0.id != move?.id }), !rest.isEmpty {
                HomeRowsCard(caption: "Also today") {
                    ForEach(rest, id: \.id) { candidate in
                        HomeValueRow(name: candidate.title, detail: candidate.evidence.first.map { "\($0.label): \($0.value)" }, value: nil)
                    }
                }
            }
        }
        .task { day = await HomeDay.load(health: health, log: log) }
        .refreshable { day = await HomeDay.load(health: health, log: log) }
        .homeSheets($sheet)
    }

    /// The day's own readings beside the rule's receipt, when the rule did not
    /// already name them.
    @ViewBuilder
    private func whyRows(_ context: NextMoveContext, move: NextMoveCandidate) -> some View {
        let named = Set(move.evidence.map(\.label))
        if !named.contains("HRV"), let hrv = context.hrv {
            HomeValueRow(
                name: "HRV",
                detail: context.hrvBaseline.map { "usual \(HomeFormat.whole($0)) ms" },
                value: "\(HomeFormat.whole(hrv)) ms",
                isWorse: context.hrvBaseline.map { hrv < $0 * 0.9 } ?? false
            )
        }
        if !named.contains("Stress peaks"), let peaks = context.stressPeaks {
            HomeValueRow(name: "Stress peaks", detail: "since you woke", value: "\(peaks)", isWorse: peaks >= 2)
        }
    }

    private var energyNote: String {
        guard let day, let energy = day.scores?.energy else {
            return "The energy line fills in once Apple Health holds a night of sleep to charge from."
        }
        let high = day.scores?.energyCurve.max { $0.level < $1.level }
        var note = "\(energy) of 100 now."
        if let high, Int(high.level.rounded()) > energy {
            note += " Down \(Int(high.level.rounded()) - energy) since the \(HomeFormat.clock(high.date)) high."
        }
        if !day.peaks.isEmpty {
            note += " \(day.peaks.count == 1 ? "One stress peak" : "\(day.peaks.count) stress peaks") on the strip."
        }
        return note
    }

    private struct Alternative: Identifiable {
        var id: String
        var title: String
        var detail: String
        var action: () -> Void
    }

    private var alternatives: [Alternative] {
        [
            Alternative(id: "walk", title: "An easy walk", detail: "15 min") { sheet = .walk(minutes: 15) },
            Alternative(id: "breathe", title: "Slow breathing", detail: "10 min") { sheet = .breathe },
            Alternative(id: "checkIn", title: "Check in first", detail: "1 min") { sheet = .checkIn },
            Alternative(id: "medical", title: "Medical card", detail: "If you feel unwell") {},
        ]
    }

    private func open(_ door: NextMoveDoor) {
        switch door {
        case .breathe: sheet = .breathe
        case .walk(let minutes): sheet = .walk(minutes: minutes)
        case .checkIn: sheet = .checkIn
        case .lastNight: sheet = .lastNight
        case .restingHeart: sheet = .marker(.restingHeartRate)
        case .nutrition, .logMeal: sheet = .foodLog
        case .quickAdd: sheet = .quickAdd
        }
    }
}

/// The move's one line of why, read before the numbers behind it.
private struct HomeWhyLine: View {
    let text: String

    @Environment(\.somaTheme) private var theme

    var body: some View {
        Text(text)
            .somaFont(theme.typography.body)
            .foregroundStyle(theme.colors.inkPrimary.color)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
