//
//  SomaOrbTap.swift
//  SomaUI
//

import SwiftUI

public extension View {
    /// Makes the orb answer a tap before it acts: a soft haptic, the sphere
    /// squeezes and springs back, and only then `action` runs. No rings
    /// ripple from the rim (owner, 2026-10-24). With Reduce Motion on, the
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
    @State private var taps = 0

    func body(content: Content) -> some View {
        content
            .scaleEffect(squeeze ? 0.94 : 1)
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
        // The theme's press in and its emphasized spring out: the squeeze
        // lands like any control under a finger, and the overshoot on the
        // way back is the orb springing rather than a button releasing.
        withAnimation(theme.motion.press) { squeeze = true }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(140))
            withAnimation(theme.motion.emphasized) { squeeze = false }
            try? await Task.sleep(for: .milliseconds(160))
            action()
        }
    }
}
