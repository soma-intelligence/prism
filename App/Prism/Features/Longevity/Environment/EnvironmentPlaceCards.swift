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
}

// MARK: - Where you are

/// The place on a small map with its name, then today's conditions there as
/// six tiles: now with the low and high, humidity, UV, air quality, sunrise
/// and sunset. Without a place, the prompt stands alone: one button asks for
/// Location, the first time only, and the tiles join with the first reading
/// rather than as six blanks under it.
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
        let tint = temperature.map { SomaDataScale.temperature.value(at: $0).color }
        let uv = EnvironmentMeasure.uv.current(report)

        SomaCard {
            VStack(alignment: .leading, spacing: metrics.cardSpacing) {
                Group {
                    if let place = here.place {
                        Button { open(.temperature) } label: {
                            EnvironmentPlaceMap(place: place, isHere: here.isHere, tint: tint ?? theme.colors.inkSecondary.color)
                        }
                        .buttonStyle(.somaGlassPress)
                    } else {
                        EnvironmentNoPlace(access: here.access, request: requestLocation)
                    }
                }

                if here.place != nil {
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
                            // No scale says what a humidity means for you: the
                            // tile stays neutral with a reading too.
                            tint: nil
                        ) { open(.temperature) }
                        EnvironmentConditionTile(
                            symbol: "sun.max.fill",
                            value: uv.map(EnvironmentMeasure.uv.format),
                            label: "UV",
                            tint: uv.map { SomaDataScale.uvIndex.value(at: $0).color }
                        ) { open(.uv) }
                        EnvironmentConditionTile(
                            symbol: "aqi.medium",
                            value: outside?.aqi.map { "\(Int($0.rounded()))" },
                            label: "AQI",
                            tint: outside?.aqi.map { SomaDataScale.airQuality.value(at: $0).color }
                        ) { open(.air) }
                        EnvironmentConditionTile(
                            symbol: "sunrise.fill",
                            value: sky.rise(words),
                            label: "Sunrise",
                            tint: nil
                        ) { open(.daylight) }
                        EnvironmentConditionTile(
                            symbol: "sunset.fill",
                            value: sky.set(words),
                            label: "Sunset",
                            tint: nil
                        ) { open(.daylight) }
                    }
                }
            }
        }
    }
}

/// One condition: its glyph, the value, a short label. A reading with a scale
/// behind it (temperature, UV, air quality) tints the tile in that reading's
/// colour; anything else, and every tile without a reading, sits on the
/// recessed surface with its glyph in the secondary ink.
private struct EnvironmentConditionTile: View {
    let symbol: String
    let value: String?
    let label: String
    /// The reading's colour on its scale, nil when there is no reading or no
    /// scale that gives it meaning.
    let tint: Color?
    let action: () -> Void

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let colors = theme.colors
        let metrics = theme.metrics
        let tint = value == nil ? nil : tint
        Button(action: action) {
            VStack(alignment: .leading, spacing: metrics.spaceXS) {
                Image(systemName: symbol)
                    .symbolRenderingMode(.monochrome)
                    .somaFont(theme.typography.body)
                    .foregroundStyle(tint ?? colors.inkSecondary.color)
                SomaNumber(value, theme.typography.rowValue)
                    .foregroundStyle(colors.inkPrimary.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(verbatim: label)
                    .somaFont(theme.typography.caption)
                    .foregroundStyle(colors.inkSecondary.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(metrics.spaceM)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint.map { $0.opacity(metrics.environmentTileWashOpacity) } ?? colors.surfaceRecessed.color,
                        in: .rect(cornerRadius: metrics.environmentTileCornerRadius, style: .continuous))
            .contentShape(.rect)
        }
        .buttonStyle(.somaGlassPress)
        .accessibilityElement(children: .combine)
    }
}

/// No place yet: one button that asks for Location the first time, a line
/// while the first fix is on its way, or a crossed out pin and how to turn
/// Location back on once it was refused.
private struct EnvironmentNoPlace: View {
    let access: EnvironmentLocation.Access
    let request: () -> Void

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let colors = theme.colors
        VStack(spacing: theme.metrics.spaceM) {
            Image(systemName: access == .denied ? "location.slash.fill" : "location.circle.fill")
                .somaFont(theme.typography.metricCompact)
                .foregroundStyle(colors.inkSecondary.color)
            if access == .notAsked {
                Button(action: request) {
                    Text("Use location")
                        .somaFont(theme.typography.body)
                        .foregroundStyle(colors.onAccent.color)
                        .padding(.horizontal, theme.metrics.spaceL)
                        .frame(minHeight: theme.metrics.chromeCapsuleHeight)
                        .background(Capsule().fill(colors.accent.color))
                }
                .buttonStyle(.somaGlassPress)
            } else {
                Text(access == .denied
                     ? "Location is off for Soma. Turn it on in Settings to read the air around you."
                     : "Finding where you are.")
                    .somaFont(theme.typography.callout)
                    .foregroundStyle(colors.inkSecondary.color)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, theme.metrics.spaceL)
            }
        }
        .frame(maxWidth: .infinity, minHeight: theme.metrics.environmentMapHeight)
        .background(colors.surfaceRecessed.color, in: .rect(cornerRadius: theme.metrics.environmentTileCornerRadius, style: .continuous))
    }
}

