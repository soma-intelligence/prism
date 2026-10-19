//
//  WeatherPage.swift
//  Prism
//

import SwiftUI
import SomaUI
import MapKit
import HealthExportCore
import HealthScoring

/// Weather: the city, the forecast and what it does to you.
///
/// The app has no WeatherKit entitlement and no other forecast source is
/// allowed yet, so the forecast half of the page is its honest empty state:
/// it says what fills it. What is real is drawn: the city you picked, and
/// your time in daylight from Apple Health against your usual.
struct WeatherPage: View {
    @Environment(HealthDashboard.self) private var health
    @Environment(\.somaTheme) private var theme
    @State private var places = SleepPlaceStore.shared
    @State private var picking = false
    @State private var daylight: [Double?] = []

    private static let daylightMetric = "HKQuantityTypeIdentifierTimeInDaylight"

    var body: some View {
        let type = theme.typography
        let colors = theme.colors
        let today = daylight.last ?? nil
        let usual = ScoringUsual.of(Array(daylight.dropLast()), spreadFloor: 5)

        ScorePageScaffold(aspect: .sleep, title: "Weather") {
            HStack {
                Button {
                    picking = true
                } label: {
                    HStack(spacing: 4) {
                        Text(places.weatherCity?.name ?? "Choose a city")
                        Image(systemName: "chevron.down").imageScale(.small)
                    }
                    .somaFont(type.body)
                    .foregroundStyle(colors.inkPrimary.color)
                    .padding(.horizontal, 12)
                    .frame(minHeight: theme.metrics.chromeCapsuleHeight)
                    .background(Capsule().fill(colors.surface.color))
                }
                .buttonStyle(SomaGlassPressStyle())
                Spacer()
                Text(Date().formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute()))
                    .somaFont(type.caption)
                    .foregroundStyle(colors.inkSecondary.color)
            }
            .padding(.top, theme.metrics.heroTopPadding)
            ScoreFigure(value: nil, unit: "°C now")
            ScoreHead(headline: "No forecast source yet.",
                      reason: "Soma reads the weather once a forecast service is connected.",
                      aside: "Until then this page shows only what your own body recorded.")
            ScoreStats(stats: [
                SomaStat("Air quality", value: nil),
                SomaStat("UV at noon", value: nil),
                SomaStat("Pollen", value: nil),
            ])
            SomaCard {
                VStack(alignment: .leading, spacing: 8) {
                    SomaCardHeader("Hour by hour", caption: "Tonight into tomorrow")
                    ScoreEmptyPlot(message: "The hours draw here from a forecast. None is connected yet.")
                }
            }
            ScoreUsualCard(title: "What it does to you", caption: "From your own history", aspect: .sleep, lines: [
                ScoreMath.usualLine(title: "Daylight outside", value: today, usual: usual, worse: .lower,
                                    format: { ScoreMath.number($0) }, unit: " min",
                                    empty: "Apple Watch counts it on its own"),
            ])
            SomaCard {
                VStack(alignment: .leading, spacing: 8) {
                    SomaCardHeader("Nights by outside temperature", caption: "Needs a forecast source")
                    ScoreEmptyPlot(message: "Your nights sort by outside temperature once a weather source is connected.")
                }
            }
            ScoreMoveCard(move: ScorePages.Move(eyebrow: "Tomorrow", title: "Outside before 09:00",
                                                detail: "Twenty minutes of morning light keeps your body clock early.",
                                                remindAt: 8.5), aspect: .sleep)
        }
        .sheet(isPresented: $picking) {
            CityPickerSheet(eyebrow: "Weather", title: "Choose a city", current: places.weatherCity,
                            recent: places.recentPlaces,
                            footnote: "A city you pick here changes the weather you see, never where your nights are counted.") {
                places.weatherCity = $0
            }
        }
        .task { await loadDaylight() }
    }

    private func loadDaylight() async {
        guard let source = await health.prepare([Self.daylightMetric]),
              let metric = HealthMetricCatalog.metric(for: Self.daylightMetric) else { return }
        let calendar = Calendar.current
        let now = Date()
        var values: [Double?] = []
        for day in SomaScoresReader.dayStarts(days: 15, now: now, calendar: calendar) {
            let end = min(now, calendar.date(byAdding: .day, value: 1, to: day) ?? now)
            values.append((try? await source.total(metric, from: day, to: end))?.value)
        }
        daylight = values
    }
}

/// Choosing a place with Apple Maps' search: the current choice, places you
/// slept lately, and search results as you type.
struct CityPickerSheet: View {
    let eyebrow: String
    let title: LocalizedStringResource
    let current: SleepPlaceStore.Place?
    let recent: [SleepPlaceStore.Place]
    var footnote: LocalizedStringResource?
    let pick: (SleepPlaceStore.Place?) -> Void

    @State private var query = ""
    @State private var results: [SleepPlaceStore.Place] = []
    @State private var searching = false
    @Environment(\.somaTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    init(eyebrow: String, title: LocalizedStringResource, current: SleepPlaceStore.Place?,
         recent: [SleepPlaceStore.Place], footnote: LocalizedStringResource? = nil,
         pick: @escaping (SleepPlaceStore.Place?) -> Void) {
        self.eyebrow = eyebrow
        self.title = title
        self.current = current
        self.recent = recent
        self.footnote = footnote
        self.pick = pick
    }

    var body: some View {
        let type = theme.typography
        let colors = theme.colors

        ScoreSheet(eyebrow: eyebrow, title: title) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(colors.inkSecondary.color)
                TextField("Search a city", text: $query)
                    .somaFont(type.body)
                    .autocorrectionDisabled()
                    .onSubmit { Task { await search() } }
            }
            .padding(.horizontal, 12)
            .frame(minHeight: theme.metrics.browseRowMinHeight)
            .background(RoundedRectangle(cornerRadius: theme.metrics.browseGroupCornerRadius, style: .continuous)
                .fill(colors.surface.color))

            if !results.isEmpty {
                section("Results", results)
            } else if searching {
                ScoreFootnote(text: "Searching Apple Maps.")
            }
            if let current {
                section("Chosen", [current], clears: true)
            }
            let others = recent.filter { $0 != current }
            if !others.isEmpty {
                section("Where you slept lately", others)
            }
            if let footnote {
                ScoreFootnote(text: footnote)
            }
        }
        .task(id: query) {
            guard query.count >= 2 else { results = []; return }
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await search()
        }
    }

    private func section(_ heading: String, _ places: [SleepPlaceStore.Place], clears: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(heading)
                .somaFont(theme.typography.eyebrow)
                .textCase(.uppercase)
                .foregroundStyle(theme.colors.inkSecondary.color)
            SomaBrowseGroup(places, hasGlyphs: false) { place in
                SomaBrowseRow(title: place.name, detail: clears ? "Clear" : nil, opensSomething: false, action: {
                    pick(clears ? nil : place)
                    dismiss()
                })
            }
        }
    }

    private func search() async {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = .address
        searching = true
        defer { searching = false }
        guard let response = try? await MKLocalSearch(request: request).start() else {
            results = []
            return
        }
        var seen: Set<String> = []
        results = response.mapItems.compactMap { item -> SleepPlaceStore.Place? in
            let name = item.addressRepresentations?.cityName ?? item.name
            guard let name, seen.insert(name).inserted else { return nil }
            let coordinate = item.location.coordinate
            return SleepPlaceStore.Place(name: name, latitude: coordinate.latitude, longitude: coordinate.longitude)
        }
    }
}
