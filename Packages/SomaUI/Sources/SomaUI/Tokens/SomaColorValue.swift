//
//  SomaColorValue.swift
//  SomaUI
//

import SwiftUI

/// The one place in the system where a raw colour value is written.
///
/// Views and components never spell a colour out: they read it off the theme,
/// so a value can never drift between two screens.
public struct SomaColorValue: Sendable, Equatable {
    public let light: UInt32
    public let dark: UInt32

    public init(light: UInt32, dark: UInt32) {
        self.light = light
        self.dark = dark
    }

    public init(_ both: UInt32) {
        self.init(light: both, dark: both)
    }

    /// Resolved once, then handed to SwiftUI: the trait lookup happens inside
    /// the platform colour, not on every render pass.
    public var color: Color {
#if canImport(UIKit)
        Color(UIColor { trait in
            UIColor(somaRGB: trait.userInterfaceStyle == .dark ? dark : light)
        })
#elseif canImport(AppKit)
        Color(NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(somaRGB: isDark ? dark : light)
        })
#else
        Color(somaRGB: light)
#endif
    }
}

#if canImport(UIKit)
private extension UIColor {
    convenience init(somaRGB rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}
#elseif canImport(AppKit)
private extension NSColor {
    convenience init(somaRGB rgb: UInt32) {
        self.init(
            srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}
#else
private extension Color {
    init(somaRGB rgb: UInt32) {
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}
#endif
