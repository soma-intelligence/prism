//
//  SomaZoneBar.swift
//  SomaUI
//

import SwiftUI

/// Where a value sits among the zones of its scale: low, optimal, high, or
/// however many the metric has. One segment a zone, each the same width so
/// its name fits under it, coloured by what the zone means (the status
/// green, the out of range orange, the alert red), the zone holding the value
/// solid and the others faint. A ring marks the value inside its zone; the
/// edge between two zones carries its number.
///
/// A missing value draws every zone faint and no ring: not measured is not
/// zero.
public struct SomaZoneBar: View {
    /// What a zone means.
    public enum Tone: Sendable, Equatable {
        case good, fair, out
    }

    /// One stretch of the scale.
    public struct Zone: Sendable, Equatable, Identifiable {
        public let name: String
        public let lower: Double
        public let upper: Double
        public let tone: Tone

        public var id: String { "\(name)\(lower)" }

        public init(name: String, lower: Double, upper: Double, tone: Tone) {
            self.name = name
            self.lower = lower
            self.upper = upper
            self.tone = tone
        }
    }

    private let zones: [Zone]
    private let value: Double?

    @Environment(\.somaTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameters:
    ///   - zones: low to high, each starting where the last ends.
    ///   - value: the reading, or nil when there is none.
    public init(zones: [Zone], value: Double?) {
        self.zones = zones
        self.value = value
    }

    /// The zone holding the value: the first it sits under the top of, the
    /// ends taking anything off the scale.
    var activeIndex: Int? {
        guard let value, !zones.isEmpty else { return nil }
        return zones.firstIndex { value < $0.upper } ?? zones.count - 1
    }

    /// Where the value sits along the bar, 0 to 1, with every zone given
    /// the same width.
    static func share(of value: Double, in zones: [Zone]) -> Double {
        guard !zones.isEmpty else { return 0 }
        let index = zones.firstIndex { value < $0.upper } ?? zones.count - 1
        let zone = zones[index]
        let span = zone.upper - zone.lower
        let inside = span > 0 ? min(max((value - zone.lower) / span, 0), 1) : 0.5
        return (Double(index) + inside) / Double(zones.count)
    }

    public var body: some View {
        let metrics = theme.metrics
        let colors = theme.colors
        let type = theme.typography
        let gap = metrics.spaceXS
        let track = metrics.environmentScaleHeight
        let marker = metrics.environmentMarkerDiameter
        let active = activeIndex

        VStack(alignment: .leading, spacing: metrics.spaceXS) {
            HStack(spacing: gap) {
                ForEach(Array(zones.enumerated()), id: \.element.id) { index, zone in
                    Capsule()
                        .fill(color(zone.tone).opacity(index == active ? 1 : metrics.chartContextOpacity))
                        .frame(height: track)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: marker)
            .overlay(alignment: .leading) {
                if let value {
                    GeometryReader { proxy in
                        let width = proxy.size.width
                        let count = CGFloat(max(zones.count, 1))
                        let segment = (width - gap * (count - 1)) / count
                        let share = Self.share(of: value, in: zones)
                        let index = min(floor(share * count), count - 1)
                        let x = index * (segment + gap) + (share * count - index) * segment
                        Circle()
                            .fill(colors.surface.color)
                            .overlay(Circle().strokeBorder(colors.inkPrimary.color, lineWidth: metrics.chartStroke))
                            .frame(width: marker, height: marker)
                            .position(x: min(max(x, marker / 2), width - marker / 2), y: proxy.size.height / 2)
                    }
                }
            }

            HStack(alignment: .top, spacing: gap) {
                ForEach(Array(zones.enumerated()), id: \.element.id) { index, zone in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(zone.name)
                            .somaFont(type.caption)
                            .foregroundStyle(index == active ? colors.inkPrimary.color : colors.inkSecondary.color)
                        Text(verbatim: index == 0 ? " " : Self.number(zone.lower))
                            .somaFont(type.captionValue)
                            .foregroundStyle(colors.inkSecondary.color)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .animation(reduceMotion ? nil : theme.motion.fold, value: value)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(zones.map(\.name).joined(separator: ", ")))
        .accessibilityValue(Text(active.map { zones[$0].name } ?? "-"))
    }

    private func color(_ tone: Tone) -> Color {
        switch tone {
        case .good: theme.colors.statusNormal.color
        case .fair: theme.colors.statusOut.color
        case .out: theme.colors.statusAlert.color
        }
    }

    /// An edge's number: whole when it is whole, else one decimal, grouped.
    static func number(_ value: Double) -> String {
        value.rounded() == value
            ? Int(value).formatted()
            : value.formatted(.number.precision(.fractionLength(1)))
    }
}

#Preview("Zone bar") {
    let resting: [SomaZoneBar.Zone] = [
        .init(name: "Very low", lower: 30, upper: 40, tone: .out),
        .init(name: "Athletic", lower: 40, upper: 50, tone: .good),
        .init(name: "Optimal", lower: 50, upper: 70, tone: .good),
        .init(name: "Normal", lower: 70, upper: 100, tone: .fair),
        .init(name: "High", lower: 100, upper: 130, tone: .out),
    ]
    let variability: [SomaZoneBar.Zone] = [
        .init(name: "Low", lower: 0, upper: 35, tone: .fair),
        .init(name: "Typical", lower: 35, upper: 70, tone: .good),
        .init(name: "High", lower: 70, upper: 105, tone: .good),
    ]
    ZStack {
        SomaPreviewBackdrop()
        VStack(alignment: .leading, spacing: 28) {
            SomaZoneBar(zones: resting, value: 58)
            SomaZoneBar(zones: variability, value: 31)
            SomaZoneBar(zones: variability, value: nil)
        }
        .padding()
    }
}
