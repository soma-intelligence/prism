//
//  EnvironmentPlaceCards.swift
//  Prism
//

import SwiftUI
import SomaUI
#if !os(visionOS)
import MapKit
#endif

/// Where the lens reads the outside for: the place, whether it is the
/// device's own, and what Location said.
struct EnvironmentHere: Equatable {
    var access: EnvironmentLocation.Access
    var place: EnvironmentSun.Place?
    var isHere: Bool
    /// The device's own position, for the map alone.
    var exact: EnvironmentSun.Place? = nil
}

// MARK: - Where you are

/// The place on a small map with its name, then today's conditions there as
/// six tiles: now with the low and high, humidity, UV, air quality, sunrise
/// and sunset. Without a place, one button asks for Location, the first time
/// only.
struct EnvironmentWhereCard: View {
    let here: EnvironmentHere
    let report: EnvironmentReport
    let sky: EnvironmentSky
    let open: (EnvironmentMeasure) -> Void
    let requestLocation: () -> Void

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics
        let outside = report.outside
        let words = PulseWording(calendar: .current, locale: .current)
        let temperature = outside?.temperature
        let tint = temperature.map { SomaDataScale.temperature.value(at: $0).color } ?? SomaHealthHue.respiratory.color

        SomaCard {
            VStack(alignment: .leading, spacing: metrics.cardSpacing) {
                Group {
                    if let place = here.place {
                        Button { open(.temperature) } label: {
                            EnvironmentPlaceMap(place: here.exact ?? place, isHere: here.isHere, isExact: here.exact != nil, tint: tint)
                        }
                        .buttonStyle(.somaGlassPress)
                    } else {
                        EnvironmentNoPlace(access: here.access, request: requestLocation)
                    }
                }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: metrics.cardSpacing), count: 3),
                          spacing: metrics.cardSpacing) {
                    EnvironmentConditionTile(
                        symbol: outside?.symbol ?? "thermometer.medium",
                        value: temperature.map { "\(Int($0.rounded()))°" },
                        label: outside?.low.flatMap { low in outside?.high.map { "\(Int(low.rounded()))° to \(Int($0.rounded()))°" } } ?? "Low, high",
                        tint: tint
                    ) { open(.temperature) }
                    EnvironmentConditionTile(
                        symbol: "humidity.fill",
                        value: outside?.humidity.map { "\(Int($0.rounded()))%" },
                        label: "Humidity",
                        tint: SomaHealthHue.hearing.color
                    ) { open(.temperature) }
                    EnvironmentConditionTile(
                        symbol: "sun.max.fill",
                        value: EnvironmentMeasure.uv.current(report).map(EnvironmentMeasure.uv.format),
                        label: "UV",
                        tint: EnvironmentMeasure.uv.current(report).map { SomaDataScale.uvIndex.value(at: $0).color }
                            ?? SomaDataScale.uvIndex.value(at: 0).color
                    ) { open(.uv) }
                    EnvironmentConditionTile(
                        symbol: "aqi.medium",
                        value: outside?.aqi.map { "\(Int($0.rounded()))" },
                        label: "AQI",
                        tint: outside?.aqi.map { SomaDataScale.airQuality.value(at: $0).color }
                            ?? SomaDataScale.airQuality.value(at: 0).color
                    ) { open(.air) }
                    EnvironmentConditionTile(
                        symbol: "sunrise.fill",
                        value: sky.rise(words),
                        label: "Sunrise",
                        tint: SomaDataScale.daylight.value(at: 60).color
                    ) { open(.daylight) }
                    EnvironmentConditionTile(
                        symbol: "sunset.fill",
                        value: sky.set(words),
                        label: "Sunset",
                        tint: SomaDataScale.daylight.value(at: 20).color
                    ) { open(.daylight) }
                }
            }
        }
    }
}

/// One condition: its glyph in its colour, the value, a short label.
private struct EnvironmentConditionTile: View {
    let symbol: String
    let value: String?
    let label: String
    let tint: Color
    let action: () -> Void

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let colors = theme.colors
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: symbol)
                    .symbolRenderingMode(.multicolor)
                    .somaFont(theme.typography.body)
                    .foregroundStyle(tint)
                Text(verbatim: value ?? "-")
                    .somaFont(theme.typography.rowValue)
                    .foregroundStyle(value == nil ? colors.inkSecondary.color : colors.inkPrimary.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(verbatim: label)
                    .somaFont(theme.typography.caption)
                    .foregroundStyle(colors.inkSecondary.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint.opacity(0.1), in: .rect(cornerRadius: theme.metrics.chartBarCornerRadius + 6, style: .continuous))
            .contentShape(.rect)
        }
        .buttonStyle(.somaGlassPress)
        .accessibilityElement(children: .combine)
    }
}

