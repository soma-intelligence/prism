//
//  SomaOrbTap.swift
//  SomaUI
//

import SwiftUI

public extension View {
    /// Makes the orb answer a touch the moment it lands: it sinks a few
    /// points and brightens while the finger is down, rises back with a
    /// little bounce when it lifts, and `action` runs on the lift with a soft
    /// haptic. Nothing leaves its rim and nothing waits on an animation.
    ///
    /// With Reduce Motion on, the orb keeps its size and only brightens
    /// under the finger, at once rather than animated.
    func somaOrbTap(action: @escaping () -> Void) -> some View {
        modifier(SomaOrbTap(action: action))
    }
}

struct SomaOrbTap: ViewModifier {
    let action: () -> Void

    @Environment(\.somaTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPressed = false
    @State private var taps = 0

    func body(content: Content) -> some View {
        let motion = theme.motion

        content
            .scaleEffect(isPressed && !reduceMotion ? motion.orbPressScale : 1)
            .brightness(isPressed ? motion.orbPressBrightness : 0)
            .animation(reduceMotion ? nil : (isPressed ? motion.orbPress : motion.orbRelease), value: isPressed)
            .contentShape(.circle)
            .onTapGesture {
                taps &+= 1
                action()
            }
            // Reports the finger down and up without ever completing, so the
            // tap above still fires and a long press set by the call site
            // still wins after its own delay. A drag past the reach, a scroll
            // starting, lets the orb rise again.
            .onLongPressGesture(minimumDuration: .infinity, maximumDistance: theme.metrics.orbPressReach) {
            } onPressingChanged: { pressing in
                isPressed = pressing
            }
            .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.7), trigger: taps)
    }
}

#Preview("Orb press") {
    struct Demo: View {
        @State private var opened = 0
        var body: some View {
            VStack(spacing: 24) {
                SomaOrb(aspect: .sleep, label: "Wind down")
                    .somaOrbTap { opened += 1 }
                Text(verbatim: "Opened \(opened)")
            }
            .padding()
        }
    }
    return Demo()
}
