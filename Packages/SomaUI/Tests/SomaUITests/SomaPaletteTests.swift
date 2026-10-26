//
//  SomaPaletteTests.swift
//  SomaUITests
//

import Foundation
import Testing
@testable import SomaUI

/// The contrast ratio WCAG defines, from two opaque sRGB values.
///
/// Computed from the numbers the palette is written in, not from a resolved
/// platform colour, so the test holds the values themselves.
enum Contrast {
    static func luminance(_ rgb: UInt32) -> Double {
        func channel(_ shift: UInt32) -> Double {
            let value = Double((rgb >> shift) & 0xFF) / 255
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(16) + 0.7152 * channel(8) + 0.0722 * channel(0)
    }

    static func ratio(_ first: UInt32, _ second: UInt32) -> Double {
        let lighter = max(luminance(first), luminance(second))
        let darker = min(luminance(first), luminance(second))
        return (lighter + 0.05) / (darker + 0.05)
    }
}

@Suite("Palette")
struct SomaPaletteTests {
    private let colors = SomaColors.standard

    /// A role over a ground, once per appearance: light first, then dark.
    private func appearances(
        of text: SomaColorValue,
        on ground: SomaColorValue
    ) -> [(text: UInt32, ground: UInt32)] {
        [(text.light, ground.light), (text.dark, ground.dark)]
    }

    @Test("Both inks read at AA on the canvas and on a card, in light and in dark")
    func inkClearsAA() {
        for ink in [colors.inkPrimary, colors.inkSecondary] {
            for ground in [colors.canvas, colors.surface] {
                for pair in appearances(of: ink, on: ground) {
                    #expect(Contrast.ratio(pair.text, pair.ground) >= 4.5)
                }
            }
        }
    }

    @Test("The accent reads at AA on the canvas, and so does what sits on the accent")
    func accentClearsAA() {
        for pair in appearances(of: colors.accent, on: colors.canvas) {
            #expect(Contrast.ratio(pair.text, pair.ground) >= 4.5)
        }
        for pair in appearances(of: colors.onAccent, on: colors.accent) {
            #expect(Contrast.ratio(pair.text, pair.ground) >= 4.5)
        }
    }

    @Test("The grounds and inks are Soma tokens")
    func groundsAreNeutral() {
        #expect(colors.canvas == SomaColorValue(light: 0xF4F4F6, dark: 0x1F2023))
        #expect(colors.surface == SomaColorValue(light: 0xFFFFFF, dark: 0x2E3037))
        #expect(colors.inkPrimary == SomaColorValue(light: 0x1C1C1E, dark: 0xFFFFFF))
        #expect(colors.inkSecondary == SomaColorValue(light: 0x6C6C72, dark: 0x9A9BA1))
    }

    /// The champagne is gone and stays gone: the accent carries no hue, so the
    /// three channels of each appearance are equal or nearly so.
    @Test("The accent is ink, not a hue")
    func accentIsNeutral() {
        for rgb in [colors.accent.light, colors.accent.dark] {
            let r = Int((rgb >> 16) & 0xFF), g = Int((rgb >> 8) & 0xFF), b = Int(rgb & 0xFF)
            #expect(max(r, g, b) - min(r, g, b) <= 4)
        }
    }
}
