//
//  TrackAddToday.swift
//  Prism
//

import SwiftUI
import SomaUI

/// "Add to today", at the head of the Journal: a grid of line glyph tiles,
/// four to a row, in the order the person set in Customize, each opening one entry as a sheet, and under it what is
/// already running or filling today (a fast, the day's glass) as rows that
/// open their page.
///
/// Two rows show at first, the last tile opening the rest: the everyday
/// entries lead, and the occasional ones (a height, a blood test) wait one
/// tap away.
///
/// A blood test is Longevity's (Lab): its tile pushes that page rather than
/// opening a Track sheet.
struct TrackAddToday: View {
    @Environment(\.somaTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var opened: TrackRoute?
    @State private var opensBloodTest = false
    @State private var showsAll = false

    private let log = TrackLogStore.shared

    private let layout = TrackQuickAddLayout.shared

    /// Tiles shown while folded: two rows, the eighth slot is "More". Eight
    /// tiles or fewer show whole, with no More.
    private static let folded = 7

    var body: some View {
        let metrics = theme.metrics
        let all = layout.shown
        let folds = all.count > Self.folded + 1
        let shown = folds && !showsAll ? Array(all.prefix(Self.folded)) : all
        let slots = shown.map(Optional.some) + (folds ? [nil] : [])
        let rows = stride(from: 0, to: slots.count, by: 4).map { Array(slots[$0..<min($0 + 4, slots.count)]) }

        VStack(alignment: .leading, spacing: metrics.cardSpacing) {
            // A plain grid rather than a lazy one: fifteen tiles at most, and
            // every one measured up front keeps the rows even.
            Grid(horizontalSpacing: metrics.journalTileSpacing, verticalSpacing: metrics.journalTileSpacing) {
                ForEach(rows.indices, id: \.self) { index in
                    GridRow {
                        ForEach(0..<4, id: \.self) { column in
                            if column < rows[index].count {
                                if let tile = rows[index][column] {
                                    SomaGlyphTile(title(tile), glyph: tile.glyph, tone: tile.tone) {
                                        if let route = tile.route { opened = route } else { opensBloodTest = true }
                                    }
                                } else {
                                    moreTile
                                }
                            } else {
                                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                            }
                        }
                    }
                }
            }

            TimelineView(.periodic(from: .now, by: 60)) { context in
                running(now: context.date)
            }
        }
        .trackEntrySheet(item: $opened)
        .task { await openFromLaunch() }
        .navigationDestination(isPresented: $opensBloodTest) {
            LabRoute.bloodPanel.page.somaScrollEdgeFade()
        }
    }

    private func title(_ tile: TrackQuickAdd) -> String {
        tile == .fast && log.currentFast != nil ? "Fasting" : tile.title
    }

    /// The last slot: opens the rest of the tiles, or folds them away.
    private var moreTile: some View {
        SomaGlyphTile(showsAll ? "Less" : "More", glyph: showsAll ? .less : .more, tone: nil) {
            if reduceMotion { showsAll.toggle() } else { withAnimation(theme.motion.selection) { showsAll.toggle() } }
        }
    }

    /// `-track.entry fasting` (or weight, height, scan, evening, mood, water,
    /// intake, plunge, wake, food, dose) opens that entry at launch, for
    /// screenshots.
    private func openFromLaunch() async {
#if DEBUG
        // After the tab's own entrance, or the sheet is dropped mid transition.
        try? await Task.sleep(for: .milliseconds(700))
        let routes: [String: TrackRoute] = [
            "fasting": .fasting, "weight": .weight, "height": .height, "scan": .cameraScan,
            "evening": .evening, "mood": .mood, "water": .drink(.water), "intake": .intake,
            "plunge": .practice(.coldPlunge), "wake": .wake, "food": .food, "dose": .dose(nil),
        ]
        if let key = UserDefaults.standard.string(forKey: "track.entry"), let route = routes[key], opened == nil {
            opened = route
        }
#endif
    }

    @ViewBuilder
    private func running(now: Date) -> some View {
        let metrics = theme.metrics
        let fast = log.currentFast
        let water = log.waterMl(on: now)
        let caffeine = log.drinks(on: now).reduce(0) { $0 + $1.caffeineMg }

        if fast != nil || water != nil {
            VStack(spacing: metrics.cardSpacing * 0.5) {
                if let fast {
                    let started = fast.start <= now
                    link(.fasting,
                         title: started ? "Fasting" : "Fast starts at \(TrackClock.time(fast.start))",
                         value: started ? "\(TrackFasting.length(fast.elapsed(at: now)))\(fast.objectiveHours.map { " of \(Int($0)) h" } ?? "")" : "-")
                }
                if let water {
                    link(.intake,
                         title: "Today\u{2019}s intake",
                         value: "\(TrackIntake.litres(water)) of \(TrackIntake.litres(log.waterGoalMl)) L" + (caffeine > 0 ? ", \(Int(caffeine)) mg caffeine" : ""))
                }
            }
        }
    }

    private func link(_ route: TrackRoute, title: String, value: String) -> some View {
        let metrics = theme.metrics
        let colors = theme.colors
        return NavigationLink(value: route) {
            HStack(spacing: metrics.cardSpacing) {
                Text(title)
                    .somaFont(theme.typography.body)
                    .foregroundStyle(colors.inkPrimary.color)
                Spacer(minLength: metrics.cardSpacing)
                Text(value)
                    .somaFont(theme.typography.rowValue)
                    .foregroundStyle(colors.inkSecondary.color)
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.system(size: metrics.browseChevronSize, weight: .semibold))
                    .foregroundStyle(colors.inkSecondary.color)
            }
            .padding(.horizontal, metrics.browseRowPadding)
            .frame(minHeight: metrics.browseRowMinHeight)
            .background(RoundedRectangle(cornerRadius: metrics.browseGroupCornerRadius, style: .continuous).fill(colors.surface.color))
            .contentShape(.rect)
        }
        .buttonStyle(.somaGlassPressDim)
    }
}
