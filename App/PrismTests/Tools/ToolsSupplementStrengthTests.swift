//
//  ToolsSupplementStrengthTests.swift
//  PrismTests
//
//  Supplement Window: the timing catalog, the day plan and its conflicts, and
//  the roster whose whole job is to be a list that CANNOT contain a
//  prescription medication.
//
//  Strength Load: volume load, the Epley one rep max, the weekly verdict and
//  per exercise progression, fed explicit sets.
//

import Foundation
import Testing
@testable import Prism

// MARK: - Supplement timing

@Suite("Tools: Supplement timing")
struct ToolsSupplementTimingTests {

    typealias Catalog = SomaTools.SupplementTimingCatalog
    typealias Engine = SomaTools.SupplementTimingEngine
    typealias Slot = SomaTools.SupplementSlot

    // MARK: Catalog

    @Test func catalogIDsAreUnique() {
        let ids = Catalog.all.map(\.id)
        #expect(ids.count == Set(ids).count)
    }

    @Test func everyEntryHasCopy() {
        for entry in Catalog.all {
            #expect(!entry.name.isEmpty, "missing name for \(entry.id)")
            #expect(!entry.reason.isEmpty, "missing reason for \(entry.id)")
        }
    }

    /// Every declared competitor must point at an existing entry, or a real
    /// conflict would stay invisible.
    @Test func everyCompetitorExistsInTheCatalog() {
        for entry in Catalog.all {
            for other in entry.competesWith {
                #expect(Catalog.entry(id: other) != nil, "\(entry.id) names \(other), absent from the catalog")
            }
        }
    }

    /// Absorption competition is physically symmetric; the catalog must say so.
    @Test func competitionIsDeclaredSymmetrically() {
        for entry in Catalog.all {
            for other in entry.competesWith {
                let back = Catalog.entry(id: other)?.competesWith ?? []
                #expect(back.contains(entry.id), "\(entry.id) names \(other) but not the reverse")
            }
        }
    }

    /// Scope: no prescription medication may enter this catalog.
    @Test func catalogHoldsNoPrescriptionMedication() {
        let forbidden = ["statin", "levothyroxine", "metformin", "warfarin", "ssri", "insulin", "lisinopril"]
        let ids = Catalog.all.map { $0.id.lowercased() }
        for banned in forbidden {
            #expect(!ids.contains(banned), "\(banned) does not belong here")
        }
    }

    // MARK: Slots

    @Test func slotsAreOrderedThroughTheDay() {
        #expect(Slot.allCases.sorted() == [.onWaking, .withBreakfast, .midday, .withDinner, .beforeBed])
    }

