//
//  TerritoryPage.swift
//  Prism
//

import SwiftUI
import MapKit
import SomaUI

/// Where this month's walks, runs and rides went: distance, outings and
/// metres climbed, every recorded route on a map with home as a dot, and the
/// places the routes gather into.
///
/// Routes are read only here, and asked for when this page opens. Place names
/// come from Apple's reverse geocoder, which is sent the middle of each place
/// and nothing else; the routes themselves never leave the device.
struct TerritoryPage: View {
    @Environment(\.somaTheme) private var theme

    @State private var routes: [Territory.Route] = []
    @State private var names: [Date: String] = [:]
    @State private var isLoaded = false

    private let reader = FitnessHealthKit()
    private var words: MetricWords { MetricWords() }

    var body: some View {
        let places = Territory.places(routes)
        let home = Territory.home(routes)
        let distance = routes.reduce(0) { $0 + $1.distance }
        let climb = routes.reduce(0) { $0 + $1.climb }
        let month = Date.now.formatted(.dateTime.month(.wide))

        TabPartScaffold(
            aspect: .activity,
            eyebrow: "\(month) so far",
            title: headline(places: places, distance: distance),
            reason: reason(places: places, home: home, distance: distance),
            stats: [
                SomaStat("Distance", value: routes.isEmpty ? nil : words.whole(distance / 1000), unit: "km"),
                SomaStat("Outings", value: routes.isEmpty ? nil : "\(routes.count)"),
                SomaStat("Climbed", value: routes.isEmpty ? nil : words.whole(climb), unit: "m"),
            ]
        ) {
            SomaCard {
                VStack(alignment: .leading, spacing: theme.metrics.cardHeaderSpacing * 2) {
                    SomaCardHeader("Where you went", caption: "Each line is a route you took. The dot is home.")
                    TerritoryMap(routes: routes, home: home)
                }
            }
            if !places.isEmpty {
                MetricRowsCard(eyebrow: "Places this month", rows: places.map { place in
                    MetricRowItem(
                        names[place.id] ?? "A place near \(words.short(place.id))",
                        detail: detail(place),
                        value: "\(words.km(place.distance)) km",
                        id: "\(place.id)"
                    )
                })
            }
            if let loop = places.last?.shortest, places.count > 1 {
                SomaActionCard(
                    eyebrow: "A short one",
                    title: "The \(names[places.last?.id ?? .distantPast] ?? "shortest") loop",
                    detail: "\(words.km(loop.distance)) km, about \(Int((loop.end.timeIntervalSince(loop.start) / 60).rounded())) minutes last time."
                ) {
                    PulseMiniOrb(aspect: .activity, diameter: theme.metrics.miniOrbDiameter)
                }
            }
        }
        .navigationTitle("Territory")
        .task { await load() }
        .refreshable { await load() }
    }

    private func headline(places: [Territory.Place], distance: Double) -> String {
        guard !routes.isEmpty else {
            return isLoaded ? "No routes recorded this month." : "Reading your routes."
        }
        let count = places.count == 1 ? "One place" : "\(places.count) places"
        return "\(count), \(words.whole(distance / 1000)) km of outings."
    }

    private func reason(places: [Territory.Place], home: Territory.Point?, distance: Double) -> String {
        guard !routes.isEmpty else {
            return "An outdoor walk, run or ride with Apple Watch records its route. Each one draws a line here, on this device only."
        }
        var text = "\(routes.count) \(routes.count == 1 ? "outing" : "outings") this month"
        let door = Territory.fromDoor(routes, home: home)
        text += door * 2 > routes.count ? ", most of them from your door." : "."
        if let first = places.first, distance > 0 {
            let share = Int((first.distance / distance * 100).rounded())
            text += " \(names[first.id] ?? "Your busiest place") carried \(share)% of the distance."
        }
        return text
    }

    private func detail(_ place: Territory.Place) -> String {
        let kinds = Dictionary(grouping: place.routes) { FitnessActivities.name($0.activity).lowercased() }
        let parts = kinds.sorted { $0.value.count > $1.value.count }.map { "\($0.value.count) \($0.key)\($0.value.count == 1 ? "" : "s")" }
        let climb = place.climb
        return parts.joined(separator: ", ") + (climb >= 20 ? ", \(words.whole(climb)) m climbed" : "")
    }

    private func load() async {
        let calendar = Calendar.current
        let now = Date()
        let start = calendar.dateInterval(of: .month, for: now)?.start ?? now
        routes = await reader.routes(from: start, to: now)
        isLoaded = true
        for place in Territory.places(routes) where names[place.id] == nil {
            if let name = await TerritoryNames.name(for: place.center) {
                names[place.id] = name
            }
        }
    }
}

/// Names a place from its middle, through Apple's reverse geocoder.
///
/// The middle is an average of workout fixes, so it can sit within metres of
/// a doorstep. It is rounded to 0.01 degree (about a kilometre) before it
/// goes to Apple, the same grid the Environment lens uses; the map keeps the
/// exact middle.
enum TerritoryNames {
    /// What is sent to the geocoder for a place: its middle on the 0.01 degree grid.
    static func lookupCoordinate(for point: Territory.Point) -> (latitude: Double, longitude: Double) {
        CoarseCoordinate.rounded(latitude: point.latitude, longitude: point.longitude)
    }

    static func name(for point: Territory.Point) async -> String? {
        let sent = lookupCoordinate(for: point)
        let location = CLLocation(latitude: sent.latitude, longitude: sent.longitude)
        guard let request = MKReverseGeocodingRequest(location: location),
              let item = try? await request.mapItems.first else { return nil }
        return item.name
    }
}

/// Every route as a line on a map, home as a dot. Interaction is off: this is
/// a picture of the month, and a map that pans under a scrolling page steals
/// the scroll.
private struct TerritoryMap: View {
    let routes: [Territory.Route]
    let home: Territory.Point?

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let hue = theme.aspects[.activity].identity.color

        Group {
            if routes.isEmpty {
                RoundedRectangle(cornerRadius: theme.metrics.chartBarCornerRadius, style: .continuous)
                    .fill(theme.colors.surfaceRecessed.color)
                    .overlay {
                        Text("Your routes draw here.")
                            .somaFont(theme.typography.caption)
                            .foregroundStyle(theme.colors.inkSecondary.color)
                    }
            } else {
                Map(interactionModes: []) {
                    ForEach(routes) { route in
                        MapPolyline(coordinates: route.points.map {
                            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                        })
                        .stroke(hue, lineWidth: theme.metrics.chartLineWidth)
                    }
                    if let home {
                        Annotation("Home", coordinate: CLLocationCoordinate2D(latitude: home.latitude, longitude: home.longitude)) {
                            Circle()
                                .fill(theme.colors.inkPrimary.color)
                                .frame(width: theme.metrics.chartDotDiameter, height: theme.metrics.chartDotDiameter)
                        }
                    }
                }
                .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
                .clipShape(.rect(cornerRadius: theme.metrics.chartBarCornerRadius, style: .continuous))
            }
        }
        .frame(height: theme.metrics.metricMapHeight)
        .accessibilityLabel("Map of this month’s routes")
    }
}

#Preview("Territory") {
    NavigationStack { TerritoryPage() }
        .environment(HealthDashboard())
}
