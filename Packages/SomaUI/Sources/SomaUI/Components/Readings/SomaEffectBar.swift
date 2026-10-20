//
//  SomaEffectBar.swift
//  SomaUI
//

import SwiftUI

/// How far something moved a reading, as a bar from a centre tick: rightwards
/// for a rise, leftwards for a fall.
///
/// The fill wears the aspect of the reading it moved, or the danger ink when
/// the move is a cost. Nil draws the track and the tick alone: nothing clear
/// yet.
///
/// The calm form (``init(fraction:isCost:)``) drops the aspect: the fill is
/// sage for a move for the better and clay for a cost (``SomaTrackTone``), for
/// a list where the direction matters more than the reading.
public struct SomaEffectBar: View {
    private let fraction: Double?
    private let aspect: SomaAspect?
    private let isCost: Bool

    @Environment(\.somaTheme) private var theme
    @Environment(\.displayScale) private var displayScale

    /// - Parameters:
    ///   - fraction: the move in -1...1 of the bar's half width, or nil.
    ///   - aspect: the reading's aspect, which colours the fill.
    ///   - isCost: whether the move is for the worse.
    public init(fraction: Double?, aspect: SomaAspect, isCost: Bool = false) {
        self.fraction = fraction.map { min(max($0, -1), 1) }
        self.aspect = aspect
        self.isCost = isCost
    }

    /// A bar in the calm tones: sage for the better, clay for a cost.
    public init(fraction: Double?, isCost: Bool) {
        self.fraction = fraction.map { min(max($0, -1), 1) }
        self.aspect = nil
        self.isCost = isCost
    }

    public var body: some View {
        let metrics = theme.metrics
        let colors = theme.colors
        let fill: Color = {
            guard let aspect else { return isCost ? SomaTrackTone.clay.color : SomaTrackTone.sage.color }
            return isCost ? colors.danger.color : theme.aspects[aspect].identity.color
        }()

        GeometryReader { proxy in
            let width = proxy.size.width
            let half = width / 2
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(colors.surfaceRecessed.color)
                    .frame(height: metrics.chartTrackHeight)

                if let fraction, fraction != 0 {
                    let length = half * abs(fraction)
                    Capsule()
                        .fill(fill)
                        .frame(width: length, height: metrics.chartTrackHeight)
                        .offset(x: fraction > 0 ? half : half - length)
                }

                Rectangle()
                    .fill(colors.inkPrimary.color.opacity(0.6))
                    .frame(width: max(1, 2 / displayScale), height: metrics.chartTrackHeight * 3)
                    .offset(x: half - 1 / displayScale)
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: metrics.chartTrackHeight * 3)
        .accessibilityHidden(true)
    }
}

#Preview("Effect bar") {
    ZStack {
        SomaPreviewBackdrop()
        VStack(spacing: 16) {
            SomaEffectBar(fraction: 0.6, aspect: .mind)
            SomaEffectBar(fraction: -0.4, aspect: .sleep, isCost: true)
            SomaEffectBar(fraction: nil, aspect: .heart)
            SomaEffectBar(fraction: 0.5, isCost: false)
            SomaEffectBar(fraction: -0.7, isCost: true)
        }
        .frame(width: 90)
        .padding()
    }
}