/// The place on a still map, a dot on it, the name in a pill. On visionOS,
/// which this page draws without a map, a coloured pill with the name.
private struct EnvironmentPlaceMap: View {
    let place: EnvironmentSun.Place
    let isHere: Bool
    let tint: Color

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics
        let shape = RoundedRectangle(cornerRadius: metrics.environmentTileCornerRadius, style: .continuous)
#if os(visionOS)
        EnvironmentPlacePill(name: place.name, isHere: isHere, tint: tint)
            .frame(maxWidth: .infinity, alignment: .leading)
#else
        let centre = CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude)
        Map(initialPosition: .region(MKCoordinateRegion(center: centre, latitudinalMeters: metrics.environmentMapSpan, longitudinalMeters: metrics.environmentMapSpan)),
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
                .padding(theme.metrics.spaceS)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: EnvironmentPlacePill.title(place.name, isHere: isHere)))
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
        HStack(spacing: theme.metrics.spaceS) {
            Image(systemName: isHere ? "location.fill" : "mappin")
                .foregroundStyle(tint)
            Text(verbatim: Self.title(name, isHere: isHere))
                .foregroundStyle(colors.inkPrimary.color)
                .lineLimit(1)
        }
        .somaFont(theme.typography.caption)
        .padding(.horizontal, theme.metrics.spaceM)
        .padding(.vertical, theme.metrics.spaceS)
        .background(Capsule().fill(colors.surface.color))
        .overlay(Capsule().strokeBorder(tint.opacity(0.5), lineWidth: 1))
    }

    /// The place's name, or what it is when Location gave no name.
    static func title(_ name: String?, isHere: Bool) -> String {
        name ?? (isHere ? String(localized: "Here") : String(localized: "Your place"))
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
        score.map { SomaEnergyRamp.standard.value(at: $0 / 100).color } ?? SomaHealthHue.sleep.color
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
                        VStack(spacing: theme.metrics.spaceS) {
                            Image(systemName: "mappin.and.ellipse")
                                .somaFont(theme.typography.metricCompact)
                                .foregroundStyle(colors.inkSecondary.color)
                            Text("Where you sleep shows here after a few nights.")
                                .somaFont(theme.typography.callout)
                                .foregroundStyle(colors.inkSecondary.color)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity, minHeight: metrics.environmentMapHeight)
                        .background(colors.surfaceRecessed.color,
                                    in: .rect(cornerRadius: metrics.environmentTileCornerRadius, style: .continuous))
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
            Text(verbatim: "\(place.nights) nights")
                .somaFont(theme.typography.caption)
                .foregroundStyle(colors.inkSecondary.color)
            SomaNumber(place.score.map { "\(Int($0.rounded()))" }, theme.typography.rowValue)
                .foregroundStyle(tint)
                .frame(minWidth: 28, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
    }
}

#if !os(visionOS)
/// The pins on a still map that fits them all.
private struct EnvironmentSleepMap: View {
    let places: [EnvironmentSleepPlace]

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics
        Map(initialPosition: .automatic, interactionModes: []) {
            ForEach(places) { place in
                let tint = EnvironmentSleepPlacesCard.color(place.score)
                let size = place.isLastNight ? metrics.environmentPinLastDiameter : metrics.environmentPinDiameter
                Annotation("", coordinate: CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude)) {
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
        .clipShape(.rect(cornerRadius: metrics.environmentTileCornerRadius, style: .continuous))
        .accessibilityHidden(true)
    }
}
#endif
