//
//  View+SomaFont.swift
//  SomaUI
//

import SwiftUI

public extension View {
    /// Applies one typographic role: its font and its tracking together.
    ///
    /// Tracking is half of a role. The display face is set tight and the
    /// eyebrow wide, and a call site that sets only the font draws neither. One
    /// call for both means the second half cannot be left out.
    func somaFont(_ spec: SomaFontSpec) -> some View {
        font(spec.font).tracking(spec.tracking)
    }

    /// Sets an SF Symbol glyph in a glyph role at the size of its control.
    ///
    /// The size comes from the metric the control is drawn at; the family and
    /// the weight come from the role, so a typography change reaches the icon
    /// as it reaches the text beside it.
    func somaGlyph(_ spec: SomaFontSpec, size: CGFloat) -> some View {
        font(.system(size: size, weight: spec.weight, design: spec.family.design))
    }
}
