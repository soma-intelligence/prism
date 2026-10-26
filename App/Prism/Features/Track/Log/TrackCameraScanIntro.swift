//
//  TrackCameraScanIntro.swift
//  Prism
//

import SwiftUI
import SomaUI

/// Camera scan, before you start: the four things that make a clean reading,
/// how long to hold, and a way not to be told again.
///
/// The scan itself (the front camera reading pulse and skin) is not in this
/// build, so the action says so rather than opening an empty camera.
struct TrackCameraScanIntro: View {
    enum Length: String, CaseIterable, Identifiable {
        case quick, complete
        var id: String { rawValue }
    }

    @Environment(\.somaTheme) private var theme
    @State private var length = Length.complete

    private let log = TrackLogStore.shared

    private static let steps = [
        "Face a lamp, not a window.",
        "Keep direct sun off your face.",
        "Hold the phone still, a forearm away.",
        "Don\u{2019}t talk or chew until it ends.",
    ]

    var body: some View {
        let metrics = theme.metrics
        let type = theme.typography
        let colors = theme.colors

        TrackEntryPage(title: "Camera scan") {
            VStack(alignment: .leading, spacing: metrics.spaceM) {
                VStack(alignment: .leading, spacing: metrics.spaceS) {
                    TrackEyebrow("Before you start")
                    Text("Thirty still seconds")
                        .somaFont(type.headline)
                        .foregroundStyle(colors.inkPrimary.color)
                        .accessibilityAddTraits(.isHeader)
                    TrackLeadText(lead: "The front camera reads your pulse and your skin.", rest: "Nothing to wear.")
                }

                SomaCard {
                    VStack(alignment: .leading, spacing: metrics.cardSpacing) {
                        ForEach(Array(Self.steps.enumerated()), id: \.offset) { index, step in
                            if index > 0 { TrackHairline() }
                            HStack(spacing: metrics.cardSpacing) {
                                Text("\(index + 1)")
                                    .somaFont(type.captionValue)
                                    .foregroundStyle(colors.inkSecondary.color)
                                    .frame(width: metrics.minimumTapTarget * 0.55, height: metrics.minimumTapTarget * 0.55)
                                    .background(Circle().fill(colors.surfaceRecessed.color))
                                Text(step)
                                    .somaFont(type.body)
                                    .foregroundStyle(colors.inkPrimary.color)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }

                Text("At the end the screen flashes a few colours for four seconds. That reads your skin, so hold the pose.")
                    .somaFont(type.caption)
                    .foregroundStyle(colors.inkSecondary.color)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: metrics.spaceS) {
                    TrackEyebrow("How long")
                    HStack(spacing: metrics.spaceS) {
                        option(.quick, title: "Quick", value: "20 seconds", detail: "Pulse only")
                        option(.complete, title: "Complete", value: "60 seconds", detail: "Pulse, HRV, breathing and skin")
                    }
                }

                SomaCard {
                    Toggle(isOn: Binding(get: { log.skipsScanIntro }, set: { log.skipsScanIntro = $0 })) {
                        Text("Don\u{2019}t show this again")
                            .somaFont(type.body)
                            .foregroundStyle(colors.inkPrimary.color)
                    }
                    .toggleStyle(.soma)
                }
            }
        } footer: {
            VStack(spacing: metrics.spaceS) {
                SomaActionButton("Start the scan") {}
                    .disabled(true)
                Text("The camera scan itself is not in this build yet.")
                    .somaFont(type.caption)
                    .foregroundStyle(colors.inkSecondary.color)
            }
        }
    }

    private func option(_ option: Length, title: String, value: String, detail: String) -> some View {
        let metrics = theme.metrics
        let type = theme.typography
        let colors = theme.colors
        let isOn = length == option

        return Button {
            length = option
        } label: {
            VStack(alignment: .leading, spacing: metrics.spaceXS) {
                HStack {
                    Text(title)
                        .somaFont(type.body)
                        .foregroundStyle(isOn ? colors.accent.color : colors.inkPrimary.color)
                    Spacer()
                    if isOn {
                        Image(systemName: "checkmark")
                            .font(.system(size: metrics.browseChevronSize, weight: .semibold))
                            .foregroundStyle(colors.accent.color)
                    }
                }
                Text(value)
                    .somaFont(type.body)
                    .foregroundStyle(colors.inkPrimary.color)
                Text(detail)
                    .somaFont(type.caption)
                    .foregroundStyle(colors.inkSecondary.color)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(metrics.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: metrics.cardCornerRadius, style: .continuous)
                    .fill(isOn ? colors.surfaceRecessed.color : colors.surface.color)
            )
            .contentShape(.rect)
        }
        .buttonStyle(.somaGlassPress)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

#if DEBUG
#Preview("Camera scan") {
    NavigationStack { TrackCameraScanIntro() }
}
#endif
