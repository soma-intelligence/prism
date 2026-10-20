//
//  SomaScrollEdgeFade.swift
//  SomaUI
//

import SwiftUI

public extension View {
    /// The top edge of a page that scrolls under the navigation bar: the page's
    /// ground fades over the content, solid at the top of the screen and clear
    /// a little below the bar, so nothing passing under the bar meets an edge.
    ///
    /// Apply it to the page (or to anything holding its scroll view) inside
    /// the navigation stack. The fade rises with the scroll: at rest the page's
    /// head shows under the bar untouched.
    ///
    /// On iOS and macOS the system's own edge effect is set to its soft form
    /// under the fade, so the frost dissolves with it rather than ending on a
    /// line. visionOS is left as the system draws it: its window is glass
    /// rather than the page's ground, and a fade in the canvas colour would lay
    /// a band across that glass.
    func somaScrollEdgeFade() -> some View {
        modifier(SomaScrollEdgeFade())
    }
}

/// How far the page under a bar has scrolled, turned into how strongly the top
/// fade is drawn.
public enum SomaEdgeFade {
    /// The fade's strength, 0 to 1, for a page scrolled `scrolled` points past
    /// its resting place: nothing at rest or during a pull, full once the page
    /// has gone up by `ramp`.
    public static func strength(scrolled: CGFloat, ramp: CGFloat) -> Double {
        guard ramp > 0 else { return scrolled > 0 ? 1 : 0 }
        return Double(min(1, max(0, scrolled / ramp)))
    }

    /// What the fade reads off the page's scroll view.
    public struct Reading: Equatable, Sendable {
        /// How far the content has gone up past where it rests. Negative
        /// during a pull.
        public var scrolled: CGFloat
        /// The scroll view's top inset: the status bar and the bar.
        public var barInset: CGFloat

        public init(scrolled: CGFloat, barInset: CGFloat) {
            self.scrolled = scrolled
            self.barInset = barInset
        }
    }

    /// The reading of a scroll view, or `nil` for one that cannot scroll
    /// vertically (a row of chips, a short page), so a horizontal strip inside
    /// the page never stands in for it.
    public static func reading(_ geometry: ScrollGeometry) -> Reading? {
        guard geometry.contentSize.height > geometry.containerSize.height else { return nil }
        return Reading(
            scrolled: geometry.contentOffset.y + geometry.contentInsets.top,
            barInset: geometry.contentInsets.top
        )
    }

    /// The fade's stops from the top of the screen down: nearly solid over the
    /// status bar, then easing out (a smoothstep, sampled) to clear, so the
    /// ramp has no visible band where it starts or ends.
    public static func stops(solidRun: Double, topOpacity: Double) -> [(location: Double, opacity: Double)] {
        let run = min(max(solidRun, 0), 0.95)
        var stops: [(Double, Double)] = [(0, topOpacity)]
        let samples = 8
        for index in 0...samples {
            let u = Double(index) / Double(samples)
            let eased = u * u * (3 - 2 * u)
            stops.append((run + (1 - run) * u, topOpacity * (1 - eased)))
        }
        return stops
    }
}

/// Where a page's scroll view hands its reading to the fade over it when its
/// part of a tab comes on screen: the part's scroll has not moved, so the
/// fade would otherwise keep the last part's reading.
@MainActor
final class SomaEdgeFadeSink {
    var receive: (SomaEdgeFade.Reading?) -> Void = { _ in }
}

extension EnvironmentValues {
    @Entry var somaEdgeFadeSink: SomaEdgeFadeSink?
}

struct SomaScrollEdgeFade: ViewModifier {
    @Environment(\.somaTheme) private var theme
    @State private var edge = SomaEdgeFade.Reading(scrolled: 0, barInset: 0)
    @State private var sink = SomaEdgeFadeSink()

    func body(content: Content) -> some View {
#if os(visionOS)
        content
#else
        let metrics = theme.metrics
        let strength = SomaEdgeFade.strength(scrolled: edge.scrolled, ramp: metrics.edgeFadeRamp)

        content
            .scrollEdgeEffectStyle(.soft, for: .top)
            .onScrollGeometryChange(for: SomaEdgeFade.Reading?.self) { geometry in
                SomaEdgeFade.reading(geometry)
            } action: { _, value in
                if let value { edge = value }
            }
            .environment(\.somaEdgeFadeSink, sink)
            .onAppear {
                sink.receive = { reading in
                    // A page that cannot scroll rests at the top.
                    edge = reading ?? SomaEdgeFade.Reading(scrolled: 0, barInset: edge.barInset)
                }
            }
            .overlay(alignment: .top) {
                // From the top of the screen: the bar's own height (the scroll
                // view's top inset, status bar included) plus the depth below
                // it. A page may lay itself out under the bar or below it, so
                // the fade measures from the screen rather than from the page.
                SomaEdgeFadeGround()
                    .frame(height: edge.barInset + metrics.edgeFadeDepth)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .ignoresSafeArea(edges: .top)
                    .opacity(strength)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
#endif
    }
}

/// The page's ground, solid at the top and fading to clear at the bottom: what
/// ``somaScrollEdgeFade()`` lays over the content under the bar.
public struct SomaEdgeFadeGround: View {
    @Environment(\.somaTheme) private var theme

    public init() {}

    public var body: some View {
        let metrics = theme.metrics
        let ground = theme.colors.canvas.color
        LinearGradient(
            stops: SomaEdgeFade.stops(
                solidRun: metrics.edgeFadeSolidRun,
                topOpacity: metrics.edgeFadeTopOpacity
            ).map { Gradient.Stop(color: ground.opacity($0.opacity), location: $0.location) },
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

#Preview("Scroll edge fade") {
    NavigationStack {
        ScrollView {
            VStack(spacing: SomaMetrics.standard.cardSpacing) {
                ForEach(0..<12, id: \.self) { index in
                    SomaCard {
                        Text(verbatim: "Card \(index + 1)")
                            .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
                    }
                }
            }
            .padding(SomaMetrics.standard.pagePadding)
        }
        .background(SomaTheme.standard.colors.canvas.color.ignoresSafeArea())
        .navigationTitle(Text(verbatim: "Page"))
        .toolbarTitleDisplayMode(.inline)
        .somaScrollEdgeFade()
    }
}
