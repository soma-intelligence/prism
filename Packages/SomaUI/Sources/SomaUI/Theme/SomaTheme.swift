//
//  SomaTheme.swift
//  SomaUI
//

import SwiftUI

/// A whole brand as one value.
///
/// It is a struct, not a protocol: reading a token off the theme is a field
/// access rather than a witness-table call, and the whole thing compares in one
/// `==`, so a view that takes the theme from the environment can be skipped
/// wholesale when nothing in it moved.
///
/// A variant is built by copying the shipped theme and editing what it needs:
/// the structure, the components and the metrics stay shared.
///
/// The values sit in one immutable box, so a theme is the size of a pointer.
/// Every component reads the theme through `@Environment`, and a property
/// wrapper stores its value inline: with the values inline, each component
/// carried two kilobytes of theme, and a Debug build copied them for every
/// token it read. The phone's main thread has a megabyte of stack, and a page
/// of such components overflowed it at launch. An edit makes a new box, which
/// is rare and cheap; reading never copies more than the part it asks for.
public struct SomaTheme: Sendable, Equatable {
    private var box: Box

    public var colors: SomaColors {
        get { box.values.colors }
        set { edit { $0.colors = newValue } }
    }

    public var typography: SomaTypography {
        get { box.values.typography }
        set { edit { $0.typography = newValue } }
    }

    public var metrics: SomaMetrics {
        get { box.values.metrics }
        set { edit { $0.metrics = newValue } }
    }

    public var motion: SomaMotion {
        get { box.values.motion }
        set { edit { $0.motion = newValue } }
    }

    /// The six aspects: the hue that names each one, and the palette its orb
    /// is painted with.
    public var aspects: SomaAspects {
        get { box.values.aspects }
        set { edit { $0.aspects = newValue } }
    }

    public init(
        colors: SomaColors,
        typography: SomaTypography = .standard,
        metrics: SomaMetrics = .standard,
        motion: SomaMotion = .standard,
        aspects: SomaAspects = .standard
    ) {
        box = Box(Values(colors: colors, typography: typography, metrics: metrics, motion: motion, aspects: aspects))
    }

    /// The website's look, and the one theme the app ships.
    public static let standard = SomaTheme(colors: .standard)

    /// A copy of this theme carrying a different accent.
    ///
    /// The one accent rule holds: this swaps the single active accent, it does
    /// not add a second one.
    public func withAccent(_ accent: SomaColorValue) -> SomaTheme {
        var copy = self
        copy.colors.accent = accent
        return copy
    }

    public static func == (lhs: SomaTheme, rhs: SomaTheme) -> Bool {
        lhs.box === rhs.box || lhs.box.values == rhs.box.values
    }

    private mutating func edit(_ change: (inout Values) -> Void) {
        var values = box.values
        change(&values)
        box = Box(values)
    }

    private struct Values: Sendable, Equatable {
        var colors: SomaColors
        var typography: SomaTypography
        var metrics: SomaMetrics
        var motion: SomaMotion
        var aspects: SomaAspects
    }

    private final class Box: Sendable {
        let values: Values

        init(_ values: Values) {
            self.values = values
        }
    }
}
