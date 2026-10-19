//
//  SomaOrbTap.swift
//  SomaUI
//

import SwiftUI

public extension View {
    /// Makes the orb answer a tap before it acts: a soft haptic, the sphere
    /// squeezes and springs back, two rings in the aspect's colour ripple out
    /// from its rim, and only then `action` runs. With Reduce Motion on, the
    /// haptic and the action alone.
    func somaOrbTap(aspect: SomaAspect, action: @escaping () -> Void) -> some View {
        modifier(SomaOrbTap(aspect: aspect, action: action))
    }
}

struct SomaOrbTap: ViewModifier {
    let aspect: SomaAspect
    let action: () -> Void

    @Environment(\.somaTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var squeeze = false
    @State private var ripple = 0
    @State private var taps = 0

    func body(content: Content) -> some View {
        let tint = theme.aspects[aspect].orb.accent.color
        let diameter = theme.metrics.orbDiameter

        content
            .scaleEffect(squeeze ? 0.94 : 1)
            .background {
                ZStack {
                    ForEach(0..<2, id: \.self) { index in
                        SomaOrbRipple(trigger: ripple, delay: Double(index) * 0.12, tint: tint, diameter: diameter)
                    }
                }
                .allowsHitTesting(false)
            }
            .contentShape(.circle)
            .onTapGesture { tap() }
            .sensoryFeedback(.impact(weight: .medium, intensity: 0.8), trigger: taps)
    }

    private func tap() {
        taps &+= 1
        guard !reduceMotion else {
            action()
            return
        }
        withAnimation(.spring(response: 0.18, dampingFraction: 0.55)) { squeeze = true }
        ripple &+= 1
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(140))
            withAnimation(.spring(response: 0.4, dampingFraction: 0.45)) { squeeze = false }
            try? await Task.sleep(for: .milliseconds(260))
            action()
        }
    }
}

/// One ring leaving the rim and fading as it grows.
private struct SomaOrbRipple: View {
    let trigger: Int
    let delay: Double
    let tint: Color
    let diameter: CGFloat

    @State private var grown = true

    var body: some View {
        Circle()
            .strokeBorder(tint.opacity(grown ? 0 : 0.7), lineWidth: grown ? 1 : 3)
            .frame(width: diameter, height: diameter)
            .scaleEffect(grown ? 1.45 : 0.95)
            .onChange(of: trigger) {
                var reset = Transaction()
                reset.disablesAnimations = true
                withTransaction(reset) { grown = false }
                withAnimation(.easeOut(duration: 0.75).delay(delay)) { grown = true }
            }
    }
}
