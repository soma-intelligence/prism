//
//  MindStore.swift
//  Prism
//
//  Mind's own record on the phone: the consent, the feelings logged, the
//  check-ins, the days told in words and the category corrections. One JSON
//  file in Application Support, beside the Journal's, never sent anywhere.
//

import Foundation
import Observation

@MainActor
@Observable
final class MindStore {
    /// The app's record. Pages read it directly, so no edit to the app's
    /// environment is needed to reach it.
    static let shared = MindStore()

    private(set) var consent: MindConsent
    private(set) var moods: [MindMoodEntry]
    private(set) var checkIns: [MindCheckIn]
    private(set) var notes: [MindDayNote]
    /// Category corrections, keyed by ``MindEventClassifier/fingerprint(_:)``.
    private(set) var corrections: [String: MindEventCategory]
    /// Each day's mood forecast, keyed by the day's `yyyy-MM-dd`, so the
    /// forecast page can say how it has done.
    private(set) var forecasts: [String: Double]

    private let url: URL?

    private struct Stored: Codable {
        var consent = MindConsent()
        var moods: [MindMoodEntry] = []
        var checkIns: [MindCheckIn] = []
        var notes: [MindDayNote] = []
        var corrections: [String: MindEventCategory] = [:]
        var forecasts: [String: Double]? = [:]
    }

    /// - Parameter url: nil keeps everything in memory, for previews and tests.
    init(url: URL? = MindStore.defaultURL) {
        self.url = url
        let stored = url.flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONDecoder().decode(Stored.self, from: $0) } ?? Stored()
        consent = stored.consent
        moods = stored.moods
        checkIns = stored.checkIns
        notes = stored.notes
        corrections = stored.corrections
        forecasts = stored.forecasts ?? [:]
    }

    nonisolated static var defaultURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appending(path: "mind.json")
    }

    // MARK: Writing

    func setConsent(_ new: MindConsent) {
        consent = new
        save()
    }

    func add(_ entry: MindMoodEntry) {
        moods.append(entry)
        save()
    }

    func markInHealth(_ id: UUID) {
        guard let index = moods.firstIndex(where: { $0.id == id }) else { return }
        moods[index].isInHealth = true
        save()
    }

    func add(_ checkIn: MindCheckIn) {
        checkIns.append(checkIn)
        save()
    }

    /// Saves a day's note, replacing the one already kept for that day.
    func save(_ note: MindDayNote, calendar: Calendar = .current) {
        notes.removeAll { calendar.isDate($0.day, inSameDayAs: note.day) }
        notes.append(note)
        save()
    }

    func note(on day: Date, calendar: Calendar = .current) -> MindDayNote? {
        notes.first { calendar.isDate($0.day, inSameDayAs: day) }
    }

    /// Moves every moment with this title to `category`, today and after.
    func correct(_ title: String, to category: MindEventCategory) {
        corrections[MindEventClassifier.fingerprint(title)] = category
        for index in notes.indices {
            for moment in notes[index].moments.indices where MindEventClassifier.fingerprint(notes[index].moments[moment].title) == MindEventClassifier.fingerprint(title) {
                notes[index].moments[moment].category = category
            }
        }
        save()
    }

    /// The category a title reads as, a person's correction first.
    func category(of title: String) -> MindEventCategory {
        corrections[MindEventClassifier.fingerprint(title)] ?? MindEventClassifier.category(title: title)
    }

    /// Keeps the first forecast made for a day: a later one would have seen
    /// part of the day it forecasts.
    func keepForecast(_ index: Double, for day: Date) {
        let key = Self.stamp(day)
        guard forecasts[key] == nil else { return }
        forecasts[key] = index
        save()
    }

    /// The forecasts by the start of their day.
    func forecastsByDay(calendar: Calendar = .current) -> [Date: Double] {
        let parser = Self.stampFormatter(calendar)
        var result: [Date: Double] = [:]
        for (key, value) in forecasts {
            if let date = parser.date(from: key) { result[calendar.startOfDay(for: date)] = value }
        }
        return result
    }

    static func stamp(_ day: Date, calendar: Calendar = .current) -> String {
        stampFormatter(calendar).string(from: day)
    }

    private static func stampFormatter(_ calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    /// Erases everything Mind keeps on the phone, the consent included.
    func deleteAll() {
        consent = MindConsent()
        moods = []
        checkIns = []
        notes = []
        corrections = [:]
        forecasts = [:]
        save()
    }

    private func save() {
        guard let url else { return }
        let stored = Stored(consent: consent, moods: moods, checkIns: checkIns, notes: notes, corrections: corrections, forecasts: forecasts)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(stored).write(to: url, options: SomaFileStorage.protectedAtomicOptions)
        } catch {
            // Nothing to fall back to: the entry stays in memory for the session.
        }
    }
}
