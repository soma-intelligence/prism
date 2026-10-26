//
//  SomaColors.swift
//  SomaUI
//

import SwiftUI

/// The colour scale a brand hands to the components.
///
/// Every field is a plain value: the whole scale is `Equatable`, so SwiftUI can
/// tell in one comparison that the theme has not changed and skip the subtree.
public struct SomaColors: Sendable, Equatable {
    /// The base ground the app sits on.
    public var canvas: SomaColorValue
    /// One tonal step above the canvas: where a card sits.
    public var surface: SomaColorValue
    /// One step below the canvas, for recessed wells.
    public var surfaceRecessed: SomaColorValue
    /// The single active accent. Action, selection, state: never decoration.
    public var accent: SomaColorValue
    /// What reads on top of a filled accent.
    public var onAccent: SomaColorValue
    /// Titles and body copy.
    public var inkPrimary: SomaColorValue
    /// Sub-text and unselected chrome.
    public var inkSecondary: SomaColorValue
    /// What cannot be undone. Deletion, withdrawal, a wipe.
    ///
    /// The eighth role, and the only one that is not part of the accent's job.
    /// An accent carries action and selection, which a person chooses freely;
    /// this carries consequence, which they do not get to take back. A row that
    /// erases data and looks like every other row is a trap, and the rule about
    /// a single accent is about decoration rather than warning.
    public var danger: SomaColorValue
    /// A recording: the timer and the record button, as the Camera app shows
    /// them. Not danger, which is for what cannot be undone, and not the
    /// accent, which carries action and selection: a red that says "recording"
    /// and nothing else.
    public var record: SomaColorValue
    /// The move written on an orb. The orb keeps its deep palette on both
    /// grounds, so what is written on it stays light on both.
    public var onOrb: SomaColorValue
    /// A reading inside its normal range: the green dot and word under a
    /// metric, and the band behind its chart.
    public var statusNormal: SomaColorValue
    /// A reading above or below its normal range: worth a look, not alarming.
    public var statusOut: SomaColorValue
    /// A reading far out of range, a blood pressure stage, say.
    public var statusAlert: SomaColorValue
    /// The four sleep stages, for hypnograms and anything that names a stage.
    public var sleepStages: SomaSleepStagePalette

    public init(
        canvas: SomaColorValue,
        surface: SomaColorValue,
        surfaceRecessed: SomaColorValue,
        accent: SomaColorValue,
        onAccent: SomaColorValue,
        inkPrimary: SomaColorValue,
        inkSecondary: SomaColorValue,
        danger: SomaColorValue,
        record: SomaColorValue = SomaColorValue(light: 0xFF3B30, dark: 0xFF453A),
        onOrb: SomaColorValue = SomaColorValue(0xFFFFFF),
        statusNormal: SomaColorValue = SomaColorValue(light: 0x1F7F38, dark: 0x34C759),
        statusOut: SomaColorValue = SomaColorValue(light: 0xC93400, dark: 0xFF9F0A),
        statusAlert: SomaColorValue = SomaColorValue(light: 0xD70015, dark: 0xFF6961),
        sleepStages: SomaSleepStagePalette = .standard
    ) {
        self.canvas = canvas
        self.surface = surface
        self.surfaceRecessed = surfaceRecessed
        self.accent = accent
        self.onAccent = onAccent
        self.inkPrimary = inkPrimary
        self.inkSecondary = inkSecondary
        self.danger = danger
        self.record = record
        self.onOrb = onOrb
        self.statusNormal = statusNormal
        self.statusOut = statusOut
        self.statusAlert = statusAlert
        self.sleepStages = sleepStages
    }
}

public extension SomaColors {
    /// The app's palette: cool graphite grounds in dark, a pale grey page
    /// under white cards in light, and no hue at all in the chrome.
    ///
    /// Neutral grounds, plain ink, colour kept for the readings themselves.
    /// The accent is therefore ink rather than a hue, white on the dark ground
    /// and near black on the light one, so a selected tab or a primary button
    /// reads as the brightest thing on the screen and nothing else competes
    /// with the data.
    ///
    /// The grounds are page `#1F2023` and card `#2E3037` in dark, page
    /// `#F4F4F6` and card white in light. The recessed well sits between page
    /// and card.
    /// The website's `--app-*` bridge still carries the old warm values.
    static let standard = SomaColors(
        canvas: SomaColorValue(light: 0xF4F4F6, dark: 0x1F2023),
        surface: SomaColorValue(light: 0xFFFFFF, dark: 0x2E3037),
        surfaceRecessed: SomaColorValue(light: 0xECECF0, dark: 0x27282D),
        accent: SomaColorValue(light: 0x1C1C1E, dark: 0xFFFFFF),
        onAccent: SomaColorValue(light: 0xFFFFFF, dark: 0x1F2023),
        inkPrimary: SomaColorValue(light: 0x1C1C1E, dark: 0xFFFFFF),
        inkSecondary: SomaColorValue(light: 0x6C6C72, dark: 0x9A9BA1),
        danger: SomaColorValue(light: 0xB3261E, dark: 0xF2B8B5),
        record: SomaColorValue(light: 0xFF3B30, dark: 0xFF453A),
        onOrb: SomaColorValue(0xFFFFFF)
    )
}
