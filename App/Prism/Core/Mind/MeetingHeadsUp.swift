//
//  MeetingHeadsUp.swift
//  Prism
//

import Foundation
import Observation
import SomaWidgetKit

/// The meeting coming up that the history says could run tense, for a word
/// on the Today page before it starts (owner, 2026-10-24).
///
/// It reads only when the calendar is already allowed: Today never asks for
/// it, Mind's meetings page does. A read holds for a quarter of an hour, so
/// coming back to Today does not read thirty days of heart again.
@MainActor
@Observable
final class MeetingHeadsUp {
    static let shared = MeetingHeadsUp()

    /// The meeting to prepare for, or nil.
    private(set) var next: MeetingStressAnalysis.Forecast?
    private(set) var readAt: Date?

    /// How far ahead a meeting earns a word on Today.
    static let horizon: TimeInterval = 24 * 3600
    /// How long a read holds.
    static let freshness: TimeInterval = 15 * 60
    /// How close a meeting must be for its countdown to go on the lock screen.
    static let liveLead: TimeInterval = 60 * 60
    /// The meeting whose countdown is showing.
    private var liveFor: String?

    /// The first meeting starting after `now` and within ``horizon`` that is
    /// likely or could be tense; the likely one first when both come up.
    nonisolated static func pick(
        _ forecasts: [MeetingStressAnalysis.Forecast],
        now: Date
    ) -> MeetingStressAnalysis.Forecast? {
        let soon = forecasts
            .filter { $0.event.start > now && $0.event.start.timeIntervalSince(now) <= horizon }
            .sorted { $0.event.start < $1.event.start }
        return soon.first { $0.level == .likely } ?? soon.first { $0.level == .possible }
    }

    func refresh(_ health: HealthDashboard, now: Date = Date(), force: Bool = false) async {
        if !force, let readAt, now.timeIntervalSince(readAt) < Self.freshness { return }
        guard MeetingCalendar.access == .granted else {
            next = nil
            return
        }
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -MindMeetingsPage.historyDays, to: calendar.startOfDay(for: now)) ?? now
        let past = MeetingCalendar.events(from: start, to: now)
        let upcoming = MeetingCalendar.events(from: now, to: now.addingTimeInterval(Self.horizon))
        let inputs = await MindLoad.inputs(health)
        let assessments = await MeetingStressLoad.assessments(health, inputs: inputs, meetings: MindMeetingStress.meetings(in: past))
        let history = MeetingStressAnalysis.history(assessments, calendar: calendar)
        let forecasts = MeetingStressAnalysis.forecasts(upcoming, history: history, now: now, calendar: calendar)
        let picked = Self.pick(forecasts, now: now)
        if picked != next { next = picked }
        readAt = now
        if let picked { await raise(picked, now: now) }
        live(picked, now: now)
    }

    /// The countdown to the meeting on the lock screen and in the Dynamic
    /// Island, once the meeting is within the hour; taken off when no meeting
    /// is picked any more. Started only from here, which runs with the app
    /// open, the one time an activity can start without a push.
    private func live(_ forecast: MeetingStressAnalysis.Forecast?, now: Date) {
        guard let forecast, forecast.event.start.timeIntervalSince(now) <= Self.liveLead else {
            if liveFor != nil, forecast?.id != liveFor {
                SomaLiveActivities.shared.end(.meeting)
                liveFor = nil
            }
            return
        }
        guard liveFor != forecast.id else { return }
        let title = MeetingDisplay.title(forecast.event.title, attendees: forecast.event.attendees)
        SomaLiveActivities.shared.start(.meeting, SomaActivityCopy.meeting(title: title, start: forecast.event.start, now: now))
        liveFor = forecast.id
    }

    /// The word twenty minutes before the meeting, into the inbox and onto
    /// the phone when notifications are on. Once per meeting.
    private func raise(_ forecast: MeetingStressAnalysis.Forecast, now: Date) async {
        let notifications = SomaNotifications.shared
        guard let alert = DataAlertRules.meetingHeadsUp(
            forecast,
            title: MeetingDisplay.title(forecast.event.title, attendees: forecast.event.attendees),
            reason: MeetingDisplay.namingPeople(in: forecast.reason),
            schedule: notifications.schedule,
            prefs: notifications.settings.notifications,
            now: now
        ), !notifications.inbox.contains(where: { $0.id == alert.id }) else { return }
        notifications.add(InboxItem(id: alert.id, kind: .dataAlert, title: alert.title, body: alert.body,
                                    date: now, link: alert.link))
        if notifications.isOn { try? await notifications.scheduler.add(alert) }
    }
}
