//
//  CheckInStore.swift
//  Prism
//

import Foundation
import Observation

/// The record of "Soma asks": one ``CheckInDayRecord`` a day, and whether
/// the app has been opened before.
///
/// One JSON file in Application Support beside the Journal's, kept on the
/// device. The answers themselves are written to the stores they belong to
/// (the Journal, the Pulse home's log, Mind, Track); this keeps what the
/// asking needs, and the answers to the questions the body asked.
@MainActor
@Observable
final class CheckInStore {
    static let shared = CheckInStore()

    /// Keyed by the day's stamp, `yyyy-MM-dd` in the person's calendar.
    private(set) var days: [String: CheckInDayRecord] = [:]
    /// False until the app has once become active with its tabs showing, so
    /// the very first launch never opens a question.
    private(set) var hasLaunchedBefore = false

    let calendar: Calendar
    private let url: URL?

    /// Days kept: enough for a fortnight's look back, no more.
    static let keptDays = 30

    private struct Stored: Codable {
        var days: [String: CheckInDayRecord] = [:]
        var hasLaunchedBefore = false
    }

    /// - Parameter url: nil keeps everything in memory, for previews and tests.
    init(url: URL? = CheckInStore.defaultURL, calendar: Calendar = .current) {
        self.url = url
        self.calendar = calendar
        guard let url, let data = try? Data(contentsOf: url),
              let stored = try? JSONDecoder().decode(Stored.self, from: data) else { return }
        days = stored.days
        hasLaunchedBefore = stored.hasLaunchedBefore
    }

    nonisolated static var defaultURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appending(path: "check-in.json")
    }

    func record(on date: Date) -> CheckInDayRecord {
        days[stamp(date)] ?? CheckInDayRecord()
    }

    func update(on date: Date, _ change: (inout CheckInDayRecord) -> Void) {
        let key = stamp(date)
        var record = days[key] ?? CheckInDayRecord()
        change(&record)
        days[key] = record
        prune()
        save()
    }

    /// Notes the first launch. Returns whether this was it.
    @discardableResult
    func noteLaunch() -> Bool {
        guard !hasLaunchedBefore else { return false }
        hasLaunchedBefore = true
        save()
        return true
    }

    func stamp(_ date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private func prune() {
        guard days.count > Self.keptDays else { return }
        for key in days.keys.sorted().dropLast(Self.keptDays) { days[key] = nil }
    }

    private func save() {
        guard let url else { return }
        let stored = Stored(days: days, hasLaunchedBefore: hasLaunchedBefore)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(stored).write(to: url, options: SomaFileStorage.protectedAtomicOptions)
        } catch {
            // A failed write keeps the day in memory; the next answer tries again.
        }
    }
}
