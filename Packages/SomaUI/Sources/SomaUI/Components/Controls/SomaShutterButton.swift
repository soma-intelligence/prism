//
//  SomaShutterButton.swift
//  SomaUI
//

import SwiftUI

/// A camera's record button: a ring in the primary ink, white on the dark
/// Measure tab, round a red disc that starts, round a red square that stops.
///
/// Driven by its state and the theme alone. `dimmed` leaves it pressable, so a
/// screen can answer a press it cannot act on by pointing at what is missing;
/// it dims as a pressed control does. The disc and the square morph into each
/// other; with Reduce Motion they swap in place.
public struct SomaShutterButton: View {
    public enum State: Sendable, Equatable {
        case ready
        case recording
    }

    private let state: State
    private let dimmed: Bool
    private let accessibilityLabel: LocalizedStringResource
    private let action: () -> Void

    @Environment(\.somaTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(state: State, dimmed: Bool = false, accessibilityLabel: LocalizedStringResource,
                action: @escaping () -> Void) {
        self.state = state
        self.dimmed = dimmed
        self.accessibilityLabel = accessibilityLabel
        self.action = action
    }

    public var body: some View {
        let m = theme.metrics
        let inner = m.shutterDiameter - 2 * (m.shutterRingWidth + m.shutterGap)
        let recording = state == .recording
        let side = recording ? m.shutterStopSide : inner

        Button(action: action) {
            ZStack {
                Circle()
                    .strokeBorder(theme.colors.inkPrimary.color, lineWidth: m.shutterRingWidth)

                RoundedRectangle(cornerRadius: recording ? m.shutterStopCornerRadius : inner / 2, style: .continuous)
                    .fill(theme.colors.record.color)
                    .frame(width: side, height: side)
            }
            .frame(width: m.shutterDiameter, height: m.shutterDiameter)
            .contentShape(.circle)
            .opacity(dimmed ? theme.motion.dimOpacity : 1)
        }
        .buttonStyle(.somaGlassPress)
        .animation(reduceMotion ? nil : theme.motion.selection, value: recording)
        .accessibilityLabel(Text(accessibilityLabel))
    }
}

#Preview("Shutter Button") {
    @Previewable @State var recording = false

    ZStack {
        SomaPreviewBackdrop()

        HStack(spacing: 32) {
            SomaShutterButton(state: .ready, accessibilityLabel: "Start") {}
            SomaShutterButton(state: .ready, dimmed: true, accessibilityLabel: "Start") {}
            SomaShutterButton(state: recording ? .recording : .ready, accessibilityLabel: "Start or stop") {
                recording.toggle()
            }
        }
    }
    .environment(\.colorScheme, .dark)
}
