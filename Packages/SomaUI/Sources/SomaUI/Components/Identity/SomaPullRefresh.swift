//
//  SomaPullRefresh.swift
//  SomaUI
//

import SwiftUI

public extension View {
    /// Pull to refresh with Soma's own indicator in place of the system
    /// spinner: as the page is pulled, the mark unfolds out of its dot, a
    /// light tap says the pull is far enough, and on release the mark loops
    /// until `action` returns, then folds away.
    ///
    /// Apply it to a scroll view, or to a view that holds one. The Mac and
    /// the headset have no pull gesture; there the system's refresh action
    /// is installed instead, so a menu or a key command can still call it.
    func somaRefreshable(_ action: @escaping @Sendable () async -> Void) -> some View {
        modifier(SomaPullRefresh(action: action))
    }
}

/// The mark at a share of its unfolding: 0 is the dot alone, 1 the whole
/// mark. Driven by a pull, not by a clock.
public struct SomaMarkPull: View {
    private let progress: Double

    @Environment(\.somaTheme) private var theme

    public init(progress: Double) {
        self.progress = progress
    }

    public var body: some View {
        SomaMarkUnfoldFrame(time: time, ink: theme.colors.inkPrimary.color)
            .accessibilityHidden(true)
    }

    /// The moment of the unfold loop that shows this much of the mark: the
    /// stretch of the cycle where the arms open.
    private var time: Double {
        let choreography = SomaMarkUnfoldChoreography.self
        let share = min(max(progress, 0), 1)
        return choreography.period * (choreography.openStart + share * (choreography.openEnd - choreography.openStart))
    }
}

struct SomaPullRefresh: ViewModifier {
    let action: @Sendable () async -> Void

    @Environment(\.somaTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// How far past the top the content is pulled, in points.
    @State private var pull: CGFloat = 0
    @State private var isInteracting = false
    @State private var isRefreshing = false
    @State private var armed = false

    /// The pull that arms a refresh.
    private var threshold: CGFloat { theme.metrics.minimumTapTarget * 1.6 }

    func body(content: Content) -> some View {
#if os(iOS)
        let side = theme.metrics.minimumTapTarget * 0.55
        let zone = side + theme.metrics.spaceM * 2
        let progress = Double(pull / threshold)

        content
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                max(0, -(geometry.contentOffset.y + geometry.contentInsets.top))
            } action: { _, new in
                pull = new
                let reached = new >= threshold
                if isInteracting, reached != armed { armed = reached }
            }
            .onScrollPhaseChange { _, phase in
                let interacting = phase == .interacting
                if isInteracting, !interacting, armed, !isRefreshing { start() }
                isInteracting = interacting
                if !interacting { armed = false }
            }
            .sensoryFeedback(.impact(weight: .light), trigger: armed) { _, new in new }
            // While it works, the mark has a strip of its own over the
            // content, which moves down to make room: it never sits on what
            // is under it (owner, 2026-10-24).
            .safeAreaInset(edge: .top, spacing: 0) {
                ZStack {
                    if isRefreshing {
                        SomaMarkUnfold(accessibilityLabel: "Updating", mode: .loop)
                            .frame(width: side, height: side)
                            .transition(.opacity.combined(with: .scale(scale: 0.6)))
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: isRefreshing ? zone : 0)
                .clipped()
                .allowsHitTesting(false)
            }
            // While pulled, the mark grows in the gap the pull opens, and
            // shows only once the gap can hold it.
            .overlay(alignment: .top) {
                if !isRefreshing, pull > side {
                    SomaMarkPull(progress: progress)
                        .frame(width: side, height: side)
                        .opacity(min(1, Double((pull - side) / side)))
                        .scaleEffect(0.7 + 0.3 * min(1, progress))
                        .padding(.top, (min(pull, threshold) - side) / 2)
                        .allowsHitTesting(false)
                }
            }
#else
        content.refreshable { await action() }
#endif
    }

    /// The strip opens and closes on its own transaction, so the page's
    /// new numbers arriving with it keep their own animations.
    private func start() {
        withAnimation(reduceMotion ? nil : theme.motion.standard) { isRefreshing = true }
        Task { @MainActor in
            await action()
            // Long enough for the loop to read as a beat, never a flash.
            try? await Task.sleep(for: .milliseconds(350))
            withAnimation(reduceMotion ? nil : theme.motion.standard) { isRefreshing = false }
        }
    }
}

/// A small glass pill that says the numbers under it are from earlier and a
/// fresh read is on its way: the mark looping, then "Updating" and how old
/// they are. Shown while a page draws its last known numbers, and gone the
/// moment the new ones land.
public struct SomaUpdatingPill: View {
    private let since: Date?

    @Environment(\.somaTheme) private var theme

    /// - Parameter since: when the numbers on screen were read.
    public init(since: Date?) {
        self.since = since
    }

    public var body: some View {
        let metrics = theme.metrics

        HStack(spacing: metrics.spaceS) {
            SomaMarkUnfold(accessibilityLabel: "Updating", mode: .loop)
                .frame(width: 14, height: 14)
            Group {
                if let since {
                    Text("Updating \u{00B7} \(since, format: .relative(presentation: .named))")
                } else {
                    Text("Updating")
                }
            }
            .somaFont(theme.typography.caption)
            .foregroundStyle(theme.colors.inkSecondary.color)
        }
        .padding(.horizontal, metrics.spaceM)
        .padding(.vertical, metrics.spaceS - 1)
        .somaGlass(in: .capsule)
        .accessibilityElement(children: .combine)
    }
}