/// No place yet: one button that asks for Location the first time, or a
/// crossed out pin once it was refused.
private struct EnvironmentNoPlace: View {
    let access: EnvironmentLocation.Access
    let request: () -> Void

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let colors = theme.colors
        VStack(spacing: 10) {
            Image(systemName: access == .notAsked ? "location.circle.fill" : "location.slash.fill")
                .somaFont(theme.typography.metricCompact)
                .foregroundStyle(access == .notAsked ? SomaHealthHue.hearing.color : colors.inkSecondary.color)
            if access == .notAsked {
                Button(action: request) {
                    Text("Use location")
                        .somaFont(theme.typography.body)
                        .foregroundStyle(colors.onAccent.color)
                        .padding(.horizontal, 18)
                        .frame(minHeight: theme.metrics.chromeCapsuleHeight)
                        .background(Capsule().fill(colors.accent.color))
                }
                .buttonStyle(.somaGlassPress)
            } else {
                Text(verbatim: "-")
                    .somaFont(theme.typography.rowValue)
                    .foregroundStyle(colors.inkSecondary.color)
            }
        }
        .frame(maxWidth: .infinity, minHeight: theme.metrics.environmentMapHeight)
        .background(colors.surfaceRecessed.color, in: .rect(cornerRadius: theme.metrics.chartBarCornerRadius + 6, style: .continuous))
    }
}

/// The place on a still map, a dot on it, the name in a pill. Where the
/// device gave its own position the map is drawn close in, on that very
/// spot; a city is drawn wider. On visionOS, which this page draws without a
/// map, a coloured pill with the name.
private struct EnvironmentPlaceMap: View {
    let place: EnvironmentSun.Place
    let isHere: Bool
    var isExact = false
    let tint: Color

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics
        let shape = RoundedRectangle(cornerRadius: metrics.chartBarCornerRadius + 6, style: .continuous)
#if os(visionOS)
        EnvironmentPlacePill(name: place.name, isHere: isHere, tint: tint)
            .frame(maxWidth: .infinity, alignment: .leading)
#else
        let centre = CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude)
        let span = isExact ? metrics.environmentMapExactSpan : metrics.environmentMapSpan
        Map(initialPosition: .region(MKCoordinateRegion(center: centre, latitudinalMeters: span, longitudinalMeters: span)),
            interactionModes: []) {
            Annotation("", coordinate: centre) {
                ZStack {
                    Circle().fill(tint.opacity(0.25)).frame(width: metrics.environmentHaloDiameter, height: metrics.environmentHaloDiameter)
                    Circle()
                        .fill(tint)
                        .overlay(Circle().strokeBorder(theme.colors.surface.color, lineWidth: 3))
                        .frame(width: metrics.environmentMarkerDiameter + 2, height: metrics.environmentMarkerDiameter + 2)
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .allowsHitTesting(false)
        .frame(height: metrics.environmentMapHeight)
        .background(theme.colors.surfaceRecessed.color)
        .clipShape(shape)
        .overlay(alignment: .bottomLeading) {
            EnvironmentPlacePill(name: place.name, isHere: isHere, tint: tint)
                .padding(8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: place.name ?? "-"))
#endif
    }
}

/// The place's name in a pill, its pin in the conditions' colour.
private struct EnvironmentPlacePill: View {
    let name: String?
    let isHere: Bool
    let tint: Color

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let colors = theme.colors
        HStack(spacing: 6) {
            Image(systemName: isHere ? "location.fill" : "mappin")
                .foregroundStyle(tint)
            Text(verbatim: name ?? "-")
                .foregroundStyle(colors.inkPrimary.color)
                .lineLimit(1)
        }
        .somaFont(theme.typography.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(colors.surface.color))
        .overlay(Capsule().strokeBorder(tint.opacity(0.5), lineWidth: 1))
    }
}

// MARK: - Sleep places

/// Where you slept over thirty days: a pin a place on a map, coloured by
/// the average sleep score there, last night's ringed, with the nights in
/// the pin; the places under it. The whole card opens the ledger.
struct EnvironmentSleepPlacesCard: View {
    let places: [EnvironmentSleepPlace]
    let open: () -> Void

    @Environment(\.somaTheme) private var theme

    static func color(_ score: Double?) -> Color {
        score.map { SomaEnergyRamp.calm.value(at: $0 / 100).color } ?? SomaHealthHue.sleep.color
    }

