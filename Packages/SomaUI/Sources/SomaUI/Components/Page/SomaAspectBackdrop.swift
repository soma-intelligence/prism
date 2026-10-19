//
//  SomaAspectBackdrop.swift
//  SomaUI
//

import SwiftUI

/// The weather of an aspect behind the head of a page: its orb's colours as a
/// soft field that fades into the canvas before the first card.
///
/// It is ground, not content: it takes no layout, never catches a tap and sits
/// under everything the page draws. It drifts slowly; with Reduce Motion on it
/// holds still.
public struct SomaAspectBackdrop: View {
    private let aspect: SomaAspect

    @Environment(\.somaTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.somaBackdropStyle) private var style
    @Environment(\.colorScheme) private var colorScheme

    public init(aspect: SomaAspect) {
        self.aspect = aspect
    }

    public var body: some View {
        if style == .landscape, let photo = SomaLandscapePhoto.image(for: aspect) {
            landscape(photo)
        } else {
            gradient
        }
    }

    /// The Landscape theme: the aspect's photograph, darkened toward the
    /// bottom so it melts into the canvas before the first card.
    private func landscape(_ photo: Image) -> some View {
        photo
            .resizable()
            .aspectRatio(contentMode: .fill)
            .overlay {
                LinearGradient(
                    stops: [
                        .init(color: theme.colors.canvas.color.opacity(0.15), location: 0),
                        .init(color: theme.colors.canvas.color.opacity(0.55), location: 0.6),
                        .init(color: theme.colors.canvas.color, location: 1),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            }
            .clipped()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var gradient: some View {
        let canvas = theme.colors.canvas.color
        // On the light ground the orb's deep stops read as a bruise: they are
        // lifted most of the way toward the canvas and the field is fainter,
        // so the header is a pale wash of the aspect's colour.
        let isLight = colorScheme == .light
        let stops = theme.aspects[aspect].orb.stops.map { stop in
            isLight ? stop.color.mix(with: canvas, by: 0.62) : stop.color
        }

        TimelineView(.animation(minimumInterval: 1.0 / 15.0, paused: reduceMotion)) { context in
            let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate / 9
            MeshGradient(
                width: 3,
                height: 3,
                points: Self.points(at: t),
                colors: Self.colors(stops, canvas: canvas)
            )
        }
        .blur(radius: 30)
        .opacity(colorScheme == .light ? 0.55 : 0.7)
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black.opacity(0.8), location: 0.45),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// A three by three mesh whose inner points wander on slow circles.
    private static func points(at t: Double) -> [SIMD2<Float>] {
        func wobble(_ phase: Double, _ reach: Double) -> Float { Float(sin(t + phase) * reach) }
        return [
            [0, 0], [0.5, 0], [1, 0],
            [0, 0.5 + wobble(1, 0.08)], [0.5 + wobble(2, 0.18), 0.45 + wobble(3, 0.12)], [1, 0.5 + wobble(4, 0.08)],
            [0, 1], [0.5, 1], [1, 1],
        ]
    }

    /// The orb's stops around the top, the canvas along the foot.
    private static func colors(_ stops: [Color], canvas: Color) -> [Color] {
        let s = stops.isEmpty ? [canvas] : stops
        func stop(_ i: Int) -> Color { s[i % s.count] }
        return [
            stop(0), stop(1), stop(2),
            stop(3), stop(0), stop(1),
            canvas, canvas, canvas,
        ]
    }
}

#Preview("Aspect backdrop") {
    ZStack(alignment: .top) {
        SomaPreviewBackdrop()
        SomaAspectBackdrop(aspect: .mind).frame(height: 360)
    }
}
