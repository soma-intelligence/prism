//
//  SomaNumber.swift
//  SomaUI
//

import SwiftUI

/// A number set in one of the theme's roles, with its unit after it if it has
/// one, or the drawn dash that stands in for it when nothing was measured.
///
/// A missing value is never a zero, and never a hyphen either: a font sets a
/// hyphen thin and low, beside figures it reads as a typo. The dash is a short
/// rule in the secondary ink, as wide as two figures and centred on the line,
/// so a column of values keeps its rhythm when one of them is absent. A unit
/// never stands beside the dash: "- mg" reads as a typo too, so the unit goes
/// with the value.
///
/// The value takes the ink of its context (set `foregroundStyle` around it);
/// the unit is always the secondary ink.
public struct SomaNumber: View {
    private let value: String?
    private let spec: SomaFontSpec
    private let unit: String?
    private let unitSpec: SomaFontSpec?

    @Environment(\.somaTheme) private var theme

    /// - Parameters:
    ///   - value: the figures as the app prints them, or nil when nothing was
    ///     measured.
    ///   - unit: set after the value in `unitSpec` (the caption role when
    ///     nil), and left out when the value is.
    public init(_ value: String?, _ spec: SomaFontSpec, unit: String? = nil, unitSpec: SomaFontSpec? = nil) {
        self.value = value
        self.spec = spec
        self.unit = unit
        self.unitSpec = unitSpec
    }

    public var body: some View {
        if let value {
            if let unit, !unit.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: theme.metrics.numberUnitGap) {
                    Text(verbatim: value).somaFont(spec)
                    Text(verbatim: unit)
                        .somaFont(unitSpec ?? theme.typography.caption)
                        .foregroundStyle(theme.colors.inkSecondary.color)
                }
            } else {
                Text(verbatim: value).somaFont(spec)
            }
        } else {
            SomaMissingValue(spec)
        }
    }
}

/// The drawn dash for a value that was not measured, sized from the role the
/// value would have been set in.
public struct SomaMissingValue: View {
    private let spec: SomaFontSpec

    @Environment(\.somaTheme) private var theme

    /// The rule's thickness against the role's size: a twelfth, the weight of
    /// a figure's stem in a regular cut.
    private static let thicknessRatio: CGFloat = 1.0 / 12.0
    /// How far the rule stops short of the two figures' edges, against the
    /// role's size, so it reads as a mark and not as an underline.
    private static let insetRatio: CGFloat = 0.12

    public init(_ spec: SomaFontSpec) {
        self.spec = spec
    }

    public var body: some View {
        // Two hidden figures give the dash the line's height, its baseline and
        // a pair of figures' width, so it sits exactly where the number would
        // and aligns on a baseline beside a unit.
        Text(verbatim: "00")
            .somaFont(spec)
            .hidden()
            .overlay {
                Capsule()
                    .fill(theme.colors.inkSecondary.color)
                    .frame(height: max(theme.metrics.glyphStroke, spec.size * Self.thicknessRatio))
                    .padding(.horizontal, spec.size * Self.insetRatio)
            }
            .accessibilityElement()
            .accessibilityLabel(Text("Not measured"))
    }
}

#Preview("Number") {
    let type = SomaTheme.standard.typography
    ZStack {
        SomaPreviewBackdrop()
        VStack(spacing: 24) {
            HStack(spacing: 32) {
                SomaNumber("78", type.metric)
                SomaNumber(nil, type.metric)
            }
            HStack(spacing: 32) {
                SomaNumber("8 412", type.rowValue)
                SomaNumber(nil, type.rowValue)
            }
            HStack(spacing: 32) {
                SomaNumber("120", type.rowValue, unit: "mg")
                SomaNumber(nil, type.rowValue, unit: "mg")
            }
        }
    }
}
