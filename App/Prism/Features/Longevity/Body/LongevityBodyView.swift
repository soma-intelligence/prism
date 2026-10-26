//
//  LongevityBodyView.swift
//  Prism
//

import SwiftUI
import SomaUI
import HealthExportCore

/// The Longevity tab's Body lens, laid out like the reference design's Biology tab: the three
/// numbers that sum the body up, the fitness readings as tiles, every
/// biomarker as a row with its last thirty days, then the pod's body map, the
/// next visit and the pages further in.
///
/// Few words on purpose (owner, 2026-10-03): each reading says its value,
/// where it sits, a cue of a few words on what that means, and the line
/// beside it drawn over the usual band. Tiles and rows are ordered by how
/// much each moved (``InsightEngine``), so what moved comes first.
///
/// It draws no stack and no top bar: the Longevity page hosts both, and maps
/// the ``LongevityRoute`` values the rows push.
struct LongevityBodyView: View {
    @Environment(HealthDashboard.self) private var health
    @Environment(\.somaTheme) private var theme

    /// Heart rhythm and mobility, read apart from the cached lens: their two
    /// tiles stay hidden until the read finds something from the last year.
    @State private var rhythmMobility = RhythmMobilityReadings()
    /// A continuous glucose monitor's fortnight, read apart like the two
    /// above: nil, and no tile, without a monitor's trace in Health.
    @State private var glucose: GlucoseTile?

    /// The last read, this launch's or the last one's: the lens draws it at
    /// once and the next read replaces every tile in one go.
    private var cache: LongevityCache { .shared }

