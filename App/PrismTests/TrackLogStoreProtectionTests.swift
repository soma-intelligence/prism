//
//  TrackLogStoreProtectionTests.swift
//  PrismTests
//

import Foundation
import Testing
@testable import Prism

/// A Track log the process could not read (a locked phone, a protected file)
/// is never overwritten by the empty store that read left behind.
@MainActor
@Suite("Track log protection", .serialized)
struct TrackLogStoreProtectionTests {
    /// A log on disk holding one drink, in a fresh folder.
    private func seededLog() throws -> (url: URL, bytes: Data) {
        let folder = FileManager.default.temporaryDirectory.appending(path: "track-protection-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "track-log.json")
        let seed = TrackLogStore(url: url)
        _ = seed.addDrink(.water, ml: 330, at: Date(timeIntervalSince1970: 1_790_000_000))
        return (url, try Data(contentsOf: url))
    }

    private func setReadable(_ readable: Bool, _ url: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: readable ? 0o644 : 0o200], ofItemAtPath: url.path)
    }

    @Test("An unreadable log is never overwritten by a change made after the failed read")
    func unreadableLogIsNotOverwritten() throws {
        let (url, bytes) = try seededLog()
        try setReadable(false, url)
        defer { try? setReadable(true, url) }

        let store = TrackLogStore(url: url)
        #expect(store.drinks.isEmpty)
        _ = store.addDrink(.coffee, ml: 120, at: Date(timeIntervalSince1970: 1_790_003_600))
        store.waterGoalMl = 2500

        try setReadable(true, url)
        #expect(try Data(contentsOf: url) == bytes)
    }

    @Test("Once the log reads again, it loads and keeps what was logged meanwhile")
    func reloadMergesWhatWasLoggedWhileUnread() throws {
        let (url, _) = try seededLog()
        try setReadable(false, url)
        defer { try? setReadable(true, url) }

        let store = TrackLogStore(url: url)
        let added = store.addDrink(.coffee, ml: 120, at: Date(timeIntervalSince1970: 1_790_003_600))

        try setReadable(true, url)
        store.reloadIfUnread()

        #expect(store.drinks.count == 2)
        #expect(store.drinks.contains { $0.id == added.id })
        let reread = TrackLogStore(url: url)
        #expect(reread.drinks.count == 2)
    }

    @Test("A log that does not exist yet is created on the first change")
    func missingLogIsCreated() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "track-missing-\(UUID().uuidString)/track-log.json")
        let store = TrackLogStore(url: url)
        _ = store.addDrink(.water, ml: 250, at: Date(timeIntervalSince1970: 1_790_000_000))
        #expect(TrackLogStore(url: url).drinks.count == 1)
    }
}
