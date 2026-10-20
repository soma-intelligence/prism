//
//  TrackRitualsTests.swift
//  PrismTests
//

import Foundation
import Testing
import HealthExportCore
import SomaUI
@testable import Prism

/// Rituals and the quick add layout: what is stored, how a day is counted as
/// kept, and the words the Rituals part says.
@MainActor
@Suite("Track rituals")
struct TrackRitualsTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }()

    func day(_ month: Int, _ day: Int, hour: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    // MARK: Store

    @Test("A new person starts with a morning and an evening ritual of three steps")
    func starter() {
        let store = TrackRitualStore(url: nil, calendar: calendar)
        #expect(store.rituals.map(\.moment) == [.morning, .evening])
        #expect(store.ritual(.morning).steps.count == 3)
        #expect(store.ritual(.evening).steps.count == 3)
    }

    @Test("Ticking a step twice leaves the day as it was")
    func toggle() {
        let store = TrackRitualStore(url: nil, calendar: calendar)
        let step = store.ritual(.morning).steps[0]
        store.toggle(step, on: day(10, 19))
        #expect(store.isDone(step, on: day(10, 19, hour: 22)))
        #expect(!store.isDone(step, on: day(10, 18)))
        #expect(store.share(.morning, on: day(10, 19)) == 1.0 / 3)
        store.toggle(step, on: day(10, 19))
        #expect(store.done.isEmpty)
    }

    @Test("Steps are added, moved and removed, and a removed step stops counting")
    func editing() {
        let store = TrackRitualStore(url: nil, calendar: calendar)
        let first = store.ritual(.evening).steps[0]
        store.toggle(first, on: day(10, 19))
        store.addStep("  Tea, no caffeine ", glyph: .coffee, to: .evening)
        store.addStep("   ", glyph: .tag, to: .evening)
        #expect(store.ritual(.evening).steps.count == 4)
        #expect(store.ritual(.evening).steps.last?.title == "Tea, no caffeine")
        #expect(store.ritual(.evening).steps.last?.kind == .coffee)

        store.moveSteps(in: .evening, from: IndexSet(integer: 3), to: 0)
        #expect(store.ritual(.evening).steps.first?.title == "Tea, no caffeine")

        store.removeStep(first.id, from: .evening)
        #expect(store.ritual(.evening).steps.count == 3)
        #expect(store.share(.evening, on: day(10, 19)) == 0)
        #expect(store.ritual(.morning).steps.count == 3)
    }

    @Test("A ritual with no steps has no share, never a zero")
    func emptyRitual() {
        let store = TrackRitualStore(url: nil, calendar: calendar)
        for step in store.ritual(.morning).steps { store.removeStep(step.id, from: .morning) }
        #expect(store.share(.morning, on: day(10, 19)) == nil)
    }

    @Test("The file reads back what was written, and a glyph it does not know draws as a tag")
    func persistence() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "rituals-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = TrackRitualStore(url: url, calendar: calendar)
        store.addStep("Walk", glyph: .walk, to: .morning)
        store.toggle(store.ritual(.morning).steps[3], on: day(10, 19))

        let again = TrackRitualStore(url: url, calendar: calendar)
        #expect(again.ritual(.morning).steps.map(\.title) == store.ritual(.morning).steps.map(\.title))
        #expect(again.isDone(again.ritual(.morning).steps[3], on: day(10, 19)))

        let step = TrackRitualStep(id: "x", title: "Something new", glyph: "comet")
        #expect(step.kind == .tag)
    }

    @Test("A file holding one ritual still opens with both")
    func completesMissingMoment() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "rituals-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let json = #"{"rituals":[{"moment":"evening","steps":[{"id":"e1","title":"Read","glyph":"read"}]}],"done":{}}"#
        try Data(json.utf8).write(to: url)
        let store = TrackRitualStore(url: url, calendar: calendar)
        #expect(store.rituals.map(\.moment) == [.morning, .evening])
        #expect(store.ritual(.morning).steps.isEmpty)
        #expect(store.ritual(.evening).steps.map(\.title) == ["Read"])
    }

    // MARK: Summary

    @Test("Two weeks of shares end today, a streak counts full days back from yesterday while today is open")
    func summary() {
        let store = TrackRitualStore(url: nil, calendar: calendar)
        let steps = store.ritual(.morning).steps
        // Kept on the 16th, 17th and 18th; one step on the 19th (today).
        for date in [day(10, 16), day(10, 17), day(10, 18)] {
            for step in steps { store.toggle(step, on: date) }
        }
        store.toggle(steps[0], on: day(10, 19))

        let summary = TrackRitualSummary.make(.morning, store: store, inputs: nil, today: day(10, 19), calendar: calendar)
        #expect(summary.shares.count == TrackRitualSummary.days)
        #expect(summary.shares.last == 1.0 / 3)
        #expect(summary.shares.suffix(4).dropLast().allSatisfy { $0 == 1 })
        #expect(summary.streak == 3)
        #expect(summary.keptThisWeek == 3)
        #expect(summary.progressText == "1 of 3")
        #expect(!summary.isKeptToday)
        #expect(summary.streakText == "3 days running")
    }

    @Test("The effect line asks for days until Soma has them, then says the move plainly")
    func effectWords() {
        var summary = TrackRitualSummary(moment: .evening, doneToday: 0, steps: 3, shares: [], streak: 0,
                                         keptThisWeek: 0, effect: EffectMath.Effect(delta: nil, held: 0, tries: 1))
        #expect(summary.effectText == "Keep it a few days and Soma shows what it does for your deep sleep.")
        summary.effect = EffectMath.Effect(delta: 12.4, held: 5, tries: 6)
        #expect(summary.effectText == "Your deep sleep runs +12 min on nights you keep it.")
        summary.moment = .morning
        summary.effect = EffectMath.Effect(delta: -3, held: 1, tries: 6)
        #expect(summary.effectText == "Your evening HRV runs -3 ms on days you keep it.")
        for text in [summary.effectText] {
            #expect(!text.contains("\u{2014}") && !text.contains("\u{2013}"))
        }
    }

    // MARK: Quick add

    @Test("Nothing saved shows every tile; saved names keep their order, drop unknowns and repeats")
    func quickAddDecode() {
        #expect(TrackQuickAddLayout.decode(nil) == TrackQuickAdd.allCases)
        #expect(TrackQuickAddLayout.decode(["meal", "comet", "drink", "meal"]) == [.meal, .drink])
        #expect(TrackQuickAddLayout.decode([]) == [])
    }

    @Test("Hiding, showing and moving a tile is saved")
    func quickAddEditing() throws {
        let defaults = try #require(UserDefaults(suiteName: "track-quick-add-\(UUID().uuidString)"))
        let layout = TrackQuickAddLayout(defaults: defaults)
        layout.hide(.scan)
        #expect(!layout.shown.contains(.scan))
        #expect(layout.hidden == [.scan])
        layout.move(from: IndexSet(integer: 1), to: 0)
        #expect(layout.shown.prefix(2) == [.meal, .drink])
        layout.show(.scan)
        #expect(layout.shown.last == .scan)

        let again = TrackQuickAddLayout(defaults: defaults)
        #expect(again.shown == layout.shown)
    }

    @Test("Every tile opens something: a sheet, or the blood test's lab page")
    func quickAddRoutes() {
        for tile in TrackQuickAdd.allCases {
            #expect(tile.route != nil || tile == .bloodTest)
        }
    }

    @Test("Tags and rituals wear calm tones, never Health's saturated hues")
    func calmTones() {
        for section in TrackTagStyle.Section.allCases {
            #expect(SomaTrackTone.allCases.contains(section.tone))
        }
        #expect(TrackTagStyle.of("alcohol").glyph == .alcohol)
        #expect(TrackTagStyle.of("custom-1234").glyph == .tag)
        #expect(TrackRitualMoment.morning.tone != TrackRitualMoment.evening.tone)
    }
}
