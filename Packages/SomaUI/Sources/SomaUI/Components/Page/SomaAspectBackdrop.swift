//
//  SomaAspectBackdrop.swift
//  SomaUI
//

import SwiftUI

/// What sits behind the head of a page: the aspect's landscape photograph,
/// melting into the canvas before the first card, when the person chose the
/// Landscape style; otherwise nothing, and the canvas shows.
///
/// It is ground, not content: it takes no layout, never catches a tap and sits
/// under everything the page draws. It never moves.
public struct SomaAspectBackdrop: View {
    private let aspect: SomaAspect

    @Environment(\.somaTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.somaBackdropStyle) private var style
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    /// False while the page behind it is hidden or the head of the page is
    /// scrolled away: the drift then stops drawing.
    @State private var isOnScreen = true
    /// False for the first moments after the page appears: the drift waits
    /// until the push or zoom that brought the page in has landed. A mesh
    /// under a blur redrawn on its own clock while the page is scaled every
    /// frame costs the transition its frames.
    @State private var hasSettled = false
    private var power = SomaPowerState.shared
    @Environment(\.displayScale) private var displayScale
    /// The Landscape photograph, decoded at the backdrop's width, with the
    /// aspect and width it was decoded for.
    @State private var loaded: (key: String, image: Image)?
    @State private var width: CGFloat = 0

    public init(aspect: SomaAspect) {
        self.aspect = aspect
    }

    public var body: some View {
        if style == .landscape, SomaLandscapePhoto.hasPhoto(for: aspect) {
            Group {
                if let photo = SomaLandscapePhoto.cached(for: aspect, pixelWidth: photoWidth)
                    ?? (loaded?.key == photoKey ? loaded?.image : nil) {
                    landscape(photo)
                } else {
                    Color.clear
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .task(id: photoKey) {
                guard photoWidth > 0 else { return }
                let key = photoKey
                if let image = await SomaLandscapePhoto.load(for: aspect, pixelWidth: photoWidth) {
                    loaded = (key, image)
                }
            }
        } else {
            gradient
        }
    }

    private var photoKey: String { "\(aspect.rawValue)@\(photoWidth)" }

    /// The width the photograph is decoded at: the backdrop's, in pixels,
    /// rounded up to a step of 128 so a small change of width reuses it.
    private var photoWidth: Int {
        let pixels = Int((width * displayScale).rounded(.up))
        return pixels <= 0 ? 0 : ((pixels + 127) / 128) * 128
    }

    /// The Landscape theme: the aspect's photograph, darkened toward the
    /// bottom so it melts into the canvas before the first card.
    private func landscape(_ photo: Image) -> some View {
        photo
            .resizable()
            .aspectRatio(contentMode: .fill)
            .overlay {
                // Clear under the bar, where the photograph shows whole,
                // then the page's ground thickening over it so the numbers
                // the head sets on it keep their contrast on an intense
                // photograph (deep moss, a low sun), and nothing of it is
                // left by the first card.
                let veil = theme.metrics.backdropVeilOpacities
                LinearGradient(
                    stops: [
                        // Heavier at the top than it once was: the bar's
                        // segments and the stats sit there, and on a pale sky
                        // their secondary ink all but vanished.
                        .init(color: theme.colors.canvas.color.opacity(theme.metrics.landscapeScrimTop), location: 0),
                        .init(color: theme.colors.canvas.color.opacity(theme.metrics.landscapeScrimMiddle), location: 0.6),
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

        // Held still in Low Power Mode and whenever nobody can see it, the
        // way Reduce Motion holds it.
        let isPaused = reduceMotion || power.isLowPower || !isOnScreen || scenePhase != .active || !hasSettled
        TimelineView(.animation(minimumInterval: 1.0 / 15.0, paused: isPaused)) { context in
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
        .somaOnScreen($isOnScreen)
        .task {
            guard !hasSettled else { return }
            try? await Task.sleep(for: .seconds(theme.motion.settleDelay))
            hasSettled = true
        }
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
