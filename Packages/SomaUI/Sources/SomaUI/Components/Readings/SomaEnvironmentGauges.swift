//
//  SomaEnvironmentGauges.swift
//  SomaUI
//

import SwiftUI

// MARK: - Scale bar

/// A measure on its coloured scale: the UV index from green to violet, the
/// air quality index from green to maroon, a sound level against its limit.
///
/// `.scale` draws the whole scale and rides a marker on the value, the way a
/// weather app draws UV. `.level` draws a grey track filled up to the value
/// in the scale's colours, with the limit as a tick, the way a meter reads.
/// A missing value draws the scale faded and no marker: not measured is not
/// zero.
public struct SomaScaleBar: View {
    public enum Style: Sendable {
        case scale
        case level
    }

    private let scale: SomaDataScale
    private let value: Double?
    private let style: Style
    private let limit: Double?
    private let ticks: [Double]

    @Environment(\.somaTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameters:
    ///   - limit: a value drawn as a tick across the bar.
    ///   - ticks: values written under the bar, where they sit on it.
    public init(scale: SomaDataScale, value: Double?, style: Style = .scale, limit: Double? = nil, ticks: [Double] = []) {
        self.scale = scale
        self.value = value
        self.style = style
        self.limit = limit
        self.ticks = ticks
    }

    public var body: some View {
        let metrics = theme.metrics
        let colors = theme.colors
        let track = metrics.environmentScaleHeight
        let marker = metrics.environmentMarkerDiameter
        let tick = metrics.environmentLimitTickHeight
        let height = max(marker, tick)
        let share = value.map(scale.share(of:)) ?? 0
        let paint = LinearGradient(gradient: scale.gradient, startPoint: .leading, endPoint: .trailing)

        VStack(spacing: 4) {
            GeometryReader { geometry in
                let width = geometry.size.width
                ZStack(alignment: .leading) {
                    switch style {
                    case .scale:
                        Capsule()
                            .fill(paint)
                            .frame(height: track)
                            .opacity(value == nil ? 0.3 : 1)
                    case .level:
                        Capsule()
                            .fill(colors.surfaceRecessed.color)
                            .frame(height: track)
                        if value != nil {
                            Capsule()
                                .fill(paint)
                                .frame(width: width, height: track)
                                .mask(alignment: .leading) {
                                    Capsule().frame(width: max(track, width * share), height: track)
                                }
                        }
                    }
                    if let limit {
                        Capsule()
                            .fill(colors.inkPrimary.color)
                            .frame(width: 2, height: tick)
                            .offset(x: width * scale.share(of: limit) - 1)
                    }
                    if let value, style == .scale {
                        Circle()
                            .fill(scale.value(at: value).color)
                            .overlay(Circle().strokeBorder(colors.surface.color, lineWidth: 3))
                            .frame(width: marker, height: marker)
                            .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                            .offset(x: min(max(width * share - marker / 2, 0), width - marker))
                    }
                }
                .frame(width: width, height: height)
            }
            .frame(height: height)

            if !ticks.isEmpty {
                GeometryReader { geometry in
                    let width = geometry.size.width
                    ForEach(ticks, id: \.self) { mark in
                        Text(verbatim: Self.number(mark))
                            .somaFont(theme.typography.captionValue)
                            .foregroundStyle(colors.inkSecondary.color)
                            .fixedSize()
                            .position(x: min(max(width * scale.share(of: mark), 8), width - 8), y: 7)
                    }
                }
                .frame(height: 14)
            }
        }
        .animation(reduceMotion ? nil : theme.motion.fold, value: value)
        .accessibilityHidden(true)
    }

    static func number(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : value.formatted(.number.precision(.fractionLength(1)))
    }
}

// MARK: - Arc gauge

/// A measure as a three quarter ring filled in its scale's colours, the
/// usual band as a thin arc outside it and a knob on the value: minutes in
/// daylight against their usual. What the ring counts sits in its middle.
public struct SomaArcGauge<Center: View>: View {
    private let scale: SomaDataScale
    private let value: Double?
    private let band: ClosedRange<Double>?
    private let center: Center

