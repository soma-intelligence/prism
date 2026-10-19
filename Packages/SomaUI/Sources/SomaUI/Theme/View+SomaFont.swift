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
}
