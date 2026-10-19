//
//  AspectWash.swift
//  Prism
//

import SwiftUI
import SomaUI

extension View {
    /// The page ground, with an aspect's weather across the top of it.
    ///
    /// Apply it to the page's `ScrollView`. The wash leaves with the content
    /// when the page scrolls up, and stays pinned to the top of the screen when
    /// a pull drags the content down. Riding inside the content, it travelled
    /// down with a pull and left a band of bare ground above it.
    func aspectWash(_ aspect: SomaAspect?) -> some View {
        modifier(AspectWash(aspect: aspect))
    }
}

private struct AspectWash: ViewModifier {
    let aspect: SomaAspect?

    @Environment(\.somaTheme) private var theme
    /// How far the content has scrolled up past its resting place. Negative
    /// during a pull.
    @State private var scrolled: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top
            } action: { _, value in
                scrolled = value
            }
            .background {
                ZStack(alignment: .top) {
                    theme.colors.canvas.color
                    if let aspect {
                        SomaAspectBackdrop(aspect: aspect)
                            .frame(height: 440)
                            .offset(y: -max(0, scrolled))
                    }
                }
                .ignoresSafeArea()
            }
    }
}