    var body: some View {
        let metrics = theme.metrics
        let state = cache.body ?? LongevityBodyState.empty(now: .now, calendar: .current)
        let page = state.overview

        ScrollViewReader { scroller in
        SomaPageScroll {
            VStack(alignment: .leading, spacing: metrics.leadSpacing) {
                // Three numbers, no line under them (owner, 2026-10-03), each a
                // door to its page.
                SomaStatRow([
                    SomaStat("Fitness age", value: page.fitnessAge.value),
                    SomaStat("Lean mass", value: page.leanMass, unit: "kg", trend: page.leanTrend),
                    SomaStat("VO2 max", value: page.vo2Max, trend: page.vo2Trend),
                ]) { stat in
                    openStat(stat)
                }
                .padding(.top, metrics.heroTopPadding)

                // The sections in one column on a phone and two where the
                // width holds them: the tiles beside the muscle map, the
                // biomarkers beside the pod.
                SomaCardColumns(gap: .sections) {
                    BodySection("Fitness") {
                        LazyVGrid(
                            columns: [GridItem(.flexible(), spacing: metrics.cardSpacing), GridItem(.flexible(), spacing: metrics.cardSpacing)],
                            spacing: metrics.cardSpacing
                        ) {
                            ForEach(ranked(BodyBiomarkerSpec.tiles, in: state), id: \.self) { spec in
                                let marker = marker(spec, in: state)
                                BodyMarkerLink(spec: spec) {
                                    SomaTrendTile(
                                        LocalizedStringResource(stringLiteral: marker.title),
                                        value: marker.value,
                                        unit: marker.unit.isEmpty ? nil : marker.unit,
                                        status: marker.status.reading,
                                        cue: marker.cue.map { LocalizedStringResource(stringLiteral: $0) },
                                        values: marker.days,
                                        band: marker.band,
                                        aspect: .body,
                                        chart: spec.sumsPerDay ? .bars : .line
                                    )
                                }
                            }
                        }
                    }

                    BodyMapCard(states: state.muscles)

                    BodySection("Biomarkers") {
                        VStack(spacing: metrics.cardSpacing) {
                            ForEach(ranked(BodyBiomarkerSpec.rows, in: state), id: \.self) { spec in
                                let marker = marker(spec, in: state)
                                BodyMarkerLink(spec: spec) {
                                    SomaTrendRow(
                                        LocalizedStringResource(stringLiteral: marker.title),
                                        value: marker.value.map { marker.unit.isEmpty ? $0 : "\($0) \(marker.unit)" },
                                        status: marker.status.reading,
                                        cue: marker.cue.map { LocalizedStringResource(stringLiteral: $0) },
                                        values: marker.days,
                                        band: marker.band,
                                        hue: spec.hue,
                                        chart: spec.sumsPerDay ? .bars : .line
                                    )
                                }
                            }
                        }
                    }

                    let rhythmTiles = RhythmMobilityTile.shown(rhythmMobility)
                    if !rhythmTiles.isEmpty || glucose != nil {
                        BodySection("Rhythm and balance") {
                            VStack(spacing: metrics.cardSpacing) {
                                if !rhythmTiles.isEmpty {
                                    BodyRhythmMobilityTiles(tiles: rhythmTiles, readings: rhythmMobility)
                                }
                                if let glucose {
                                    BodyGlucoseTile(tile: glucose)
                                }
                            }
                        }
                        .id("rhythm")
                    }

                    BodySection("Lab") {
                        BodyLabTiles()
                    }
                    .id("lab")

                    BodySection("Fitness age") {
                        BodyFitnessAgeCard(age: page.age)
                    }

                    BodyMoreRows(vo2Max: page.vo2Max)
                }
            }
            .padding(.horizontal, metrics.pagePadding)
            .padding(.bottom, metrics.pagePadding)
            .frame(maxWidth: metrics.pageMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .softScrollEdges()
#if DEBUG
        .task {
            // `-longevity.metric mobility` (or afib, rhythm, oral) pushes that page.
            let metrics: [String: MetricRoute] = ["mobility": .mobility, "afib": .afibBurden, "rhythm": .rhythmEvents, "oral": .oral]
            if let name = UserDefaults.standard.string(forKey: "longevity.metric"), let route = metrics[name], router.longevityPath.isEmpty {
                router.longevityPath.append(route)
            }
            // `-longevity.metric cycle` pushes the cycle page.
            if UserDefaults.standard.string(forKey: "longevity.metric") == "cycle", router.longevityPath.isEmpty {
                router.longevityPath.append(HomeRoute.cycle)
            }
            // `-longevity.scroll lab` (or rhythm) brings that section into view, for screenshots.
            if let section = UserDefaults.standard.string(forKey: "longevity.scroll"), ["lab", "rhythm"].contains(section) {
                try? await Task.sleep(for: .milliseconds(1200))
                scroller.scrollTo(section, anchor: .top)
            }
        }
#endif
        }
        .aspectWash(.body)
        .task { await cache.loadBody(health) }
        .task { rhythmMobility = await health.rhythmMobility() }
        .task { glucose = GlucoseTile.make(samples: await health.glucoseFortnight()) }
        .somaRefreshable {
            await cache.loadBody(health, force: true)
            rhythmMobility = await health.rhythmMobility()
            glucose = GlucoseTile.make(samples: await health.glucoseFortnight())
        }
    }

    @Environment(AppRouter.self) private var router

    /// Fitness age opens the biological age page; the two Health readings open
    /// their page in the Vault.
    private func openStat(_ stat: SomaStat) {
        switch stat.id {
        case "Fitness age":
            router.longevityPath.append(LabRoute.biologicalAge)
        case "Lean mass":
            open(.leanBodyMass)
        case "VO2 max":
            open(.vo2Max)
        default:
            break
        }
    }

    private func open(_ spec: BodyBiomarkerSpec) {
        guard let metric = HealthMetricCatalog.metric(for: spec.identifier) else { return }
        router.longevityPath.append(VaultRoute.dataType(BodyDataType(metric)))
    }

    private func marker(_ spec: BodyBiomarkerSpec, in state: LongevityBodyState) -> BodyBiomarker {
        state.markers[spec] ?? BodyBiomarkers.make(spec, readings: [], now: .now, calendar: .current)
    }

    /// What moved first: the full list, ordered by how far each reading moved
    /// from its usual, Soma's order kept among equals.
    private func ranked(_ specs: [BodyBiomarkerSpec], in state: LongevityBodyState) -> [BodyBiomarkerSpec] {
        InsightEngine.sortedBySeverity(specs) { state.markers[$0]?.insight.severity ?? 0 }
    }
}

/// A tile or row that opens its reading's page in the Vault: the chart over
/// a chosen span and every record behind it.
private struct BodyMarkerLink<Label: View>: View {
    let spec: BodyBiomarkerSpec
    @ViewBuilder let label: Label

    var body: some View {
        if let metric = HealthMetricCatalog.metric(for: spec.identifier) {
            NavigationLink(value: VaultRoute.dataType(BodyDataType(metric))) {
                label.contentShape(.rect)
            }
            .zoomSource(VaultRoute.dataType(BodyDataType(metric)))
            .buttonStyle(.somaGlassPress)
        } else {
            label
        }
    }
}

/// The Rhythm and balance section: AFib History and the heart notifications
/// as one tile, walking steadiness and falls as the other. Each opens its
/// page, and each is left out when its readings are empty.
private struct BodyRhythmMobilityTiles: View {
    let tiles: [RhythmMobilityTile]
    let readings: RhythmMobilityReadings

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let rhythm = readings.rhythm()
        let mobility = readings.mobility()

        VStack(spacing: theme.metrics.cardSpacing) {
            ForEach(tiles, id: \.self) { tile in
                switch tile {
                case .heartRhythm:
                    let latestWeek = rhythm.weeks.last
                    link(latestWeek == nil ? .rhythmEvents : .afibBurden) {
                        SomaTrendRow(
                            "Heart rhythm",
                            value: latestWeek.map { "\(HeartRhythmSummary.burdenText($0.burden)) in AFib" }
                                ?? "\(rhythm.events.count) \(rhythm.events.count == 1 ? "notification" : "notifications")",
                            cue: LocalizedStringResource(stringLiteral: latestWeek == nil ? "This year" : "AFib History, latest week"),
                            values: rhythm.weeks.suffix(30).map { Optional($0.burden * 100) },
                            hue: .heart,
                            chart: .bars
                        )
                    }
                case .mobility:
                    link(.mobility) {
                        SomaTrendRow(
                            "Mobility",
                            value: mobility.steadiness.map { "\(Int(($0 * 100).rounded()))% steady" }
                                ?? "\(mobility.fallsLast12Months) \(mobility.fallsLast12Months == 1 ? "fall" : "falls")",
                            status: mobility.steadiness == nil ? .none
                                : mobility.level == .ok ? .normal : .below,
                            cue: mobility.fallsLast12Months > 0
                                ? LocalizedStringResource(stringLiteral: "\(mobility.fallsLast12Months) \(mobility.fallsLast12Months == 1 ? "fall" : "falls") this year")
                                : nil,
                            values: mobility.history.suffix(30).map { Optional($0.value * 100) },
                            hue: .mobility
                        )
                    }
                }
            }
        }
    }

    private func link<Label: View>(_ route: MetricRoute, @ViewBuilder label: () -> Label) -> some View {
        NavigationLink(value: route) {
            label().contentShape(.rect)
        }
        .zoomSource(route)
        .buttonStyle(.somaGlassPress)
    }

}

/// The Glucose tile under the rhythm tiles: a monitor's time in range over
/// the fortnight, a bar for each of the last seven days, opening the
/// monitor's page (`LabRoute.cgm`). Only drawn when Health holds a
/// continuous trace (``GlucoseTile``).
private struct BodyGlucoseTile: View {
    let tile: GlucoseTile

