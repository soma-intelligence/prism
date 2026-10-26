//
//  OralHealth.swift
//  Prism
//
//  Mouth and teeth from what the phone already holds: each brushing an
//  electric toothbrush (or a log on the page) wrote to Health, with how long
//  it lasted; floss, mouthwash and bleeding gums from the Journal; and the
//  last dental visit from the screening ledger, the next booked one from the
//  medical record. Nothing here touches HealthKit or a store's file: the readings
//  and the days come in as values, so the tests drive it directly.
//
//  The habits are the American Dental Association's: brush twice a day for
//  two minutes, clean between the teeth once a day, and see a dentist at the
//  interval they set, six months for most people.
//

import Foundation
import HealthExportCore
#if canImport(HealthKit)
import HealthKit
#endif

/// The Journal tags the page reads. Starter tags, so every Journal offers
/// them (`JournalStore.starterTags`).
nonisolated enum OralTag {
    static let floss = "floss"
    static let mouthwash = "mouthwash"
    /// Written by the weekly evening question, "Gums bleed when brushing?".
    static let gumsBleed = "gums-bleed"
}

/// Thirty days of mouth and teeth. Nil is "not recorded", never zero: a
/// count of brushings needs Health to hold at least one, a count of floss
/// days needs at least one answer in the Journal. On the main actor, as the
/// Journal days it reads are.
struct OralSummary: Equatable, Sendable {
    static let brushingID = "HKCategoryTypeIdentifierToothbrushingEvent"
    /// The window every count covers, today included.
    static let windowDays = 30
    /// ADA: two minutes a brushing.
    static let targetSeconds: TimeInterval = 120
    /// ADA: the dentist sets the interval; six months for most people.
    static let visitMonths = 6

    /// True when Health holds a brushing in the window.
    var hasBrushing = false
    /// Days of the thirty with a brushing.
    var brushedDays: Int?
    /// Days of the thirty with two brushings or more.
    var brushedTwiceDays: Int?
    /// The mean length of the brushings that carry one.
    var averageSeconds: TimeInterval?
    /// Brushings each day, oldest first, today last: thirty slots, every one
    /// nil without a brushing in Health.
    var perDay: [Double?] = Array(repeating: nil, count: OralSummary.windowDays)
    var lastBrushing: Date?
    /// Days the Journal says yes, nil when it was never answered in the window.
    var flossDays: Int?
    var mouthwashDays: Int?
    var gumBleedDays: Int?
    var lastVisit: Date?
    /// A booked visit, or six months after the last one.
    var nextVisit: Date?
    var isVisitDue = false

    /// The average brushing falls short of two minutes.
    var isShortBrush: Bool { averageSeconds.map { $0 < Self.targetSeconds } ?? false }

    /// Nothing from Health, the Journal or a visit.
    var isEmpty: Bool {
        !hasBrushing && flossDays == nil && mouthwashDays == nil && gumBleedDays == nil
            && lastVisit == nil && nextVisit == nil
    }

    /// - Parameters:
    ///   - brushing: toothbrushing events from Health, any order, any age.
    ///   - journalDays: the Journal's days, each at its start.
    ///   - lastVisit: the last dental checkup, from the screening ledger.
    ///   - bookedVisit: a visit already booked: the next dental appointment
    ///     in the medical record (`MedicalRecord.nextDentalVisit`).
    static func make(
        brushing: [HealthReading],
        journalDays: [(date: Date, day: JournalDay)],
        lastVisit: Date?,
        bookedVisit: Date? = nil,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> OralSummary {
        var summary = OralSummary()
        let today = calendar.startOfDay(for: now)
        guard let first = calendar.date(byAdding: .day, value: -(windowDays - 1), to: today) else { return summary }
        func slot(_ date: Date) -> Int? {
            let day = calendar.startOfDay(for: date)
            guard day >= first, day <= today else { return nil }
            return calendar.dateComponents([.day], from: first, to: day).day
        }

        let inWindow = brushing.filter { $0.start <= now && slot($0.start) != nil }
        if !inWindow.isEmpty {
            var counts = Array(repeating: 0, count: windowDays)
            for reading in inWindow {
                if let index = slot(reading.start), counts.indices.contains(index) { counts[index] += 1 }
            }
            summary.hasBrushing = true
            summary.perDay = counts.map { Double($0) }
            summary.brushedDays = counts.filter { $0 >= 1 }.count
            summary.brushedTwiceDays = counts.filter { $0 >= 2 }.count
            // A brushing written without a length (start equals end) counts
            // as a brushing but says nothing about time.
            let lengths = inWindow.map { $0.end.timeIntervalSince($0.start) }.filter { $0 > 0 }
            summary.averageSeconds = lengths.isEmpty ? nil : lengths.reduce(0, +) / Double(lengths.count)
            summary.lastBrushing = inWindow.map(\.start).max()
        }

        let recent = journalDays.filter { slot($0.date) != nil }.map(\.day)
        func days(_ tag: String) -> Int? {
            let answers = recent.compactMap { $0.answer(tag) }
            return answers.isEmpty ? nil : answers.filter { $0 }.count
        }
        summary.flossDays = days(OralTag.floss)
        summary.mouthwashDays = days(OralTag.mouthwash)
        summary.gumBleedDays = days(OralTag.gumsBleed)

        summary.lastVisit = lastVisit
        summary.nextVisit = bookedVisit ?? lastVisit.flatMap { calendar.date(byAdding: .month, value: visitMonths, to: $0) }
        summary.isVisitDue = summary.nextVisit.map { $0 <= now } ?? false
        return summary
    }

    /// The Journal read as it stands.
    static func make(
        brushing: [HealthReading],
        journal: JournalStore,
        lastVisit: Date?,
        bookedVisit: Date? = nil,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> OralSummary {
        make(brushing: brushing, journalDays: journal.loggedDays, lastVisit: lastVisit, bookedVisit: bookedVisit,
             now: now, calendar: calendar)
    }

    /// A brushing's length as the page writes it: "1:45".
    static func duration(_ seconds: TimeInterval?) -> String? {
        guard let seconds else { return nil }
        let whole = Int(seconds.rounded())
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }
}

// MARK: - Writing

/// A brushing logged by hand, for a manual brush: two minutes ending now,
/// written to Health as a toothbrushing event. Through the one sheet's
/// write types (`HealthAccess.shareTypes`), so nothing asks again.
@MainActor
enum OralHealthWriter {
    /// - Parameter seconds: the brushing's length, two minutes when nil.
    static func logBrushing(endingAt end: Date = .now, seconds: TimeInterval? = nil) async -> LabHealthWriter.Outcome {
        #if canImport(HealthKit)
        guard LabHealthWriter.canWrite else { return .notWritten }
        let seconds = seconds ?? OralSummary.targetSeconds
        let type = HKCategoryType(.toothbrushingEvent)
        let sample = HKCategorySample(type: type, value: HKCategoryValue.notApplicable.rawValue,
                                      start: end.addingTimeInterval(-seconds), end: end)
        let store = HKHealthStore()
        do {
            try await store.requestAuthorization(toShare: [type], read: [])
            try await store.save(sample)
            return .saved
        } catch {
            return .failed(error.localizedDescription)
        }
        #else
        return .notWritten
        #endif
    }
}
