//
//  SoftScrollEdges.swift
//  Prism
//

import SwiftUI

extension View {
    /// Scroll views fade under their top bar instead of stopping at a frosted
    /// block with a line under it, which is what the system draws once a bar
    /// has items (owner, 2026-10-23).
    ///
    /// Applied at the app's root it reaches every tab and every pushed page,
    /// but not a sheet: a sheet is hosted apart and starts from the system's
    /// default again. So every vertical scroll view and list applies it as
    /// well, right after its closing brace, and a page reads the same in a
    /// sheet as in a tab. A new scroll view takes it too. visionOS draws no
    /// edge effect, so there it changes nothing.
    @ViewBuilder
    func softScrollEdges() -> some View {
#if os(visionOS)
        self
#else
        scrollEdgeEffectStyle(.soft, for: .top)
#endif
    }
}
