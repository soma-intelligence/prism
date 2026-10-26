//
//  SomaReadout.swift
//  SomaUI
//

import SwiftUI

/// The one number an input screen is about, with its unit on the same
/// baseline: 68.4 kg, 250 ml, 14 h.
///
/// Set in the metric role at the readout size, so the digits hold their
/// columns while a drag turns them over. A nil value is a dash.
public struct SomaReadout: View {
    private let value: String?
    private let unit: String?
    private let caption: String?

    @Environment(\.somaTheme) private var theme

    /// - Parameters:
    ///   - value: the number as text, or nil for a dash.
    ///   - unit: what it counts, set small and grey beside it.
    ///   - caption: one line under it: when, or what it means.
    public init(_ value: String?, unit: String? = nil, caption: String? = nil) {
        self.value = value
        self.unit = unit
        self.caption = caption
    }

    public var body: some View {
        let metrics = theme.metrics
        let colors = theme.colors
        var number = theme.typography.metric
        number.size = metrics.readoutSize
        number.tracking = theme.typography.metric.tracking * metrics.readoutSize / theme.typography.metric.size
        var small = theme.typography.body
        small.size = metrics.readoutUnitSize

        return VStack(spacing: metrics.spaceXS) {
            HStack(alignment: .firstTextBaseline, spacing: metrics.readoutUnitGap) {
                SomaNumber(value, number)
                    .foregroundStyle(colors.inkPrimary.color)
                    .contentTransition(.numericText())
                if let unit, !unit.isEmpty {
                    Text(unit)
                        .somaFont(small)
                        .foregroundStyle(colors.inkSecondary.color)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            if let caption {
                Text(caption)
                    .somaFont(theme.typography.caption)
                    .foregroundStyle(colors.inkSecondary.color)
                    .multilineTextAlignment(.center)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// The small white disc a finger drags along a track: crisp, with a hairline
/// edge and a short, soft shadow, the way the system's slider thumb sits.
public struct SomaKnob: View {
    @Environment(\.somaTheme) private var theme

    public init() {}

    public var body: some View {
        let metrics = theme.metrics
        let ink = theme.colors.inkPrimary.color
        Circle()
            .fill(theme.colors.onOrb.color)
            .frame(width: metrics.knobDiameter, height: metrics.knobDiameter)
            .overlay(Circle().strokeBorder(ink.opacity(metrics.hairlineOpacity), lineWidth: metrics.inputHairline * 0.5))
            .shadow(color: .black.opacity(0.18), radius: metrics.knobRingWidth, y: metrics.knobRingWidth * 0.5)
            .accessibilityHidden(true)
    }
}

#Preview("Readout") {
    ZStack {
        SomaPreviewBackdrop()
        VStack(spacing: 32) {
            SomaReadout("68.4", unit: "kg", caption: "Today, 18:02")
            SomaReadout(nil, unit: "ml")
            SomaKnob()
        }
    }
}
