//
//  SomaMotion+Charts.swift
//  SomaUI
//

import SwiftUI

/// How a metric's chart moves: drawn in once when it arrives, morphed when
/// its span changes, and how quickly its readout follows a finger.
///
/// Computed so they add no stored field to the theme. Every one has a still
/// counterpart: under Reduce Motion the chart arrives drawn and swaps spans
/// with a short fade.
public extension SomaMotion {
    /// A chart drawing itself in: bars rising, a line tracing left to right.
    var chartDraw: Animation { .smooth(duration: 0.7) }
    /// The delay between one bar and the next as they rise, as a share of
    /// the whole draw, so a month of bars rises in the same time as a week.
    var chartStagger: Double { 0.28 }
    /// One span becoming another: values glide to their new height and place.
    var chartMorph: Animation { .spring(duration: 0.5, bounce: 0.08) }
    /// The readout and the rule following a finger across the plot.
    var chartScrub: Animation { .interactiveSpring(duration: 0.18) }
    /// The still counterpart of a morph under Reduce Motion.
    var chartFade: Animation { .easeOut(duration: 0.2) }
    /// A number rolling to its new value.
    var numberRoll: Animation { .snappy(duration: 0.35) }
    /// How long a rolling number with a unit after it keeps its old width,
    /// in seconds: until its digits have rolled.
    var numberRollHold: Double { 0.4 }
    /// The quiet "Updated" line fading out once a fresh read lands.
    var updatedNoteFade: Animation { .easeOut(duration: 0.3) }
}
