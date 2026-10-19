//
//  MindCalendar.swift
//  Prism
//
//  The calendar's busy times: each event's title and window, never its notes,
//  its place or who was invited. Asked only when a page that reads it opens,
//  and only when the consent screen allowed it.
//

import Foundation
#if canImport(EventKit)
import EventKit
#endif

@MainActor
enum MindCalendar {
    enum Access: Equatable, Sendable {
        /// The consent screen left the calendar off.
        case off
        /// The system has not been asked yet.
        case notAsked
        case granted
        case denied
    }

#if canImport(EventKit)
    private static let store = EKEventStore()

    static var access: Access {
        guard MindStore.shared.consent.calendar else { return .off }
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: return .granted
        case .notDetermined: return .notAsked
        default: return .denied
        }
    }

    /// Asks once, when a page that reads the calendar opens.
    static func requestAccess() async -> Access {
        guard access == .notAsked else { return access }
        _ = try? await store.requestFullAccessToEvents()
        return access
    }

    /// Timed events between two moments. Empty without access.
    static func events(from start: Date, to end: Date) -> [MindCalendarEvent] {
        guard access == .granted, end > start else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate)
            .filter { !$0.isAllDay }
            .map { event in
                MindCalendarEvent(
                    id: (event.eventIdentifier ?? UUID().uuidString) + "\(event.startDate.timeIntervalSince1970)",
                    title: event.title ?? "Busy",
                    calendarTitle: event.calendar?.title ?? "",
                    start: event.startDate,
                    end: event.endDate
                )
            }
            .sorted { $0.start < $1.start }
    }
#else
    static var access: Access { .off }
    static func requestAccess() async -> Access { .off }
    static func events(from start: Date, to end: Date) -> [MindCalendarEvent] { [] }
#endif
}