    @Test func slotTimesFollowWakeNotTheClock() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        // A night worker waking at 16:00 gets the same order.
        let wake = Date(timeIntervalSince1970: 16 * 3600)
        let waking = Engine.time(for: .onWaking, wake: wake, calendar: calendar)
        let bed = Engine.time(for: .beforeBed, wake: wake, calendar: calendar)
        #expect(waking == wake)
        #expect(abs(bed.timeIntervalSince(wake) - 15 * 3600) <= 60)
    }

    // MARK: Plan

    @Test func emptySelectionYieldsAnEmptyPlan() {
        #expect(Engine.plan(forSelectedIDs: []).isEmpty)
    }

    @Test func planGroupsBySlotInDayOrder() {
        let plan = Engine.plan(forSelectedIDs: ["magnesium", "iron", "vitaminD"])
        #expect(plan.slots.map(\.slot) == [.onWaking, .withBreakfast, .beforeBed])
        #expect(plan.slots.first?.entryIDs == ["iron"])
    }

    @Test func duplicatesAreCollapsed() {
        let plan = Engine.plan(forSelectedIDs: ["iron", "iron", "iron"])
        #expect(plan.slots.count == 1)
        #expect(plan.slots.first?.entryIDs == ["iron"])
    }

    @Test func unknownIDsAreReportedNotSilentlyDropped() {
        let plan = Engine.plan(forSelectedIDs: ["iron", "unobtainium"])
        #expect(plan.unknownIDs == ["unobtainium"])
        #expect(plan.slots.count == 1)
    }

    @Test func slotContentsAreAlphabeticalForStableRenders() {
        let plan = Engine.plan(forSelectedIDs: ["zinc", "calcium"])
        #expect(plan.slots.first { $0.slot == .withDinner }?.entryIDs == ["calcium", "zinc"])
    }

    // MARK: Conflicts

    @Test func competingItemsInTheSameSlotConflict() {
        let plan = Engine.plan(forSelectedIDs: ["calcium", "zinc"])
        #expect(plan.conflicts.count == 1)
        #expect(plan.conflicts.first?.slot == .withDinner)
    }

    @Test func competingItemsInDifferentSlotsDoNotConflict() {
        #expect(Engine.plan(forSelectedIDs: ["iron", "calcium"]).conflicts.isEmpty)
    }

    @Test func nonCompetingItemsInTheSameSlotDoNotConflict() {
        #expect(Engine.plan(forSelectedIDs: ["magnesium", "melatonin"]).conflicts.isEmpty)
    }

    @Test func aPairIsReportedOnce() {
        let plan = Engine.plan(forSelectedIDs: ["calcium", "zinc"])
        #expect(plan.conflicts.count == 1)
        #expect(Set(plan.conflicts.map(\.id)).count == plan.conflicts.count)
    }

    /// Calcium, zinc and magnesium compete pairwise, but magnesium sits at bed
    /// time: only calcium and zinc share a slot.
    @Test func threeWayClashYieldsOnlyTheSharedSlotPair() {
        #expect(Engine.plan(forSelectedIDs: ["calcium", "zinc", "magnesium"]).conflicts.count == 1)
    }

    @Test func conflictIDIsOrderIndependent() {
        let a = Engine.Conflict(firstID: "zinc", secondID: "calcium", slot: .withDinner)
        let b = Engine.Conflict(firstID: "calcium", secondID: "zinc", slot: .withDinner)
        #expect(a.id == b.id)
    }

    // MARK: Food rules

    @Test func fatSolubleItemsAskForFat() {
        #expect(Catalog.entry(id: "vitaminD")?.foodRule == .withFat)
        #expect(Catalog.entry(id: "omega3")?.foodRule == .withFat)
    }

    @Test func ironWantsAnEmptyStomach() {
        #expect(Catalog.entry(id: "iron")?.foodRule == .emptyStomach)
        #expect(Catalog.entry(id: "iron")?.preferredSlot == .onWaking)
    }

    @Test func coffeeIsPresentOnlyForItsIronClash() {
        #expect(Catalog.entry(id: "coffee")?.competesWith.contains("iron") == true)
    }

    // MARK: Roster derived slots

    @Test func aKnownJournalIDGetsItsCatalogSlot() {
        #expect(Catalog.slot(forJournalID: "magnesium", section: "Daytime") == .beforeBed)
    }

    @Test func anUnknownEveningIDFallsBackToBeforeBed() {
        #expect(Catalog.slot(forJournalID: "custom.abc12345", section: "Evening") == .beforeBed)
    }

    @Test func anUnknownDaytimeIDFallsBackToWithBreakfast() {
        #expect(Catalog.slot(forJournalID: "probiotic", section: "Daytime") == .withBreakfast)
    }

    @Test func aCustomChoiceWinsOverTheSection() {
        var custom = SomaTools.SupplementCustomSlots()
        custom.set(slot: .midday, foodRule: .withFood, for: "custom.abc12345")
        #expect(Catalog.slot(forJournalID: "custom.abc12345", section: "Evening", custom: custom) == .midday)
        #expect(Catalog.foodRule(forJournalID: "custom.abc12345", custom: custom) == .withFood)
    }

    @Test func customSlotsSurviveARoundTripAndDropUnknownValues() throws {
        var custom = SomaTools.SupplementCustomSlots()
        custom.set(slot: .withDinner, foodRule: .withFat, for: "custom.a")
        let decoded = try JSONDecoder().decode(SomaTools.SupplementCustomSlots.self,
                                               from: JSONEncoder().encode(custom))
        #expect(decoded == custom)

        let json = #"{"slots":{"custom.a":"withDinner","custom.b":"atDawn"},"foodRules":{}}"#
        let lenient = try JSONDecoder().decode(SomaTools.SupplementCustomSlots.self, from: Data(json.utf8))
        #expect(lenient.slots == ["custom.a": .withDinner])
    }

    @Test func anUnknownIDInventsNoFoodRuleAndNoConflict() {
        #expect(Catalog.foodRule(forJournalID: "turmeric") == .anyTime)
        let plan = Engine.plan(forJournalEntries: [(id: "turmeric", section: "Daytime"),
                                                   (id: "probiotic", section: "Daytime")])
        #expect(plan.conflicts.isEmpty)
    }

    @Test func competingJournalIDsInOneSlotStillConflict() {
        let plan = Engine.plan(forJournalEntries: [(id: "zinc", section: "Daytime"),
                                                   (id: "calcium", section: "Daytime")])
        #expect(plan.conflicts.count == 1)
        #expect(plan.conflicts.first?.slot == .withDinner)
    }

    @Test func journalIDLookupResolvesTheTwin() {
        #expect(Catalog.entry(journalID: "vit-d")?.id == "vitaminD")
        #expect(Catalog.entry(journalID: "fish-oil")?.id == "omega3")
    }

    // MARK: Cross space invariants

    @Test func everyJournalTwinIsATrackableSupplement() {
        for entry in Catalog.all {
            guard let twin = entry.journalEntryID else { continue }
            #expect(!SomaTools.SupplementRoster.prescriptionIDs.contains(twin),
                    "\(entry.id) points at prescription id \(twin)")
            #expect(SomaTools.SupplementRoster.builtInIDs.contains(twin),
                    "\(entry.id) points at \(twin), which is not a tracked supplement")
        }
    }

    @Test func competitorsAreDeclaredInTimingIDsNotJournalIDs() {
        let timingIDs = Set(Catalog.all.map(\.id))
        for entry in Catalog.all {
            for competitor in entry.competesWith {
                #expect(timingIDs.contains(competitor))
            }
        }
    }

    // MARK: Day read

    @Test func dayReadCountsTakenAndPicksTheNextSlot() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let day = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 29)))
        let now = day.addingTimeInterval(9 * 3600)
        let entries = [SomaTools.SupplementRoster.Entry(id: "iron", title: "Iron"),
                       SomaTools.SupplementRoster.Entry(id: "magnesium", title: "Magnesium")]
        let read = SomaTools.SupplementDayRead.make(entries: entries,
                                                    answers: ["iron": true, "magnesium": false],
                                                    date: day, now: now, wakeMinutes: 7 * 60,
                                                    calendar: calendar)
        #expect(read.taken == 1)
        #expect(read.total == 2)
        #expect(read.isToday)
        // Iron at 07:00 is past; magnesium before bed at 22:00 is next.
        #expect(read.next?.slot == .beforeBed)
        #expect(read.next.map { SomaTools.SupplementDayRead.clockHour($0.time, calendar: calendar) } == 22)
    }
}

