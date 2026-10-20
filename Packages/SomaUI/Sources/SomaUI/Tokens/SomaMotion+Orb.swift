//
//  SomaMotion+Orb.swift
//  SomaUI
//

import Foundation

/// How the hero orb lives while nobody touches it: a slow breath and a
/// colour field that drifts rather than churns.
///
/// Computed so they add no stored field to the theme. Under Reduce Motion the
/// orb holds still at the middle of its breath.
public extension SomaMotion {
    /// One whole breath, in and out, in seconds. About seven breaths a
    /// minute, the pace a slow breathing exercise settles on.
    var orbBreathPeriod: Double { 8.5 }
    /// How far the orb grows at the top of a breath, as a share of its size.
    /// Small enough to be felt rather than seen.
    var orbBreathDepth: Double { 0.014 }
    /// How much brighter the halo glows at the top of a breath.
    var orbHaloBreath: Double { 0.22 }
    /// The weather's pace at rest against the aspect's own speed: the
    /// website's flow, slowed until it drifts.
    var orbFlowRate: Double { 0.3 }
    /// How much of the weather's fine swirl is smoothed away, 0 to 1: the
    /// large shapes stay, the small eddies that read as boiling go.
    var orbCalm: Double { 0.75 }
}

/// The orb's idle motion as pure functions of the clock, so a frame costs a
/// few multiplications and nothing accumulates between frames.
public enum SomaOrbIdle {
    /// The breath at `time` seconds, from -1 (all out) to 1 (all in).
    ///
    /// A slow sine with a second, slower one laid over it at a fifth of its
    /// strength, so no two breaths are quite the same and the rhythm never
    /// reads as a metronome. Smooth at every instant: no jitter, no kink.
    public static func breath(at time: Double, period: Double) -> Double {
        guard period > 0 else { return 0 }
        let main = sin(2 * .pi * time / period)
        let drift = sin(2 * .pi * time / (period * 1.618) + 1.1)
        return (main * 0.8 + drift * 0.2)
    }

    /// The orb's scale at `time`: one plus the breath's share of `depth`.
    public static func scale(at time: Double, period: Double, depth: Double) -> Double {
        1 + depth * breath(at: time, period: period)
    }
}

public extension SomaMotion {
    /// The longest the orb waits between frames while it rests, with no
    /// travel to a new look: its drift is slow enough that thirty frames a
    /// second read as smooth, where a ProMotion screen would otherwise draw
    /// the shader a hundred and twenty times a second.
    var orbRestFrameInterval: Double { 1.0 / 30.0 }
}
