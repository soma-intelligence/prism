//
//  SomaOrbTap.swift
//  SomaUI
//

import SwiftUI

public extension View {
    /// Makes the orb a button: it answers the moment the finger lands (the
    /// theme's press, a scale and a dim, with its haptic) and `action` runs as
    /// the finger lifts, with no wait in between. The page it opens zooms out
    /// of the orb, which carries the continuity a squeeze used to. No rings
    /// ripple from the rim (owner, 2026-10-24).
    ///
    /// `longPress`, when given, runs on a long press instead, and the lift
    /// that ends that press does not also run `action`.
    func somaOrbTap(aspect: SomaAspect, longPress: (() -> Void)? = nil, action: @escaping () -> Void) -> some View {
        modifier(SomaOrbTap(aspect: aspect, longPress: longPress, action: action))
    }
}

struct SomaOrbTap: ViewModifier {
    let aspect: SomaAspect
    let longPress: (() -> Void)?
    let action: () -> Void

    /// Set when a long press fired, so the button's own lift, which follows
    /// it, is swallowed rather than opening the page under the sheet.
    @State private var heldLong = false

    func body(content: Content) -> some View {
        Button {
            if heldLong {
                heldLong = false
                return
            }
            action()
        } label: {
            content.contentShape(.circle)
        }
        // The theme's press: scale and dim on touch down, the same in every
        // context. A three percent scale is feedback, not travel, so Reduce
        // Motion keeps it and both paths open the page at the same moment.
        .buttonStyle(.somaGlassPress)
        .simultaneousGesture(
            LongPressGesture().onEnded { _ in
                guard let longPress else { return }
                heldLong = true
                longPress()
            },
            including: longPress == nil ? .subviews : .all
        )
    }
}

#Preview("Orb tap") {
    @Previewable @State var taps = 0
    ZStack {
        SomaPreviewBackdrop()
        VStack(spacing: 24) {
            SomaOrb(aspect: .mind, label: "Slow down")
                .somaOrbTap(aspect: .mind) { taps += 1 }
            Text(verbatim: "\(taps)")
        }
    }
}
