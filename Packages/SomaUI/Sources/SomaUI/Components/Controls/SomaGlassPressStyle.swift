//
//  SomaGlassPressStyle.swift
//  SomaUI
//

import SwiftUI

/// Press feedback for controls that sit on Liquid Glass.
///
/// Glass chrome stays non-interactive (an interactive glass background swallows
/// the button's tap), so the press state is carried by the label instead: a
/// scale down plus a light dim, over a single short beat, both read off the
/// theme. The same style serves every pressable card and tile in the app.
///
/// `scales` is what a control as wide as its container turns off. A disc or a
/// chip shrinking under the finger reads as the thing being pressed; a row
/// spanning the whole accessory shrinking reads as the surface itself flinching,
/// and its content detaches from the glass edge it was flush with. Those keep
/// a deeper dim alone, which says the same thing without moving the layout.
///
/// Reduce Motion keeps the press: a three percent scale under the finger is
/// feedback, not travel, and a control that stopped answering would read as
/// broken.
public struct SomaGlassPressStyle: ButtonStyle {
    private let scales: Bool

    @Environment(\.somaTheme) private var theme

    public init(scales: Bool = true) {
        self.scales = scales
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(scales && configuration.isPressed ? theme.motion.pressScale : 1)
            .opacity(configuration.isPressed ? (scales ? theme.motion.pressOpacity : theme.motion.pressDimOpacity) : 1)
            // A spring, so a finger that lifts before the press has landed
            // turns the scale round where it is instead of snapping back.
            .animation(theme.motion.press, value: configuration.isPressed)
            // A light tap as the finger lands, none as it lifts: the press is
            // the moment the control answers.
            .sensoryFeedback(.impact(weight: .light, intensity: 0.7), trigger: configuration.isPressed) { _, pressed in pressed }
    }
}

public extension ButtonStyle where Self == SomaGlassPressStyle {
    /// Scale-and-dim press feedback for controls layered on glass.
    static var somaGlassPress: SomaGlassPressStyle { SomaGlassPressStyle() }

    /// Dim-only press feedback, for a control that spans its whole surface.
    static var somaGlassPressDim: SomaGlassPressStyle { SomaGlassPressStyle(scales: false) }
}
