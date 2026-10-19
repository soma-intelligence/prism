//
//  SomaMoodOrb.swift
//  SomaUI
//

import SwiftUI

/// The colours a feeling wears, from very unpleasant to very pleasant: calm
/// and cool below neutral, warm and bright above it.
///
/// Each stop borrows an aspect's palette, so the mood orb travels between
/// palettes the way the hero orb travels between aspects, and the slider's
/// track, its thumb and a chosen chip all wear the same colour as the orb.
public enum SomaMoodScale {
    /// The palettes along the scale, evenly spaced from its low end to its
    /// high end: dusk violet, then the cool of the mind, the plain stone of
    /// neutral, then green growing to amber.
    public static let aspects: [SomaAspect] = [.sleep, .sleep, .mind, .body, .gut, .activity, .activity]

    /// The palette before anything is chosen: the mind's own.
    public static let unset: SomaAspect = .mind

    /// The palette one stop of a scale wears, or the unset one for nil.
    public static func aspect(for value: Int?, stops: Int = 7) -> SomaAspect {
        guard let value else { return unset }
        return aspects[index(for: share(value, stops: stops))]
    }

    /// Where one stop sits along the scale, from 0 at the low end to 1.
    public static func share(_ value: Int, stops: Int) -> Double {
        let last = max(stops - 1, 1)
        return Double(min(max(value, 0), last)) / Double(last)
    }

    static func index(for share: Double) -> Int {
        let last = aspects.count - 1
        return min(max(Int((share * Double(last)).rounded()), 0), last)
    }

    /// The bright colour of the palette a stop wears: the track's colour at
    /// that stop and the dot in the thumb.
    static func glow(_ aspect: SomaAspect, theme: SomaTheme) -> Color {
        theme.aspects[aspect].orb.stops[1].color
    }

    /// The track's gradient: one colour per palette, at its place on the scale.
    static func gradient(theme: SomaTheme) -> Gradient {
        let last = Double(max(aspects.count - 1, 1))
        return Gradient(stops: aspects.enumerated().map { index, aspect in
            Gradient.Stop(color: glow(aspect, theme: theme), location: Double(index) / last)
        })
    }
}

/// The mood sheet's orb: the feeling itself.
///
/// It wears the palette of the stop chosen and grows as the feeling turns
/// pleasant, settling smaller and cooler below neutral. A change of palette
/// travels the way the hero orb's does; with Reduce Motion on, the size and
/// the palette change at once.
public struct SomaMoodOrb: View {
    private let value: Int?
    private let stops: Int

    @Environment(\.somaTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameters:
    ///   - value: 0...stops minus one, or nil before a feeling is chosen.
    public init(value: Int?, stops: Int = 7) {
        self.value = value
        self.stops = max(2, stops)
    }

    public var body: some View {
        let metrics = theme.metrics
        let stage = metrics.moodOrbDiameter
        let fill = value.map { metrics.moodOrbSmallest + (1 - metrics.moodOrbSmallest) * SomaMoodScale.share($0, stops: stops) }
            ?? metrics.moodOrbUnset
        // The hero orb draws at its own diameter; this sets it to the stage.
        let scale = stage * fill / metrics.orbDiameter

        SomaOrb(aspect: SomaMoodScale.aspect(for: value, stops: stops), scale: .hero)
            .scaleEffect(scale)
            .frame(width: stage, height: stage)
            // Room for the halo and the shadow, so nothing above or below
            // the orb is ever drawn over it.
            .padding(.vertical, stage * theme.aspects.shading.haloReach * 0.5)
            .animation(reduceMotion ? nil : theme.motion.selection, value: value)
            .accessibilityHidden(true)
    }
}

#Preview("Mood orb") {
    @Previewable @State var feeling: Int? = 4
    ZStack {
        SomaPreviewBackdrop()
        VStack(spacing: 24) {
            SomaMoodOrb(value: feeling)
            SomaValenceSlider(value: $feeling, low: "Very unpleasant", high: "Very pleasant", names: [])
        }
        .padding()
    }
}