    @Environment(\.somaTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The ring's sweep, as a share of a full turn.
    private static var sweep: Double { 0.75 }

    public init(scale: SomaDataScale, value: Double?, band: ClosedRange<Double>? = nil, @ViewBuilder center: () -> Center) {
        self.scale = scale
        self.value = value
        self.band = band
        self.center = center()
    }

    public var body: some View {
        let metrics = theme.metrics
        let colors = theme.colors
        let diameter = metrics.environmentGaugeDiameter
        let stroke = metrics.environmentGaugeStroke
        let share = value.map(scale.share(of:)) ?? 0
        let sweep = Self.sweep
        let round = StrokeStyle(lineWidth: stroke, lineCap: .round)
        let paint = AngularGradient(gradient: scale.gradient, center: .center,
                                    startAngle: .degrees(-8), endAngle: .degrees(278))

        ZStack {
            Group {
                Circle()
                    .trim(from: 0, to: sweep)
                    .stroke(colors.surfaceRecessed.color, style: round)
                if value != nil {
                    Circle()
                        .trim(from: 0, to: max(0.001, sweep * share))
                        .stroke(paint, style: round)
                    Circle()
                        .fill(value.map { scale.value(at: $0).color } ?? colors.inkSecondary.color)
                        .overlay(Circle().strokeBorder(colors.surface.color, lineWidth: 2.5))
                        .frame(width: stroke + 4, height: stroke + 4)
                        .offset(x: diameter / 2)
                        .rotationEffect(.degrees(360 * sweep * share))
                }
            }
            .frame(width: diameter, height: diameter)
            .rotationEffect(.degrees(135))

            if let band {
                let low = scale.share(of: band.lowerBound)
                let high = scale.share(of: band.upperBound)
                Circle()
                    .trim(from: sweep * low, to: sweep * max(high, low + 0.01))
                    .stroke(colors.inkSecondary.color.opacity(0.75), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: diameter + stroke + 6, height: diameter + stroke + 6)
                    .rotationEffect(.degrees(135))
            }

            center
                .frame(width: diameter - stroke * 2)
        }
        .frame(width: diameter + stroke + 10, height: diameter + stroke + 10)
        .animation(reduceMotion ? nil : theme.motion.fold, value: value)
    }
}

// MARK: - Thermometer pill

/// The temperature now and the day's range as a pill: the number, then the
/// low to high span in the temperature colours with a dot on now.
public struct SomaThermometerPill: View {
    private let now: Double?
    private let low: Double?
    private let high: Double?

    @Environment(\.somaTheme) private var theme

    /// Degrees Celsius; nil for a dash.
    public init(now: Double?, low: Double?, high: Double?) {
        self.now = now
        self.low = low
        self.high = high
    }

