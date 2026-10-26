//
//  SomaCategoryInk.swift
//  SomaUI
//

import SwiftUI

/// The ink a category's glyph is drawn in, and the latest bar of its charts.
///
/// The Health hues (`SomaHealthHue`) are tile colours, tuned to carry dark ink
/// on top of them. Set as a line on a white card they fall under 3:1, which a
/// glyph cannot afford. These are the same hues stepped down on the light
/// ground until they clear 4.5:1 on `surface`, and lifted on the dark one until
/// they clear it there too (design system v2, 2026-10-14).
///
/// Data colours, never chrome: a category's name and value stay in ink, and
/// only its glyph and its latest bar wear the hue.
public enum SomaCategoryInk: String, CaseIterable, Sendable {
    case sleep, heart, activity, mind, body, gut, energy, environment

    public var value: SomaColorValue {
        switch self {
        case .sleep: SomaColorValue(light: 0x4A5BE0, dark: 0x8A97FF)
        case .heart: SomaColorValue(light: 0xD81E48, dark: 0xFF6B86)
        case .activity: SomaColorValue(light: 0xC94100, dark: 0xFF7A33)
        case .mind: SomaColorValue(light: 0x00806A, dark: 0x2FE0C2)
        case .body: SomaColorValue(light: 0xB020BE, dark: 0xEE6BF7)
        case .gut: SomaColorValue(light: 0x13803B, dark: 0x3EDB74)
        case .energy: SomaColorValue(light: 0x9A6200, dark: 0xFFC233)
        case .environment: SomaColorValue(light: 0x0A6FBF, dark: 0x4DB2FF)
        }
    }

    public var color: Color { value.color }

    /// The ink an aspect wears.
    public init(_ aspect: SomaAspect) {
        switch aspect {
        case .sleep: self = .sleep
        case .heart: self = .heart
        case .activity: self = .activity
        case .mind: self = .mind
        case .body: self = .body
        case .gut: self = .gut
        }
    }
}
