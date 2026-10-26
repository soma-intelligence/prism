//
//  OnboardingIntroSteps.swift
//  Prism
//

import SwiftUI
import SomaUI

// MARK: - Focus

/// Six areas, many can be picked, nothing preselected. Continue stays off
/// until one is chosen. Each pick sends the orb above to that area's colour,
/// so the screen answers the tap without a word.
struct OnboardingFocusView: View {
    let model: OnboardingModel

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let spacing = theme.metrics.cardSpacing

        OnboardingPage(title: String(localized: "What matters most to you?")) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: spacing), GridItem(.flexible(), spacing: spacing)], spacing: spacing) {
                ForEach(Array(FocusArea.allCases.enumerated()), id: \.element.id) { index, area in
                    OnboardingFocusTile(area: area, isOn: model.focus.contains(area)) {
                        if let found = model.focus.firstIndex(of: area) {
                            model.focus.remove(at: found)
                        } else {
                            model.focus.append(area)
                        }
                    }
                    .onboardingArrival(1 + index / 2)
                }
            }
        }
    }
}

private struct OnboardingFocusTile: View {
    let area: FocusArea
    let isOn: Bool
    let action: () -> Void

    @Environment(\.somaTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let metrics = theme.metrics
        let colors = theme.colors

        Button(action: action) {
            VStack(alignment: .leading, spacing: theme.metrics.spaceM) {
                HStack(alignment: .top) {
                    SomaObjectIcon(aspect: area.aspect, size: .row)
                    Spacer()
                    Image(systemName: "checkmark")
                        .font(.system(size: metrics.browseChevronSize, weight: .semibold))
                        .foregroundStyle(colors.accent.color)
                        .opacity(isOn ? 1 : 0)
                        .scaleEffect(isOn || reduceMotion ? 1 : 0.6)
                }
                Text(area.title)
                    .somaFont(theme.typography.callout)
                    .foregroundStyle(isOn ? colors.accent.color : colors.inkPrimary.color)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: metrics.miniOrbDiameter * 2.3, alignment: .topLeading)
            .padding(metrics.spaceM)
            .background(
                RoundedRectangle(cornerRadius: metrics.cardCornerRadius, style: .continuous)
                    .fill(isOn ? colors.surface.color : colors.surfaceRecessed.color)
            )
            .overlay(
                RoundedRectangle(cornerRadius: metrics.cardCornerRadius, style: .continuous)
                    .strokeBorder(colors.inkPrimary.color.opacity(metrics.hairlineOpacity), lineWidth: 0.5)
            )
            .contentShape(.rect)
        }
        .buttonStyle(.somaGlassPress)
        .animation(reduceMotion ? theme.motion.onboardingStepStill : theme.motion.fold, value: isOn)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

extension FocusArea {
    /// The aspect whose orb marks the area on the Focus grid, and whose
    /// colour the run's orb takes when it is picked.
    var aspect: SomaAspect {
        switch self {
        case .sleep: .sleep
        case .energy: .activity
        case .stress: .mind
        case .longevity: .heart
        case .skin: .body
        case .routines: .gut
        }
    }
}
