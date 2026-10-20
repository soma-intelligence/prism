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

// MARK: - Now

/// The top of the lens, one block: where you are and the weather there, the
/// three readings that matter outside (air quality, UV now, your daylight),
/// the humidity and the sun's times, and the spot on a small map. Each part
/// opens its page. Without a place, the map's room holds one button that
/// asks for Location, the first time only.
struct EnvironmentNowCard: View {
    let here: EnvironmentHere
    let report: EnvironmentReport
    let sky: EnvironmentSky
    let open: (EnvironmentMeasure) -> Void
    let requestLocation: () -> Void

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics
        let colors = theme.colors
        let type = theme.typography
        let outside = report.outside
        let words = PulseWording(calendar: .current, locale: .current)
        let temperature = outside?.temperature.map { "\(Int($0.rounded()))°" }
        let tint = outside?.temperature.map { SomaDataScale.temperature.value(at: $0).color } ?? SomaHealthHue.respiratory.color

        SomaCard {
            VStack(alignment: .leading, spacing: metrics.cardSpacing) {
                Button { open(.temperature) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Image(systemName: here.isHere ? "location.fill" : "mappin")
                                .foregroundStyle(colors.inkSecondary.color)
                            Text(verbatim: here.place?.name ?? (here.place == nil ? "-" : String(localized: "Here")))
                                .foregroundStyle(colors.inkSecondary.color)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .foregroundStyle(colors.inkSecondary.color)
                        }
                        .somaFont(type.caption)
                        HStack(alignment: .center, spacing: metrics.cardSpacing) {
                            Image(systemName: outside?.symbol ?? "cloud.sun.fill")
                                .symbolRenderingMode(.hierarchical)
                                .somaFont(type.metricCompact)
                                .foregroundStyle(colors.inkSecondary.color)
                            Text(verbatim: temperature ?? "-")
                                .somaFont(type.metricHero)
                                .foregroundStyle(temperature == nil ? colors.inkSecondary.color : colors.inkPrimary.color)
                                .somaRollingNumber(temperature)
                            Spacer(minLength: 0)
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(verbatim: outside?.word ?? "-")
                                    .somaFont(type.body)
                                    .foregroundStyle(colors.inkPrimary.color)
                                Text(verbatim: outside?.low.flatMap { low in
                                    outside?.high.map { "\(Int(low.rounded()))° to \(Int($0.rounded()))°" }
                                } ?? "-")
                                    .somaFont(type.captionValue)
                                    .foregroundStyle(colors.inkSecondary.color)
                            }
                        }
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.somaGlassPress)
                .accessibilityElement(children: .combine)

                EnvironmentHairline()

                SomaStatRow(stats) { stat in
                    switch stat.id {
                    case "Air quality": open(.air)
                    case "UV now": open(.uv)
                    default: open(.daylight)
                    }
                }

                EnvironmentHairline()

                HStack(spacing: 0) {
                    EnvironmentFact(symbol: "humidity", value: outside?.humidity.map { "\(Int($0.rounded()))%" },
                                    label: "Humidity") { open(.temperature) }
                    EnvironmentFact(symbol: "sunrise", value: sky.rise(words), label: "Sunrise") { open(.daylight) }
                    EnvironmentFact(symbol: "sunset", value: sky.set(words), label: "Sunset") { open(.daylight) }
                }

                if let place = here.place {
#if !os(visionOS)
                    Button { open(.temperature) } label: {
                        EnvironmentPlaceMap(place: here.exact ?? place, isExact: here.exact != nil, tint: tint)
                    }
                    .buttonStyle(.somaGlassPress)
#endif
                } else {
                    EnvironmentNoPlace(access: here.access, request: requestLocation)
                }
            }
        }
    }

    private var stats: [SomaStat] {
        let colors = theme.colors
        let uv = EnvironmentMeasure.uv.current(report)
        let uvStatus = EnvironmentMeasure.uv.status(uv, report: report, colors: colors)
        let daylightStatus = EnvironmentMeasure.daylight.status(report.daylight, report: report, colors: colors)
        let aqi = report.outside?.aqi
        let airStatus = EnvironmentMeasure.air.status(aqi, report: report, colors: colors)
        return [
            SomaStat("Air quality", value: aqi.map(EnvironmentMeasure.air.format),
                     cue: airStatus.map { LocalizedStringResource(stringLiteral: $0.word) },
                     cueTone: (aqi ?? 0) > 100 ? .watch : (aqi == nil ? .neutral : .good)),
            SomaStat("UV now", value: uv.map(EnvironmentMeasure.uv.format),
                     cue: uvStatus.map { LocalizedStringResource(stringLiteral: $0.word) },
                     cueTone: (uv ?? 0) >= 6 ? .watch : .neutral),
            SomaStat("Daylight", value: report.daylight.map(EnvironmentMeasure.daylight.format), unit: "min",
                     trend: report.isDaylightLow ? .down : nil,
                     cue: daylightStatus.map { LocalizedStringResource(stringLiteral: $0.word) },
                     cueTone: report.isDaylightLow ? .watch : (daylightStatus == nil ? .neutral : .good)),
        ]
    }
}

/// A hairline across a card, between its parts.
struct EnvironmentHairline: View {
    @Environment(\.somaTheme) private var theme

    var body: some View {
        Rectangle()
            .fill(theme.colors.inkPrimary.color.opacity(theme.metrics.hairlineOpacity))
            .frame(height: 0.5)
    }
}

