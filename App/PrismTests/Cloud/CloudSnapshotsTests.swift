//
//  CloudSnapshotsTests.swift
//  PrismTests
//

import Foundation
import Testing
import SyncCore
@testable import Prism

/// The snapshots are the one place a local store becomes a server row. A field
/// mapped to the wrong key, a unit left off or a skipped answer sent as an
/// answer would not fail anything on the phone; it would sit wrong in the
/// account until someone exported it. So each store's mapping is read back
/// field by field.
@Suite("Cloud snapshots")
@MainActor
struct CloudSnapshotsTests {
    let user = "0f8fad5b-d9cb-469f-a165-70867728950e"

    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }()

    /// 3 October 2026 at the given time, Paris.
    func at(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 3, hour: hour, minute: minute))!
    }

    // MARK: Days

    @Test("A day key reads back as noon on that day, and a malformed key reads as nothing")
    func dayKeys() {
        #expect(CloudSnapshots.dayKey(at(0, 30), calendar: calendar) == "2026-10-03")
        #expect(CloudSnapshots.dayKey(at(23, 59), calendar: calendar) == "2026-10-03")
        #expect(CloudSnapshots.date(fromDayKey: "2026-10-03", calendar: calendar) == at(12))
        #expect(CloudSnapshots.date(fromDayKey: "2026-10", calendar: calendar) == nil)
        #expect(CloudSnapshots.date(fromDayKey: "yesterday", calendar: calendar) == nil)
    }

    @Test("Dates round to the millisecond and no further")
    func milliseconds() {
        let date = Date(timeIntervalSince1970: 1_790_000_000.123_456)
        #expect(abs(CloudSnapshots.ms(date).timeIntervalSince1970 - 1_790_000_000.123) < 1e-6)
        #expect(CloudSnapshots.ms(CloudSnapshots.ms(date)) == CloudSnapshots.ms(date))
    }

    // MARK: Soma asks

    @Test("Every answer kind keeps its value, and only scales and numbers carry one")
    func answerKinds() {
        let answers: [CheckInAnswer] = [.yes, .no, .scale(4), .number(7)]
        let kinds = answers.map { CloudSnapshots.answer($0).0 }
        let values = answers.map { CloudSnapshots.answer($0).1 }
        #expect(kinds == ["yes", "no", "scale", "number"])
        #expect(values == [nil, nil, 4, 7])
    }

    @Test("Answers and skips become one row per question, and an answered question is never also skipped")
    func checkIns() throws {
        var day = CheckInDayRecord()
        day.answers = ["sleep.rested": .scale(4), "journal.alcohol": .no]
        day.asked = ["sleep.rested": "How rested do you feel?"]
        day.skipped = ["journal.alcohol", "home.stress"]

        let records = CloudSnapshots.checkIns(["2026-10-03": day], userID: user)
        #expect(records.count == 3)

        let rested = try #require(records.first { $0.questionID == "sleep.rested" })
        #expect(rested.answerKind == "scale")
        #expect(rested.answerValue == 4)
        #expect(rested.questionText == "How rested do you feel?")
        #expect(!rested.skipped)

        let alcohol = try #require(records.first { $0.questionID == "journal.alcohol" })
        #expect(alcohol.answerKind == "no")
        #expect(!alcohol.skipped)

        let stress = try #require(records.first { $0.questionID == "home.stress" })
        #expect(stress.skipped)
        #expect(stress.answerKind == nil)
        #expect(stress.answerValue == nil)

        #expect(rested.id == CloudRecords.id(CloudRecords.checkInAnswers, userID: user, key: "2026-10-03|sleep.rested"))
    }

    // MARK: Mood and Mind

    @Test("Moods from Mind and Track land on one scale, each saying where it came from")
    func moods() throws {
        let mind = MindMoodEntry(date: at(9), kind: .daily, valence: 1.4, labels: ["calm"], associations: ["work"])
        let track = TrackMoodEntry(valence: 0, isDaily: false, words: ["tense"], contexts: ["family"], date: at(18))

        let records = CloudSnapshots.moods(mind: [mind], track: [track])
        #expect(records.count == 2)

        let fromMind = try #require(records.first { $0.origin == "mind" })
        #expect(fromMind.kind == "daily")
        #expect(fromMind.valence == 1)
        #expect(fromMind.labels == ["calm"])
        #expect(fromMind.associations == ["work"])
        #expect(fromMind.id == CloudRecords.id(mind.id))

        let fromTrack = try #require(records.first { $0.origin == "track" })
        #expect(fromTrack.kind == "momentary")
        #expect(fromTrack.valence == -1)
        #expect(fromTrack.labels == ["tense"])
        #expect(fromTrack.associations == ["family"])
    }

    @Test("A check-in keeps its three steps and its answer word")
    func mindCheckIns() {
        let entry = MindCheckIn(date: at(10), energy: 3, mood: nil, focus: 1, question: "Slept badly?", answer: .notSure)
        let record = CloudSnapshots.mindCheckIns([entry]).first
        #expect(record?.energy == 3)
        #expect(record?.mood == nil)
        #expect(record?.focus == 1)
        #expect(record?.question == "Slept badly?")
        #expect(record?.answer == "notSure")
        #expect(record?.loggedAt == CloudSnapshots.ms(at(10)))
    }

    // MARK: Track

    @Test("Each kind of Track entry becomes a row with its unit")
    func trackKinds() throws {
        let supplementID = UUID()
        var input = CloudSnapshots.TrackInput()
        input.drinks = [TrackDrinkEntry(drink: .coffee, ml: 250, caffeineMg: 95, date: at(8))]
        input.meals = [TrackMealEntry(name: "Rice bowl", meal: .lunch, protein: 30, carbs: 80, fat: 15, portions: 1.5, date: at(12))]
        input.supplements = [TrackSupplement(id: supplementID, name: "Magnesium", amount: 300, unit: .milligrams, minute: 21 * 60, startedOn: at(7))]
        input.doses = [TrackDoseEntry(supplementID: supplementID, name: "Magnesium", amount: 300, unit: .milligrams, date: at(21))]
        input.fasts = [TrackFast(start: at(0), objectiveHours: 16, end: at(16))]
        input.practices = [TrackPracticeEntry(practice: .sauna, minutes: 20, date: at(19))]
        input.measures = [
            TrackMeasureEntry(measure: .weight, value: 71.4, date: at(7)),
            TrackMeasureEntry(measure: .waist, value: 82, date: at(7)),
        ]

        let records = CloudSnapshots.track(input, userID: user, calendar: calendar)
        func record(_ kind: String) throws -> TrackLogRecord { try #require(records.first { $0.kind == kind }) }

        let drink = try record("drink")
        #expect(drink.value == 250)
        #expect(drink.unit == "ml")
        #expect(drink.label == "coffee")
        #expect(drink.detail["caffeine_mg"] == .number(95))

        let meal = try record("meal")
        #expect(meal.unit == "kcal")
        let kcal: Double = (30 * 4 + 80 * 4 + 15 * 9) * 1.5
        #expect(meal.value == kcal)
        #expect(meal.detail["meal"] == .text("lunch"))
        #expect(meal.detail["portions"] == .number(1.5))

        let supplement = try record("supplement")
        #expect(supplement.unit == TrackDoseUnit.milligrams.rawValue)
        #expect(supplement.detail["minute"] == .number(1260))
        #expect(supplement.detail["active"] == .flag(true))

        let dose = try record("dose")
        #expect(dose.detail["supplement_id"] == .text(supplementID.uuidString.lowercased()))

        let fast = try record("fast")
        #expect(fast.value == 16)
        #expect(fast.unit == "h")
        #expect(fast.endedAt == CloudSnapshots.ms(at(16)))

        let practice = try record("practice")
        #expect(practice.unit == "min")
        #expect(practice.label == TrackPractice.sauna.rawValue)

        let measures = records.filter { $0.kind == "measure" }
        #expect(measures.first { $0.label == TrackMeasure.weight.rawValue }?.unit == "kg")
        #expect(measures.first { $0.label == TrackMeasure.waist.rawValue }?.unit == "cm")
    }

    @Test("A dose taken on its own carries no supplement, and an open fast no end")
    func trackOpenEnds() {
        var input = CloudSnapshots.TrackInput()
        input.doses = [TrackDoseEntry(name: "Ibuprofen", amount: 400, unit: .milligrams, date: at(14))]
        input.fasts = [TrackFast(start: at(20), objectiveHours: nil)]
        let records = CloudSnapshots.track(input, userID: user, calendar: calendar)
        #expect(records.first { $0.kind == "dose" }?.detail.isEmpty == true)
        #expect(records.first { $0.kind == "fast" }?.endedAt == nil)
        #expect(records.first { $0.kind == "fast" }?.value == nil)
    }

    @Test("A wake rating is one row per day at noon, and a day that does not parse is dropped")
    func wakeRatings() {
        var input = CloudSnapshots.TrackInput()
        input.wakeRatings = ["2026-10-03": 7, "not a day": 4]
        let records = CloudSnapshots.track(input, userID: user, calendar: calendar)
        #expect(records.count == 1)
        #expect(records.first?.value == 7)
        #expect(records.first?.unit == "of 10")
        #expect(records.first?.loggedAt == at(12))
        #expect(records.first?.detail["day"] == .text("2026-10-03"))
        #expect(records.first?.id == CloudRecords.id(CloudRecords.trackLogs, userID: user, key: "wake_rating|2026-10-03"))
    }

    // MARK: Lab, inbox, providers

    @Test("A blood panel is filed under the day it was drawn, each marker in the unit it was entered in")
    func labs() {
        let panel = BloodPanel(sampledAt: at(8), createdAt: at(18), markers: [
            BloodMarkerValue(key: "ferritin", value: 80, enteredUnit: "ng/mL", source: .extracted),
        ])
        let record = CloudSnapshots.labs([panel], calendar: calendar).first
        #expect(record?.collectedOn == "2026-10-03")
        #expect(record?.markers == [LabResultRecord.Marker(marker: "ferritin", value: 80, unit: "ng/mL")])
        #expect(record?.id == CloudRecords.id(panel.id))
    }

    @Test("An inbox item keeps its read state and the link it opens")
    func inbox() {
        let item = InboxItem(id: "bedtime-2026-10-03", kind: .bedtime, title: "Wind down", body: "Bed in 45 min.",
                             date: at(22, 15), isRead: true, link: .sleep)
        let record = CloudSnapshots.inbox([item], userID: user).first
        #expect(record?.kind == "bedtime")
        #expect(record?.isRead == true)
        #expect(record?.deepLink == SomaDeepLink.sleep.url.absoluteString)
        #expect(record?.deliveredAt == CloudSnapshots.ms(at(22, 15)))
    }

    @Test("Only settled provider states are sent: connected with its last sync, or failed")
    func providers() {
        let states: [String: ProviderConnectionState] = [
            "oura": .connected(account: "ada@example.com", lastSync: at(6)),
            "whoop": .failed("expired"),
            "withings": .connecting,
            "garmin": .notConnected,
        ]
        let records = CloudSnapshots.providers(states, userID: user)
        #expect(Set(records.map(\.provider)) == ["oura", "whoop"])

        let oura = records.first { $0.provider == "oura" }
        #expect(oura?.status == "connected")
        #expect(oura?.accountLabel == "ada@example.com")
        #expect(oura?.lastSyncAt == CloudSnapshots.ms(at(6)))

        let whoop = records.first { $0.provider == "whoop" }
        #expect(whoop?.status == "failed")
        #expect(whoop?.accountLabel == nil)
    }

    @Test("A direct connection carries the moment it was made, one through Open Health Sync none")
    func providerConnectedAt() {
        let states: [String: ProviderConnectionState] = [
            "oura": .connected(account: "ada@example.com", lastSync: at(6)),
            "whoop": .connected(account: nil, lastSync: at(7)),
        ]
        let records = CloudSnapshots.providers(states, connectedAt: ["oura": at(5)], userID: user)
        #expect(records.first { $0.provider == "oura" }?.connectedAt == CloudSnapshots.ms(at(5)))
        #expect(records.first { $0.provider == "whoop" }?.connectedAt == nil)
    }
}
