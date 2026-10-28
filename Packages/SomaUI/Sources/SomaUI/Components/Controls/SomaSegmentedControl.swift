//
//  SomaSegmentedControl.swift
//  SomaUI
//

import SwiftUI

/// One segment of a ``SomaSegmentedControl``.
public struct SomaSegment<ID: Hashable>: Identifiable {
    public let id: ID
    public let title: LocalizedStringResource

    public init(id: ID, title: LocalizedStringResource) {
        self.id = id
        self.title = title
    }
}

extension SomaSegment: Sendable where ID: Sendable {}

/// A row of labels on one glass track, the selected one sitting in a pill.
///
/// Built for the middle of a top bar, where a page offers its parts. The track
/// is glass because it floats as chrome; the pill is not, because glass laid on
/// glass is decoration. The pill is a fill moved by `matchedGeometryEffect`, so
/// it slides from one segment to the next and settles where it lands.
public struct SomaSegmentedControl<ID: Hashable>: View {
    private let segments: [SomaSegment<ID>]
    @Binding private var selection: ID

    @Environment(\.somaTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var pill

    public init(segments: [SomaSegment<ID>], selection: Binding<ID>) {
        self.segments = segments
        self._selection = selection
    }

    public var body: some View {
        HStack(spacing: theme.metrics.segmentSpacing) {
            ForEach(segments) { segment in
                SomaSegmentButton(
                    segment: segment,
                    isSelected: segment.id == selection,
                    namespace: pill
                ) {
                    select(segment.id)
                }
            }
        }
        .padding(.horizontal, theme.metrics.segmentTrackPadding)
        // The control stands as tall as the smallest touch target and draws its
        // track inset by the difference, so every segment answers a tap across
        // that whole height while the track keeps its drawn size. A hit shape
        // reaching past the control's frame would not do: a toolbar hosts an
        // item in a view its own size, and a touch outside it never arrives.
        .background {
            Color.clear
                .somaGlass(.regular, in: .capsule)
                .padding(.vertical, theme.metrics.segmentReach)
        }
        .sensoryFeedback(.selection, trigger: selection)
    }

    private func select(_ id: ID) {
        guard id != selection else { return }
        // The still counterpart: under Reduce Motion the pill settles on the
        // new segment rather than travelling there.
        withAnimation(reduceMotion ? nil : theme.motion.selection) {
            selection = id
        }
    }
}

// MARK: - One segment

private struct SomaSegmentButton<ID: Hashable>: View {
    let segment: SomaSegment<ID>
    let isSelected: Bool
    let namespace: Namespace.ID
    let action: () -> Void

    @Environment(\.somaTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    /// In light, the pill is the dark appearance's surface under its ink: the
    /// concept's dark lozenge on bright glass. In dark that surface sank into
    /// the dark glass (the selection all but vanished), so there the pill is
    /// a tonal step up from the track instead: the ink laid thin over it. Never
    /// cream: a light pill would be the loudest thing on a dark screen.
    private var pillFill: Color {
        colorScheme == .dark
            ? theme.colors.inkPrimary.color.opacity(theme.metrics.segmentPillDarkLift)
            : SomaColorValue(theme.colors.surface.dark).color
    }
    private var pillInk: Color { SomaColorValue(theme.colors.inkPrimary.dark).color }

    var body: some View {
        Button(action: action) {
            Text(segment.title)
                .somaFont(theme.typography.segment)
                .fontWeight(isSelected ? theme.typography.segment.weight : .regular)
                .lineLimit(1)
                // Primary ink on the unselected segments, as the system's
                // own segmented controls set them: the pill alone marks the
                // selection. Secondary ink sinks into the glass wherever a
                // page's wash sits behind the bar (under 2:1 on Body and
                // Mind in dark mode).
                .foregroundStyle(isSelected ? pillInk : theme.colors.inkPrimary.color)
                .padding(.horizontal, theme.metrics.segmentLabelPadding)
                .frame(minHeight: theme.metrics.segmentHeight)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(pillFill)
                            .overlay {
                                Capsule().strokeBorder(
                                    pillInk.opacity(theme.metrics.hairlineOpacity),
                                    lineWidth: 0.5
                                )
                            }
                            .matchedGeometryEffect(id: "pill", in: namespace)
                    }
                }
                // The track's inset and the reach past it are part of every
                // segment's hit area, so a tap anywhere in the control's
                // height lands, not only on the pill.
                .padding(.vertical, theme.metrics.segmentTrackPadding + theme.metrics.segmentReach)
                .contentShape(.rect)
        }
        // Dim without the scale: a label shrinking inside its track reads as
        // the track flinching.
        .buttonStyle(.somaGlassPressDim)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

#Preview("Segmented Control") {
    @Previewable @State var selection = "today"

    ZStack {
        SomaPreviewBackdrop()

        SomaSegmentedControl(
            segments: [
                SomaSegment(id: "today", title: "Today"),
                SomaSegment(id: "trends", title: "Trends"),
                SomaSegment(id: "explore", title: "Explore"),
            ],
            selection: $selection
        )
    }
}