// MARK: - Supplement roster

@Suite("Tools: Supplement roster")
struct ToolsSupplementRosterTests {

    typealias Roster = SomaTools.SupplementRoster

    // MARK: The boundary

    @Test(arguments: ["adhd-med", "anxiety-med", "birth-control", "pain-med", "sleep-med", "weightloss-med"])
    func prescriptionIDsAreRefusedByCanTrack(id: String) {
        #expect(!Roster.canTrack(id), "\(id) is prescription medication and must never be trackable")
    }

    @Test func addRefusesAPrescriptionID() {
        #expect(Roster.adding("sleep-med", to: []) == [])
    }

    @Test func theAllowlistAndTheDenylistDoNotOverlap() {
        #expect(Roster.builtInIDs.isDisjoint(with: Roster.prescriptionIDs))
    }

    @Test(arguments: ["magnesium", "melatonin", "vit-d", "iron", "zinc", "calcium", "fish-oil", "creatine", "ashwagandha"])
    func knownSupplementsAreTrackable(id: String) {
        #expect(Roster.canTrack(id))
    }

    @Test func customIDsAreAlwaysTrackable() {
        #expect(Roster.canTrack("custom.abc12345"))
    }

    @Test func coffeeIsNotTrackable() {
        #expect(!Roster.canTrack("caffeine"))
        #expect(!Roster.canTrack("coffee"))
    }

