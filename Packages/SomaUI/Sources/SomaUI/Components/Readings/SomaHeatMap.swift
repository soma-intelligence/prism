//
//  SomaHeatMap.swift
//  SomaUI
//

import SwiftUI
#if !os(visionOS)
import MapKit
#endif

/// One warm spot on a ``SomaHeatMap``: where, and how much happened there
/// against the busiest spot (0 to 1).
public struct SomaHeatPoint: Identifiable, Equatable, Sendable {
    public var id: String
    public var latitude: Double
    public var longitude: Double
    /// 1 for the busiest spot on the map, less for the others.
    public var weight: Double

    public init(id: String, latitude: Double, longitude: Double, weight: Double) {
        self.id = id
        self.latitude = latitude
        self.longitude = longitude
        self.weight = min(1, max(0, weight))
    }
}

/// The ground under a set of warm spots, drawn on the device: how much area
/// to frame, and each spot as soft rings that sum to a glow.
public struct SomaHeatGeometry: Equatable, Sendable {
    /// Metres in a degree of latitude, near enough for framing a map.
    static let metresPerDegree = 111_320.0

    public struct Region: Equatable, Sendable {
        public var latitude: Double
        public var longitude: Double
        /// Metres across, north to south and east to west.
        public var span: Double
    }

    /// One ring of a spot's glow: its radius in metres and its opacity.
    public struct Ring: Equatable, Sendable {
        public var radius: Double
        public var opacity: Double
    }

    /// The area that holds every spot with room around it, never closer than
    /// `minimumSpan`. Nil without a spot.
    public static func region(_ points: [SomaHeatPoint], minimumSpan: Double, margin: Double = 1.6) -> Region? {
        guard let first = points.first else { return nil }
        var south = first.latitude, north = first.latitude
        var west = first.longitude, east = first.longitude
        for point in points {
            south = min(south, point.latitude)
            north = max(north, point.latitude)
            west = min(west, point.longitude)
            east = max(east, point.longitude)
        }
        let latitude = (south + north) / 2
        let longitude = (west + east) / 2
        let tall = (north - south) * metresPerDegree
        let wide = (east - west) * metresPerDegree * cos(latitude * .pi / 180)
        return Region(latitude: latitude, longitude: longitude, span: max(minimumSpan, max(tall, wide) * margin))
    }

    /// A spot's glow as rings, widest first: a busier spot is wider and
    /// denser, and the rings stack so the middle is the warmest.
    public static func rings(weight: Double, radius: Double, layers: Int, opacity: Double) -> [Ring] {
        guard layers > 0 else { return [] }
        let reach = radius * (0.55 + 0.45 * weight)
        let each = opacity * (0.6 + 0.6 * weight)
        return (0..<layers).map { layer in
            Ring(radius: reach * (1 - Double(layer) / Double(layers + 1)), opacity: each)
        }
    }

    /// The glow's colour: sand at the edge of what happened, clay where it
    /// happened most.
    public static func tone(weight: Double) -> SomaColorValue {
        SomaEnergyRamp.calm.value(at: 0.35 * (1 - weight))
    }
}

/// Where something happened, as a heat map on Apple Maps: each spot a soft
/// warm glow, the busiest the warmest, on a quiet still map framed to hold
/// them all. Drawn on the device; only the map's tiles come from Apple.
///
/// The map frames `framing` when given (the place that matters, close
/// enough to read its street), else every spot; spots outside the frame
/// still glow where they reach into it. Nothing to show draws the map's
/// ground alone. visionOS draws the glow on the recessed ground without a
/// map.
public struct SomaHeatMap: View {
    private let points: [SomaHeatPoint]
    private let framing: [SomaHeatPoint]?

    @Environment(\.somaTheme) private var theme

    public init(points: [SomaHeatPoint], framing: [SomaHeatPoint]? = nil) {
        self.points = points
        self.framing = framing
    }

    public var body: some View {
        let metrics = theme.metrics
        let framed = framing.flatMap { $0.isEmpty ? nil : $0 } ?? points
        let region = SomaHeatGeometry.region(framed, minimumSpan: metrics.heatMapMinimumSpan)

#if os(visionOS)
        Canvas { context, size in
            guard let region else { return }
            let scale = Double(min(size.width, size.height)) / region.span
            for point in points {
                let x = (point.longitude - region.longitude) * SomaHeatGeometry.metresPerDegree
                    * cos(region.latitude * .pi / 180) * scale + Double(size.width) / 2
                let y = (region.latitude - point.latitude) * SomaHeatGeometry.metresPerDegree * scale + Double(size.height) / 2
                let tone = SomaHeatGeometry.tone(weight: point.weight).color
                for ring in SomaHeatGeometry.rings(weight: point.weight, radius: metrics.heatSpotRadius,
                                                   layers: metrics.heatSpotLayers, opacity: metrics.heatLayerOpacity) {
                    let r = ring.radius * scale
                    context.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                                 with: .color(tone.opacity(ring.opacity)))
                }
            }
        }
        .background(theme.colors.surfaceRecessed.color)
        .accessibilityHidden(true)
#else
        Map(initialPosition: Self.position(region), interactionModes: []) {
            ForEach(points) { point in
                let centre = CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)
                let tone = SomaHeatGeometry.tone(weight: point.weight).color
                ForEach(Array(SomaHeatGeometry.rings(weight: point.weight, radius: metrics.heatSpotRadius,
                                                     layers: metrics.heatSpotLayers,
                                                     opacity: metrics.heatLayerOpacity).enumerated()), id: \.offset) { _, ring in
                    MapCircle(center: centre, radius: ring.radius)
                        .foregroundStyle(tone.opacity(ring.opacity))
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
        .allowsHitTesting(false)
        .background(theme.colors.surfaceRecessed.color)
        .id(region.map { "\($0.latitude),\($0.longitude),\($0.span)" } ?? "none")
        .accessibilityHidden(true)
#endif
    }

#if !os(visionOS)
    static func position(_ region: SomaHeatGeometry.Region?) -> MapCameraPosition {
        guard let region else { return .automatic }
        return .region(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: region.latitude, longitude: region.longitude),
                                          latitudinalMeters: region.span, longitudinalMeters: region.span))
    }
#endif
}

#Preview("Heat map") {
    SomaHeatMap(points: [
        SomaHeatPoint(id: "a", latitude: 37.4443, longitude: -122.1598, weight: 1),
        SomaHeatPoint(id: "b", latitude: 37.4446, longitude: -122.1601, weight: 0.4),
        SomaHeatPoint(id: "c", latitude: 37.4462, longitude: -122.1570, weight: 0.15),
    ])
    .frame(height: 220)
    .clipShape(.rect(cornerRadius: 20))
    .padding(16)
}