    var body: some View {
        NavigationLink(value: LabRoute.cgm) {
            SomaTrendRow(
                "Glucose",
                value: tile.timeInRange.map { "\(Int(($0 * 100).rounded()))% in range" },
                cue: "Time in range, 14 days",
                values: tile.days,
                hue: .nutrition,
                chart: .bars
            )
            .contentShape(.rect)
        }
        .zoomSource(LabRoute.cgm)
        .buttonStyle(.somaGlassPress)
    }
}

/// The Lab section: blood, urine, gut, genome and imaging and functional tests,
/// each a card with its latest date and a headline (markers to watch,
/// variants read, tests on file) that opens its page. Owner's call,
/// 2026-10-24: a tile per kind of test here, and each one can also be added
/// from Track's add grid.
private struct BodyLabTiles: View {
    @Environment(\.somaTheme) private var theme

    private var blood: BloodPanelStore { .shared }
    private var urine: UrinePanelStore { .shared }
    private var genome: GenomeStore { .shared }
    private var functional: FunctionalResultStore { .shared }
    private var stool: StoolPanelStore { .shared }

    var body: some View {
        VStack(spacing: theme.metrics.cardSpacing) {
            tile(.bloodPanel, symbol: "drop.fill", title: "Blood", hue: .vitals,
                 date: blood.latest?.date.labCompactDay, caption: blood.latest.map { "\($0.markers.count) markers" },
                 value: blood.latest.map { panel in "\(panel.markers.filter { LabMath.reading($0).isOutside }.count)" },
                 unit: "to watch",
                 bars: blood.panels.prefix(7).reversed().map { panel in Double(panel.markers.filter { LabMath.reading($0).isOutside }.count) })
            tile(.urine, symbol: "flask.fill", title: "Urine", hue: .nutrition,
                 date: urine.latest?.date.labCompactDay,
                 caption: urine.latest.map { $0.kind == .dipstick ? "Strip, approximate" : "\($0.values.count) markers" },
                 value: urine.latest.map { "\($0.flagged.count)" },
                 unit: "to watch",
                 bars: urine.panels.prefix(7).reversed().map { Double($0.flagged.count) })
            // Green like the Gut aspect: nutrition is the health hue nearest it.
            tile(.stool, symbol: "leaf.fill", title: "Gut", hue: .nutrition,
                 date: stool.latest?.date.labCompactDay,
                 caption: stool.latest.map { $0.kind == .microbiomeKit ? "Microbiome kit" : "\($0.values.count) markers" },
                 value: stool.latest.map { "\($0.flagged.count)" },
                 unit: "to watch",
                 bars: stool.panels.prefix(7).reversed().map { Double($0.flagged.count) })
            tile(.genome, symbol: "point.3.filled.connected.trianglepath.dotted", title: "Genome", hue: .symptoms,
                 date: genome.result?.importedAt.labCompactDay,
                 caption: genome.result.map { "\($0.provider.title), \($0.snpsRead.formatted(.number.notation(.compactName))) read" },
                 value: genome.result.map { "\($0.found.count)" },
                 unit: "variants",
                 bars: [])
            // One card for the six imaging and functional tests: each is
            // rare and one off, so six cards would bury blood and urine.
            tile(.functional, symbol: "figure.strengthtraining.functional", title: "Tests", hue: .activity,
                 date: functional.latest?.date.labCompactDay,
                 caption: functional.latest.map { $0.kind.title },
                 value: functional.latest.map { _ in "\(functional.kinds.count)" },
                 unit: functional.kinds.count == 1 ? "test" : "tests",
                 bars: [])
        }
    }

