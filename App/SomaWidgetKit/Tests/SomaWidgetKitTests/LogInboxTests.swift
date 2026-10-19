import Foundation
import Testing
@testable import SomaWidgetKit

private func tempDir() -> URL {
    URL.temporaryDirectory.appending(path: UUID().uuidString)
}

private let utc: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}()

/// Noon UTC on a "yyyy-MM-dd" day.
private func day(_ s: String) -> Date {
    let f = DateFormatter()
    f.calendar = utc
    f.timeZone = utc.timeZone
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd HH:mm"
    return f.date(from: s + " 12:00")!
}

@Test func appendThenPending() throws {
    let inbox = LogInbox(directory: tempDir())
    let item = LogItem(id: UUID(), kind: .water, ml: 250, date: .now)
    try inbox.append(item)
    #expect(inbox.pending() == [item])
}

@Test func pendingEmptyWhenNoFile() {
    #expect(LogInbox(directory: tempDir()).pending().isEmpty)
}

@Test func removeDrops() throws {
    let inbox = LogInbox(directory: tempDir())
    let a = LogItem(id: UUID(), kind: .water, ml: 250, date: .now)
    let b = LogItem(id: UUID(), kind: .coffee, ml: 250, date: .now)
    try inbox.append(a)
    try inbox.append(b)
    try inbox.remove(ids: [a.id])
    #expect(inbox.pending() == [b])
}

@Test func tallyCountsPendingOnce() {
    let id = UUID()
    var t = SomaWidgetSnapshot.Tally.empty(day: "2026-10-03")
    t.waterMl = 250
    t.countedIDs = [id]
    let pending = [
        LogItem(id: id, kind: .water, ml: 250, date: day("2026-10-03")),
        LogItem(id: UUID(), kind: .coffee, ml: 250, date: day("2026-10-03")),
    ]
    t = t.adding(pending, day: "2026-10-03", calendar: utc)
    // The coffee counts as poured, like the app's own water total.
    #expect(t.waterMl == 500)
    #expect(t.caffeineMg == 80)
}

@Test func tallyCountsPendingCoffeeAsWater() {
    let t = SomaWidgetSnapshot.Tally.empty(day: "2026-10-03")
        .adding([LogItem(id: UUID(), kind: .coffee, ml: 150, date: day("2026-10-03"))], day: "2026-10-03", calendar: utc)
    #expect(t.waterMl == 150)
    #expect(t.caffeineMg == 48)
}

@Test func tallyCountsADuplicatedPendingItemOnce() {
    let item = LogItem(id: UUID(), kind: .water, ml: 250, date: day("2026-10-03"))
    let t = SomaWidgetSnapshot.Tally.empty(day: "2026-10-03")
        .adding([item, item], day: "2026-10-03", calendar: utc)
    #expect(t.waterMl == 250)
}

@Test func tallyAddsPendingWater() {
    let t = SomaWidgetSnapshot.Tally.empty(day: "2026-10-03")
        .adding([LogItem(id: UUID(), kind: .water, ml: 330, date: day("2026-10-03"))], day: "2026-10-03", calendar: utc)
    #expect(t.waterMl == 330)
}

@Test func tallyIgnoresOtherDays() {
    let t = SomaWidgetSnapshot.Tally.empty(day: "2026-10-03")
        .adding([LogItem(id: UUID(), kind: .water, ml: 250, date: day("2026-10-02"))], day: "2026-10-03", calendar: utc)
    #expect(t.waterMl == 0)
}

@Test func snapshotTallyFromYesterdayResets() {
    var old = SomaWidgetSnapshot.Tally.empty(day: "2026-10-02")
    old.waterMl = 900
    old.waterGoalMl = 2500
    let t = old.adding([], day: "2026-10-03", calendar: utc)
    #expect(t.day == "2026-10-03")
    #expect(t.waterMl == 0)
    #expect(t.waterGoalMl == 2500)
}

@Test func appendOnUndecodableFileSetsItAsideAndStartsFresh() throws {
    let dir = tempDir()
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let file = dir.appending(path: "log-inbox.json")
    let garbage = Data("not json".utf8)
    try garbage.write(to: file)
    let inbox = LogInbox(directory: dir)
    let item = LogItem(id: UUID(), kind: .water, ml: 250, date: .now)
    try inbox.append(item)
    #expect(inbox.pending() == [item])
    // Never silently overwritten: the bytes survive beside the new inbox.
    let aside = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        .filter { $0.hasPrefix("log-inbox.corrupt-") && $0.hasSuffix(".json") }
    #expect(aside.count == 1)
    let name = try #require(aside.first)
    #expect(try Data(contentsOf: dir.appending(path: name)) == garbage)
}

#if canImport(AppIntents)
/// Shortcuts can call the intent with any amount: it takes one drink's worth.
@Test func logDrinkIntentRefusesAnAmountOutsideOneDrink() async {
    for ml in [0.0, -250, 2001, .infinity, .nan] {
        await #expect(throws: LogIntentError.invalidAmount) {
            _ = try await LogDrinkIntent(kind: .water, ml: ml).perform()
        }
    }
    #expect(LogDrinkIntent.mlRange == 1...2000)
}
#endif