    public var body: some View {
        let metrics = theme.metrics
        let colors = theme.colors
        let scale = SomaDataScale.temperature
        let known = [now, low, high].compactMap { $0 }
        let floor = (known.min() ?? 5) - 4
        let ceiling = (known.max() ?? 25) + 4
        let span = max(ceiling - floor, 1)
        let share = { (value: Double) -> Double in min(1, max(0, (value - floor) / span)) }
        let window = Gradient(colors: (0...6).map { scale.value(at: floor + span * Double($0) / 6).color })
        let track = metrics.environmentScaleHeight

        HStack(spacing: metrics.cardSpacing) {
            Image(systemName: "thermometer.medium")
                .somaFont(theme.typography.body)
                .foregroundStyle(now.map { scale.value(at: $0).color } ?? colors.inkSecondary.color)
            Text(verbatim: now.map(Self.degrees) ?? "-")
                .somaFont(theme.typography.metricCompact)
                .foregroundStyle(now == nil ? colors.inkSecondary.color : colors.inkPrimary.color)
                .frame(minWidth: 44, alignment: .leading)

            VStack(spacing: 5) {
                GeometryReader { geometry in
                    let width = geometry.size.width
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(colors.surfaceRecessed.color)
                            .frame(height: track)
                        if let low, let high {
                            Capsule()
                                .fill(LinearGradient(gradient: window, startPoint: .leading, endPoint: .trailing))
                                .frame(width: width, height: track)
                                .mask(alignment: .leading) {
                                    Capsule()
                                        .frame(width: max(track, width * (share(high) - share(low))), height: track)
                                        .offset(x: width * share(low))
                                }
                        }
                        if let now {
                            let dot = metrics.environmentMarkerDiameter - 4
                            Circle()
                                .fill(colors.inkPrimary.color)
                                .overlay(Circle().strokeBorder(colors.surface.color, lineWidth: 2))
                                .frame(width: dot, height: dot)
                                .offset(x: min(max(width * share(now) - dot / 2, 0), width - dot))
                        }
                    }
                    .frame(width: width, height: metrics.environmentMarkerDiameter)
                }
                .frame(height: metrics.environmentMarkerDiameter)

                HStack {
                    Text(verbatim: "L \(low.map(Self.degrees) ?? "-")")
                    Spacer(minLength: 0)
                    Text(verbatim: "H \(high.map(Self.degrees) ?? "-")")
                }
                .somaFont(theme.typography.captionValue)
                .foregroundStyle(colors.inkSecondary.color)
            }
        }
        .padding(.horizontal, metrics.cardPadding)
        .frame(minHeight: metrics.environmentPillHeight)
        .background(Capsule().fill(colors.surface.color))
        .overlay(Capsule().strokeBorder(colors.inkPrimary.color.opacity(metrics.hairlineOpacity), lineWidth: 0.5))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Temperature"))
        .accessibilityValue(Text(verbatim: now.map(Self.degrees) ?? "-"))
    }

    static func degrees(_ value: Double) -> String { "\(Int(value.rounded()))°" }
}

// MARK: - Weather pill

/// The weather pill: a disc with the sky's glyph, the reading, and the
/// place under it. Missing values read as a dash.
public struct SomaWeatherPill: View {
    private let symbol: String
    private let value: String?
    private let place: String?

    @Environment(\.somaTheme) private var theme

    public init(symbol: String, value: String?, place: String?) {
        self.symbol = symbol
        self.value = value
        self.place = place
    }

    public var body: some View {
        let metrics = theme.metrics
        let colors = theme.colors

        HStack(spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(colors.inkSecondary.color)
                .frame(width: metrics.environmentPillDisc, height: metrics.environmentPillDisc)
                .background(Circle().fill(colors.surfaceRecessed.color))
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: value ?? "-")
                    .somaFont(theme.typography.body)
                    .foregroundStyle(colors.inkPrimary.color)
                Text(verbatim: place ?? "-")
                    .somaFont(theme.typography.caption)
                    .foregroundStyle(colors.inkSecondary.color)
                    .lineLimit(1)
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, metrics.cardPadding)
        .frame(minHeight: metrics.environmentPillHeight)
        .background(Capsule().fill(colors.surface.color))
        .overlay(Capsule().strokeBorder(colors.inkPrimary.color.opacity(metrics.hairlineOpacity), lineWidth: 0.5))
        .accessibilityElement(children: .combine)
    }
}

#Preview("Environment gauges") {
    ZStack {
        SomaPreviewBackdrop()
        ScrollView {
            VStack(spacing: 20) {
                HStack {
                    SomaWeatherPill(symbol: "cloud.sun.fill", value: "18°C", place: "San Francisco")
                    Spacer()
                }
                SomaArcGauge(scale: .daylight, value: 48, band: 40...85) {
                    Text(verbatim: "48")
                }
                SomaScaleBar(scale: .uvIndex, value: 6, ticks: [0, 3, 6, 8, 11])
                SomaScaleBar(scale: .airQuality, value: nil, ticks: [0, 50, 100, 150, 200, 300])
                SomaScaleBar(scale: .soundLevel, value: 64, style: .level, limit: 70)
                SomaScaleBar(scale: .soundLevel, value: 83, style: .level, limit: 80)
                SomaThermometerPill(now: 18, low: 12, high: 21)
                SomaThermometerPill(now: nil, low: nil, high: nil)
            }
            .padding(16)
        }
    }
}