    private func tile(_ route: LabRoute, symbol: String, title: LocalizedStringResource, hue: SomaHealthHue,
                      date: String?, caption: String?, value: String?, unit: String, bars: [Double?]) -> some View {
        NavigationLink(value: route) {
            // The same row as the biomarkers above it (owner, 2026-10-25):
            // the title, what the latest test holds, when it was, and the
            // tests over time on the trailing edge.
            SomaTrendRow(
                title,
                value: value.map { "\($0) \(unit)" },
                cue: LocalizedStringResource(stringLiteral: caption.map { text in date.map { "\(text) \u{00B7} \($0)" } ?? text } ?? "Nothing added yet"),
                // A shape needs a few tests: one or two draw as a block.
                values: bars.count >= 3 ? bars : [],
                hue: hue,
                chart: .bars
            )
            .contentShape(.rect)
        }
        .zoomSource(route)
        .buttonStyle(.somaGlassPress)
    }
}

/// A titled group on the Body lens, the way the reference design heads "Other Biomarkers".
private struct BodySection<Content: View>: View {
    let title: LocalizedStringResource
    let content: Content

    @Environment(\.somaTheme) private var theme

    init(_ title: LocalizedStringResource, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.metrics.cardSpacing) {
            Text(title)
                .somaFont(theme.typography.headline)
                .foregroundStyle(theme.colors.inkPrimary.color)
                .accessibilityAddTraits(.isHeader)
            content
        }
    }
}

