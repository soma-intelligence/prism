//
//  AspectWash.swift
//  Prism
//

import SwiftUI
import SomaUI

extension View {
    /// The page ground. Apply it to the page's `ScrollView`.
    func aspectWash(_ aspect: SomaAspect?) -> some View {
        modifier(AspectWash(aspect: aspect))
    }
}

private struct AspectWash: ViewModifier {
    let aspect: SomaAspect?

    @Environment(\.somaTheme) private var theme

    /// The plain canvas. The aspect's coloured weather across the top of the
    /// page left with the redesign (owner, 2026-10-23): colour on Soma means a
    /// state, never a mood.
    func body(content: Content) -> some View {
        content
            .background(theme.colors.canvas.color.ignoresSafeArea())
    }
}