    /// The retroactive half of the boundary: a stored roster written before an
    /// id became prescription must not keep serving it.
    @Test func aPersistedPrescriptionIDDoesNotSurviveARead() {
        #expect(Roster.sanitized(["sleep-med", "magnesium"]) == ["magnesium"])
    }

    // MARK: Add and remove

    @Test func addIsIdempotentAndOrderPreserving() {
        var ids: [String] = []
        ids = Roster.adding("magnesium", to: ids)
        ids = Roster.adding("vit-d", to: ids)
        ids = Roster.adding("magnesium", to: ids)
        #expect(ids == ["magnesium", "vit-d"])
    }

    @Test func removeDropsOnlyTheNamedID() {
        #expect(Roster.removing("magnesium", from: ["magnesium", "vit-d"]) == ["vit-d"])
    }

    // MARK: Migration from a legacy selection

    @Test func migrationMapsLegacyIDsOntoTheirJournalTwins() {
        let migrated = Roster.migrated(roster: nil, legacy: ["magnesium", "vitaminD", "omega3", "iron"])
        #expect(Set(migrated) == ["magnesium", "vit-d", "fish-oil", "iron"])
    }

    @Test func migrationDropsCoffee() {
        #expect(Roster.migrated(roster: nil, legacy: ["coffee", "magnesium"]) == ["magnesium"])
    }

    /// A stored empty roster is an answer: migration must not resurrect what
    /// the user deleted.
    @Test func migrationIsIdempotent() {
        #expect(Roster.migrated(roster: [], legacy: ["magnesium"]) == [])
    }

    // MARK: Resolution against the journal catalog

    @Test func resolveDropsAnIDTheCatalogNoLongerKnows() {
        let catalog = [Roster.Entry(id: "magnesium", title: "Magnesium", section: "Evening")]
        #expect(Roster.resolve(ids: ["magnesium", "gone-from-catalog"], catalog: catalog).map(\.id)
                == ["magnesium"])
    }

    @Test func resolvePreservesRosterOrderNotCatalogOrder() {
        let catalog = [Roster.Entry(id: "a", title: "A"), Roster.Entry(id: "b", title: "B")]
        #expect(Roster.resolve(ids: ["b", "a"], catalog: catalog).map(\.id) == ["b", "a"])
    }

    @Test func suggestionsSkipTrackedAndPrescriptionEntries() {
        let catalog = [Roster.Entry(id: "zinc", title: "Zinc"),
                       Roster.Entry(id: "sleep-med", title: "Sleep medication"),
                       Roster.Entry(id: "iron", title: "Iron")]
        #expect(Roster.suggestions(tracked: ["iron"], catalog: catalog).map(\.id) == ["zinc"])
    }
}

// MARK: - Strength load

@Suite("Tools: Strength load")
struct ToolsStrengthLoadTests {

    typealias Engine = SomaTools.StrengthLoad

    let day: TimeInterval = 86_400
    let end = Date(timeIntervalSince1970: 1_790_000_000)

    func set(_ reps: Int?, _ kg: Double?, done: Bool = true) -> Engine.LiftSet {
        Engine.LiftSet(reps: reps, weightKg: kg, completed: done)
    }

    func exercise(_ id: String, _ sets: [Engine.LiftSet]) -> Engine.Exercise {
        Engine.Exercise(exerciseID: id, name: id.capitalized, sets: sets)
    }

    func session(_ exercises: [Engine.Exercise], daysAgo: Double) -> Engine.Session {
        Engine.Session(date: end.addingTimeInterval(-daysAgo * day), exercises: exercises)
    }

    var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    // MARK: Volume load

    @Test func volumeLoadIsRepsTimesWeight() {
        #expect(Engine.volumeLoad(of: set(5, 100)) == 500)
    }

    @Test func incompleteSetHasNoVolume() {
        #expect(Engine.volumeLoad(of: set(5, 100, done: false)) == nil)
    }

