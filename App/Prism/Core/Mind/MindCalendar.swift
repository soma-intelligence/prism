//
//  MindCalendar.swift
//  Prism
//
//  The calendar's busy times: each event's title, its window, who it is with
//  and the series it repeats in. Never its notes or its place. The names are
//  what lets Mind say a meeting with one person tends to run tense, and they
//  stay on the device: nothing here is written anywhere or sent. Asked only
//  when a page that reads it opens, and only when the consent screen allowed
//  it.
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
        #if DEBUG && targetEnvironment(simulator)
        if FixtureCalendar.isOn { return .granted }
        #endif
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

    /// Timed events between two moments, read off the main actor: a month
    /// of a busy calendar takes the event store a while. Empty without
    /// access.
    static func events(from start: Date, to end: Date) async -> [MindCalendarEvent] {
        guard access == .granted, end > start else { return [] }
        #if DEBUG && targetEnvironment(simulator)
        if FixtureCalendar.isOn { return FixtureCalendar.events(from: start, to: end) }
        #endif
        return await Task.detached(priority: .utility) {
            Self.read(EKEventStore(), from: start, to: end)
        }.value
    }

    /// The same events read on the caller's actor, for the small windows
    /// the meeting pages and the heads up ask for (a day or two).
    static func eventsNow(from start: Date, to end: Date) -> [MindCalendarEvent] {
        guard access == .granted, end > start else { return [] }
        #if DEBUG && targetEnvironment(simulator)
        if FixtureCalendar.isOn { return FixtureCalendar.events(from: start, to: end) }
        #endif
        return read(store, from: start, to: end)
    }

    nonisolated private static func read(_ store: EKEventStore, from start: Date, to end: Date) -> [MindCalendarEvent] {
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate)
            .filter { !$0.isAllDay }
            .map { event in
                MindCalendarEvent(
                    id: (event.eventIdentifier ?? UUID().uuidString) + "\(event.startDate.timeIntervalSince1970)",
                    title: event.title ?? "Busy",
                    calendarTitle: event.calendar?.title ?? "",
                    start: event.startDate,
                    end: event.endDate,
                    attendees: people(in: event),
                    // Every occurrence of a repeating event shares its item
                    // identifier; a one off has no series to join.
                    seriesID: event.hasRecurrenceRules ? event.calendarItemIdentifier : nil
                )
            }
            .sorted { $0.start < $1.start }
    }

    /// The other people on an event, by name. The person themself, rooms,
    /// resources and mailing lists are left out: a room is not who a meeting
    /// is with, and a list stands for people the calendar cannot name. The
    /// organizer counts when the invitation lists them apart.
    nonisolated private static func people(in event: EKEvent) -> [String] {
        var everyone = event.attendees ?? []
        if let organizer = event.organizer { everyone.append(organizer) }
        var seen = Set<String>()
        var names: [String] = []
        for participant in everyone where !participant.isCurrentUser {
            switch participant.participantType {
            case .room, .resource, .group: continue
            default: break
            }
            guard let name = displayName(participant), seen.insert(name.lowercased()).inserted else { continue }
            names.append(name)
        }
        return names
    }

    /// The name an invitation gives, else the address it was sent to, which
    /// is still the one person and reads better than nothing.
    nonisolated private static func displayName(_ participant: EKParticipant) -> String? {
        if let name = participant.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        let address = participant.url.absoluteString.replacingOccurrences(of: "mailto:", with: "")
        return address.isEmpty ? nil : address
    }
#else
    static var access: Access { .off }
    static func requestAccess() async -> Access { .off }
    static func events(from start: Date, to end: Date) async -> [MindCalendarEvent] { [] }
    static func eventsNow(from start: Date, to end: Date) -> [MindCalendarEvent] { [] }
#endif
}
