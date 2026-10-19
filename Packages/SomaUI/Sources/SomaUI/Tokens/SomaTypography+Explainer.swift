//
//  SomaTypography+Explainer.swift
//  SomaUI
//

import SwiftUI

/// The explainer's roles, derived from the scale rather than added to it:
/// the same sizes and tracking, a heavier weight for the title and each row's
/// term (bold).
public extension SomaTypography {
    /// The sheet's title, under the picture.
    var explainerTitle: SomaFontSpec { weighted(display, .bold) }
    /// A row's term, and a contribution's name.
    var explainerTerm: SomaFontSpec { weighted(body, .semibold) }
    /// The number in the middle of the ring or the donut.
    var explainerHeroValue: SomaFontSpec { weighted(metric, .semibold) }

    private func weighted(_ spec: SomaFontSpec, _ weight: Font.Weight) -> SomaFontSpec {
        var spec = spec
        spec.weight = weight
        return spec
    }
}