    /// A bodyweight or timed set is real training, but not volume: counting it
    /// as zero would silently deflate the number.
    @Test func setWithoutWeightOrRepsIsExcluded() {
        #expect(Engine.volumeLoad(of: set(10, nil)) == nil)
        #expect(Engine.volumeLoad(of: set(nil, 60)) == nil)
        #expect(Engine.volumeLoad(of: set(0, 60)) == nil)
    }

    @Test func aSetLoggedWithoutACheckboxCountsAsDone() {
        #expect(Engine.volumeLoad(of: Engine.LiftSet(reps: 5, weightKg: 100)) == 500)
    }

    @Test func sessionVolumeSumsItsSets() {
        let s = session([exercise("squat", [set(5, 100), set(5, 100), set(3, 120)])], daysAgo: 0)
        #expect(Engine.volumeLoad(of: s) == 500 + 500 + 360)
    }

    // MARK: Epley

    @Test func epleyOneRepMax() throws {
        // 100 kg x 5 gives 100 * (1 + 5/30) = 116.67
        let e1rm = try #require(Engine.estimatedOneRepMax(of: set(5, 100)))
        #expect(abs(e1rm - 116.666) < 0.01)
    }

    @Test func singleRepIsItsOwnMax() throws {
        let e1rm = try #require(Engine.estimatedOneRepMax(of: set(1, 140)))
        let expected: Double = 140 * (1 + 1.0 / 30)
        #expect(abs(e1rm - expected) < 0.001)
    }

    /// Past ten reps Epley drifts high: the set is left out rather than
    /// quietly inflating a record.
    @Test func highRepSetIsExcludedFromOneRepMax() {
        #expect(Engine.estimatedOneRepMax(of: set(11, 60)) == nil)
        #expect(Engine.estimatedOneRepMax(of: set(10, 60)) != nil)
    }

    @Test func bestOneRepMaxPerExercise() throws {
        let s = session([exercise("squat", [set(5, 100), set(3, 120)]),
                         exercise("bench", [set(5, 80)])], daysAgo: 0)
        let best = Engine.bestOneRepMaxes(in: s)
        let squat = try #require(best["squat"])
        let bench = try #require(best["bench"])
        let squatExpected: Double = 120 * (1 + 3.0 / 30)
        let benchExpected: Double = 80 * (1 + 5.0 / 30)
        #expect(abs(squat - squatExpected) < 0.01)
        #expect(abs(bench - benchExpected) < 0.01)
    }

    // MARK: Weeks

    @Test func weeksBucketByTrailingSevenDays() {
        let sessions = [session([exercise("a", [set(10, 100)])], daysAgo: 1),
                        session([exercise("a", [set(10, 100)])], daysAgo: 9)]
        let weeks = Engine.weeks(from: sessions, endingOn: end, count: 3, calendar: calendar)
        #expect(weeks.map(\.volumeLoad) == [1000, 1000, 0])
    }

    /// A week with no session is information, not a gap to skip.
    @Test func emptyWeeksAreKeptAsZero() {
        let weeks = Engine.weeks(from: [], endingOn: end, count: 4, calendar: calendar)
        #expect(weeks.count == 4)
        #expect(weeks.allSatisfy { $0.volumeLoad == 0 && $0.sessionCount == 0 })
    }

    @Test func zeroWeekCountYieldsNothing() {
        #expect(Engine.weeks(from: [], endingOn: end, count: 0, calendar: calendar).isEmpty)
    }

    // MARK: Verdict

    func twoWeekReport(current: Double, previous: Double) -> Engine.Report {
        var sessions: [Engine.Session] = []
        if current > 0 { sessions.append(session([exercise("a", [set(1, current)])], daysAgo: 1)) }
        if previous > 0 { sessions.append(session([exercise("a", [set(1, previous)])], daysAgo: 9)) }
        return Engine.report(from: sessions, endingOn: end, calendar: calendar)
    }

    @Test func flatWeekReadsAsHolding() {
        #expect(twoWeekReport(current: 1020, previous: 1000).trend == .holding)
    }

    @Test func moderateRiseReadsAsBuilding() {
        #expect(twoWeekReport(current: 1080, previous: 1000).trend == .building)
    }

