//
//  OnboardingFirstWeekCard.swift
//  Prism
//

import SwiftUI
import SomaUI

/// The Today page's first week: what Soma still needs to learn the person,
/// shown while fewer than seven nights are recorded and gone after.
///
/// The count is `SomaScores.nightsRecorded`, the same one the scores wait on,
/// so the card and the dashes above it can never disagree. Before the first
/// read there is no count, and the card stays away rather than guess one.
struct OnboardingFirstWeekCard: View {
    @Environment(HealthDashboard.self) private var health
    @Environment(AppRouter.self) private var router
    @Environment(\.somaTheme) private var theme

    var body: some View {
        if let nights = health.scores?.nightsRecorded {
            let week = FirstWeek(nightsRecorded: nights)
            if week.isLearning {
                card(week)
            }
        }
    }

    private func card(_ week: FirstWeek) -> some View {
        let colors = theme.colors
        let type = theme.typography
        let metrics = theme.metrics

        return SomaCard {
            VStack(alignment: .leading, spacing: 0) {
                Text(week.headline)
                    .somaFont(type.title)
                    .foregroundStyle(colors.inkPrimary.color)
                    .accessibilityAddTraits(.isHeader)
                Text(FirstWeek.reason)
                    .somaFont(type.caption)
                    .foregroundStyle(colors.inkSecondary.color)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)

                Text("What Soma needs to learn you")
                    .somaFont(type.eyebrow)
                    .textCase(.uppercase)
                    .foregroundStyle(colors.inkSecondary.color)
                    .padding(.top, metrics.leadSpacing)
                    .padding(.bottom, 4)

                row(title: "Apple Health", detail: healthDetail) {
                    if health.status == .ready { check }
                }
                divider
                row(title: "Sleep with your watch", detail: "\(week.nights) of \(FirstWeek.length) nights") {
                    OnboardingNightDots(nights: week.nights)
                }
                divider
                Button {
                    router.selection = "track"
                } label: {
                    row(title: "How you feel", detail: "Once a day, in Track") {
                        Image(systemName: "chevron.right")
                            .font(.system(size: metrics.browseChevronSize, weight: .semibold))
                            .foregroundStyle(colors.inkSecondary.color)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.somaGlassPressDim)
            }
        }
    }

    private var healthDetail: LocalizedStringResource {
        switch health.status {
        case .ready: "Connected, read on this phone"
        case .unavailable: "No Health store on this device"
        case .failed: "Not connected. Settings, then Health, then Soma"
        case .idle, .loading: "Reading"
        }
    }

    private var check: some View {
        Image(systemName: "checkmark")
            .font(.system(size: theme.metrics.browseChevronSize, weight: .semibold))
            .foregroundStyle(theme.colors.accent.color)
    }

    private var divider: some View {
        Rectangle()
            .fill(theme.colors.inkPrimary.color.opacity(theme.metrics.browseSeparatorOpacity))
            .frame(height: 0.5)
    }

    private func row<Trailing: View>(title: LocalizedStringResource, detail: LocalizedStringResource, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .somaFont(theme.typography.callout)
                    .foregroundStyle(theme.colors.inkPrimary.color)
                Text(detail)
                    .somaFont(theme.typography.caption)
                    .foregroundStyle(theme.colors.inkSecondary.color)
            }
            Spacer()
            trailing()
        }
        .padding(.vertical, 10)
    }
}

/// Seven dots, the recorded nights lit in the accent's state role.
private struct OnboardingNightDots: View {
    let nights: Int

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let size = theme.metrics.aspectDotSize * 0.8

        HStack(spacing: size * 0.6) {
            ForEach(0..<FirstWeek.length, id: \.self) { index in
                Circle()
                    .fill(index < nights ? theme.colors.accent.color : theme.colors.inkSecondary.color.opacity(0.3))
                    .frame(width: size, height: size)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Text("\(nights) of \(FirstWeek.length) nights"))
    }
}
