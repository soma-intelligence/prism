//
//  SomaMetrics+Settings.swift
//  SomaUI
//

import CoreGraphics

public extension SomaMetrics {
    /// Keeps settings readable when presented in a wide sheet or window.
    var settingsContentWidth: CGFloat { 560 }
    /// A little breathing room around each full-width settings action.
    var settingsRowHeight: CGFloat { minimumTapTarget + browseRowVerticalPadding }
    /// Settings symbols support the labels rather than competing with them.
    var settingsGlyphSize: CGFloat { browseGlyphSize - scoreLabelSpacing }
}
