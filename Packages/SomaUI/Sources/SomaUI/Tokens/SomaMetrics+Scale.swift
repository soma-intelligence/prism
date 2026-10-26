//
//  SomaMetrics+Scale.swift
//  SomaUI
//

import CoreGraphics

/// The spacing scale every measurement in the system is read from: steps of
/// four points, named so a view asks for a step rather than a number.
///
/// Mirrored in the Figma kit, page `24 Harmony`. A token that is not one of
/// these steps is either a size (a glyph, a diameter, a height) or a defect.
/// The same steps serve touch and pointer: the pointer scale is tighter
/// because its semantic tokens pick smaller steps, not because a step shrinks.
public extension SomaMetrics {
    /// 2: between a value and the label tight under it.
    var spaceXXS: CGFloat { 2 }
    /// 4: icon to label, number to unit.
    var spaceXS: CGFloat { 4 }
    /// 8: label to value, lines of stacked text.
    var spaceS: CGFloat { 8 }
    /// 12: between cards, between the parts of a row.
    var spaceM: CGFloat { 12 }
    /// 16: a card's padding, the phone's gutter.
    var spaceL: CGFloat { 16 }
    /// 24: between sections.
    var spaceXL: CGFloat { 24 }
    /// 32: breathing room at the head of a page.
    var spaceXXL: CGFloat { 32 }
}
