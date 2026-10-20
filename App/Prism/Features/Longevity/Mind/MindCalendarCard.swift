//
//  MindCalendarCard.swift
//  Prism
//

import SwiftUI
import SomaUI

/// What the Mind lens knows of the calendar: whether it may read it, and the
/// lines it found. Held in memory only, never in the lens's snapshot.
struct MindCalendarState: Equatable {
    var access: MindCalendar.Access
    /// Nil while the lines are being worked out.
    var insights: [MindCalendarInsights.Insight]? = nil
}

/// The calendar against stress: a few plain lines, each with an arrow in the
/// tone it reads in and the days it rests on, or, before the calendar is
/// read, one line and the way to connect it.
struct MindCalendarCard: View {
    let state: MindCalendarState
    /// Asks for the calendar, or opens Mind's choices when it is off there.
    var onConnect: () -> Void = {}

    @Environment(\.somaTheme) private var theme

    var body: some View {
        SomaCard {
            VStack(alignment: .leading, spacing: theme.metrics.cardSpacing) {
                switch state.access {
                case .granted:
                    if let insights = state.insights, !insights.isEmpty {
                        ForEach(Array(insights.enumerated()), id: \.element.id) { index, insight in
                            if index > 0 { MindHairline() }
                            MindCalendarInsightRow(insight: insight)
                        }
                    } else {
                        prompt(state.insights == nil ? "Reading your calendar" : "Nothing stands out yet",
                               detail: state.insights == nil ? nil : "Compared over your last 30 weekdays")
                    }
                case .notAsked:
                    prompt("See what in your week lines up with stress", action: "Connect")
                case .off:
                    prompt("Calendar is off in Mind’s choices", action: "Turn on")
                case .denied:
                    prompt("No calendar access", detail: "Settings, Privacy, Calendars")
                }
                footnote
            }
        }
    }

    private func prompt(_ title: LocalizedStringResource, detail: LocalizedStringResource? = nil,
                        action: LocalizedStringResource? = nil) -> some View {
        let type = theme.typography
        let colors = theme.colors
        let metrics = theme.metrics

        return HStack(spacing: metrics.cardSpacing) {
            SomaMindGlyph(.meetings)
            VStack(alignment: .leading, spacing: metrics.cardHeaderSpacing) {
                Text(title)
                    .somaFont(type.body)
                    .foregroundStyle(colors.inkPrimary.color)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail)
                        .somaFont(type.caption)
                        .foregroundStyle(colors.inkSecondary.color)
                }
            }
            Spacer(minLength: 0)
            if let action {
                Button(action: onConnect) {
                    Text(action)
                        .somaFont(type.callout)
                        .foregroundStyle(colors.onAccent.color)
                        .padding(.horizontal, metrics.cardPadding)
                        .frame(minHeight: metrics.minimumTapTarget * 0.8)
                        .background(colors.accent.color, in: .capsule)
                        .contentShape(.capsule)
                }
                .buttonStyle(SomaGlassPressStyle())
            }
        }
    }

    /// Where the lines are worked out, in four words and a lock.
    private var footnote: some View {
        HStack(spacing: theme.metrics.trendMarkSpacing) {
            Image(systemName: "lock.fill")
                .accessibilityHidden(true)
            Text("Read on this iPhone only")
        }
        .somaFont(theme.typography.caption)
        .foregroundStyle(theme.colors.inkSecondary.color)
    }
}

/// One line: an arrow in the tone it reads in, the line, and what it rests
/// on.
struct MindCalendarInsightRow: View {
    let insight: MindCalendarInsights.Insight

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let type = theme.typography
        let colors = theme.colors
        let tone = insight.isCost ? MindZone.high.color : MindZone.low.color

        HStack(alignment: .firstTextBaseline, spacing: theme.metrics.cardSpacing) {
            Image(systemName: insight.isCost ? "arrow.up.right" : "arrow.down.right")
                .somaFont(type.callout)
                .fontWeight(.semibold)
                .foregroundStyle(tone)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: theme.metrics.cardHeaderSpacing) {
                Text(insight.text)
                    .somaFont(type.body)
                    .foregroundStyle(colors.inkPrimary.color)
                    .fixedSize(horizontal: false, vertical: true)
                Text(insight.detail)
                    .somaFont(type.caption)
                    .foregroundStyle(colors.inkSecondary.color)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview("Calendar against stress") {
    SomaPageScroll {
        VStack(spacing: 16) {
            MindCalendarCard(state: MindCalendarState(access: .granted, insights: [
                .init(kind: .busyAfternoons, text: "Afternoons with three or more meetings line up with higher stress.",
                      detail: "14 points higher, 8 busy afternoons against 12", isCost: true, strength: 1.8),
                .init(kind: .breaks, text: "Days with time for people or movement on the calendar run calmer.",
                      detail: "9 points lower, 4 days with a break against 16", isCost: false, strength: 1.1),
            ]))
            MindCalendarCard(state: MindCalendarState(access: .notAsked))
            MindCalendarCard(state: MindCalendarState(access: .granted, insights: []))
        }
        .padding()
    }
    .somaTheme(.standard)
}
#endif
