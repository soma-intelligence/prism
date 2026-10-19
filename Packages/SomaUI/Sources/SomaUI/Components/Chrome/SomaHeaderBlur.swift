//
//  SomaHeaderBlur.swift
//  SomaUI
//

import SwiftUI

/// The backdrop a floating header is anchored to.
///
/// Frosted at the very top and dissolving downward, so the header has something
/// to sit on without drawing an edge across the page. There is no line and no
/// plate: content passing under it fades rather than being cut.
public struct SomaHeaderBlur: View {
    @Environment(\.somaTheme) private var theme

    public init() {}

    public var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .mask {
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0),
                            .init(color: .black, location: 0.45),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }

            // A neutral scrim under the frost, so a glyph stays legible over a
            // bright card sliding beneath it.
            LinearGradient(
                stops: [
                    .init(color: theme.colors.canvas.color.opacity(0.55), location: 0),
                    .init(color: theme.colors.canvas.color.opacity(0.28), location: 0.5),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .frame(maxWidth: .infinity)
        .frame(height: theme.metrics.headerBlurHeight)
        .ignoresSafeArea(edges: .top)
        .allowsHitTesting(false)
    }
}