/// Fitness age over visits. Built from the pod, so it is empty until the
/// first visit, with your age already drawn as the line to read it against.
private struct BodyFitnessAgeCard: View {
    let age: Int?

    var body: some View {
        TileLink(value: PulseRoute.category("Body Measurements")) {
            SomaChartCard(
                eyebrow: "Fitness age",
                value: nil,
                unit: "give or take",
                note: "Your first visit to the pod draws this."
            ) {
                BodyFitnessAgeFrame(age: age)
            }
        }
    }
}

/// Every muscle front and back, filled by how rested it is, as the reference design's Muscle
/// Groups page draws it, with the three states as a legend under the figure.
/// Read from the last month of workouts (``MuscleFreshness``) with the rest
/// of the lens, so it fills in the same moment as the tiles.
private struct BodyMapCard: View {
    let states: [SomaMuscle: SomaMuscleState]

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics

        VStack(alignment: .leading, spacing: metrics.cardSpacing) {
            Text("Muscle freshness")
                .somaFont(theme.typography.cardTitle)
                .fontWeight(.semibold)
                .foregroundStyle(theme.colors.inkPrimary.color)
            SomaMuscleMap(states)
                .frame(maxWidth: .infinity)
            // Roomy, or packed tight when the card shares a row: a column
            // of the unfolded screen of a foldable broke "Recovered" in two.
            ViewThatFits(in: .horizontal) {
                legend(isTight: false)
                legend(isTight: true)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(metrics.cardPadding)
        .background(theme.colors.surface.color, in: .rect(cornerRadius: metrics.cardCornerRadius, style: .continuous))
    }

    private func legend(isTight: Bool) -> some View {
        HStack(spacing: isTight ? theme.metrics.spaceXS : theme.metrics.cardSpacing) {
            ForEach([SomaMuscleState.recovered, .fatigued, .depleted], id: \.self) { state in
                BodyLegendChip(state: state, isTight: isTight)
            }
        }
    }
}

/// A dot and a word, as the reference design's filter chips under the figure.
private struct BodyLegendChip: View {
    let state: SomaMuscleState
    var isTight = false

    @Environment(\.somaTheme) private var theme

    var body: some View {
        HStack(spacing: theme.metrics.spaceS) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(state.title)
                .somaFont(theme.typography.caption)
                .foregroundStyle(theme.colors.inkPrimary.color)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, isTight ? theme.metrics.spaceS : theme.metrics.spaceM)
        .padding(.vertical, theme.metrics.spaceS)
        .background(theme.colors.surfaceRecessed.color, in: .capsule)
    }

    private var color: Color {
        switch state {
        case .recovered: theme.colors.statusNormal.color
        case .fatigued: theme.colors.statusOut.color
        case .depleted: theme.colors.statusAlert.color
        case .none: theme.colors.inkSecondary.color
        }
    }
}

/// The rows under the cards: Cardio and Strength, the blood panel, the lab
/// pages, and mouth and teeth.
private struct BodyMoreRows: View {
    let vo2Max: String?

    @Environment(\.somaTheme) private var theme
    @State private var isShowingBloodPanel = false

