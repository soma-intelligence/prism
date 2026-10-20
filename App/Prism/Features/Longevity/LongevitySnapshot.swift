//
//  LongevitySnapshot.swift
//  Prism
//

import CryptoKit
import Foundation
import SomaUI

/// What the Body lens draws: its three numbers and their words, every
/// reading's tile and row, and muscle freshness.
struct BodyLensSnapshot: Codable, Equatable {
    var page: BodyOverview
    var sex: BodyFitnessAge.Sex
    var markers: [BodyBiomarkerSpec: BodyBiomarker]
    var muscles: [SomaMuscleReading]

    /// Nothing read yet: every value a dash.
    static func empty(now: Date = .now) -> BodyLensSnapshot {
        BodyLensSnapshot(
            page: BodyOverview.make(from: BodyOverviewInputs(now: now)),
            sex: .unknown,
            markers: [:],
            muscles: MuscleFreshness.readings([], now: now)
        )
    }
}

/// What the Environment lens draws from its reads: the report with the
/// weather laid in, last night outside and in the bedroom, and where you
/// are (the rounded place and its name, never the device's own position).
/// Sleep places are not kept here: ``SleepPlaceFinder`` keeps its own file.
struct EnvironmentLensSnapshot: Codable, Equatable {
    var report: EnvironmentReport
    var outdoorNight: Double?
    var noise: Double?
    var place: EnvironmentSun.Place?
    var isHere: Bool
}

/// A lens's values and when they were read.
struct LongevityKept<Value> {
    var value: Value
    var savedAt: Date
}

extension LongevityKept: Equatable where Value: Equatable {}
extension LongevityKept: Codable where Value: Codable {}

/// What a lens draws: the read that just landed, else the values kept from
/// the last one, so the page opens on its numbers rather than on dashes.
struct LongevityShown<Value> {
    var kept: LongevityKept<Value>?
    var fresh: Value?

    /// Kept values older than this say when they were read.
    static var staleAfter: TimeInterval { 12 * 3_600 }

    /// Nil only before the first read ever lands.
    var value: Value? { fresh ?? kept?.value }

    /// True while the kept values stand in for a read still on its way.
    var isKept: Bool { fresh == nil && kept != nil }

    /// When the values on screen were read, while they are kept ones older
    /// than ``staleAfter``: what the quiet "Updated" line says. Nil once
    /// the fresh read lands.
    func updated(now: Date) -> Date? {
        guard fresh == nil, let kept, now.timeIntervalSince(kept.savedAt) >= Self.staleAfter else { return nil }
        return kept.savedAt
    }
}

/// The Longevity tab's last read, as one small file in the app's own
/// storage: what each lens drew the last time it read Health, so the tab
/// opens on those numbers after a relaunch while it reads again.
///
/// It holds what the lenses draw (formatted values, the lines' days, the
/// words), not the samples behind them, and it never leaves the device: no
/// sync, no export. It belongs to one person: written under who is signed in
/// (a hash of the account id, or this device when nobody is), and dropped,
/// file and all, as soon as someone else is. "Delete my data" and deleting
/// what Mind keeps clear it too. A file from another version of the app
/// reads as nothing and is removed.
struct LongevitySnapshot: Codable, Equatable {
    /// Raised whenever a lens's snapshot changes shape.
    static let currentVersion = 1

    var version = Self.currentVersion
    /// Whose numbers these are: ``LongevitySnapshotStore/owner(of:)``.
    var owner: String
    var body: LongevityKept<BodyLensSnapshot>?
    var mind: LongevityKept<MindLensModel>?
    var environment: LongevityKept<EnvironmentLensSnapshot>?

    /// Just the fields read before the rest, so a file from another
    /// version or another person is dropped without decoding it whole.
    private struct Header: Decodable {
        var version: Int
        var owner: String
    }

    enum Reading: Equatable {
        case found(LongevitySnapshot)
        /// No file, or one this build cannot read: it goes.
        case unreadable
        /// Another version's file: it goes.
        case otherVersion
        /// Someone else's numbers: they go.
        case otherOwner
    }

