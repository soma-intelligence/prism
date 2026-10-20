//
//  SomaPageScroll.swift
//  SomaUI
//

import SwiftUI

/// A page's vertical scroll view, whose column is held to exactly the width
/// it is shown at, so the page never moves sideways.
///
/// A plain `ScrollView` takes its content's width as the scrollable width:
/// a column a third of a point wider than the screen (a rounded padding, a
/// label that will not wrap, a fixed size chart) lets a finger drag the
/// whole page sideways and leaves it there. Here the column is framed to the
/// scroll view's own width (`containerRelativeFrame(.horizontal)`), so there
/// is nothing to scroll across. Anything wider than that is a layout bug to
/// fix where it is; this only keeps it from moving the page.
///
/// Modifiers that act on the scroll views within a view (`scrollPosition`,
/// `scrollTargetBehavior`, `refreshable`, `defaultScrollAnchor`, the edge
/// fade) work on this one as on a `ScrollView`.
public struct SomaPageScroll<Content: View>: View {
    private let showsIndicators: Bool
    private let content: Content

    public init(showsIndicators: Bool = true, @ViewBuilder content: () -> Content) {
        self.showsIndicators = showsIndicators
        self.content = content()
    }

    @Environment(\.somaPartIsCurrent) private var isCurrent
    @Environment(\.somaEdgeFadeSink) private var fadeSink
    @State private var last = SomaPageScrollReading()

    public var body: some View {
        ScrollView(.vertical, showsIndicators: showsIndicators) {
            content
                .containerRelativeFrame(.horizontal)
        }
        // Kept without redrawing the page, for the moment its part of a tab
        // comes on screen and the fade over the bar has to read this scroll.
        .onScrollGeometryChange(for: SomaEdgeFade.Reading?.self) { geometry in
            SomaEdgeFade.reading(geometry)
        } action: { _, reading in
            last.reading = reading
        }
        // A part kept aside does not scroll, and is not the scroll the tab
        // bar follows.
        .scrollDisabled(!isCurrent)
        .onChange(of: isCurrent) { _, current in
            if current { fadeSink?.receive(last.reading) }
        }
    }
}

/// The last reading of a page's scroll, held in a box so keeping it does not
/// redraw the page on every frame of a scroll.
@MainActor
private final class SomaPageScrollReading {
    var reading: SomaEdgeFade.Reading?
}

#Preview("SomaPageScroll") {
    SomaPageScroll {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(1...30, id: \.self) { row in
                Text("Row \(row)")
            }
            // Wider than the screen: it is cut at the edge, the page stays put.
            Text("A line that will not wrap, however narrow the screen it is shown on")
                .fixedSize()
        }
        .padding(20)
    }
    .somaTheme(.standard)
}
