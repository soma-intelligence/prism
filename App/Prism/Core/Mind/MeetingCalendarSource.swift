//
//  MeetingCalendarSource.swift
//  Prism
//
//  Where meetings come from. Apple Calendar is the one source today; Google
//  Calendar is meant to join as a second one, read straight from its own
//  account rather than through an Apple Calendar subscription. Each source
//  answers the same three questions, and the meetings page reads them all
//  through ``MeetingCalendar`` without knowing which is which.
//
//  A Google account already added to Apple Calendar shows its events through
//  EventKit too, so the same meeting can arrive twice once a direct Google
//  source exists. ``MeetingCalendar/merged(_:)`` keeps the first copy.
//

import Foundation

/// One calendar a meeting can come from. Every source honours the consent
/// screen's calendar switch, and returns nothing until it has access.
@MainActor
protocol MeetingCalendarSource {
    /// A short name for the source, for a settings row or a log.
    var name: String { get }
    var access: MindCalendar.Access { get }
    /// Asks for access when it has not been asked, and returns the answer.
    func requestAccess() async -> MindCalendar.Access
    /// Timed events between two moments, each with its window, title,
    /// attendees and series. Never notes or a place.
    func events(from start: Date, to end: Date) -> [MindCalendarEvent]
}

/// Apple Calendar, through EventKit.
struct EventKitMeetingSource: MeetingCalendarSource {
    var name: String { "Apple Calendar" }
    var access: MindCalendar.Access { MindCalendar.access }
    func requestAccess() async -> MindCalendar.Access { await MindCalendar.requestAccess() }
    func events(from start: Date, to end: Date) -> [MindCalendarEvent] {
        MindCalendar.eventsNow(from: start, to: end)
    }
}

/// Every source at once.
@MainActor
enum MeetingCalendar {
    static let sources: [any MeetingCalendarSource] = {
#if DEBUG && targetEnvironment(simulator)
        // The made up month of meetings that goes with the Health fixture:
        // `-health.fixture YES`. Never compiled for a device.
        if UserDefaults.standard.bool(forKey: FixtureHealthSource.launchKey) { return [FixtureMeetingSource()] }
#endif
        return [EventKitMeetingSource()]
    }()

    /// Granted when any source is: one calendar read is enough to fill the
    /// page. Otherwise the first source's answer, which says what to do.
    static var access: MindCalendar.Access {
        let answers = sources.map(\.access)
        if answers.contains(.granted) { return .granted }
        return answers.first ?? .off
    }

    static func requestAccess() async -> MindCalendar.Access {
        for source in sources { _ = await source.requestAccess() }
        return access
    }

    static func events(from start: Date, to end: Date) -> [MindCalendarEvent] {
        merged(sources.map { $0.events(from: start, to: end) })
    }

    /// The sources' events as one list, oldest first. Two events with the
    /// same folded title starting within a minute of each other are one
    /// meeting seen through two calendars; the first source's copy stays,
    /// with the attendees of both.
    nonisolated static func merged(_ lists: [[MindCalendarEvent]]) -> [MindCalendarEvent] {
        var kept: [MindCalendarEvent] = []
        for event in lists.joined() {
            let title = MindEventClassifier.normalize(event.title)
            if let index = kept.firstIndex(where: {
                abs($0.start.timeIntervalSince(event.start)) < 60 && MindEventClassifier.normalize($0.title) == title
            }) {
                let known = Set(kept[index].attendees.map { $0.lowercased() })
                kept[index].attendees += event.attendees.filter { !known.contains($0.lowercased()) }
                if kept[index].seriesID == nil { kept[index].seriesID = event.seriesID }
            } else {
                kept.append(event)
            }
        }
        return kept.sorted { $0.start < $1.start }
    }
}
