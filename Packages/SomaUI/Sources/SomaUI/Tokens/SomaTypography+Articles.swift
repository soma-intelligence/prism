//
//  SomaTypography+Articles.swift
//  SomaUI
//

import SwiftUI

/// The article library's roles, derived from the scale rather than added to
/// it: the same sizes and tracking, a heavier weight where Apple Health sets
/// a story's title in bold.
public extension SomaTypography {
    /// The featured card's title.
    var articleFeatureTitle: SomaFontSpec { weighted(title, .bold) }
    /// A tile's title in the grid.
    var articleTileTitle: SomaFontSpec { weighted(body, .semibold) }
    /// The title at the head of the reader page.
    var articleReaderTitle: SomaFontSpec { weighted(display, .bold) }
    /// A section heading inside an article.
    var articleHeading: SomaFontSpec { weighted(title, .semibold) }

    private func weighted(_ spec: SomaFontSpec, _ weight: Font.Weight) -> SomaFontSpec {
        var spec = spec
        spec.weight = weight
        return spec
    }
}
