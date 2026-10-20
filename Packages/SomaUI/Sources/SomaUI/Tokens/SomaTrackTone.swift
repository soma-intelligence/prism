//
//  SomaTrackTone.swift
//  SomaUI
//

import SwiftUI

/// The colours of what a person logs by hand: a few natural, muted tones
/// rather than Apple Health's saturated category hues.
///
/// Sage, sand and clay are the calm energy ramp's own stops
/// (``SomaEnergyRamp/calm``); the others sit beside them at the same low
/// saturation: a dusk for the evening, a tide for water, a stone for a
/// person's own habits, a moss for training and a rose for mood. Each is set a
/// step deeper on the light page and a step lighter on the dark one, so a thin
/// line glyph reads against either.
///
/// Data colours, like the aspect identities, never chrome: the accent stays
/// ink.
public enum SomaTrackTone: String, CaseIterable, Sendable, Identifiable {
    case sage, moss, sand, clay, dusk, tide, stone, rose

    public var id: String { rawValue }

    public var value: SomaColorValue {
        switch self {
        case .sage: SomaColorValue(light: 0x4E8A72, dark: 0x82BFA5)
        case .moss: SomaColorValue(light: 0x6F8248, dark: 0xA6B87C)
        case .sand: SomaColorValue(light: 0xA97C3F, dark: 0xD9B07A)
        case .clay: SomaColorValue(light: 0xB0644A, dark: 0xDE9478)
        case .dusk: SomaColorValue(light: 0x6E6A94, dark: 0xA9A4CF)
        case .tide: SomaColorValue(light: 0x4F7F8E, dark: 0x8BB6C2)
        case .stone: SomaColorValue(light: 0x75736B, dark: 0xADAAA0)
        case .rose: SomaColorValue(light: 0xA2646F, dark: 0xD497A1)
        }
    }

    public var color: Color { value.color }
}
