//
//  MindConnectionPage.swift
//  Prism
//

import SwiftUI
import SomaUI

/// Connection: the week's time with people, how lonely the last monthly
/// check read and how that has moved month to month, the purpose item, one
/// thing to do this week, the monthly check itself and its reminder.
///
/// The week is read from what the phone holds (`ConnectionWeek`): the
/// calendar's social events, the feelings logged with friends, family or a
/// partner, and the Journal's social tags. Nothing is sent anywhere.
struct MindConnectionPage: View {
    @Environment(JournalStore.self) private var journal
    @Environment(\.somaTheme) private var theme

    @State private var notifications = SomaNotifications.shared
    @State private var moods: [MindMoodEntry] = []
    @State private var events: [MindCalendarEvent] = []
    @State private var calendarAllowed = false
    @State private var isTaking = false

    var body: some View {
        @Bindable var notifications = notifications
        let calendar = Calendar.current
        let now = Date()
        let store = MindStore.shared
        let week = ConnectionWeek.make(
            moods: moods, events: events, calendarAllowed: calendarAllowed,
            journal: journalDays(), now: now, calendar: calendar,
            category: { store.category(of: $0.title) }
        )
        let loneliness = store.latest(.ucla3)
        let purpose = store.latest(.purpose)
        let lonely = loneliness?.score.map(LonelinessScore.isLonely) ?? false
        let suggestion = week.suggestion(lonely: lonely)
        let monthly = store.history(.ucla3)

        MindPage(
            navigationTitle: "Connection",
            title: "Connection",
            stats: [
                SomaStat("With people", value: week.socialMinutes.map(MindFormat.duration)),
                SomaStat("Days tagged", value: "\(week.taggedDays)", unit: "of 7"),
                SomaStat("Moods", value: "\(week.moodsWithPeople)", unit: "with people"),
            ]
        ) {
            if !calendarAllowed {
                MindTextCard(title: "Time with people", text: "The minutes come from your calendar's social events, once Mind may read the calendar.")
            }

            SomaActionCard(eyebrow: "This week", title: suggestion.title, detail: suggestion.detail) {
                SomaOrb(aspect: .mind, scale: .mini)
            }

            if let loneliness {
                MindAssessmentResultCard(assessment: loneliness)
            } else {
                MindTextCard(
                    title: "No check yet",
                    text: "Three questions on feeling connected and one on purpose. Under a minute."
                )
            }

            if monthly.count > 1 {
                SomaCard {
                    VStack(alignment: .leading, spacing: theme.metrics.cardHeaderSpacing) {
                        SomaCardHeader("Loneliness over time", caption: "The line marks where lonely begins")
                        MindScoreHistoryChart(assessments: monthly)
                    }
                }
            }

            if let purpose {
                MindAssessmentResultCard(assessment: purpose)
            }

            MindWideButton(title: loneliness == nil ? "Take the check" : "Take the monthly check") {
                isTaking = true
            }

            MindReminderCard(
                title: "Each month",
                detail: "A reminder at \(MindQuestionnaireReminders.morning.text), a month after the last check",
                isOn: $notifications.schedule.connectionReminders
            )

            Text("Loneliness: the three item UCLA scale (Hughes and colleagues, 2004). Purpose: one item from Ryff's well-being scales. Not a diagnosis. Your answers stay on this phone.")
                .somaFont(theme.typography.caption)
                .foregroundStyle(theme.colors.inkSecondary.color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .sheet(isPresented: $isTaking, onDismiss: {
            Task { await MindQuestionnaireReminders.sync() }
        }) {
            MindEntryGate { MindAssessmentSheet(instruments: MindConnectionCheck.instruments) }
        }
        .onChange(of: notifications.schedule.connectionReminders) { _, isOn in
            Task { await MindQuestionnaireReminders.sync(asking: isOn) }
        }
        .task { await load() }
    }

    private func load() async {
        let calendar = Calendar.current
        let now = Date()
        let start = calendar.date(byAdding: .day, value: -(ConnectionWeek.days - 1), to: calendar.startOfDay(for: now)) ?? now
        moods = await MindJourneyLoad.moods(since: start, store: .shared)
        calendarAllowed = MindCalendar.access == .granted
        events = MindCalendar.eventsNow(from: start, to: now)
        await MindQuestionnaireReminders.sync()
    }

    private func journalDays() -> [Date: Set<String>] {
        var days: [Date: Set<String>] = [:]
        for (date, day) in journal.loggedDays {
            days[date] = Set(day.tags)
        }
        return days
    }
}

#if DEBUG
#Preview("Connection") {
    NavigationStack { MindConnectionPage() }
        .environment(JournalStore(url: nil))
        .somaTheme(.standard)
}
#endif
