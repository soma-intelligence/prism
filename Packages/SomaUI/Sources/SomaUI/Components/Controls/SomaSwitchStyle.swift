//
//  SomaSwitchStyle.swift
//  SomaUI
//

import SwiftUI

/// Every switch in the app, on in the theme's status green.
///
/// The accent is ink, white on the dark canvas, and a switch tinted with it
/// turned on reads as a blank white pill (owner, 2026-10-24). Green is what a
/// switch means on Apple's own lists, and the status green already says "on"
/// elsewhere in Soma. Applied once at the root, it reaches every toggle.
public struct SomaSwitchStyle: ToggleStyle {
    @Environment(\.somaTheme) private var theme

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        Toggle(configuration)
            .toggleStyle(.switch)
            .tint(theme.colors.statusNormal.color)
    }
}

public extension ToggleStyle where Self == SomaSwitchStyle {
    static var soma: SomaSwitchStyle { SomaSwitchStyle() }
}
