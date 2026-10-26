//
//  SomaBandStrip.swift
//  SomaUI
//

import SwiftUI

/// A scale cut into named bands, end to end, with today marked on it and each
/// band's name and threshold under its own stretch.
///
/// Reads where a value sits without repeating the value: the explainer's
/// ranges section draws it inside a section, a score card draws it bare.
public struct SomaBandStrip: View {
    private let bands: [SomaExplainerBand]
    private let aspect: SomaAspect
    private let marker: Double?
    private let markerLabel: String?

    @Environment(\.somaTheme) private var theme

    /// - Parameters:
    ///   - bands: in order, low to high, meeting end to end: each band's
    ///     upper bound is where the next one starts (0...34, 34...67, 67...100).
    ///   - aspect: the colour of the step tones.
    ///   - marker: today's value on the same scale, or nil.
    ///   - markerLabel: the word over the marker: "Today, 72".
    public init(bands: [SomaExplainerBand], aspect: SomaAspect,
                marker: Double? = nil, markerLabel: String? = nil) {
        self.bands = bands
        self.aspect = aspect
        self.marker = marker
        self.markerLabel = markerLabel
    }

    public var body: some View {
        let metrics = theme.metrics
        let type = theme.typography
        let colors = theme.colors
        let low = bands.first?.range.lowerBound ?? 0
        let high = bands.last?.range.upperBound ?? 1
        let span = max(0.0001, high - low)
        let gap = metrics.explainerRangeGap
        let position = marker.map { min(1, max(0, ($0 - low) / span)) }

        VStack(alignment: .leading, spacing: metrics.explainerBarGap) {
            GeometryReader { proxy in
                let width = proxy.size.width
                let usable = width - gap * CGFloat(max(0, bands.count - 1))
                ZStack(alignment: .topLeading) {
                    HStack(spacing: gap) {
                        ForEach(bands) { band in
                            Capsule()
                                .fill(color(band.tone))
                                .frame(width: usable * (band.range.upperBound - band.range.lowerBound) / span)
                        }
                    }
                    .frame(height: metrics.explainerRangeHeight)
                    .offset(y: metrics.explainerRangeLabelRoom + (metrics.explainerRangeMarker - metrics.explainerRangeHeight) / 2)

                    if let position {
                        let x = width * position
                        Circle()
                            .fill(colors.inkPrimary.color)
                            .overlay(Circle().strokeBorder(colors.surface.color, lineWidth: 3))
                            .frame(width: metrics.explainerRangeMarker, height: metrics.explainerRangeMarker)
                            .offset(x: x - metrics.explainerRangeMarker / 2, y: metrics.explainerRangeLabelRoom)
                        if let markerLabel {
                            Text(markerLabel)
                                .somaFont(type.captionValue)
                                .foregroundStyle(colors.inkPrimary.color)
                                .fixedSize()
                                .frame(width: width, alignment: position < 0.2 ? .leading : position > 0.8 ? .trailing : .center)
                                .offset(x: position < 0.2 || position > 0.8 ? 0 : x - width / 2)
                        }
                    }
                }
            }
            .frame(height: metrics.explainerRangeLabelRoom + metrics.explainerRangeMarker)

            GeometryReader { proxy in
                let usable = proxy.size.width - gap * CGFloat(max(0, bands.count - 1))
                HStack(alignment: .top, spacing: gap) {
                    ForEach(bands) { band in
                        VStack(alignment: .leading, spacing: metrics.explainerLineSpacing) {
                            Text(band.title)
                                .somaFont(type.caption)
                                .foregroundStyle(colors.inkPrimary.color)
                            Text(threshold(band))
                                .somaFont(type.captionValue)
                                .foregroundStyle(colors.inkSecondary.color)
                        }
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(width: usable * (band.range.upperBound - band.range.lowerBound) / span, alignment: .leading)
                    }
                }
            }
            .frame(height: metrics.explainerGlyphDiameter + metrics.explainerLineSpacing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(bands.map { "\($0.title), \(threshold($0))" }.joined(separator: "; ")))
        .accessibilityValue(Text(markerLabel ?? ""))
    }

    /// "Under 34", "34 to 66", "67 and over": each band's upper bound is
    /// where the next one starts.
    private func threshold(_ band: SomaExplainerBand) -> String {
        if let detail = band.detail { return detail }
        let lower = Int(band.range.lowerBound.rounded())
        let upper = Int(band.range.upperBound.rounded())
        if band.id == bands.first?.id { return String(localized: "under \(upper)") }
        if band.id == bands.last?.id { return String(localized: "\(lower) and over") }
        return String(localized: "\(lower) to \(upper - 1)")
    }

    private func color(_ tone: SomaExplainerBand.Tone) -> Color {
        let hue = theme.aspects[aspect].identity.color
        switch tone {
        case .good: return SomaHealthHue.nutrition.color
        case .fair: return SomaHealthHue.mobility.color
        case .poor: return SomaHealthHue.vitals.color
        case .light: return hue.opacity(0.3)
        case .middle: return hue.opacity(0.6)
        case .strong: return hue
        }
    }
}

#Preview("Band strip") {
    VStack(spacing: 32) {
        SomaBandStrip(bands: [
            SomaExplainerBand("Run down", 0...34, tone: .poor),
            SomaExplainerBand("Partly", 34...67, tone: .fair),
            SomaExplainerBand("Recovered", 67...100, tone: .good),
        ], aspect: .heart, marker: 71, markerLabel: "Today, 71")
        SomaBandStrip(bands: [
            SomaExplainerBand("Light", 0...34, tone: .light),
            SomaExplainerBand("Moderate", 34...67, tone: .middle),
            SomaExplainerBand("Hard", 67...100, tone: .strong),
        ], aspect: .activity)
    }
    .padding()
}
