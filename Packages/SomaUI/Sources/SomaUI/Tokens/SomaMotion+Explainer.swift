//
//  SomaMotion+Explainer.swift
//  SomaUI
//

import SwiftUI

/// The explainer's one movement: the ring or the donut drawing itself as the
/// sheet arrives. Computed, like the other feature timings, so it adds no
/// stored field to the theme. Reduce Motion skips it and the drawing sits at
/// its value from the first frame.
public extension SomaMotion {
    /// The shared reveal, held back a beat so the sheet has landed before the
    /// drawing starts. It was a 0.9 second ease once, which left the ring
    /// still filling after the reader had moved on to the words.
    var explainerDraw: Animation { reveal.delay(0.1) }
}