    var body: some View {
        let metrics = theme.metrics
        let colors = theme.colors

        Button(action: open) {
            SomaCard {
                VStack(alignment: .leading, spacing: metrics.cardSpacing) {
                    HStack {
                        Text("Sleep places")
                            .somaFont(theme.typography.cardTitle)
                            .foregroundStyle(colors.inkPrimary.color)
                        Text("30 days")
                            .somaFont(theme.typography.caption)
                            .foregroundStyle(colors.inkSecondary.color)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .somaFont(theme.typography.caption)
                            .foregroundStyle(colors.inkSecondary.color)
                    }
                    if places.isEmpty {
                        VStack(spacing: 6) {
                            Image(systemName: "mappin.and.ellipse")
                                .somaFont(theme.typography.metricCompact)
                                .foregroundStyle(SomaHealthHue.sleep.color)
                            Text(verbatim: "-")
                                .somaFont(theme.typography.rowValue)
                                .foregroundStyle(colors.inkSecondary.color)
                        }
                        .frame(maxWidth: .infinity, minHeight: metrics.environmentMapHeight)
                        .background(colors.surfaceRecessed.color,
                                    in: .rect(cornerRadius: metrics.chartBarCornerRadius + 6, style: .continuous))
                    } else {
#if !os(visionOS)
                        EnvironmentSleepMap(places: places)
#endif
                        VStack(spacing: 8) {
                            ForEach(places.prefix(4)) { place in
                                EnvironmentSleepPlaceRow(place: place)
                            }
                        }
                    }
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.somaGlassPress)
    }
}

private struct EnvironmentSleepPlaceRow: View {
    let place: EnvironmentSleepPlace

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let colors = theme.colors
        let tint = EnvironmentSleepPlacesCard.color(place.score)
        HStack(spacing: 8) {
            Circle()
                .fill(tint)
                .overlay(Circle().strokeBorder(colors.inkPrimary.color, lineWidth: place.isLastNight ? 2 : 0))
                .frame(width: theme.metrics.environmentLegendDot, height: theme.metrics.environmentLegendDot)
            Text(verbatim: place.name)
                .somaFont(theme.typography.body)
                .foregroundStyle(colors.inkPrimary.color)
                .lineLimit(1)
            if place.isLastNight {
                Image(systemName: "moon.fill")
                    .somaFont(theme.typography.caption)
                    .foregroundStyle(SomaHealthHue.sleep.color)
            }
            Spacer(minLength: 0)
            Text(place.nights == 1 ? "1 night" : "\(place.nights) nights")
                .somaFont(theme.typography.caption)
                .foregroundStyle(colors.inkSecondary.color)
            Text(verbatim: place.score.map { "\(Int($0.rounded()))" } ?? "-")
                .somaFont(theme.typography.rowValue)
                .foregroundStyle(place.score == nil ? colors.inkSecondary.color : tint)
                .frame(minWidth: 28, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
    }
}

#if !os(visionOS)
/// The pins on a still map that fits them all, each at the exact spot it
/// was set and named beside it.
private struct EnvironmentSleepMap: View {
    let places: [EnvironmentSleepPlace]

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics
        Map(initialPosition: Self.position(places, span: metrics.environmentMapExactSpan), interactionModes: []) {
            ForEach(places) { place in
                let tint = EnvironmentSleepPlacesCard.color(place.score)
                let size = place.isLastNight ? metrics.environmentPinLastDiameter : metrics.environmentPinDiameter
                Annotation(place.name, coordinate: CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude)) {
                    Text(verbatim: "\(place.nights)")
                        .somaFont(theme.typography.captionValue)
                        .foregroundStyle(SomaHealthHue.ink.color)
                        .frame(width: size, height: size)
                        .background(Circle().fill(tint))
                        .overlay(Circle().strokeBorder(theme.colors.surface.color, lineWidth: 2))
                        .overlay(Circle().strokeBorder(theme.colors.inkPrimary.color, lineWidth: place.isLastNight ? 2 : 0).padding(-4))
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .allowsHitTesting(false)
        .frame(height: metrics.environmentMapHeight)
        .background(theme.colors.surfaceRecessed.color)
        .clipShape(.rect(cornerRadius: metrics.chartBarCornerRadius + 6, style: .continuous))
        .accessibilityHidden(true)
    }

    /// One place is drawn round its spot, close enough to read the street;
    /// several are fitted together.
    static func position(_ places: [EnvironmentSleepPlace], span: Double) -> MapCameraPosition {
        guard places.count == 1, let only = places.first else { return .automatic }
        return .region(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: only.latitude, longitude: only.longitude),
                                          latitudinalMeters: span, longitudinalMeters: span))
    }
}
#endif
