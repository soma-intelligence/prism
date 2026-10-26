//
//  PulseMiniOrb.swift
//  Prism
//

import SwiftUI
import SomaUI

/// An aspect's mini orb at a size of the part's own: the orb draws at the
/// theme's mini diameter, so the theme is handed down with that one size
/// changed.
struct PulseMiniOrb: View {
    let aspect: SomaAspect
    let diameter: CGFloat

    @Environment(\.somaTheme) private var theme

    var body: some View {
        var sized = theme
        sized.metrics.miniOrbDiameter = diameter
        return SomaObjectIcon(aspect: aspect, size: .row)
            .environment(\.somaTheme, sized)
            .frame(width: diameter, height: diameter)
    }
}
