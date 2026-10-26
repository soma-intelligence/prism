//
//  HealthSnapshotStore.swift
//  Prism
//

import Foundation
import HealthExportCore

/// What the pages showed last time, kept on the device so the next launch
/// opens on numbers instead of dashes: the scores, the Today page and the
/// day's readings. The first read from Health then replaces them as it lands.
///
/// The owner asked for the pages to be "there but not yet current, and update
/// as they go" rather than empty and then filled (2026-10-24).
nonisolated struct HealthSnapshot: Codable, Equatable, Sendable {
    /// Bumped when a cached type changes shape; an older file is dropped.
    static let version = 1

    var version = Self.version
    var savedAt: Date
    var scores: SomaScores?
    var today: PulseToday?
    var readings: [String: HealthReading] = [:]
    var durations: [String: TimeInterval] = [:]
}

/// Reads and writes the one snapshot file.
///
/// The file sits in Application Support with the system's default data
/// protection, closed until the phone is first unlocked after a restart, and
/// never leaves the device: no backup flag is lifted and nothing syncs it.
/// Every failure (a missing file, an older shape, a corrupt write) reads as
/// no snapshot: the app opens as it did before, and never crashes on it.
nonisolated struct HealthSnapshotStore: Sendable {
    let url: URL

    /// The app's own file.
    static let shared = HealthSnapshotStore(
        url: (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
              ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("Soma", isDirectory: true)
            .appendingPathComponent("health-snapshot.json")
    )

    /// How old a snapshot may be and still be shown. Past it, a stale page
    /// would mislead more than an empty one.
    static let maximumAge: TimeInterval = 7 * 86_400

    /// The snapshot, trimmed to what still holds at `now`: the scores for a
    /// week, the Today page and the day's readings only on the day they
    /// were read, since a yesterday's step count shown as today's is wrong.
    func load(now: Date = Date(), calendar: Calendar = .current) -> HealthSnapshot? {
        guard let data = try? Data(contentsOf: url),
              var snapshot = try? JSONDecoder().decode(HealthSnapshot.self, from: data),
              snapshot.version == HealthSnapshot.version,
              snapshot.savedAt <= now.addingTimeInterval(60),
              now.timeIntervalSince(snapshot.savedAt) < Self.maximumAge
        else { return nil }
        if !calendar.isDate(snapshot.savedAt, inSameDayAs: now) {
            snapshot.today = nil
            snapshot.readings = [:]
            snapshot.durations = [:]
        }
        return snapshot
    }

    /// Writes the snapshot atomically, so a crash mid-write leaves the old
    /// file whole rather than half of a new one.
    func save(_ snapshot: HealthSnapshot) throws {
        let data = try JSONEncoder().encode(snapshot)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: [.atomic])
    }

    /// Removes the file, for a reset or an account deletion.
    func clear() {
        try? FileManager.default.removeItem(at: url)
    }
}
