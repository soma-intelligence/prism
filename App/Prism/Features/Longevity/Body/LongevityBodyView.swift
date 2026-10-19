//
//  LongevityBodyView.swift
//  Prism
//

import SwiftUI
import SomaUI
import HealthExportCore

/// The Longevity tab's Body lens: the three
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

    @State private var page = BodyOverview.make(from: BodyOverviewInputs(now: .now))
    @State private var markers: [BodyBiomarkerSpec: BodyBiomarker] = [:]
    @State private var isBooking = false

    var body: some View {
        let metrics = theme.metrics

        ScrollView {
            VStack(alignment: .leading, spacing: metrics.leadSpacing) {
                // Three numbers, no line under them (owner, 2026-10-03), each a
                // door to its page.
                SomaStatRow([
                    SomaStat("Fitness age", value: nil),
                    SomaStat("Lean mass", value: page.leanMass, unit: "kg", trend: page.leanTrend),
                    SomaStat("VO2 max", value: page.vo2Max, trend: page.vo2Trend),
                ]) { stat in
                    openStat(stat)
                }
                .padding(.top, metrics.heroTopPadding)

                BodySection("Fitness") {
                    LazyVGrid(
                        columns: [GridItem(.flexible(), spacing: metrics.cardSpacing), GridItem(.flexible(), spacing: metrics.cardSpacing)],
                        spacing: metrics.cardSpacing
                    ) {
                        ForEach(ranked(BodyBiomarkerSpec.tiles), id: \.self) { spec in
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
                }

                BodyMapCard()

                BodySection("Biomarkers") {
                    VStack(spacing: metrics.cardSpacing) {
                        ForEach(ranked(BodyBiomarkerSpec.rows), id: \.self) { spec in
                            let marker = marker(spec)
                            BodyMarkerLink(spec: spec) {
                                SomaTrendRow(
                                    LocalizedStringResource(stringLiteral: marker.title),
                                    value: marker.value.map { marker.unit.isEmpty ? $0 : "\($0) \(marker.unit)" },
                                    status: marker.status.reading,
                                    cue: marker.cue.map { LocalizedStringResource(stringLiteral: $0) },
                                    values: marker.days,
                                    band: marker.band,
                                    hue: spec.hue
                                )
                            }
                        }
                    }
                }

                BodySection("From a Soma visit") {
                    VStack(spacing: metrics.cardSpacing) {
                        BodyFitnessAgeCard(age: page.age)
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
                }

                BodyMoreRows(vo2Max: page.vo2Max)
            }
            .padding(.horizontal, metrics.pagePadding)
            .padding(.bottom, metrics.pagePadding)
            .frame(maxWidth: metrics.pageMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .aspectWash(.body)
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $isBooking) {
            NotWiredPage(
                eyebrow: "Next visit",
                title: "Book a visit",
                message: "Booking a Soma visit isn’t connected yet. When it is, this is where you pick a time."
            )
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

    private func marker(_ spec: BodyBiomarkerSpec) -> BodyBiomarker {
        markers[spec] ?? BodyBiomarkers.make(spec, readings: [], now: .now, calendar: .current)
    }

    /// What moved first: the full list, ordered by how far each reading moved
    /// from its usual, Soma's order kept among equals.
    private func ranked(_ specs: [BodyBiomarkerSpec]) -> [BodyBiomarkerSpec] {
        InsightEngine.sortedBySeverity(specs) { markers[$0]?.insight.severity ?? 0 }
    }

    private func cue(_ spec: BodyBiomarkerSpec) -> LocalizedStringResource? {
        markers[spec]?.cue.map { LocalizedStringResource(stringLiteral: $0) }
    }

    private func tone(_ spec: BodyBiomarkerSpec) -> SomaCueTone {
        markers[spec]?.insight.tone.cueTone ?? .neutral
    }

    private func load() async {
        guard let source = await health.prepare(BodyOverviewInputs.metrics + BodyBiomarkers.metrics) else { return }
        async let overview = BodyOverviewInputs.read(from: source, now: .now, calendar: .current)
        async let readings = BodyBiomarkers.read(from: source, now: .now, calendar: .current)
        page = BodyOverview.make(from: await overview)
        let all = await readings
        var built: [BodyBiomarkerSpec: BodyBiomarker] = [:]
        for spec in BodyBiomarkerSpec.allCases {
            built[spec] = BodyBiomarkers.make(spec, readings: all[spec] ?? [], now: .now, calendar: .current)
        }
        markers = built
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
                note: "Comes from a Soma visit."
            ) {
                BodyFitnessAgeFrame(age: age)
            }
        }
    }
}

/// Every muscle front and back, filled by how rested it is, with the three
/// states as a legend under the figure.
/// Read from the last month of workouts (``MuscleFreshness``).
private struct BodyMapCard: View {
    @Environment(HealthDashboard.self) private var health
    @Environment(\.somaTheme) private var theme
    @State private var states: [SomaMuscle: SomaMuscleState] = MuscleFreshness.map([:])

    var body: some View {
        let metrics = theme.metrics

        VStack(alignment: .leading, spacing: metrics.cardSpacing) {
            Text("Muscle freshness")
                .somaFont(theme.typography.cardTitle)
                .fontWeight(.semibold)
                .foregroundStyle(theme.colors.inkPrimary.color)
            SomaMuscleMap(states)
                .frame(maxWidth: .infinity)
            HStack(spacing: metrics.cardSpacing) {
                ForEach([SomaMuscleState.recovered, .fatigued, .depleted], id: \.self) { state in
                    BodyLegendChip(state: state)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(metrics.cardPadding)
        .background(theme.colors.surface.color, in: .rect(cornerRadius: metrics.cardCornerRadius, style: .continuous))
        .task {
            guard let history = await health.fitnessHistory(days: Int(MuscleFreshness.days)) else { return }
            states = MuscleFreshness.map(MuscleFreshness.states(history.workouts, now: .now))
        }
    }
}

/// A dot and a word, a legend chip under the figure.
private struct BodyLegendChip: View {
    let state: SomaMuscleState

    @Environment(\.somaTheme) private var theme

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(state.title)
                .somaFont(theme.typography.caption)
                .foregroundStyle(theme.colors.inkPrimary.color)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
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
            Row(id: "strength", title: "Strength", detail: "Grip -", route: .strength),
            Row(id: "visit", title: "Visit results", detail: "-", route: nil, lab: .visit),
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