/// A small fact in a row of three: a quiet glyph, the value, its label.
private struct EnvironmentFact: View {
    let symbol: String
    let value: String?
    let label: LocalizedStringResource
    let action: () -> Void

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let colors = theme.colors
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .somaFont(theme.typography.caption)
                    .foregroundStyle(colors.inkSecondary.color)
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: value ?? "-")
                        .somaFont(theme.typography.captionValue)
                        .foregroundStyle(value == nil ? colors.inkSecondary.color : colors.inkPrimary.color)
                        .somaRollingNumber(value)
                        .lineLimit(1)
                    Text(label)
                        .somaFont(theme.typography.caption)
                        .foregroundStyle(colors.inkSecondary.color)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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

#if !os(visionOS)
/// The place on a still map, a dot on it. Where the device gave its own
/// position the map is drawn close in, on that very spot; a city is drawn
/// wider. visionOS draws this page without a map.
private struct EnvironmentPlaceMap: View {
    let place: EnvironmentSun.Place
    var isExact = false
    let tint: Color

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics
        let shape = RoundedRectangle(cornerRadius: metrics.chartBarCornerRadius + 6, style: .continuous)
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
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
        .allowsHitTesting(false)
        .frame(height: metrics.environmentMapHeight)
        .background(theme.colors.surfaceRecessed.color)
        .clipShape(shape)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: place.name ?? "-"))
    }
}
#endif

// MARK: - Sleep places

/// Sleep places as one map: warm where you slept these last weeks, the
/// warmest where you slept most, framed close on the main place so the
/// street reads. A chip names the main place and its nights, or asks for a
/// name when a new place turned up. The whole tile opens the sheet.
struct EnvironmentSleepPlacesCard: View {
    let heat: SleepPlaceHeat
    /// The place slept in most.
    let main: SleepPlaceCluster?
    /// A place found that has no name yet.
    let pending: SleepPlaceCluster?
    /// Where you are, for the map's ground before any night is placed.
    var here: EnvironmentSun.Place? = nil
    let open: () -> Void

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics
        let colors = theme.colors
        let shape = RoundedRectangle(cornerRadius: metrics.cardCornerRadius, style: .continuous)

        Button(action: open) {
            Group {
                if heat.points.isEmpty, let here {
                    // No night placed yet: the ground round where you are,
                    // nothing warm on it.
                    SomaHeatMap(points: [], framing: [SomaHeatPoint(id: "here", latitude: here.latitude,
                                                                    longitude: here.longitude, weight: 0)])
                } else if heat.points.isEmpty {
                    Image(systemName: "bed.double")
                        .somaFont(theme.typography.metricCompact)
                        .foregroundStyle(colors.inkSecondary.color)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(colors.surfaceRecessed.color)
                } else {
                    SomaHeatMap(points: heat.points, framing: heat.framing)
                }
            }
            .frame(height: metrics.heatMapHeight)
            .clipShape(shape)
            .overlay(shape.strokeBorder(colors.inkPrimary.color.opacity(metrics.hairlineOpacity), lineWidth: 0.5))
            .overlay(alignment: .topLeading) {
                EnvironmentMapChip {
                    Image(systemName: "moon.fill")
                        // The sleep aspect's own calm tone, not the chart hue.
                        .foregroundStyle(theme.aspects[.sleep].identity.color)
                    Text("Sleep places")
                        .foregroundStyle(colors.inkPrimary.color)
                }
                .padding(metrics.mapChipInset)
            }
            .overlay(alignment: .bottomLeading) {
                EnvironmentMapChip {
                    if pending != nil {
                        Circle()
                            .fill(colors.accent.color)
                            .frame(width: metrics.chartPointDiameter, height: metrics.chartPointDiameter)
                    }
                    Text(verbatim: status)
                        .foregroundStyle(colors.inkPrimary.color)
                    Image(systemName: "chevron.right")
                        .foregroundStyle(colors.inkSecondary.color)
                }
                .padding(metrics.mapChipInset)
            }
            .contentShape(shape)
        }
        .buttonStyle(.somaGlassPress)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Sleep places"))
        .accessibilityValue(Text(verbatim: status))
        .accessibilityAddTraits(.isButton)
    }

    /// What the chip says: a new place to name, else the main place and
    /// its nights, else how to start.
    var status: String {
        if let pending { return Self.status(pending: pending) }
        if let main { return Self.status(main: main) }
        return String(localized: "Find where you sleep")
    }

    static func nights(_ count: Int) -> String {
        count == 1 ? String(localized: "1 night") : String(localized: "\(count) nights")
    }

    static func status(pending: SleepPlaceCluster) -> String {
        String(localized: "New place, \(nights(pending.nights.count)). Name it")
    }

    static func status(main: SleepPlaceCluster) -> String {
        "\(main.name ?? String(localized: "Unnamed")) · \(nights(main.nights.count))"
    }
}

/// A chip laid on a map: a glyph and a few words on the card's surface.
struct EnvironmentMapChip<Content: View>: View {
    @ViewBuilder let content: Content

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let colors = theme.colors
        HStack(spacing: 6) { content }
            .somaFont(theme.typography.caption)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(colors.surface.color))
            .overlay(Capsule().strokeBorder(colors.inkPrimary.color.opacity(theme.metrics.hairlineOpacity), lineWidth: 0.5))
    }
}
