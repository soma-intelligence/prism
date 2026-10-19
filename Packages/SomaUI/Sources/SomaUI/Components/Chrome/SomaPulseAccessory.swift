//
//  SomaPulseAccessory.swift
//  SomaUI
//

import SwiftUI

/// A glass disc holding a slowly turning seal, a breathing glyph, and an accent
/// glow behind the glass.
///
/// This is the one element on the bar allowed to move on its own: a breathing
/// glow marks something alive, never a piece of content. The glyph uses the
/// system's own `.breathe` symbol effect rather than a hand-rolled scale, and
/// every motion has a still counterpart under Reduce Motion.
///
/// Both animations run as Core Animation loops driven by a single state flip,
/// so a bar left on screen costs nothing per frame on the SwiftUI side.
public struct SomaPulseAccessory: View {
    private let symbol: String
    private let badge: String
    private let diameter: CGFloat?
    private let accessibilityLabel: LocalizedStringResource
    private let action: () -> Void

    @Environment(\.somaTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isBreathing = false
    @State private var isSpinning = false

    public init(
        symbol: String = "star.fill",
        badge: String = "seal.fill",
        diameter: CGFloat? = nil,
        accessibilityLabel: LocalizedStringResource,
        action: @escaping () -> Void
    ) {
        self.symbol = symbol
        self.badge = badge
        self.diameter = diameter
        self.accessibilityLabel = accessibilityLabel
        self.action = action
    }

    private var size: CGFloat {
        max(diameter ?? theme.metrics.accessoryDiameter, theme.metrics.minimumTapTarget)
    }

    public var body: some View {
        Button(action: action) {
            SomaPulseGlyph(symbol: symbol, badge: badge, diameter: size)
                .contentShape(.circle)
        }
        .buttonStyle(.somaGlassPress)
        .somaGlass(.regular, in: .circle)
        .accessibilityLabel(Text(accessibilityLabel))
    }
}

/// The living mark on its own: a slowly turning seal, a breathing glyph, and an
/// accent glow behind them.
///
/// Split out of ``SomaPulseAccessory`` so it can ride a surface that already
/// brings its own material, such as the tab view's bottom accessory, without a
/// second layer of glass over the system's.
///
/// Both animations are Core Animation loops driven by a single state flip, so
/// one left on screen costs nothing per frame on the SwiftUI side, and each has
/// a still counterpart under Reduce Motion.
public struct SomaPulseGlyph: View {
    private let symbol: String
    private let badge: String
    private let diameterOverride: CGFloat?

    @Environment(\.somaTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isBreathing = false
    @State private var isSpinning = false

    public init(
        symbol: String = "star.fill",
        badge: String = "seal.fill",
        diameter: CGFloat? = nil
    ) {
        self.symbol = symbol
        self.badge = badge
        self.diameterOverride = diameter
    }

    private var size: CGFloat { diameterOverride ?? theme.metrics.accessoryDiameter }

    public var body: some View {
        ZStack {
            Image(systemName: badge)
                .font(.system(size: size * 0.54))
                .foregroundStyle(theme.colors.accent.color)
                .rotationEffect(.degrees(isSpinning ? 360 : 0))

            Image(systemName: symbol)
                .font(.system(size: size * 0.24, weight: .semibold))
                .foregroundStyle(theme.colors.onAccent.color)
                .symbolEffect(.breathe, isActive: !reduceMotion)
        }
        .frame(width: size, height: size)
        // Behind the mark, so the glow reads as a halo and not a blurred fill.
        .background {
            Circle()
                .fill(theme.colors.accent.color)
                .blur(radius: theme.metrics.glowRadius)
                .opacity(
                    isBreathing
                        ? theme.metrics.glowOpacityRange.upperBound
                        : theme.metrics.glowOpacityRange.lowerBound
                )
                .scaleEffect(isBreathing ? 1.08 : 0.92)
                .allowsHitTesting(false)
        }
        .onAppear { syncMotion() }
        .onChange(of: reduceMotion) { _, _ in syncMotion() }
    }

    private func syncMotion() {
        guard !reduceMotion else {
            // Stop both loops and settle at the still pose.
            withAnimation(.none) {
                isSpinning = false
                isBreathing = false
            }
            return
        }

        withAnimation(.linear(duration: theme.motion.spinDuration).repeatForever(autoreverses: false)) {
            isSpinning = true
        }
        withAnimation(.easeInOut(duration: theme.motion.breathDuration).repeatForever(autoreverses: true)) {
            isBreathing = true
        }
    }
}
