//
//  HomeTodayLayout.swift
//  Prism
//

import SwiftUI
import SomaUI
import HealthExportCore

/// A card Today can show under the orb, the scores and the headline, which
/// always stay on top.
enum HomeTodayCard: String, CaseIterable, Codable, Identifiable, Sendable {
    case tonight, energy, today, sleep, heart, body, nutrition, stand, cycle, environment

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tonight: "Tonight"
        case .energy: "Energy"
        case .today: "Today so far"
        case .sleep: "Sleep"
        case .heart: "Heart"
        case .body: "Body"
        case .nutrition: "Nutrition"
        case .stand: "Stand hours"
        case .cycle: "Cycle"
        case .environment: "Environment"
        }
    }

    var detail: String {
        switch self {
        case .tonight: "Soma’s suggestions for the evening"
        case .energy: "The day’s charge, 0 to 100"
        case .today: "The day as it happened"
        case .sleep: "Last night, stage by stage"
        case .heart: "Resting rate against your usual"
        case .body: "Fitness age and body composition"
        case .nutrition: "Meals, water and caffeine you log"
        case .stand: "Hours stood, from your watch"
        case .cycle: "Day and phase, from Cycle Tracking"
        case .environment: "Air, noise and daylight"
        }
    }
}

/// Which cards Today shows, in which order. Kept as one defaults string, so
/// a hidden card leaves the page and never the data.
struct HomeTodayLayout: Equatable, Sendable {
    static let key = "pulse.todayLayout"
    /// Soma's order. Last night's sleep shows, drawn as its stages (owner,
    /// 2026-10-19); Heart and Body start hidden: the scores and "What moved"
    /// already show their numbers against the usual.
    static let standard = HomeTodayLayout(
        shown: [.tonight, .sleep, .energy, .today],
        hidden: [.heart, .body, .nutrition, .stand, .cycle, .environment]
    )

    var shown: [HomeTodayCard]
    var hidden: [HomeTodayCard]

    init(shown: [HomeTodayCard], hidden: [HomeTodayCard]) {
        self.shown = shown
        self.hidden = hidden
    }

    /// Reads the stored string: shown cards, a bar, hidden ones. A card the
    /// string does not name, added in a later version, joins the hidden ones.
    init(stored: String) {
        let halves = stored.split(separator: "|", omittingEmptySubsequences: false).map {
            $0.split(separator: ",").compactMap { HomeTodayCard(rawValue: String($0)) }
        }
        guard halves.count == 2 else {
            self = .standard
            return
        }
        var seen = Set<HomeTodayCard>()
        shown = halves[0].filter { seen.insert($0).inserted }
        hidden = halves[1].filter { seen.insert($0).inserted }
        hidden += HomeTodayCard.allCases.filter { !seen.contains($0) }
    }

    var stored: String {
        shown.map(\.rawValue).joined(separator: ",") + "|" + hidden.map(\.rawValue).joined(separator: ",")
    }

    mutating func set(_ card: HomeTodayCard, shown isShown: Bool) {
        shown.removeAll { $0 == card }
        hidden.removeAll { $0 == card }
        if isShown { shown.append(card) } else { hidden.append(card) }
    }
}

/// Chooses and orders Today's cards: the shown ones with a grip and a switch,
/// the hidden ones with a switch, and a way back to Soma's order.
struct HomeEditTodaySheet: View {
    @Environment(\.somaTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @AppStorage(HomeTodayLayout.key) private var stored = HomeTodayLayout.standard.stored

    var body: some View {
        let layout = HomeTodayLayout(stored: stored)

        NavigationStack {
            List {
                Section {
                    ForEach(layout.shown) { card in row(card, isShown: true) }
                        .onMove { from, to in
                            var next = layout
                            next.shown.move(fromOffsets: from, toOffset: to)
                            stored = next.stored
                        }
                } header: {
                    HomeEyebrow("Shown, in this order")
                }
                Section {
                    ForEach(layout.hidden) { card in row(card, isShown: false) }
                } header: {
                    HomeEyebrow("Hidden")
                }
                Section {
                    Button("Reset to Soma’s order") { stored = HomeTodayLayout.standard.stored }
                        .somaFont(theme.typography.body)
                        .foregroundStyle(theme.colors.inkPrimary.color)
                }
            }
            .softScrollEdges()
            .scrollContentBackground(.hidden)
            .background(theme.colors.canvas.color.ignoresSafeArea())
#if os(iOS)
            .environment(\.editMode, .constant(.active))
#endif
            .navigationTitle("Edit Today")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationBackground(theme.colors.canvas.color)
    }

    private func row(_ card: HomeTodayCard, isShown: Bool) -> some View {
        Toggle(isOn: Binding(
            get: { isShown },
            set: { value in
                var next = HomeTodayLayout(stored: stored)
                next.set(card, shown: value)
                stored = next.stored
            }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text(card.title)
                    .somaFont(theme.typography.body)
                    .foregroundStyle(theme.colors.inkPrimary.color)
                Text(card.detail)
                    .somaFont(theme.typography.caption)
                    .foregroundStyle(theme.colors.inkSecondary.color)
            }
        }
        .toggleStyle(.soma)
        .listRowBackground(theme.colors.surface.color)
    }
}
