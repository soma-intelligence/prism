//
//  TrackAddToday.swift
//  Prism
//

import SwiftUI
import SomaUI

/// "Add to today", at the head of the Journal: a grid of quiet glyph tiles,
/// four to a row, each opening one entry as a sheet, and under it what is
/// already running or filling today (a fast, the day's glass) as rows that
/// open their page.
///
/// Two rows show at first, the last tile opening the rest: the everyday
/// entries lead, and the occasional ones (a height, a blood test) wait one
/// tap away.
///
/// A blood, urine, stool, genome or functional test is Longevity's (Lab): its tile
/// pushes that page rather than opening a Track sheet.
///
/// Period opens the cycle log, and only shows for a person who tracks a
/// cycle (`CycleVisibility`).
///
/// Appointment books a visit into the medical record (`AppointmentSheet`).
struct TrackAddToday: View {
    @Environment(\.somaTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var opened: TrackRoute?
    @State private var opensLab: LabRoute?
    @State private var isLoggingCycle = false
    @State private var isAddingAppointment = false
    @State private var isTestingFitness = false
    /// The medical record pushed at launch, for screenshots.
    @State private var opensRecord: GlobalRoute?
    @State private var showsAll = false

    private let log = TrackLogStore.shared

    private struct Tile: Identifiable {
        var id: String { title }
        var title: String
        var symbol: String
        var hue: SomaHealthHue
        var route: TrackRoute?
        /// A Lab page pushed instead of a Track sheet.
        var lab: LabRoute?
        /// The cycle log, a sheet of its own.
        var opensCycle = false
        /// An appointment for the medical record, a sheet of its own.
        var opensAppointment = false
        /// The guided cardio fitness test, over the whole screen.
        var opensFitnessTest = false
    }

    private var tiles: [Tile] {
        var tiles = [
            Tile(title: "Drink", symbol: "drop", hue: .medications, route: .drink(.water)),
            Tile(title: "Meal", symbol: "fork.knife", hue: .nutrition, route: .food),
            Tile(title: log.currentFast == nil ? "Fast" : "Fasting", symbol: "hourglass", hue: .mobility, route: .fasting),
            Tile(title: "Mood", symbol: "smiley", hue: .symptoms, route: .moodNow),
            Tile(title: "Weight", symbol: "scalemass", hue: .body, route: .weight),
            Tile(title: "Breathe", symbol: "wind", hue: .mind, route: .practice(.meditation)),
            Tile(title: "Sauna", symbol: "flame", hue: .vitals, route: .practice(.sauna)),
            Tile(title: "Cold plunge", symbol: "snowflake", hue: .hearing, route: .practice(.coldPlunge)),
            Tile(title: "Evening", symbol: "moon.stars", hue: .sleep, route: .evening),
            Tile(title: "Woke", symbol: "sunrise", hue: .cycle, route: .wake),
            Tile(title: "Supplement", symbol: "pills", hue: .respiratory, route: .dose(nil)),
            Tile(title: "Scan", symbol: "camera.viewfinder", hue: .heart, route: .cameraScan),
            Tile(title: "Blood test", symbol: "drop.halffull", hue: .vitals, route: nil, lab: .bloodPanel),
            Tile(title: "Urine test", symbol: "flask", hue: .nutrition, route: nil, lab: .urine),
            Tile(title: "Stool test", symbol: "leaf", hue: .nutrition, route: nil, lab: .stool),
            Tile(title: "Genome", symbol: "point.3.connected.trianglepath.dotted", hue: .symptoms, route: nil, lab: .genome),
            Tile(title: "Scan or test", symbol: "figure.strengthtraining.functional", hue: .activity, route: nil, lab: .functional),
            Tile(title: "Fitness test", symbol: "figure.walk.motion", hue: .heart, route: nil, opensFitnessTest: true),
            Tile(title: "Height", symbol: "ruler", hue: .body, route: .height),
            Tile(title: "Appointment", symbol: "calendar.badge.clock", hue: .heart, route: nil, opensAppointment: true),
        ]
        if CycleVisibility.tracksCycle {
            tiles.insert(Tile(title: "Period", symbol: "drop.circle", hue: .cycle, route: nil, opensCycle: true), at: 4)
        }
        return tiles
    }

    /// Tiles shown while folded: two rows, the eighth slot is "More".
    private static let folded = 7

    var body: some View {
        let metrics = theme.metrics
        let all = tiles
        let shown = showsAll ? all : Array(all.prefix(Self.folded))
        let slots = shown.map(Optional.some) + [nil]
        let rows = stride(from: 0, to: slots.count, by: 4).map { Array(slots[$0..<min($0 + 4, slots.count)]) }

        VStack(alignment: .leading, spacing: metrics.cardSpacing) {
            // A plain grid rather than a lazy one: twenty tiles at most, and
            // every one measured up front keeps the rows even.
            Grid(horizontalSpacing: metrics.journalTileSpacing, verticalSpacing: metrics.journalTileSpacing) {
                ForEach(rows.indices, id: \.self) { index in
                    GridRow {
                        ForEach(0..<4, id: \.self) { column in
                            if column < rows[index].count {
                                if let tile = rows[index][column] {
                                    SomaGlyphTile(tile.title, symbol: tile.symbol, hue: tile.hue) {
                                        if let route = tile.route {
                                            opened = route
                                        } else if tile.opensCycle {
                                            isLoggingCycle = true
                                        } else if tile.opensAppointment {
                                            isAddingAppointment = true
                                        } else if tile.opensFitnessTest {
                                            isTestingFitness = true
                                        } else {
                                            opensLab = tile.lab
                                        }
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
        .sheet(isPresented: $isAddingAppointment) { AppointmentSheet(appointment: nil) }
        .cardioFitnessTest(isPresented: $isTestingFitness)
        .sheet(isPresented: $isLoggingCycle) {
            NavigationStack { CycleLogSheet() }
                .environment(\.trackInSheet, true)
                .presentationDragIndicator(.visible)
        }
        .task { await openFromLaunch() }
        .navigationDestination(item: $opensLab) { route in
            route.page
        }
        .navigationDestination(item: $opensRecord) { route in
            route.page
        }
    }

    /// The last slot: opens the rest of the tiles, or folds them away.
    private var moreTile: some View {
        let metrics = theme.metrics
        let colors = theme.colors
        return Button {
            if reduceMotion { showsAll.toggle() } else { withAnimation(theme.motion.selection) { showsAll.toggle() } }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                Image(systemName: showsAll ? "chevron.up" : "ellipsis")
                    .font(.system(size: metrics.journalTileGlyph, weight: .light))
                    .foregroundStyle(colors.inkSecondary.color)
                    .frame(height: metrics.journalTileGlyph * 1.2, alignment: .leading)
                Spacer(minLength: metrics.spaceS)
                Text(showsAll ? "Less" : "More")
                    .somaFont(theme.typography.caption)
                    .foregroundStyle(colors.inkSecondary.color)
            }
            .padding(metrics.spaceM - 2)
            .frame(maxWidth: .infinity, minHeight: metrics.journalTileHeight, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: metrics.journalTileCornerRadius, style: .continuous)
                    .fill(colors.surface.color)
            )
            .overlay(
                RoundedRectangle(cornerRadius: metrics.journalTileCornerRadius, style: .continuous)
                    .strokeBorder(colors.inkPrimary.color.opacity(metrics.hairlineOpacity), lineWidth: 0.5)
            )
            .contentShape(.rect)
        }
        .buttonStyle(.somaGlassPress)
    }

    /// `-track.entry fasting` (or weight, height, scan, evening, mood, water,
    /// intake, plunge, wake, food, dose, appointment, record, fitness) opens that entry
    /// at launch, for screenshots.
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
        switch UserDefaults.standard.string(forKey: "track.entry") {
        case "appointment": isAddingAppointment = true
        case "fitness": isTestingFitness = true
        case "record": opensRecord = .medicalRecord
        default: break
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
            VStack(spacing: metrics.spaceS) {
                if let fast {
                    let started = fast.start <= now
                    link(.fasting,
                         title: started ? "Fasting" : "Fast starts at \(TrackClock.time(fast.start))",
                         value: started ? "\(TrackFasting.length(fast.elapsed(at: now)))\(fast.objectiveHours.map { " of \(TrackFasting.length($0 * 3600))" } ?? "")" : nil)
                }
                if let water {
                    link(.intake,
                         title: "Today\u{2019}s intake",
                         value: "\(TrackIntake.litres(water)) of \(TrackIntake.litres(log.waterGoalMl)) L" + (caffeine > 0 ? ", \(Int(caffeine)) mg caffeine" : ""))
                }
            }
        }
    }

    /// A running entry as a row that opens it. A nil value (a fast that has
    /// not started) leaves the title alone, with no mark beside it.
    private func link(_ route: TrackRoute, title: String, value: String?) -> some View {
        let metrics = theme.metrics
        let colors = theme.colors
        return NavigationLink(value: route) {
            HStack(spacing: metrics.cardSpacing) {
                Text(title)
                    .somaFont(theme.typography.body)
                    .foregroundStyle(colors.inkPrimary.color)
                Spacer(minLength: metrics.cardSpacing)
                if let value {
                    Text(value)
                        .somaFont(theme.typography.rowValue)
                        .foregroundStyle(colors.inkSecondary.color)
                        .lineLimit(1)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: metrics.browseChevronSize, weight: .semibold))
                    .foregroundStyle(colors.inkSecondary.color)
            }
            .padding(.horizontal, metrics.browseRowPadding)
            .frame(minHeight: metrics.browseRowMinHeight)
            .background(RoundedRectangle(cornerRadius: metrics.browseGroupCornerRadius, style: .continuous).fill(colors.surface.color))
            .contentShape(.rect)
        }
        .zoomSource(route)
        .buttonStyle(.somaGlassPressDim)
    }
}
