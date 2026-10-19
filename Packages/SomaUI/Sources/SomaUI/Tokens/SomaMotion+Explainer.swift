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
    var explainerDraw: Animation { .smooth(duration: 0.9).delay(0.12) }
}
