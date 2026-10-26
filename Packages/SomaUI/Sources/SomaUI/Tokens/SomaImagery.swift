//
//  SomaImagery.swift
//  SomaUI
//

import SwiftUI

/// The tactile objects Soma draws instead of a glyph: one clay object per
/// aspect, plus the two readings that are not aspects.
///
/// The owner picked them from the Airbnb mockups of 2026-10-13: the app keeps
/// its own bar and its own data layout, and takes only the imagery and these
/// objects. All of them share one camera, one light and one matte material, so
/// they read as a family rather than as clip art. They ship as images in this
/// package's asset catalog, never as views drawn in code.
public enum SomaObject: String, Sendable, Equatable, CaseIterable {
    case sleep
    case heart
    case activity
    case mind
    case body
    case gut
    case energy
    case environment

    /// The object an aspect wears.
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

    /// The image set's name in `Imagery.xcassets`.
    public var assetName: String { "object.\(rawValue)" }
}

/// The photographs a card can sit on: a real, quiet place for each aspect,
/// with no people in them.
public enum SomaPhoto: String, Sendable, Equatable, CaseIterable {
    case sleep
    case heart
    case activity
    case mind
    case body
    case environment

    /// The photograph an aspect's card sits on. Gut has no place of its own
    /// yet and borrows the quiet window seat of Mind.
    public init(_ aspect: SomaAspect) {
        switch aspect {
        case .sleep: self = .sleep
        case .heart: self = .heart
        case .activity: self = .activity
        case .mind, .gut: self = .mind
        case .body: self = .body
        }
    }

    /// The image set's name in `Imagery.xcassets`.
    public var assetName: String { "photo.\(rawValue)" }
}

public extension SomaColors {
    /// The shade laid over a photograph so the words on it stay legible. The
    /// same near black in both appearances: a photograph does not change with
    /// the system's.
    var photoScrim: SomaColorValue { SomaColorValue(0x0B0B0D) }
    /// The ink of a label or a caption laid on a photograph. The dark
    /// appearance's secondary grey is drawn for a flat ground and sinks into
    /// a busy picture, so the words and the outline of a move's check take a
    /// near white instead: still a step under the primary white.
    var photoInkSecondary: SomaColorValue { SomaColorValue(0xE2E2E6) }
}

/// The proportions of the imagery.
///
/// Computed from the stored metrics so they follow the touch and pointer
/// scales without adding a stored field to the theme.
public extension SomaMetrics {
    /// An object set inline beside a label: a score's name, a card's title.
    var objectInline: CGFloat { identityDotDiameter * 2.5 }
    /// An object leading a row, such as a next move.
    var objectRow: CGFloat { checkDiameter * 1.45 }
    /// The shortest a photo card may be, so the photograph reads as a place
    /// rather than a strip.
    var photoCardMinHeight: CGFloat { orbDiameter * 0.78 }
    /// The scrim's opacity at the top of a photo card, where the photograph
    /// shows most, and at the bottom, where the words sit.
    var photoScrimTop: Double { 0.22 }
    var photoScrimBottom: Double { 0.74 }
}

/// The canvas veil over a landscape page head: at the top, where the bar's
/// segments and the stats sit, and partway down.
public extension SomaMetrics {
    var landscapeScrimTop: Double { 0.5 }
    var landscapeScrimMiddle: Double { 0.65 }
}
