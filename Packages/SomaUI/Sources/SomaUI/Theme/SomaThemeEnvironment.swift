//
//  SomaThemeEnvironment.swift
//  SomaUI
//

import SwiftUI

public extension EnvironmentValues {
    /// The brand in force for this subtree.
    ///
    /// Components read the theme from here rather than taking it as a parameter,
    /// so a screen, a sheet or a single card can be re-branded without touching
    /// any call site below it.
    @Entry var somaTheme: SomaTheme = .standard
}

public extension View {
    /// Applies a brand to this view and everything under it.
    func somaTheme(_ theme: SomaTheme) -> some View {
        environment(\.somaTheme, theme)
    }
}
