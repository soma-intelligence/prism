//
//  SomaCardArrival.swift
//  SomaUI
//

import SwiftUI

public extension View {
    /// A card's first appearance: it fades up a few points into place, a
    /// short step after the card before it.
    ///
    /// The list flips `isShown` once, when it first shows; every card then
    /// arrives in order of `index`. Cards past
    /// ``SomaMotion/cardArrivalSteps`` arrive with the last stepped one, and a
    /// card built after the flip (scrolled into a lazy stack) is simply there.
    /// Under Reduce Motion every card is in place from the first frame.
    func somaCardArrival(index: Int, isShown: Bool) -> some View {
        modifier(SomaCardArrival(index: index, isShown: isShown))
    }

    /// A card easing as it scrolls in or out at an edge of its scroll view:
    /// a touch smaller and softer there, itself again once it is in view.
    /// Still under Reduce Motion.
    func somaScrollEdge(_ axis: Axis = .vertical) -> some View {
        modifier(SomaScrollEdge(axis: axis))
    }
}

struct SomaCardArrival: ViewModifier {
    let index: Int
    let isShown: Bool

    @Environment(\.somaTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let motion = theme.motion
        let shown = isShown || reduceMotion
        let step = Double(min(max(index, 0), motion.cardArrivalSteps)) * motion.cardArrivalStep

        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : motion.cardArrivalRise)
            .scaleEffect(shown ? 1 : motion.cardArrivalFrom, anchor: .top)
            .animation(reduceMotion ? nil : motion.cardArrival.delay(step), value: isShown)
    }
}

struct SomaScrollEdge: ViewModifier {
    let axis: Axis

    @Environment(\.somaTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let motion = theme.motion
        let still = reduceMotion

        content
            .scrollTransition(.interactive, axis: axis) { view, phase in
                view
                    .scaleEffect(still || phase.isIdentity ? 1 : motion.scrollEdgeScale)
                    .opacity(still || phase.isIdentity ? 1 : motion.scrollEdgeOpacity)
            }
    }
}

#Preview("Card arrival and scroll edge") {
    @Previewable @State var shown = false
    ScrollView {
        VStack(spacing: 12) {
            ForEach(0..<12, id: \.self) { index in
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(SomaTrackTone.allCases[index % SomaTrackTone.allCases.count].color.opacity(0.25))
                    .frame(height: 96)
                    .somaCardArrival(index: index, isShown: shown)
                    .somaScrollEdge()
            }
        }
        .padding()
    }
    .onAppear { shown = true }
}