    @Test func steepRiseReadsAsClimbingFast() {
        #expect(twoWeekReport(current: 1300, previous: 1000).trend == .climbingFast)
    }

    @Test func dropReadsAsEasing() {
        #expect(twoWeekReport(current: 800, previous: 1000).trend == .easing)
    }

    /// Zero to something is not a percentage: no ratio from a standing start.
    @Test func startingFromZeroHasNoPercentage() {
        let r = twoWeekReport(current: 1000, previous: 0)
        #expect(r.weekOverWeekChange == nil)
        #expect(r.trend == .building)
    }

    @Test func noSessionsAtAllIsEmpty() {
        let r = Engine.report(from: [], endingOn: end, calendar: calendar)
        #expect(r.isEmpty)
        #expect(r.weekOverWeekChange == nil)
        #expect(r.trend == .holding)
    }

    @Test func weekOverWeekChangeIsSigned() throws {
        let up = try #require(twoWeekReport(current: 1200, previous: 1000).weekOverWeekChange)
        let down = try #require(twoWeekReport(current: 900, previous: 1000).weekOverWeekChange)
        #expect(abs(up - 0.2) < 0.0001)
        #expect(abs(down + 0.1) < 0.0001)
    }

    @Test func priorMeanSkipsRestWeeks() {
        let sessions = [session([exercise("a", [set(1, 1000)])], daysAgo: 1),
                        session([exercise("a", [set(1, 600)])], daysAgo: 9),
                        session([exercise("a", [set(1, 800)])], daysAgo: 23)]
        let r = Engine.report(from: sessions, endingOn: end, weekCount: 4, calendar: calendar)
        #expect(r.priorLoadedWeeksMean == 700)
    }

    // MARK: Progression

    @Test func progressionTracksBestAndLatest() throws {
        let sessions = [session([exercise("squat", [set(1, 150)])], daysAgo: 20),
                        session([exercise("squat", [set(1, 120)])], daysAgo: 2)]
        let progress = Engine.progression(from: sessions)
        #expect(progress.count == 1)
        let first = try #require(progress.first)
        let bestExpected: Double = 150 * (1 + 1.0 / 30)
        let latestExpected: Double = 120 * (1 + 1.0 / 30)
        #expect(abs(first.bestOneRepMax - bestExpected) < 0.01)
        #expect(abs(first.latestOneRepMax - latestExpected) < 0.01)
        #expect(first.appearances == 2)
        #expect(!first.isAtBest)
        #expect(first.name == "Squat")
    }

    @Test func progressionFlagsAPersonalBest() throws {
        let sessions = [session([exercise("squat", [set(1, 120)])], daysAgo: 20),
                        session([exercise("squat", [set(1, 150)])], daysAgo: 2)]
        let first = try #require(Engine.progression(from: sessions).first)
        #expect(first.isAtBest)
        #expect(first.isNewPersonalBest)
        #expect(Engine.personalBests(from: sessions).map(\.exerciseID) == ["squat"])
    }

    @Test func aFirstAppearanceIsNotARecord() throws {
        let sessions = [session([exercise("squat", [set(1, 150)])], daysAgo: 2)]
        let first = try #require(Engine.progression(from: sessions).first)
        #expect(first.isAtBest)
        #expect(!first.isNewPersonalBest)
    }

    @Test func progressionIsSortedStrongestFirst() {
        let sessions = [session([exercise("squat", [set(1, 150)]), exercise("bench", [set(1, 90)])], daysAgo: 1)]
        #expect(Engine.progression(from: sessions).map(\.exerciseID) == ["squat", "bench"])
    }

    @Test func exerciseWithNoEligibleSetDoesNotAppear() {
        let sessions = [session([exercise("plank", [set(nil, nil)])], daysAgo: 1)]
        #expect(Engine.progression(from: sessions).isEmpty)
    }

    @Test func signedPercentCarriesItsSign() {
        #expect(Engine.signedPercent(0.12) == "+12%")
        #expect(Engine.signedPercent(-0.08) == "-8%")
        #expect(Engine.signedPercent(0) == "0%")
    }
}