    static func read(_ data: Data, owner: String) -> Reading {
        let decoder = JSONDecoder()
        guard let header = try? decoder.decode(Header.self, from: data) else { return .unreadable }
        guard header.version == currentVersion else { return .otherVersion }
        guard header.owner == owner else { return .otherOwner }
        guard let snapshot = try? decoder.decode(LongevitySnapshot.self, from: data) else { return .unreadable }
        return .found(snapshot)
    }
}

/// Keeps the ``LongevitySnapshot`` on the device: read once, on the first
/// lens that opens, then held in memory; written after every fresh read.
@MainActor
final class LongevitySnapshotStore {
    static let shared = LongevitySnapshotStore()

    nonisolated static var defaultURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appending(path: "longevity-snapshot.json")
    }

    /// Whose numbers a file holds: a hash of the signed in account's id, so
    /// the id itself is not written again, or this device when nobody is
    /// signed in.
    nonisolated static func owner(of userID: String?) -> String {
        guard let userID else { return "device" }
        return SHA256.hash(data: Data(userID.lowercased().utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private let url: URL?
    private let currentOwner: @MainActor () -> String
    private var snapshot: LongevitySnapshot?
    private var hasRead = false
    /// The last write or removal, so they land on disk in order.
    private var pending: Task<Void, Never>?

    /// - Parameters:
    ///   - url: nil keeps everything in memory, for previews and tests.
    ///   - owner: who the numbers belong to now.
    init(url: URL? = LongevitySnapshotStore.defaultURL,
         owner: @escaping @MainActor () -> String = { LongevitySnapshotStore.owner(of: AccountSession.shared.state.user?.id) }) {
        self.url = url
        self.currentOwner = owner
    }

    var body: LongevityKept<BodyLensSnapshot>? { current?.body }
    var mind: LongevityKept<MindLensModel>? { current?.mind }
    var environment: LongevityKept<EnvironmentLensSnapshot>? { current?.environment }

    func save(body: BodyLensSnapshot, at date: Date = .now) {
        update { $0.body = LongevityKept(value: body, savedAt: date) }
    }

    func save(mind: MindLensModel, at date: Date = .now) {
        update { $0.mind = LongevityKept(value: mind, savedAt: date) }
    }

    func save(environment: EnvironmentLensSnapshot, at date: Date = .now) {
        update { $0.environment = LongevityKept(value: environment, savedAt: date) }
    }

    /// Forgets Mind's lens, for when what Mind keeps is deleted: its mood
    /// strip carries the moods.
    func clearMind() {
        guard current?.mind != nil else { return }
        update { $0.mind = nil }
    }

    /// Forgets every lens, file and all.
    func clear() {
        snapshot = nil
        hasRead = true
        remove()
    }

    /// Waits for the writes in flight, for tests.
    func settle() async {
        await pending?.value
    }

    // MARK: Inside

    /// The snapshot for whoever is signed in now; someone else's is dropped.
    private var current: LongevitySnapshot? {
        if !hasRead {
            hasRead = true
            snapshot = readFile()
        }
        if let snapshot, snapshot.owner != currentOwner() {
            clear()
            return nil
        }
        return snapshot
    }

    private func update(_ change: (inout LongevitySnapshot) -> Void) {
        var next = current ?? LongevitySnapshot(owner: currentOwner())
        change(&next)
        guard next != snapshot else { return }
        snapshot = next
        write(next)
    }

    private func readFile() -> LongevitySnapshot? {
        // Unreadable while the phone is locked (complete protection): the
        // lenses then simply read Health as on a first launch.
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        switch LongevitySnapshot.read(data, owner: currentOwner()) {
        case .found(let snapshot):
            return snapshot
        case .unreadable, .otherVersion, .otherOwner:
            remove()
            return nil
        }
    }

    private func write(_ snapshot: LongevitySnapshot) {
        guard let url, let data = try? JSONEncoder().encode(snapshot) else { return }
        let previous = pending
        pending = Task.detached(priority: .utility) {
            await previous?.value
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: url, options: SomaFileStorage.protectedAtomicOptions)
            } catch {
                // Kept in memory for this run; the next read starts from Health.
            }
        }
    }

    private func remove() {
        guard let url else { return }
        let previous = pending
        pending = Task.detached(priority: .utility) {
            await previous?.value
            try? FileManager.default.removeItem(at: url)
        }
    }
}
