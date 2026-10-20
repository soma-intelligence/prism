//
//  SomaOrbPager.swift
//  SomaUI
//

import SwiftUI

/// The orb at the head of a page, and the dots that say which aspect it shows.
///
/// A swipe across the orb moves to the next or the previous aspect, wrapping
/// round, and the orb travels to that aspect's palette. VoiceOver reads it as
/// an adjustable control: swipe up or down to move between aspects.
///
/// The swipe is recognised alongside the page's scroll rather than instead of
/// it, so a vertical drag that starts on the orb still scrolls the page, and
/// only a drag that is mostly sideways changes the aspect.
public struct SomaOrbPager: View {
    @Binding private var selection: SomaAspect
    private let labels: [SomaAspect: LocalizedStringResource]

    @Environment(\.somaTheme) private var theme

    /// - Parameters:
    ///   - selection: the aspect the orb shows.
    ///   - labels: the move written on each aspect's orb. An aspect with no
    ///     move shows its name, so the orb never carries a move that nothing
    ///     in the data asked for.
    public init(selection: Binding<SomaAspect>, labels: [SomaAspect: LocalizedStringResource]) {
        _selection = selection
        self.labels = labels
    }

    public var body: some View {
        VStack(spacing: theme.metrics.heroSpacing) {
            SomaOrb(aspect: selection, label: labels[selection] ?? selection.title)
                .contentShape(.circle)
                .somaClaimsSwipe()
                .simultaneousGesture(swipe)

            SomaAspectDots(selection: selection)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(labels[selection] ?? selection.title))
        .accessibilityValue(Text(selection.title))
        .accessibilityHint(Text("Swipe up or down to read another aspect."))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: selection = selection.next
            case .decrement: selection = selection.previous
            @unknown default: break
            }
        }
    }

    private var swipe: some Gesture {
        DragGesture(minimumDistance: theme.metrics.minimumTapTarget / 2)
            .onEnded { value in
                let across = value.translation.width
                let down = value.translation.height
                // Mostly sideways, and far enough to mean it.
                guard abs(across) > abs(down) * 1.5, abs(across) > theme.metrics.minimumTapTarget else { return }
                selection = across < 0 ? selection.next : selection.previous
            }
    }
}

/// One dot per aspect, the selected one stretched: where the orb is in the
/// run of six.
public struct SomaAspectDots: View {
    private let selection: SomaAspect

    @Environment(\.somaTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(selection: SomaAspect) {
        self.selection = selection
    }

    public var body: some View {
        HStack(spacing: theme.metrics.aspectDotSpacing) {
            ForEach(SomaAspect.allCases) { aspect in
                Capsule()
                    .fill(theme.colors.inkPrimary.color)
                    .opacity(aspect == selection ? 1 : theme.metrics.aspectDotOpacity)
                    .frame(
                        width: aspect == selection ? theme.metrics.aspectDotSelectedWidth : theme.metrics.aspectDotSize,
                        height: theme.metrics.aspectDotSize
                    )
            }
        }
        .animation(reduceMotion ? nil : theme.motion.selection, value: selection)
        .accessibilityHidden(true)
    }
}

#Preview("Orb pager") {
    @Previewable @State var aspect: SomaAspect = .mind
    ZStack {
        SomaPreviewBackdrop()
        SomaOrbPager(selection: $aspect, labels: [.mind: "Slow down", .sleep: "Wind down"])
    }
}
