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
    /// The answer knob sliding from one slot to another: a short spring
    /// with a touch of give.
    var trackAnswer: Animation { .spring(duration: 0.32, bounce: 0.16) }
    /// A ritual's check drawing itself once its square has filled.
    var trackMarkDraw: Animation { .easeOut(duration: 0.22).delay(0.06) }
    /// The scale a ticked ritual square grows from.
    var trackAnswerFrom: CGFloat { 0.72 }
}
