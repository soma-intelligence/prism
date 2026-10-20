//
//  LongevityBodyView.swift
//  Prism
//

import SwiftUI
import SomaUI
import HealthExportCore

/// The Longevity tab's Body lens: the three numbers that sum the body up,
/// then every reading the wearables give as a tile or a row with its last
/// thirty days: heart and fitness, movement, walking, muscle freshness, the
/// biomarkers, and the pages further in.
///
/// Few words on purpose (owner, 2026-10-03): each reading says its value,
/// where it sits, a cue of a few words on what that means, and the line
/// beside it drawn over the usual band. Tiles and rows are ordered by how
/// much each moved (``InsightEngine``), so what moved comes first. Prism reads
/// wearables (owner, 2026-10-19): nothing here waits on a visit.
///
/// It draws no stack and no top bar: the Longevity page hosts both, and maps
/// the ``LongevityRoute`` values the rows push.
struct LongevityBodyView: View {
    @Environment(HealthDashboard.self) private var health
    @Environment(\.somaTheme) private var theme

    /// What the lens drew the last time, kept on the device, so it opens on
    /// its numbers rather than on dashes (``LongevitySnapshotStore``).
    @State private var kept = LongevitySnapshotStore.shared.body
    /// This opening's read, once it lands. The numbers roll to it.
    @State private var fresh: BodyLensSnapshot?

    private var shown: LongevityShown<BodyLensSnapshot> { LongevityShown(kept: kept, fresh: fresh) }
    private var lens: BodyLensSnapshot { shown.value ?? .empty() }
    private var page: BodyOverview { lens.page }
    private var sex: BodyFitnessAge.Sex { lens.sex }
    private var markers: [BodyBiomarkerSpec: BodyBiomarker] { lens.markers }

