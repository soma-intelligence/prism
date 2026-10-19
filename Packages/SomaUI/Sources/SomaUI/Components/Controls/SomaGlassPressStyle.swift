//
//  SomaGlassPressStyle.swift
//  SomaUI
//

import SwiftUI

/// Press feedback for controls that sit on Liquid Glass.
///
/// Glass chrome stays non-interactive: an interactive glass background swallows
/// the button's tap: so the press state is carried by the label instead: a
/// scale down plus a dim, over a single short beat, both read off the theme.
///
/// `scales` is what a control as wide as its container turns off. A disc or a
/// chip shrinking under the finger reads as the thing being pressed; a row
/// spanning the whole accessory shrinking reads as the surface itself flinching,
/// and its content detaches from the glass edge it was flush with. Those keep
/// the dim alone, which says the same thing without moving the layout.
public struct SomaGlassPressStyle: ButtonStyle {
    private let scales: Bool

    @Environment(\.somaTheme) private var theme

    public init(scales: Bool = true) {
        self.scales = scales
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(scales && configuration.isPressed ? theme.motion.pressScale : 1)
            .opacity(configuration.isPressed ? theme.motion.pressOpacity : 1)
            .animation(
                .easeOut(duration: theme.motion.pressDuration),
                value: configuration.isPressed
            )
    }
}

public extension ButtonStyle where Self == SomaGlassPressStyle {
    /// Scale-and-dim press feedback for controls layered on glass.
    static var somaGlassPress: SomaGlassPressStyle { SomaGlassPressStyle() }

    /// Dim-only press feedback, for a control that spans its whole surface.
    static var somaGlassPressDim: SomaGlassPressStyle { SomaGlassPressStyle(scales: false) }
}
