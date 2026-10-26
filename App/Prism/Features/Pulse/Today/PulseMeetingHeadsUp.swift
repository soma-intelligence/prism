//
//  PulseMeetingHeadsUp.swift
//  Prism
//

import SwiftUI
import SomaUI

/// A word on Today before a meeting the history says could run tense: when,
/// what, why, and the way to the meetings page. Nothing shows when no
/// meeting in the next day leans tense, or the calendar is not allowed.
struct PulseMeetingHeadsUp: View {
    @Environment(HealthDashboard.self) private var health
    @Environment(\.somaTheme) private var theme
    @Environment(\.scenePhase) private var phase
    @State private var headsUp = MeetingHeadsUp.shared

    var body: some View {
        Group {
            if let next = headsUp.next {
                card(next)
                    .transition(.opacity)
            }
        }
        .animation(theme.motion.standard, value: headsUp.next?.id)
        .task(id: phase) {
            guard phase == .active else { return }
            await headsUp.refresh(health)
        }
    }

    private func card(_ next: MeetingStressAnalysis.Forecast) -> some View {
        let metrics = theme.metrics
        let type = theme.typography
        let colors = theme.colors
        let calendar = Calendar.current
        let event = next.event
        let when = MeetingDisplay.dayTitle(event.start, now: Date(), calendar: calendar)
        let title = MeetingDisplay.title(event.title, attendees: event.attendees)
        let tint = next.level == .likely ? colors.statusAlert.color : colors.statusOut.color

        return NavigationLink(value: MindRoute.meetings) {
            SomaCard {
                VStack(alignment: .leading, spacing: metrics.spaceS) {
                    HStack(spacing: metrics.spaceS) {
                        Circle().fill(tint).frame(width: metrics.aspectDotSize, height: metrics.aspectDotSize)
                        Text(next.level.title)
                            .somaFont(type.caption)
                            .foregroundStyle(tint)
                        Spacer(minLength: 0)
                        Text(verbatim: "\(when) \(ScoreMath.clock(event.start, calendar: calendar))")
                            .somaFont(type.captionValue)
                            .foregroundStyle(colors.inkSecondary.color)
                    }
                    Text(title)
                        .somaFont(type.cardTitle)
                        .foregroundStyle(colors.inkPrimary.color)
                        .lineLimit(1)
                    Text(MeetingDisplay.namingPeople(in: next.reason))
                        .somaFont(type.caption)
                        .foregroundStyle(colors.inkSecondary.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.somaGlassPress)
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Opens your meetings"))
    }
}
