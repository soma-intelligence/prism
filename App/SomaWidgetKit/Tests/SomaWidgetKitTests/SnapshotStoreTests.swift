import Foundation
import Testing
@testable import SomaWidgetKit

@Test func roundTrip() throws {
    let dir = URL.temporaryDirectory.appending(path: UUID().uuidString)
    let store = SnapshotStore(directory: dir)
    try store.write(.placeholder)
    #expect(store.read() == .placeholder)
}

@Test func olderPayloadDecodes() throws {
    let json = #"{"generatedAt": 0, "hasData": true}"#
    let snap = try JSONDecoder().decode(SomaWidgetSnapshot.self, from: Data(json.utf8))
    #expect(snap.hasData)
    #expect(snap.recovery.value == nil)
    #expect(snap.energyCurve.isEmpty)
    #expect(snap.tally.waterGoalMl == 2000)
    #expect(snap.tally.countedIDs.isEmpty)
}

@Test func malformedSleepBandDropsOnlyTheBand() throws {
    // A reversed range throws on decode; the rest of the snapshot must survive.
    let json = #"{"generatedAt": 0, "hasData": true, "recovery": {"value": 82}, "sleepBand": [100, 0]}"#
    let snap = try JSONDecoder().decode(SomaWidgetSnapshot.self, from: Data(json.utf8))
    #expect(snap.sleepBand == nil)
    #expect(snap.recovery.value == 82)
    #expect(snap.hasData)
}

@Test func missingFileReadsNil() {
    #expect(SnapshotStore(directory: .temporaryDirectory.appending(path: UUID().uuidString)).read() == nil)
}

@Test func staleAfterTwelveHours() {
    var s = SomaWidgetSnapshot.placeholder
    s.generatedAt = Date(timeIntervalSince1970: 0)
    #expect(s.freshness(now: Date(timeIntervalSince1970: 12 * 3600)) == .fresh)
    #expect(s.freshness(now: Date(timeIntervalSince1970: 12 * 3600 + 1)) == .stale(hours: 12))
    #expect(s.freshness(now: Date(timeIntervalSince1970: 18 * 3600)) == .stale(hours: 18))
}

#if !os(iOS)
/// Widgets ship on iOS only: off iOS there is no App Group, and
/// `containerURL` still hands back a path, so the shared accessors must refuse.
@Test func sharedAccessorsAreNilOffIOS() {
    #expect(SnapshotStore.shared == nil)
    #expect(LogInbox.shared == nil)
}
#endif
