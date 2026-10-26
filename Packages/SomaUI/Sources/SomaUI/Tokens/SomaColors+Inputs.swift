//
//  SomaColors+Inputs.swift
//  SomaUI
//

/// The colours a few inputs need that no aspect carries: the moon's own
/// greys, which are the moon's and nobody's identity.
///
/// Computed so they add no stored field to the palette.
public extension SomaColors {
    /// The sunlit face of the moon: a warm, chalky grey.
    var moonLit: SomaColorValue { SomaColorValue(light: 0xFAF8F3, dark: 0xE9E6DF) }
    /// The seas on its face, darker and cooler than the highlands.
    var moonMare: SomaColorValue { SomaColorValue(light: 0xB9B6B0, dark: 0xA19F9B) }
    /// The night side, where only earthshine reaches.
    var moonNight: SomaColorValue { SomaColorValue(light: 0xCFD0D6, dark: 0x3A3B42) }
}
