//
//  Territory.swift
//  Prism
//

import Foundation

/// Where a month of walks, runs and rides went, from the routes the watch
/// recorded.
///
/// Every route is a
/// line, the place a person starts from most is home, and routes whose middles
/// sit close together are one place. Everything here is plain arithmetic on
/// coordinates, so it runs and tests without a map.
nonisolated enum Territory {
    struct Point: Equatable, Sendable {
        var latitude: Double
        var longitude: Double
        /// Metres above sea level, when the fix carried one.
        var altitude: Double?
    }

    /// One recorded route.
    struct Route: Equatable, Sendable, Identifiable {
        var start: Date
        var end: Date
        var activity: Int
        var points: [Point]
        var id: Date { start }

        var distance: Double { Territory.length(points) }
        var climb: Double { Territory.climb(points) }
        var middle: Point? { Territory.centroid(points) }
    }

    /// Routes gathered as one place.
    struct Place: Equatable, Sendable, Identifiable {
        var routes: [Route]
        var center: Point
        var id: Date { routes.first?.start ?? .distantPast }

        var distance: Double { routes.reduce(0) { $0 + $1.distance } }
        var climb: Double { routes.reduce(0) { $0 + $1.climb } }
        /// The shortest route, for the loop a suggestion names.
        var shortest: Route? { routes.min { $0.distance < $1.distance } }
    }

    /// How close a start has to be to home to count as from the door.
    static let doorRadius = 300.0
    /// How close two routes' middles have to be to count as one place.
    static let placeRadius = 1200.0
    /// A rise smaller than this between two fixes is GPS noise, not a hill.
    static let climbStep = 1.0

    /// Metres between two points on a sphere the size of the Earth.
    static func metres(_ a: Point, _ b: Point) -> Double {
        let radius = 6_371_000.0
        let lat1 = a.latitude * .pi / 180, lat2 = b.latitude * .pi / 180
        let dLat = lat2 - lat1
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * radius * asin(min(1, sqrt(h)))
    }

    static func length(_ points: [Point]) -> Double {
        zip(points, points.dropFirst()).reduce(0) { $0 + metres($1.0, $1.1) }
    }

    /// Metres climbed: every rise between fixes past ``climbStep``, measured
    /// from the last low point so a slow climb in small steps still counts.
    static func climb(_ points: [Point]) -> Double {
        let heights = points.compactMap(\.altitude)
        guard var base = heights.first else { return 0 }
        var total = 0.0
        for height in heights.dropFirst() {
            if height - base >= climbStep {
                total += height - base
                base = height
            } else if height < base {
                base = height
            }
        }
        return total
    }

    static func centroid(_ points: [Point]) -> Point? {
        guard !points.isEmpty else { return nil }
        let n = Double(points.count)
        return Point(latitude: points.reduce(0) { $0 + $1.latitude } / n,
                     longitude: points.reduce(0) { $0 + $1.longitude } / n)
    }

    /// The start most other starts sit near. Nil without routes.
    static func home(_ routes: [Route]) -> Point? {
        let starts = routes.compactMap(\.points.first)
        return starts.max { a, b in
            starts.filter { metres($0, a) <= doorRadius }.count < starts.filter { metres($0, b) <= doorRadius }.count
        }
    }

    /// Routes that began within ``doorRadius`` of `home`.
    static func fromDoor(_ routes: [Route], home: Point?) -> Int {
        guard let home else { return 0 }
        return routes.filter { $0.points.first.map { metres($0, home) <= doorRadius } ?? false }.count
    }

    /// Routes gathered by their middles, the most distance first.
    static func places(_ routes: [Route]) -> [Place] {
        var places: [Place] = []
        for route in routes.sorted(by: { $0.start < $1.start }) {
            guard let middle = route.middle else { continue }
            if let index = places.firstIndex(where: { metres($0.center, middle) <= placeRadius }) {
                places[index].routes.append(route)
                let middles = places[index].routes.compactMap(\.middle)
                places[index].center = centroid(middles) ?? middle
            } else {
                places.append(Place(routes: [route], center: middle))
            }
        }
        return places.sorted { $0.distance > $1.distance }
    }
}
