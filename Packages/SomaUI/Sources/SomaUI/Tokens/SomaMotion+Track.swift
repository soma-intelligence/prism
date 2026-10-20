//
//  SomaMotion+Track.swift
//  SomaUI
//

import SwiftUI

/// How Track's answers and ticks move: quick, physical and quiet.
///
/// Computed so they add no stored field to the theme. Under Reduce Motion
/// each control lands in its new state at once, with no slide, scale or draw.
public extension SomaMotion {
    /// A chosen cell sliding from one answer to the other, or settling in
    /// from nothing: a short spring with a touch of give.
    var trackAnswer: Animation { .spring(duration: 0.32, bounce: 0.16) }
    /// A check or a cross drawing itself once its cell has landed.
    var trackMarkDraw: Animation { .easeOut(duration: 0.22).delay(0.06) }
    /// A cell giving way under the finger.
    var trackPress: Animation { .spring(duration: 0.16, bounce: 0) }
    /// How far a cell sinks while pressed.
    var trackPressScale: CGFloat { 0.92 }
    /// The scale a newly chosen cell grows from.
    var trackAnswerFrom: CGFloat { 0.72 }
}
