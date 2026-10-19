//
//  SomaHealthHue.swift
//  SomaUI
//

import SwiftUI

/// The colour of one Health category, as Apple Health's iOS 27 Browse paints
/// it: a two stop gradient on the category's tile, the same hue on the name of
/// each of its data types and on the latest bar of their charts, and a wash of
/// it behind the category's page.
///
/// These are data colours, like the aspect identities, never chrome: the
/// accent stays ink. The values were read off the Health app on the iOS 27
/// Simulator (2026-10-03), stepped so the dark ink on a tile clears 4.5:1.
public enum SomaHealthHue: String, CaseIterable, Sendable {
    case activity, body, cycle, hearing, heart, medications, mind, mobility,
         nutrition, respiratory, sleep, symptoms, vitals, other

    /// The tile's deep end, where the glyph sits.
    public var start: SomaColorValue {
        switch self {
        case .activity: SomaColorValue(0xFF5200)
        case .body: SomaColorValue(0xE93BF5)
        case .cycle: SomaColorValue(0x7183FF)
        case .hearing: SomaColorValue(0x0A8BFF)
        case .heart: SomaColorValue(0xFF2D5F)
        case .medications: SomaColorValue(0x00D2FA)
        case .mind: SomaColorValue(0x00D9B5)
        case .mobility: SomaColorValue(0xFF8A00)
        case .nutrition: SomaColorValue(0x00D24E)
        case .respiratory: SomaColorValue(0x00CBFA)
        case .sleep: SomaColorValue(0x6E7FFF)
        case .symptoms: SomaColorValue(0xA66BFF)
        case .vitals: SomaColorValue(0xFF453A)
        case .other: SomaColorValue(0x9A9BA1)
        }
    }

    /// The tile's light end.
    public var end: SomaColorValue {
        switch self {
        case .activity: SomaColorValue(0xFF8F5E)
        case .body: SomaColorValue(0xF77DFF)
        case .cycle: SomaColorValue(0x93A5FF)
        case .hearing: SomaColorValue(0x45B3FF)
        case .heart: SomaColorValue(0xFF6D85)
        case .medications: SomaColorValue(0x5DE5FF)
        case .mind: SomaColorValue(0x45E8D0)
        case .mobility: SomaColorValue(0xFFB066)
        case .nutrition: SomaColorValue(0x52E482)
        case .respiratory: SomaColorValue(0x62DEFF)
        case .sleep: SomaColorValue(0x96A3FF)
        case .symptoms: SomaColorValue(0xC49BFF)
        case .vitals: SomaColorValue(0xFF7D73)
        case .other: SomaColorValue(0xBDBEC3)
        }
    }

    /// The hue as one colour: the name of a data type, its latest bar.
    public var color: Color { start.color }

    /// What sits on the tile: a near black, in both appearances.
    public static let ink = SomaColorValue(0x111114)
}
