//
//  SomaSleepStagePalette.swift
//  SomaUI
//

import Foundation

/// The four sleep stages, each in its own colour: awake a warm orange that stands out of the night, then the stages
/// darkening from a pale periwinkle for REM through blue for core to indigo
/// for deep. The three asleep shades sit round the sleep identity's violet, so
/// a hypnogram still reads as the sleep aspect.
///
/// The owner preferred a hypnogram in separate colours to a single hue in four
/// shades (2026-10-03): separate colours tell the lanes apart at a glance.
public struct SomaSleepStagePalette: Sendable, Equatable {
    public var awake: SomaColorValue
    public var rem: SomaColorValue
    public var core: SomaColorValue
    public var deep: SomaColorValue

    public init(awake: SomaColorValue, rem: SomaColorValue, core: SomaColorValue, deep: SomaColorValue) {
        self.awake = awake
        self.rem = rem
        self.core = core
        self.deep = deep
    }

    /// Lifted a step on the light page.
    public static let standard = SomaSleepStagePalette(
        awake: SomaColorValue(light: 0xE8804F, dark: 0xF4A47E),
        rem: SomaColorValue(light: 0x8C9DF0, dark: 0xAEBBFA),
        core: SomaColorValue(light: 0x4A6FE3, dark: 0x6286F4),
        deep: SomaColorValue(light: 0x4B3FB3, dark: 0x5D54CC)
    )
}
