//
//  MedicationTests.swift
//  PrismTests
//

import Foundation
import Testing
@testable import Prism

/// Medications and supplements: when the next dose falls on its declared
/// rhythm, the reminder for each dose at the local wall clock time, the
/// notes where a supplement can skew a blood marker or meet a medication,
/// and the one list Apple Health and the Track plan share.
@Suite("Track: Medications")
@MainActor
struct MedicationTests {

    let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    func calendar(_ zone: String) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: zone)!
        return c
    }

    func date(_ y: Int, _ m: Int, _ d: Int, hour: Int = 0, minute: Int = 0, in calendar: Calendar? = nil) -> Date {
        (calendar ?? utc).date(from: DateComponents(year: y, month: m, day: d, hour: hour, minute: minute))!
    }

    func supplement(_ name: String, minute: Int = 8 * 60, cadence: TrackCadence = .daily,
                    startedOn: Date, reminds: Bool = true) -> TrackSupplement {
        var item = TrackSupplement(name: name, amount: 5, unit: .milligrams, minute: minute, cadence: cadence, startedOn: startedOn)
        item.reminds = reminds
        return item
    }

    // MARK: Schedule

    @Test func everyOtherDaySchedule() throws {
        let start = date(2026, 10, 1, hour: 7)
        let item = supplement("Iron", cadence: try #require(.everyNDays(2)), startedOn: start)
        // Before the first dose on the first day: that dose.
        #expect(MedicationSchedule.next(for: item, after: date(2026, 10, 1, hour: 7), calendar: utc) == date(2026, 10, 1, hour: 8))
        // Once it has passed, the day after next.
        #expect(MedicationSchedule.next(for: item, after: date(2026, 10, 1, hour: 9), calendar: utc) == date(2026, 10, 3, hour: 8))
        // The day off in between has no dose.
        #expect(MedicationSchedule.next(for: item, after: date(2026, 10, 2, hour: 7), calendar: utc) == date(2026, 10, 3, hour: 8))
        // Nothing before the plan starts.
        #expect(MedicationSchedule.next(for: item, after: date(2026, 9, 20), calendar: utc) == date(2026, 10, 1, hour: 8))
    }

    @Test func cycleOnOffSkipsOffWeeks() throws {
        // Three weeks on, one week off, from Monday 5 October.
        let start = date(2026, 10, 5)
        let item = supplement("Rhodiola", cadence: try #require(.cycleOnOff(on: 21, off: 7)), startedOn: start)
        // The last day on is the 25th; the 26th to 1 November are off.
        #expect(MedicationSchedule.next(for: item, after: date(2026, 10, 25, hour: 7), calendar: utc) == date(2026, 10, 25, hour: 8))
        #expect(MedicationSchedule.next(for: item, after: date(2026, 10, 25, hour: 9), calendar: utc) == date(2026, 11, 2, hour: 8))
        let week = MedicationSchedule.upcoming(for: item, after: date(2026, 10, 25, hour: 9), days: 10, calendar: utc)
        #expect(week.first == date(2026, 11, 2, hour: 8))
        #expect(week.allSatisfy { $0 >= date(2026, 11, 2) })
    }

    @Test func pausedSupplementHasNoNextDose() {
        var item = supplement("Zinc", startedOn: date(2026, 10, 1))
        item.isActive = false
        #expect(MedicationSchedule.next(for: item, after: date(2026, 10, 10), calendar: utc) == nil)
    }

    // MARK: Reminders

    /// A daily 09:00 dose in New York stays at 09:00 local the morning the
    /// clocks go back, and the trigger is a wall clock time, so in Paris it
    /// fires at 09:00 in Paris.
    @Test func reminderLocalTimeAcrossDST() throws {
        let newYork = calendar("America/New_York")
        let now = date(2026, 10, 31, hour: 12, in: newYork)
        let item = supplement("Magnesium", minute: 9 * 60, startedOn: date(2026, 10, 1, in: newYork))
        let planned = MedicationReminders.reminders(for: [item], doses: [], schedule: NotificationSchedule(), now: now, calendar: newYork)
        #expect(!planned.isEmpty)
        #expect(planned.allSatisfy { $0.kind == .dose })
        #expect(planned.allSatisfy { SomaNotificationKind.kind(forIdentifier: $0.id) == .dose })
        #expect(planned.allSatisfy { MedicationReminders.supplementID(fromIdentifier: $0.id) == item.id })

        let fires = planned.compactMap { NotificationPlanner.nextFire($0.trigger, after: now, calendar: newYork) }.sorted()
        // Sunday 1 November, after the clocks went back: 09:00 is 14:00 UTC.
        #expect(fires.first == date(2026, 11, 1, hour: 14))
        for fire in fires {
            #expect(newYork.component(.hour, from: fire) == 9)
            #expect(newYork.component(.minute, from: fire) == 0)
        }

        let paris = calendar("Europe/Paris")
        let inParis = try #require(NotificationPlanner.nextFire(planned[0].trigger, after: now, calendar: paris))
        #expect(paris.component(.hour, from: inParis) == 9)
    }

    @Test func remindersOnlyForWhatWasAskedAndStillAhead() {
        let now = date(2026, 10, 10, hour: 7)
        let asked = supplement("Vitamin D", startedOn: date(2026, 10, 1))
        let quiet = supplement("Omega 3", startedOn: date(2026, 10, 1), reminds: false)
        let planned = MedicationReminders.reminders(for: [asked, quiet], doses: [], schedule: NotificationSchedule(), now: now, calendar: utc)
        #expect(planned.allSatisfy { MedicationReminders.supplementID(fromIdentifier: $0.id) == asked.id })
        #expect(planned.count == MedicationReminders.horizonDays)

        // Taken already this morning: today's reminder goes, tomorrow's stays.
        let taken = TrackDoseEntry(supplementID: asked.id, name: asked.name, amount: 5, unit: .milligrams, date: date(2026, 10, 10, hour: 6))
        let after = MedicationReminders.reminders(for: [asked], doses: [taken], schedule: NotificationSchedule(), now: now, calendar: utc)
        let first = after.compactMap { NotificationPlanner.nextFire($0.trigger, after: now, calendar: utc) }.min()
        #expect(first == date(2026, 10, 11, hour: 8))

        var silent = NotificationSchedule()
        silent.isEnabled = false
        #expect(MedicationReminders.reminders(for: [asked], doses: [], schedule: silent, now: now, calendar: utc).isEmpty)
    }

    @Test func takenFromNotificationLogsDose() throws {
        let store = TrackLogStore(url: nil, calendar: utc)
        let added = try #require(store.addSupplement(name: "Creatine", amount: 3, unit: .grams, minute: 8 * 60, startedOn: date(2026, 10, 1)))
        store.setReminds(true, supplement: added.id)
        let now = date(2026, 10, 10, hour: 8, minute: 2)
        let planned = MedicationReminders.reminders(for: store.supplements, doses: store.doses, schedule: NotificationSchedule(), now: date(2026, 10, 10, hour: 7), calendar: utc)
        let id = try #require(planned.first?.id)

        let entry = try #require(MedicationReminders.logTaken(identifier: id, in: store, at: now))
        #expect(entry.supplementID == added.id)
        #expect(entry.amount == 3)
        #expect(entry.unit == .grams)
        #expect(store.doses(on: now).count == 1)
        // A second tap the same day logs nothing more.
        #expect(MedicationReminders.logTaken(identifier: id, in: store, at: now.addingTimeInterval(60)) == nil)
        #expect(store.doses(on: now).count == 1)
        // Something that is not a dose reminder logs nothing.
        #expect(MedicationReminders.logTaken(identifier: "soma.reminder.bedtime", in: store, at: now) == nil)
    }

    // MARK: Interactions

    @Test func biotinFlagsTSH() throws {
        let biotin = supplement("Biotin", startedOn: date(2026, 1, 1))
        let tsh = try #require(BloodMarkerCatalog.marker(id: "tsh"))
        let ldl = try #require(BloodMarkerCatalog.marker(id: "ldl"))
        let notes = MedicationInteractions.notes(for: [biotin], markers: [tsh, ldl])
        #expect(notes.map(\.markerID) == ["tsh"])
        #expect(notes.allSatisfy { !$0.source.isEmpty })
        // The same supplement under another name on the label.
        let b7 = supplement("Vitamin B7", startedOn: date(2026, 1, 1))
        #expect(MedicationInteractions.notes(for: [b7], markers: [tsh]).count == 1)
        // No biotin, or no TSH on the panel: nothing to say.
        #expect(MedicationInteractions.notes(for: [supplement("Zinc", startedOn: date(2026, 1, 1))], markers: [tsh]).isEmpty)
        #expect(MedicationInteractions.notes(for: [biotin], markers: [ldl]).isEmpty)
        // Stopped: it no longer touches the next panel.
        var stopped = biotin
        stopped.isActive = false
        #expect(MedicationInteractions.notes(for: [stopped], markers: [tsh]).isEmpty)
    }

    @Test func creatineFlagsCreatinine() throws {
        let creatine = supplement("Creatine monohydrate", startedOn: date(2026, 1, 1))
        let creatinine = try #require(BloodMarkerCatalog.marker(id: "creatinine"))
        let egfr = try #require(BloodMarkerCatalog.marker(id: "egfr"))
        let notes = MedicationInteractions.notes(for: [creatine], markers: [creatinine, egfr])
        #expect(Set(notes.compactMap(\.markerID)) == ["creatinine", "egfr"])
    }

    @Test func medicationPairsNeedTheMedication() {
        let vitaminK = supplement("Vitamin K2", startedOn: date(2026, 1, 1))
        let wort = supplement("St. John's Wort", startedOn: date(2026, 1, 1))
        #expect(MedicationInteractions.notes(for: [vitaminK, wort], markers: []).isEmpty)
        let notes = MedicationInteractions.notes(for: [vitaminK, wort], markers: [], medications: ["Warfarin 5 mg", "Sertraline"])
        #expect(notes.count == 2)
        #expect(notes.allSatisfy { $0.markerID == nil && !$0.source.isEmpty })
    }

    // MARK: Apple Health

    @Test func healthMedicationsMerge() {
        let plan = [supplement("Magnesium", startedOn: date(2026, 1, 1)), supplement("Créatine", startedOn: date(2026, 1, 1))]
        let health = [
            HealthMedication(id: "a", name: "magnesium", isArchived: false, hasSchedule: true),
            HealthMedication(id: "b", name: "Levothyroxine", isArchived: false, hasSchedule: true),
            HealthMedication(id: "c", name: "Amoxicillin", isArchived: true, hasSchedule: false),
        ]
        let merged = MedicationList.merged(supplements: plan, health: health)
        #expect(merged.map(\.name) == ["Créatine", "Levothyroxine", "Magnesium"])
        let magnesium = merged.first { $0.name == "Magnesium" }
        #expect(magnesium?.supplementID == plan[0].id)
        #expect(magnesium?.healthID == "a")
        #expect(merged.first { $0.name == "Levothyroxine" }?.supplementID == nil)
        // An archived medication is one the person stopped: it stays out.
        #expect(!merged.contains { $0.name == "Amoxicillin" })
    }
}
