//
//  ToolsStore.swift
//  Prism
//

import Foundation
import Observation

/// What a person tells the tools, kept on the device.
///
/// One JSON file in Application Support beside the Journal's, for the same
/// reason: it is the person's own record (a skin type, a shift, a trip, the
/// supplements they take, the screenings they have had), so it never leaves
/// the phone from here.
@MainActor
@Observable
final class ToolsStore {
    static let shared = ToolsStore()

    /// Everything stored, as one value so a save is one write.
    struct Record: Codable, Equatable {
        /// Tools switched off. A tool is on until someone turns it off.
        var off: Set<ToolKind> = []
        /// The day each tool was first opened.
        var since: [ToolKind: Date] = [:]
        /// Tools allowed to send a quiet note.
        var notes: Set<ToolKind> = []
        /// Fitzpatrick type, 1 to 6.
        var skinType: Int?
        var alarm = AlarmPrefs()
        var evening = EveningPrefs()
        var shift = ShiftPrefs()
        var trip: TripPrefs?
        var supplements: [SupplementItem] = []
        /// Supplement id to the moments it was taken.
        var taken: [String: [Date]] = [:]
        var screening = ScreeningRecord()
        var lifts: [LiftSet] = []
        /// Sleep Forecast's prediction for each night, keyed by the wake day's
        /// `yyyy-MM-dd`, so the next morning can check it against the night.
        var forecasts: [String: Int] = [:]
    }

    private(set) var record: Record
    private let url: URL?

    init(url: URL? = ToolsStore.defaultURL) {
        self.url = url
        if let url, let data = try? Data(contentsOf: url),
           let stored = try? JSONDecoder().decode(Record.self, from: data) {
            record = stored
        } else {
            record = Record()
        }
    }

    nonisolated static var defaultURL: URL? {
        guard let folder = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                        appropriateFor: nil, create: true) else { return nil }
        return folder.appendingPathComponent("tools.json")
    }

    /// Changes the record and writes it.
    func update(_ change: (inout Record) -> Void) {
        var next = record
        change(&next)
        guard next != record else { return }
        record = next
        save()
    }

    static func stamp(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    func isOn(_ kind: ToolKind) -> Bool { !record.off.contains(kind) }

    func setOn(_ isOn: Bool, _ kind: ToolKind) {
        update { if isOn { $0.off.remove(kind) } else { $0.off.insert(kind) } }
    }

    /// Notes the first visit, so the intro can say how long the tool has run.
    func markOpened(_ kind: ToolKind, now: Date = Date()) {
        guard record.since[kind] == nil else { return }
        update { $0.since[kind] = now }
    }

    private func save() {
        guard let url else { return }
        do {
            let data = try JSONEncoder().encode(record)
            try data.write(to: url, options: SomaFileStorage.protectedAtomicOptions)
        } catch {
            // A failed write leaves the last good file in place; the change
            // stays in memory for this run.
        }
    }
}

extension ToolsStore.Record {
    /// Each field is read on its own. A file written before a field existed,
    /// or by a build that stored one differently, keeps everything else the
    /// person entered: one new setting never wipes their screenings,
    /// supplements, sets or trip.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let empty = Self()
        off = container.value(.off, or: empty.off)
        since = container.value(.since, or: empty.since)
        notes = container.value(.notes, or: empty.notes)
        skinType = try? container.decodeIfPresent(Int.self, forKey: .skinType)
        alarm = container.value(.alarm, or: empty.alarm)
        evening = container.value(.evening, or: empty.evening)
        shift = container.value(.shift, or: empty.shift)
        trip = try? container.decodeIfPresent(TripPrefs.self, forKey: .trip)
        supplements = container.value(.supplements, or: empty.supplements)
        taken = container.value(.taken, or: empty.taken)
        screening = container.value(.screening, or: empty.screening)
        lifts = container.value(.lifts, or: empty.lifts)
        forecasts = container.value(.forecasts, or: empty.forecasts)
    }
}

// MARK: - What each tool stores

/// The Smart Alarm's settings, as the settings sheet draws them.
struct AlarmPrefs: Codable, Equatable, Sendable {
    var isOn = false
    /// Minutes after midnight the alarm never rings later than.
    var neverAfter = 7 * 60
    /// Weekdays it rings on, 1 is Sunday.
    var days: Set<Int> = [2, 3, 4, 5, 6]
    /// How early before `neverAfter` it may ring, in minutes.
    var window = 30
    var followCalendar = false
    var readyMinutes = 60
    var bedtimeReminder = true
    var remindBefore = 45
    var snooze = false
}

/// Evening Close's settings and its record of evenings.
struct EveningPrefs: Codable, Equatable, Sendable {
    var closesByItself = true
    /// Minutes after midnight.
    var closes = 21 * 60 + 30
    var opens = 7 * 60 + 15
    var noteWhenCloses = true
    /// Evenings the close ran, and whether it was opened early.
    var evenings: [EveningEntry] = []
}

struct EveningEntry: Codable, Equatable, Sendable {
    var day: Date
    var closedOnTime: Bool
    var openedEarly: Bool
}

/// Shift Work Reset's settings.
struct ShiftPrefs: Codable, Equatable, Sendable {
    enum Kind: String, Codable, CaseIterable, Sendable {
        case nights = "Nights"
        case earlyMornings = "Early mornings"
        case rotating = "Rotating"
    }

    var kind: Kind?
    /// Minutes after midnight.
    var starts: Int?
    /// Minutes after midnight; nil reads it from your sleep.
    var usualWake: Int?
    var firstNight: Date?
}

/// A trip for the Travel tool.
struct TripPrefs: Codable, Equatable, Sendable {
    var place: String
    var timeZone: String
    var departs: Date
    /// Hours in the air.
    var flightHours: Double?
}

/// A supplement on the Supplement Window's list.
struct SupplementItem: Codable, Equatable, Identifiable, Sendable {
    var id = UUID().uuidString
    var name: String
    var dose: String
}

/// The Screening Ledger's record: what was done when, the family history
/// answers that change a cadence, and the age and sex the catalog filters on
/// when the profile does not hold them.
struct ScreeningRecord: Codable, Equatable, Sendable {
    var ledger = SomaTools.ScreeningLedger()
    /// "female", "male", "other", or nil when not said. The profile's answer
    /// wins over this one.
    var sex: String?
    /// The date of birth the ledger asked for, when neither the profile nor
    /// Apple Health holds one. Optional, so a file written before it decodes.
    var birthday: Date?
}

/// One set logged on the Strength Load page.
struct LiftSet: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var exercise: String
    var date: Date
    var reps: Int
    var kilograms: Double
}