    private struct Row: Identifiable {
        let id: String
        let title: String
        let detail: String?
        let route: LongevityRoute?
        /// A Body lab page (lane 4), pushed through `journeyDestinations()`.
        var lab: LabRoute? = nil
        /// A metric page, pushed the same way.
        var metric: MetricRoute? = nil
        /// A page Today also opens (the cycle), pushed the same way.
        var home: HomeRoute? = nil
    }

    private var rows: [Row] {
        [
            Row(id: "cardio", title: "Cardio", detail: "VO2 max \(vo2Max ?? "-")", route: .cardio),
            Row(id: "strength", title: "Strength", detail: "Grip -", route: .strength),
            Row(id: "bioage", title: "Biological age", detail: nil, route: nil, lab: .biologicalAge),
            Row(id: "blood", title: "Blood panel", detail: BloodPanelStore.shared.latest?.date.labDay ?? "-", route: nil, lab: .bloodPanel),
            Row(id: "risk", title: "Cardiometabolic risk", detail: nil, route: nil, lab: .risk),
            Row(id: "ledger", title: "Longevity ledger", detail: nil, route: nil, lab: .ledger),
            Row(id: "measurements", title: "Body measurements", detail: nil, route: nil, lab: .measurements),
            Row(id: "weight", title: "Weight", detail: nil, route: nil, lab: .weight),
            Row(id: "lean", title: "Lean body mass", detail: nil, route: nil, lab: .leanMass),
            Row(id: "pressure", title: "Blood pressure", detail: nil, route: nil, lab: .bloodPressure),
            Row(id: "glucose", title: "Blood glucose", detail: nil, route: nil, lab: .glucose),
            Row(id: "oral", title: "Mouth and teeth", detail: nil, route: nil, metric: .oral),
            Row(id: "skin", title: "Skin report", detail: nil, route: nil, lab: .skin),
        ] + cycleRow
    }

    /// The cycle, only for a person who tracks one (`CycleVisibility`).
    private var cycleRow: [Row] {
        CycleVisibility.tracksCycle ? [Row(id: "cycle", title: "Cycle", detail: nil, route: nil, home: .cycle)] : []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.metrics.browseHeadingSpacing) {
            Text("More")
                .somaFont(theme.typography.headline)
                .foregroundStyle(theme.colors.inkPrimary.color)
                .accessibilityAddTraits(.isHeader)

            SomaBrowseGroup(rows, hasGlyphs: false) { row in
                if let route = row.route {
                    NavigationLink(value: route) {
                        SomaBrowseRow(title: row.title, detail: row.detail)
                            .contentShape(.rect)
                            .zoomSource(route)
                    }
                    .buttonStyle(.plain)
                } else if let lab = row.lab {
                    NavigationLink(value: lab) {
                        SomaBrowseRow(title: row.title, detail: row.detail)
                            .contentShape(.rect)
                            .zoomSource(lab)
                    }
                    .buttonStyle(.plain)
                } else if let metric = row.metric {
                    NavigationLink(value: metric) {
                        SomaBrowseRow(title: row.title, detail: row.detail)
                            .contentShape(.rect)
                            .zoomSource(metric)
                    }
                    .buttonStyle(.plain)
                } else if let home = row.home {
                    NavigationLink(value: home) {
                        SomaBrowseRow(title: row.title, detail: row.detail)
                            .contentShape(.rect)
                            .zoomSource(home)
                    }
                    .buttonStyle(.plain)
                } else {
                    SomaBrowseRow(title: row.title, detail: row.detail) {
                        isShowingBloodPanel = true
                    }
                }
            }
        }
        .sheet(isPresented: $isShowingBloodPanel) {
            NotWiredPage(
                eyebrow: "Blood panel",
                title: "Your blood panel",
                message: "Blood results are not connected yet. When they are, each panel lands here with its date."
            )
        }
    }
}

#Preview("Longevity body") {
    NavigationStack {
        LongevityBodyView()
    }
    .environment(HealthDashboard())
    .environment(AppRouter())
}
