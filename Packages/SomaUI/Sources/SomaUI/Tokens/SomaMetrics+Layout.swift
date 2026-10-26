//
//  SomaMetrics+Layout.swift
//  SomaUI
//

import CoreGraphics

/// The widths a page reflows at, read off the room a view is given rather than
/// off the device: one rule serves a phone, a foldable folded and unfolded, an
/// iPad in a Split View third or full screen, and a Mac window being resized.
///
/// Computed so they add no stored field to the theme.
public extension SomaMetrics {
    /// The narrowest a card column may be before the cards go back to one
    /// column. A card is drawn to hold at the width of the smallest phone, so a
    /// column this wide never squeezes one: a page two columns of this wide,
    /// plus the gap, gets a second column.
    var cardColumnMinWidth: CGFloat { 280 }
    /// The most card columns a page lays out, however wide it is. Past two, a
    /// page's cards stop reading as one story.
    var cardColumnLimit: Int { 2 }
    /// The widest a column of prose, a form or a conversation grows. Lines
    /// longer than this are hard to follow back to their start.
    var readableMaxWidth: CGFloat { 680 }
    /// The width from which a page sets two panes side by side: a list beside
    /// its detail, or the orb beside its cards.
    var twoPaneMinWidth: CGFloat { 700 }
    /// The leading pane's width when a list sits beside its detail.
    var listPaneWidth: CGFloat { 360 }
    /// The narrowest page whose top bar still holds a page's parts between the
    /// account and the bell without cutting a label short. Narrower (a Split
    /// View third, a slim window), the parts move under the bar.
    var partsInBarMinWidth: CGFloat { 390 }
}
