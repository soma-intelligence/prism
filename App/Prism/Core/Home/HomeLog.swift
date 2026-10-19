//
//  HomeLog.swift
//  Prism
//

import Foundation
import Observation

/// How the body felt, from the evening check-in.
enum HomeBodyFeel: String, Codable, CaseIterable, Sendable, Identifiable {
    case fresh, normal, sore, unwell

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fresh: "Fresh"
        case .normal: "Normal"
        case .sore: "Sore"
        case .unwell: "Unwell"
        }
    }
}

/// One evening check-in: energy and stress on five levels, the body, and
/// anything unusual.
struct HomeCheckIn: Codable, Equatable, Sendable, Identifiable {
    var id = UUID()
    var date: Date
    /// 1 (very low) to 5 (very high).
    var energy: Int
    var stress: Int
    var body: HomeBodyFeel
    var tags: [String]
}

/// How hard a workout felt, rated after it.
struct HomeEffort: Codable, Equatable, Sendable, Identifiable {
    var id: Date { workoutStart }
    var workoutStart: Date
    var minutes: Double
    /// 1 (easy) to 10 (all out): Borg's CR10 scale.
    var rating: Int
}

/// What the medical card holds beside what Apple Health knows. Kept on the
/// phone only.
struct HomeMedicalCard: Codable, Equatable, Sendable {
    var name = ""
    var allergies = ""
    var medications = ""
    var conditions = ""
    /// Nil until the person says.
    var organDonor: Bool?
    var contactName = ""
    var contactRelation = ""
    var contactPhone = ""

    var isEmpty: Bool { self == HomeMedicalCard() }
}

/// What the Pulse home keeps that no other tab logs: check-ins, workout
/// efforts, the medical card, the stand goal and the notifications read.
/// Water, caffeine, meals, moods and how the person woke live in
/// ``TrackLogStore``, the one record every tab reads.
///
/// One JSON file in Application Support beside the Journal's, never sent
/// anywhere from here. The Health source Soma reads through cannot write, so
/// these entries live here; the pages read them next to Apple Health's.
@MainActor
@Observable
final class HomeLog {
    /// The app's one log. Pages read it directly rather than through the
    /// environment: it is the person's record, and there is only one.
    static let shared = HomeLog()

    private(set) var checkIns: [HomeCheckIn] = []
    private(set) var efforts: [HomeEffort] = []
    var medical = HomeMedicalCard() { didSet { save() } }
    /// Stand hours a day the person aims for.
    var standGoal = 12 { didSet { save() } }
    /// Notifications already opened, by id.
    private(set) var readNotes: Set<String> = []

    private let url: URL?
    let calendar: Calendar

    private struct Stored: Codable {
        var checkIns: [HomeCheckIn] = []
        var efforts: [HomeEffort] = []
        var medical = HomeMedicalCard()
        var standGoal = 12
        var readNotes: Set<String> = []
    }

    /// - Parameter url: where the log lives. Nil keeps it in memory only,
    ///   which is what previews and tests use.
    init(url: URL? = HomeLog.defaultURL, calendar: Calendar = .current) {
        self.url = url
        self.calendar = calendar
        guard let url, let data = try? Data(contentsOf: url),
              let stored = try? JSONDecoder().decode(Stored.self, from: data) else { return }
        checkIns = stored.checkIns
        efforts = stored.efforts
        medical = stored.medical
        standGoal = stored.standGoal
        readNotes = stored.readNotes
    }

    nonisolated static var defaultURL: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return base.appending(path: "home-log.json")
    }

    // MARK: Reading

    func isSameDay(_ date: Date, _ other: Date) -> Bool {
        calendar.isDate(date, inSameDayAs: other)
    }

    func checkIn(on date: Date) -> HomeCheckIn? {
        checkIns.filter { isSameDay($0.date, date) }.max { $0.date < $1.date }
    }

    func effort(for workoutStart: Date) -> HomeEffort? {
        efforts.first { abs($0.workoutStart.timeIntervalSince(workoutStart)) < 60 }
    }

    func isRead(_ note: String) -> Bool { readNotes.contains(note) }

    // MARK: Writing

    func addCheckIn(_ checkIn: HomeCheckIn) {
        checkIns.removeAll { isSameDay($0.date, checkIn.date) }
        checkIns.append(checkIn)
        save()
    }

    func setEffort(_ effort: HomeEffort) {
        efforts.removeAll { abs($0.workoutStart.timeIntervalSince(effort.workoutStart)) < 60 }
        efforts.append(effort)
        save()
    }

    func markRead(_ note: String) {
        guard !readNotes.contains(note) else { return }
        readNotes.insert(note)
        save()
    }

    // MARK: Store

    func stamp(_ date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private func save() {
        guard let url else { return }
        let stored = Stored(
            checkIns: checkIns, efforts: efforts, medical: medical,
            standGoal: standGoal, readNotes: readNotes
        )
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(stored).write(to: url, options: SomaFileStorage.protectedAtomicOptions)
        } catch {
            // A failed write keeps the entry in memory; the next change tries again.
        }
    }
}

/// How the home writes its numbers.
enum HomeFormat {
    /// Millilitres as litres to one decimal: 1600 reads "1.6 L".
    static func litres(_ ml: Int) -> String {
        litres(Double(ml))
    }

    static func litres(_ ml: Double) -> String {
        (ml / 1000).formatted(.number.precision(.fractionLength(1))) + " L"
    }

    /// A whole number with the locale's grouping: 1240 reads "1,240".
    static func whole(_ value: Double) -> String {
        value.rounded().formatted(.number.precision(.fractionLength(0)))
    }

    static func whole(_ value: Int) -> String {
        Double(value).formatted(.number.precision(.fractionLength(0)))
    }

    static func decimal(_ value: Double, _ digits: Int = 1) -> String {
        value.formatted(.number.precision(.fractionLength(digits)))
    }

    /// A signed change: "+1.3", "-0.4", or "0.0".
    static func signed(_ value: Double, _ digits: Int = 1) -> String {
        let text = abs(value).formatted(.number.precision(.fractionLength(digits)))
        if value.rounded(toPlaces: digits) > 0 { return "+" + text }
        if value.rounded(toPlaces: digits) < 0 { return "-" + text }
        return text
    }

    /// A clock time, 24 hour, in `calendar`'s zone.
    static func clock(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    /// A duration as "7:12".
    static func hoursMinutes(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        return String(format: "%d:%02d", minutes / 60, minutes % 60)
    }

    /// A duration as "1 h 10" or "24 min".
    static func span(_ seconds: TimeInterval) -> String {
        NextMoveContext.span(minutes: Int((seconds / 60).rounded()))
    }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let factor = pow(10, Double(places))
        return (self * factor).rounded() / factor
    }
}
