//
//  SomaSleepStagePalette.swift
//  SomaUI
//

import Foundation

/// The four sleep stages, each in its own colour, as the earlier app paints a night:
/// awake a red orange that stands out of the night, then the stages
/// darkening from a pale cyan for REM through periwinkle for light sleep to
/// royal blue for deep.
///
/// The owner preferred a hypnogram in separate colours to a single hue in four
/// shades (2026-10-03): separate colours tell the lanes apart at a glance.
public struct SomaSleepStagePalette: Sendable, Equatable {
    public var awake: SomaColorValue
    public var rem: SomaColorValue
    public var core: SomaColorValue
    public var deep: SomaColorValue

    /// The ground the full bleed night stands on where it meets the page: the
    /// earlier app's night sky in the dark, its dawn sky in the light. The
    /// plot fades from the page into it and back out at its foot.
    public var sky: SomaColorValue

    public init(awake: SomaColorValue, rem: SomaColorValue, core: SomaColorValue, deep: SomaColorValue,
                sky: SomaColorValue) {
        self.awake = awake
        self.rem = rem
        self.core = core
        self.deep = deep
        self.sky = sky
    }

    /// Read from the earlier app's night chart (owner, 2026-10-24): awake a red orange,
    /// REM a pale cyan, light sleep a periwinkle blue, deep a royal blue,
    /// each a step deeper on the light page so it holds on white.
    public static let standard = SomaSleepStagePalette(
        awake: SomaColorValue(light: 0xE8553A, dark: 0xF2603F),
        rem: SomaColorValue(light: 0x4FB3D9, dark: 0xA6DDF7),
        core: SomaColorValue(light: 0x5A72F0, dark: 0x5368F2),
        deep: SomaColorValue(light: 0x3438C2, dark: 0x2D3FD8),
        // The earlier app's skies: the night's middle stop, #1B2349, and its
        // dawn's deepest, #DFE5F5.
        sky: SomaColorValue(light: 0xDFE5F5, dark: 0x1B2349)
    )
}