    var body: some View {
        let metrics = theme.metrics
        let updated = shown.updated(now: .now)

        SomaPageScroll {
            VStack(alignment: .leading, spacing: metrics.leadSpacing) {
                // Three numbers, no line under them (owner, 2026-10-03), each a
                // door to its page, under the quiet "Updated" line while they
                // are kept ones.
                SomaUpdatedHeader(updated) {
                    SomaStatRow([
                        SomaStat(
                            "Fitness age",
                            value: page.fitnessAge.value,
                            cue: page.fitnessAge.cue.map { LocalizedStringResource(stringLiteral: $0) },
                            cueTone: page.fitnessAge.isGood ? .good : .neutral
                        ),
                        SomaStat("Lean mass", value: page.leanMass, unit: "kg", trend: page.leanTrend),
                        SomaStat("VO2 max", value: page.vo2Max, trend: page.vo2Trend),
                    ]) { stat in
                        openStat(stat)
                }
                .padding(.top, metrics.heroTopPadding)
                }

                BodySection("Heart and fitness") {
                    BodyTileGrid {
                        NavigationLink(value: LabRoute.biologicalAge) {
                            BodyFitnessAgeTile(stat: page.fitnessAge, days: fitnessAgeDays)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.somaGlassPress)
                        tiles(ranked(BodyBiomarkerSpec.tiles))
                    }
                }

                BodySection("Movement") {
                    BodyTileGrid { tiles(ranked(BodyBiomarkerSpec.movement)) }
                }

                // Shown once the read has landed, with only the readings
                // Health holds: deciding before would draw every tile and
                // then take most of them away.
                let walking = ranked(BodyBiomarkerSpec.walking).filter(hasReadings)
                if !walking.isEmpty {
                    BodySection("Walking") {
                        BodyTileGrid { tiles(walking) }
                    }
                    .transition(.opacity)
                }

                SomaMuscleFreshness(lens.muscles)

                BodyBiomarkersSection(specs: ranked(BodyBiomarkerSpec.rows), marker: marker)

                BodyMoreRows(vo2Max: page.vo2Max)
            }
            .padding(.horizontal, metrics.pagePadding)
            .padding(.bottom, metrics.pagePadding)
            .frame(maxWidth: metrics.pageMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .aspectWash(.body)
        .task { await load(force: false) }
        .refreshable { await load(force: true) }
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Environment(AppRouter.self) private var router

    /// One tile per reading, each a door to its page in the Vault.
    @ViewBuilder
    private func tiles(_ specs: [BodyBiomarkerSpec]) -> some View {
        ForEach(specs, id: \.self) { spec in
            let marker = marker(spec)
            BodyMarkerLink(spec: spec) {
                SomaTrendTile(
                    LocalizedStringResource(stringLiteral: marker.title),
                    value: marker.value,
                    unit: marker.unit.isEmpty ? nil : marker.unit,
                    status: marker.status.reading,
                    cue: marker.cue.map { LocalizedStringResource(stringLiteral: $0) },
                    values: marker.days,
                    band: marker.band,
                    hue: spec.hue
                )
            }
        }
    }

    /// Fitness age day by day, read off each day's VO2 max: the same curve
    /// the stat reads, so the tile's line and the number agree.
    private var fitnessAgeDays: [Double?] {
        marker(.vo2Max).days.map { day in day.map { Double(BodyFitnessAge.estimate(vo2Max: $0, sex: sex)) } }
    }

    private func hasReadings(_ spec: BodyBiomarkerSpec) -> Bool {
        markers[spec].map { $0.value != nil || $0.days.contains { $0 != nil } } ?? false
    }

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

    private func marker(_ spec: BodyBiomarkerSpec) -> BodyBiomarker {
        markers[spec] ?? BodyBiomarkers.make(spec, readings: [], now: .now, calendar: .current)
    }

    /// What moved first: the full list, ordered by how far each reading moved
    /// from its usual, Soma's order kept among equals.
    private func ranked(_ specs: [BodyBiomarkerSpec]) -> [BodyBiomarkerSpec] {
        InsightEngine.sortedBySeverity(specs) { markers[$0]?.insight.severity ?? 0 }
    }

    /// Reads Health, or takes the read kept from the last minute, with the
    /// last month of workouts for muscle freshness; then rolls the numbers
    /// on screen to it and keeps it for the next opening. Nothing changes
    /// when Health could not be read: the kept numbers stay.
    private func load(force: Bool) async {
        async let read = BodyLensCache.shared.read(health: health, force: force)
        let muscles = await muscleReadings()
        guard let read = await read else { return }
        let snapshot = BodyLensSnapshot(
            page: BodyOverview.make(from: read.inputs),
            sex: read.inputs.sex,
            markers: read.markers,
            muscles: muscles ?? lens.muscles
        )
        withAnimation(reduceMotion ? nil : theme.motion.numberRoll) { fresh = snapshot }
        LongevitySnapshotStore.shared.save(body: snapshot)
    }

    /// Muscle freshness from the last month of workouts. Nil when Health
    /// could not be read.
    private func muscleReadings() async -> [SomaMuscleReading]? {
#if DEBUG
        if EnvironmentReport.usesPreview { return MuscleFreshness.preview }
#endif
        guard let history = await health.fitnessHistory(days: Int(MuscleFreshness.days)) else { return nil }
        return MuscleFreshness.readings(history.workouts, now: .now)
    }
}

/// The reading cards, one to a row on a phone (each sets its value beside
/// its line, which needs the width), two or more side by side where the
/// page is wide enough.
private struct BodyTileGrid<Content: View>: View {
    @ViewBuilder let content: Content

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let spacing = theme.metrics.cardSpacing
        LazyVGrid(columns: [GridItem(.adaptive(minimum: theme.metrics.bodyReadingCardMinWidth), spacing: spacing)], spacing: spacing) {
            content
        }
    }
}

/// The biomarkers as quiet rows on one card, each the same height (its
/// name, where it sits, its month as a small line, the value), and one way
/// to add to them: a blood test read on the phone, or a reading written to
/// Health where Health lets an app write it.
private struct BodyBiomarkersSection: View {
    let specs: [BodyBiomarkerSpec]
    let marker: (BodyBiomarkerSpec) -> BodyBiomarker

    @Environment(\.somaTheme) private var theme
    @State private var adding: BodyAddition?

    var body: some View {
        VStack(alignment: .leading, spacing: theme.metrics.cardSpacing) {
            HStack(alignment: .center) {
                Text("Biomarkers")
                    .somaFont(theme.typography.headline)
                    .foregroundStyle(theme.colors.inkPrimary.color)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: theme.metrics.cardSpacing)
                Menu {
                    ForEach(BodyAddition.offered) { addition in
                        Button(addition.title, systemImage: addition.symbol) { adding = addition }
                    }
                } label: {
                    SomaQuietPill("Add", systemImage: "plus")
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .accessibilityLabel("Add to biomarkers")
            }

            SomaBrowseGroup(specs, hasGlyphs: false) { spec in
                let marker = marker(spec)
                BodyMarkerLink(spec: spec) {
                    SomaReadingRow(
                        title: marker.title,
                        caption: marker.cue,
                        value: marker.value,
                        unit: marker.unit.isEmpty ? nil : marker.unit,
                        week: marker.days,
                        aspect: .body,
                        status: marker.status.reading
                    )
                }
            }
        }
        .sheet(item: $adding) { addition in
            switch addition {
            case .bloodTest: AddBloodTestSheet()
            case .log(let kind): LabLogSheet(kind: kind)
            }
        }
    }
}

extension BodyBiomarkerSpec: Identifiable {
    var id: String { rawValue }
}

/// What the Biomarkers section offers to add.
enum BodyAddition: Identifiable, Hashable {
    /// A lab's blood panel: photographed, imported or typed, read on the phone.
    case bloodTest
    /// One reading written to Apple Health.
    case log(LabLogSheet.Kind)

    var id: String {
        switch self {
        case .bloodTest: "blood"
        case .log(let kind): "log.\(kind)"
        }
    }

    var title: LocalizedStringResource {
        switch self {
        case .bloodTest: "Blood test"
        case .log(.weight): "Weight"
        case .log(.pressure): "Blood pressure"
        case .log(.leanMass): "Lean mass"
        case .log(.glucose): "Blood glucose"
        }
    }

    var symbol: String {
        switch self {
        case .bloodTest: "drop"
        case .log(.weight): "scalemass"
        case .log(.pressure): "heart.text.square"
        case .log(.leanMass): "figure.strengthtraining.traditional"
        case .log(.glucose): "chart.line.uptrend.xyaxis"
        }
    }

    /// A blood test always; a reading only where this build writes to
    /// Health, since a reading kept nowhere else would be lost.
    static func offered(canWrite: Bool) -> [BodyAddition] {
        [.bloodTest] + (canWrite ? [.log(.weight), .log(.pressure), .log(.leanMass), .log(.glucose)] : [])
    }

    @MainActor
    static var offered: [BodyAddition] { offered(canWrite: LabHealthWriter.canWrite) }
}

/// Fitness age as a tile: the age, how it sits against yours, and the age
/// day by day as the watch's VO2 max moved.
private struct BodyFitnessAgeTile: View {
    let stat: BodyFitnessAge.Stat
    let days: [Double?]

    var body: some View {
        SomaTrendTile(
            "Fitness age",
            value: stat.value,
            unit: stat.value == nil ? nil : "years",
            status: .none,
            cue: stat.cue.map { LocalizedStringResource(stringLiteral: $0) },
            values: days,
            hue: .activity
        )
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
            .buttonStyle(.somaGlassPress)
        } else {
            label
        }
    }
}

/// A titled group on the Body lens, such as "Other Biomarkers".
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

/// The rows under the cards: Cardio and Strength, the blood panel and the lab
/// pages.
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
    }

    private var rows: [Row] {
        [
            Row(id: "cardio", title: "Cardio", detail: "VO2 max \(vo2Max ?? "-")", route: .cardio),
            Row(id: "strength", title: "Strength", detail: nil, route: .strength),
            Row(id: "bioage", title: "Biological age", detail: nil, route: nil, lab: .biologicalAge),
            Row(id: "blood", title: "Blood panel", detail: BloodPanelStore.shared.latest?.date.labDay ?? "-", route: nil, lab: .bloodPanel),
            Row(id: "risk", title: "Cardiometabolic risk", detail: nil, route: nil, lab: .risk),
            Row(id: "ledger", title: "Longevity ledger", detail: nil, route: nil, lab: .ledger),
            Row(id: "measurements", title: "Body measurements", detail: nil, route: nil, lab: .measurements),
            Row(id: "weight", title: "Weight", detail: nil, route: nil, lab: .weight),
            Row(id: "lean", title: "Lean body mass", detail: nil, route: nil, lab: .leanMass),
            Row(id: "pressure", title: "Blood pressure", detail: nil, route: nil, lab: .bloodPressure),
            Row(id: "glucose", title: "Blood glucose", detail: nil, route: nil, lab: .glucose),
            Row(id: "skin", title: "Skin report", detail: nil, route: nil, lab: .skin),
        ]
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
