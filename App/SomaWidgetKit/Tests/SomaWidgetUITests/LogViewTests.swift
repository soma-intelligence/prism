import Foundation
import Testing
import SwiftUI
import SomaUI
import SomaWidgetKit
@testable import SomaWidgetUI

struct LogViewTests {
    static let snapshot = SomaWidgetSnapshot.placeholder
    static let now = snapshot.generatedAt

    static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    /// The fixture with today's tally emptied, for the day `now` falls on.
    static func emptied(calendar: Calendar) -> SomaWidgetSnapshot {
        var copy = snapshot
        let day = SomaWidgetSnapshot.Tally.dayString(now, calendar: calendar)
        copy.tally = .empty(day: day)
        return copy
    }

    @Test func waterFormat() {
        #expect(LogText.water(ml: 1250) == "1.25 L")
        #expect(LogText.water(ml: 400) == "400 ml")
    }

    @Test func waterFormatEdges() {
        #expect(LogText.water(ml: 0) == "0 ml")
        #expect(LogText.water(ml: 1000) == "1 L")
        #expect(LogText.water(ml: 1500) == "1.5 L")
        #expect(LogText.water(ml: 999.6) == "1 L")
        #expect(LogText.water(ml: .nan) == "-")
        #expect(LogText.water(ml: -5) == "-")
    }

    @Test func caffeineAndCounts() {
        #expect(LogText.caffeine(mg: 80) == "80 mg")
        #expect(LogText.caffeine(mg: .infinity) == "-")
        #expect(LogText.count(2) == "2")
        #expect(LogText.count(-1) == "-")
    }

    @Test func pendingShowsAtOnce() {
        let empty = Self.emptied(calendar: .current)
        let pending = [LogItem(kind: .water, ml: 250, date: Self.now)]
        let model = LogMedium.Model(snapshot: empty, pending: pending, now: Self.now)
        #expect(model.tally.waterMl == 250)
        #expect(model.display == .data(.fresh))
    }

    @Test func pendingCoffeeAddsCaffeine() {
        let empty = Self.emptied(calendar: Self.utc)
        let pending = [LogItem(kind: .coffee, ml: 250, date: Self.now)]
        let model = LogMedium.Model(snapshot: empty, pending: pending, now: Self.now, calendar: Self.utc)
        #expect(model.tally.caffeineMg == 80)
        // Coffee counts as poured, like the app's own water total.
        #expect(model.tally.waterMl == 250)
    }

    @Test func pendingFromYesterdayIsLeftOut() {
        let empty = Self.emptied(calendar: Self.utc)
        let yesterday = Self.now.addingTimeInterval(-24 * 3600)
        let pending = [LogItem(kind: .water, ml: 250, date: yesterday)]
        let model = LogMedium.Model(snapshot: empty, pending: pending, now: Self.now, calendar: Self.utc)
        #expect(model.tally.waterMl == 0)
    }

    @Test func modelWithoutSnapshotIsEmpty() {
        let pending = [LogItem(kind: .water, ml: 250, date: Self.now)]
        let model = LogMedium.Model(snapshot: nil, pending: pending, now: Self.now)
        #expect(model.display == .empty)
    }

    @Test func yesterdaysTallyStartsTodayEmpty() {
        // Review focus 4: the app wrote yesterday's tally and nothing since.
        var old = Self.snapshot
        let yesterday = Self.now.addingTimeInterval(-24 * 3600)
        old.tally = SomaWidgetSnapshot.Tally(
            day: SomaWidgetSnapshot.Tally.dayString(yesterday, calendar: Self.utc),
            waterMl: 1800,
            caffeineMg: 160,
            moods: 2,
            meals: 3,
            waterGoalMl: 2500
        )
        let model = LogMedium.Model(snapshot: old, pending: [], now: Self.now, calendar: Self.utc)
        #expect(model.tally.day == SomaWidgetSnapshot.Tally.dayString(Self.now, calendar: Self.utc))
        #expect(model.tally.waterMl == 0)
        #expect(model.tally.caffeineMg == 0)
        #expect(model.tally.moods == 0)
        #expect(model.tally.meals == 0)
        #expect(model.tally.waterGoalMl == 2500)
        #expect(model.waterFraction == 0)
    }

    @Test func pendingCountsOnce() {
        // Review focus 2: an item already drained into the tally, and one
        // item listed twice in the inbox, each count once.
        let drained = LogItem(kind: .water, ml: 250, date: Self.now)
        let fresh = LogItem(kind: .water, ml: 250, date: Self.now)
        var snapshot = Self.emptied(calendar: Self.utc)
        snapshot.tally.waterMl = 250
        snapshot.tally.countedIDs = [drained.id]
        let model = LogMedium.Model(
            snapshot: snapshot, pending: [drained, fresh, fresh], now: Self.now, calendar: Self.utc
        )
        #expect(model.tally.waterMl == 500)
    }

    @Test func facesOnlyButtonsRunNothing() {
        // The app's gallery draws the buttons; a tap there must not log a drink.
        #expect(LogButton(action: .water).runsIntent)
        #expect(LogButton(action: .coffee).runsIntent)
        #expect(!LogButton(action: .water, facesOnly: true).runsIntent)
        #expect(!LogButton(action: .coffee, facesOnly: true).runsIntent)
        #expect(!LogButton(action: .mood).runsIntent)
    }

    @Test func buttonsShowBeforeFirstScores() {
        // A snapshot without Health data still logs: the App Group exists.
        var blank = Self.snapshot
        blank.hasData = false
        let model = LogMedium.Model(snapshot: blank, pending: [], now: Self.now, calendar: Self.utc)
        #expect(model.display == .data(.fresh))
    }

    @Test func ringFractionClamps() {
        var over = Self.snapshot
        over.tally.waterMl = 5000
        let full = LogMedium.Model(snapshot: over, pending: [], now: Self.now, calendar: Self.utc)
        #expect(full.waterFraction == 1)
        let half = LogMedium.Model(snapshot: Self.snapshot, pending: [], now: Self.now, calendar: Self.utc)
        #expect(half.waterFraction == 1250.0 / 2000.0)
        var noGoal = Self.snapshot
        noGoal.tally.waterGoalMl = 0
        let none = LogMedium.Model(snapshot: noGoal, pending: [], now: Self.now, calendar: Self.utc)
        #expect(none.waterFraction == nil)
    }

    @Test func accessibilityReadsTheDay() {
        let model = LogMedium.Model(snapshot: Self.snapshot, pending: [], now: Self.now, calendar: Self.utc)
        #expect(LogText.accessibility(model) == "Water 1.25 L, Caffeine 0 mg, Moods 0, Meals 0")
        let stale = LogMedium.Model(
            snapshot: Self.snapshot, pending: [], now: Self.now.addingTimeInterval(14 * 3600), calendar: Self.utc
        )
        #expect(LogText.accessibility(stale).hasSuffix(", 14 h ago"))
    }

    @Test func buttonsNameWhatTheyLog() {
        #expect(LogAction.allCases.map(\.symbol) == ["drop", "cup.and.saucer", "face.smiling", "fork.knife"])
        #expect(LogAction.allCases.map(\.label) == ["Log water", "Log coffee", "Log mood", "Log meal"])
    }
}
