//
//  SomaMotion+Arrival.swift
//  SomaUI
//

import SwiftUI

/// How a list of cards arrives the first time it shows, and how a card eases
/// as it scrolls in from an edge.
///
/// Quiet on purpose: the owner turned down cards that swim into place
/// (2026-10-03), so a card only fades up a few points, one after the other
/// in quick steps, and scrolling only softens the cards at the very edges.
/// Computed so they add no stored field to the theme. Under Reduce Motion
/// cards are simply there and scrolling leaves them as they are.
public extension SomaMotion {
    /// One card fading up into place: a spring with no bounce.
    var cardArrival: Animation { .spring(duration: 0.38, bounce: 0) }
    /// The wait between one card and the next.
    var cardArrivalStep: Double { 0.045 }
    /// Cards past this many arrive together with the last stepped one, so a
    /// long list never makes anyone wait.
    var cardArrivalSteps: Int { 7 }
    /// How far below its place a card starts, in points.
    var cardArrivalRise: CGFloat { 8 }
    /// The scale a card starts from. Never from nothing.
    var cardArrivalFrom: CGFloat { 0.985 }
    /// A card at the edge of a scroll view, on its way in or out.
    var scrollEdgeScale: CGFloat { 0.96 }
    var scrollEdgeOpacity: Double { 0.72 }
    /// How long a page waits, once it shows again, before it reorders: long
    /// enough for a zoom back to land on the card it came from.
    var zoomBackSettle: Double { 0.6 }
    /// Cards taking their new places when a page reorders under the person.
    var pageReorder: Animation { .spring(duration: 0.45, bounce: 0) }
}
