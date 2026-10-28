//
//  AskDrawerMotion.swift
//  Prism
//

import SwiftUI
import SomaUI

/// Where the history drawer sits under a finger, and where it goes when the
/// finger lets go.
///
/// Offsets are measured from the open drawer: 0 is open, `-width` is shut.
enum AskDrawerMotion {
    /// The rate a flicked scroll view slows at, which a flick of the drawer
    /// is projected with.
    static let deceleration: CGFloat = 0.998

    /// How long a finger has to hold still before it lets go at rest rather
    /// than at the speed it last moved.
    static let restAfter: CFTimeInterval = 0.08

    /// How far a flick moving at `velocity` points a second would carry on
    /// before it came to rest, the way a scroll view coasts.
    static func projection(_ velocity: CGFloat) -> CGFloat {
        velocity / 1000 * deceleration / (1 - deceleration)
    }

    /// The drawer's offset for a finger's: one to one while it is between
    /// shut and open, held at shut, and damped past open, so a pull the wrong
    /// way gives a little and no more.
    static func offset(_ finger: CGFloat, width: CGFloat) -> CGFloat {
        if finger > 0 { return SomaPartMath.resisted(finger, width: width) }
        return max(finger, -width)
    }

    /// Whether the drawer ends open when let go at `offset`, moving at
    /// `velocity` points a second. A flick decides by its direction alone,
    /// however short it was; a slow release by where the projection lands.
    static func landsOpen(offset: CGFloat, velocity: CGFloat, width: CGFloat, flick: CGFloat) -> Bool {
        if velocity <= -flick { return false }
        if velocity >= flick { return true }
        return offset + projection(velocity) > -width / 2
    }

    /// The finger's speed as a spring's starting velocity, which is counted
    /// in whole journeys a second: the distance left to `target` from `from`.
    /// A finger still moving away from the target gives a negative start,
    /// which carries the drawer on a little before it turns back.
    static func springVelocity(_ velocity: CGFloat, from: CGFloat, to target: CGFloat) -> Double {
        let distance = target - from
        guard abs(distance) > 1 else { return 0 }
        return Double(min(max(velocity / distance, -12), 12))
    }
}

#if os(iOS)
/// The pan that drags the history drawer.
///
/// Two kinds: one on the open drawer and its scrim that begins only on a
/// sideways move, so the conversation list keeps every upright drag; and one
/// from the screen's leading edge that pulls the shut drawer out. The list's
/// scroll waits on the first for the instant it takes to decide.
struct AskDrawerPan: UIGestureRecognizerRepresentable {
    enum Kind { case drawer, edge }

    let kind: Kind
    var isEnabled = true
    /// Whether the leading edge is on the right, as it is for a right to
    /// left script.
    var isRightToLeft = false
    /// The finger's sideways travel since it came down, toward the trailing
    /// edge positive.
    var changed: @MainActor (CGFloat) -> Void
    /// The travel and the speed, in points a second, when it lets go.
    var ended: @MainActor (CGFloat, CGFloat) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan: UIPanGestureRecognizer
        switch kind {
        case .drawer:
            pan = UIPanGestureRecognizer()
        case .edge:
            let edge = UIScreenEdgePanGestureRecognizer()
            edge.edges = isRightToLeft ? .right : .left
            pan = edge
        }
        pan.maximumNumberOfTouches = 1
        pan.delegate = context.coordinator
        pan.isEnabled = isEnabled
        return pan
    }

    func updateUIGestureRecognizer(_ recognizer: UIPanGestureRecognizer, context: Context) {
        recognizer.isEnabled = isEnabled
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        // Toward the trailing edge is positive whichever way the script runs.
        let sign: CGFloat = isRightToLeft ? -1 : 1
        let travel = recognizer.translation(in: nil).x * sign
        let now = CACurrentMediaTime()
        switch recognizer.state {
        case .began, .changed:
            context.coordinator.lastMove = now
            changed(travel)
        case .ended:
            // A pan's velocity is worked out from the last moves, so a finger
            // that came to rest before lifting still reports the speed it had.
            // Held still, it lets go at rest.
            let held = now - context.coordinator.lastMove > AskDrawerMotion.restAfter
            ended(travel, held ? 0 : recognizer.velocity(in: nil).x * sign)
        case .cancelled, .failed:
            ended(travel, 0)
        default:
            break
        }
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        /// When the finger last moved, on the media clock.
        var lastMove: CFTimeInterval = 0

        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let pan = recognizer as? UIPanGestureRecognizer else { return false }
            if pan is UIScreenEdgePanGestureRecognizer { return true }
            let velocity = pan.velocity(in: nil)
            return abs(velocity.x) > abs(velocity.y) * 1.4
        }

        /// The list's scroll waits for the drawer's pan to fail, which it
        /// does at once for an upright drag.
        func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
            !(recognizer is UIScreenEdgePanGestureRecognizer) && other.view is UIScrollView && other is UIPanGestureRecognizer
        }
    }
}
#endif
