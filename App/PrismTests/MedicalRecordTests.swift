//
//  MedicalRecordTests.swift
//  PrismTests
//

import Foundation
import Testing
@testable import Prism

/// The structured medical record: the medical card's free text moved into
/// lists once and kept as a note, family history that moves a screening
/// earlier, appointment reminders the evening before and an hour before, and
/// a record that comes back from disk as it was written.
@Suite("Medical record")
@MainActor
struct MedicalRecordTests {

    func calendar(_ zone: String) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: zone)!
        return c
    }

    var utc: Calendar { calendar("UTC") }

    func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0, minute: Int = 0, in calendar: Calendar? = nil) -> Date {
        (calendar ?? utc).date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    // MARK: Migration

    /// "Penicillin, peanuts" on the card becomes two allergies, and the text
    /// it came from stays in the record as a note. Running it twice changes
    /// nothing.
    @Test func migratesFreeText() {
        var card = HomeMedicalCard()
        card.allergies = "Penicillin, peanuts"
        card.conditions = "Asthma; migraine"
        card.medications = "Vitamin D, 1,000 IU a day"

        var record = MedicalRecord()
        record.migrate(from: card)
        #expect(record.allergies.map(\.substance) == ["Penicillin", "peanuts"])
        #expect(record.conditions.map(\.name) == ["Asthma", "migraine"])
        #expect(record.migratedFromCard)
        let note = record.cardNote ?? ""
        #expect(note.contains("Penicillin, peanuts"))
        #expect(note.contains("Asthma; migraine"))
        #expect(note.contains("Vitamin D, 1,000 IU a day"))

        record.migrate(from: card)
        #expect(record.allergies.count == 2)
        #expect(record.conditions.count == 2)
    }

    /// "None known" is an answer, not a condition.
    @Test func migrationSkipsNone() {
        var card = HomeMedicalCard()
        card.conditions = "None known"
        var record = MedicalRecord()
        record.migrate(from: card)
        #expect(record.conditions.isEmpty)
        #expect(record.cardNote?.contains("None known") == true)
    }

    /// An empty card migrates to nothing, and is still marked done so the
    /// card stops asking for free text.
    @Test func emptyCardMigratesToNothing() {
        var record = MedicalRecord()
        record.migrate(from: HomeMedicalCard())
        #expect(record.isEmpty)
        #expect(record.cardNote == nil)
        #expect(record.migratedFromCard)
    }

    // MARK: Family history

    /// A father with colorectal cancer at 52 sets the family colorectal flag,
    /// and the screening schedule then starts colorectal screening at 40
    /// instead of 45 (USPSTF 2021; the catalog's family modifier).
    @Test func familyColonCancerFlag() {
        var record = MedicalRecord()
        record.familyHistory = [FamilyHistoryEntry(relative: .father, condition: .colorectalCancer, ageAtOnset: 52)]
        #expect(record.screeningRiskFlags == [.familyColorectal])
        #expect(record.screeningRisks.first?.earliestDiagnosisAge == 52)

        var profile = SomaProfile()
        profile.birthday = date(1985, 3, 10)
        profile.sex = .male
        let now = date(2026, 10, 24, hour: 12)
        let plain = SomaTools.ScreeningLedger()
        let before = SomaTools.ScreeningSchedule.due(for: profile, ledger: plain, now: now, calendar: utc)
            .first { $0.item.id == "colorectal" }
        #expect(before?.state == .later)

        let merged = plain.withFamilyHistory(record.screeningRisks)
        let after = SomaTools.ScreeningSchedule.due(for: profile, ledger: merged, now: now, calendar: utc)
            .first { $0.item.id == "colorectal" }
        #expect(after?.state == .overdue)
        #expect(after?.dueDate == date(2025, 3, 10))
    }

    /// Only first degree relatives count, and an early heart attack only
    /// before 55, as the flag asks.
    @Test func familyFlagsNeedFirstDegree() {
        var record = MedicalRecord()
        record.familyHistory = [
            FamilyHistoryEntry(relative: .grandparent, condition: .breastCancer, ageAtOnset: 60),
            FamilyHistoryEntry(relative: .mother, condition: .heartAttackOrStroke, ageAtOnset: 70),
            FamilyHistoryEntry(relative: .brother, condition: .heartAttackOrStroke, ageAtOnset: 50),
            FamilyHistoryEntry(relative: .sister, condition: .other, ageAtOnset: nil, note: "Lupus"),
        ]
        #expect(record.screeningRiskFlags == [.familyEarlyCardiac])
    }

    /// The youngest relative's diagnosis wins, and a yes in the record beats
    /// an earlier no on the ledger: risk only pulls a screening forward.
    @Test func familyHistoryMergesWithLedger() {
        var record = MedicalRecord()
        record.familyHistory = [
            FamilyHistoryEntry(relative: .father, condition: .colorectalCancer, ageAtOnset: 52),
            FamilyHistoryEntry(relative: .sister, condition: .colorectalCancer, ageAtOnset: 44),
        ]
        var ledger = SomaTools.ScreeningLedger()
        ledger.answer(flag: .familyColorectal, isPresent: false)
        ledger.answer(flag: .tobaccoEverSmoker, isPresent: true)
        let merged = ledger.withFamilyHistory(record.screeningRisks)
        #expect(merged.answer(for: .familyColorectal)?.isPresent == true)
        #expect(merged.answer(for: .familyColorectal)?.earliestDiagnosisAge == 44)
        #expect(merged.answer(for: .tobaccoEverSmoker)?.isPresent == true)
        #expect(merged.records == ledger.records)
    }

    // MARK: Appointments

    /// Upcoming appointments, soonest first, past ones left out.
    @Test func upcomingSoonestFirst() {
        let now = date(2026, 10, 24, hour: 12)
        var record = MedicalRecord()
        record.appointments = [
            Appointment(date: date(2026, 12, 1, hour: 9), with: "Dr Lee", reason: .checkup),
            Appointment(date: date(2026, 10, 1, hour: 9), with: "Dr Old", reason: .checkup),
            Appointment(date: date(2026, 11, 3, hour: 14), with: "Dr Park", reason: .followUp),
        ]
        #expect(record.upcoming(now: now).map(\.with) == ["Dr Park", "Dr Lee"])
    }

    /// The next dental visit is an appointment for the teeth, or one with a
    /// dentist on the care team.
    @Test func nextDentalVisit() {
        let now = date(2026, 10, 24, hour: 12)
        let dentist = CareTeamMember(name: "Dr Smile", role: .dentist)
        var record = MedicalRecord()
        record.careTeam = [dentist]
        record.appointments = [
            Appointment(date: date(2026, 11, 2, hour: 9), with: "Dr Lee", reason: .checkup),
            Appointment(date: date(2027, 1, 5, hour: 9), with: "Dr Smile", reason: .checkup, careTeamID: dentist.id),
            Appointment(date: date(2026, 12, 5, hour: 9), with: "Clinic", reason: .dental),
        ]
        #expect(record.nextDentalVisit(now: now) == date(2026, 12, 5, hour: 9))
        record.appointments.removeLast()
        #expect(record.nextDentalVisit(now: now) == date(2027, 1, 5, hour: 9))
        #expect(MedicalRecord().nextDentalVisit(now: now) == nil)
    }

    /// The evening before at 18:00 and an hour before, both wall clock
    /// times, and nothing for an appointment already past.
    @Test func appointmentReminders() {
        let newYork = calendar("America/New_York")
        let now = date(2026, 10, 24, hour: 12, in: newYork)
        let soon = Appointment(date: date(2026, 11, 2, hour: 10, minute: 30, in: newYork), with: "Dr Lee", reason: .checkup)
        let past = Appointment(date: date(2026, 10, 20, hour: 10, in: newYork), with: "Dr Old", reason: .checkup)
        let planned = AppointmentReminderRules.reminders(for: [soon, past], schedule: NotificationSchedule(),
                                                         prefs: NotificationPreferences(), now: now, calendar: newYork)
        #expect(planned.count == 2)
        #expect(planned.allSatisfy { $0.kind == .appointment })
        #expect(planned.allSatisfy { SomaNotificationKind.kind(forIdentifier: $0.id) == .appointment })
        #expect(planned.allSatisfy { $0.title.contains("Dr Lee") })
        // A tap opens the medical record, not the inbox.
        #expect(planned.allSatisfy { $0.link == .medicalRecord })

        let fires = planned.compactMap { NotificationPlanner.nextFire($0.trigger, after: now, calendar: newYork) }.sorted()
        #expect(fires == [date(2026, 11, 1, hour: 18, in: newYork), date(2026, 11, 2, hour: 9, minute: 30, in: newYork)])
        for trigger in planned.map(\.trigger) {
            guard case .wallClock = trigger else { Issue.record("Expected a wall clock trigger"); continue }
        }
        // The body says the time on a 24 hour clock.
        #expect(planned.contains { $0.body.contains("10:30") })

        var off = NotificationSchedule()
        off.isEnabled = false
        #expect(AppointmentReminderRules.reminders(for: [soon], schedule: off, prefs: NotificationPreferences(),
                                                   now: now, calendar: newYork).isEmpty)

        var silent = soon
        silent.remind = false
        #expect(AppointmentReminderRules.reminders(for: [silent], schedule: NotificationSchedule(),
                                                   prefs: NotificationPreferences(), now: now, calendar: newYork).isEmpty)
    }

    /// Booked for tomorrow at 08:00 at 19:00 tonight: the evening reminder has
    /// passed, the hour before still comes.
    @Test func lateBookingKeepsTheHourBefore() {
        let paris = calendar("Europe/Paris")
        let now = date(2026, 10, 24, hour: 19, in: paris)
        let tomorrow = Appointment(date: date(2026, 10, 25, hour: 8, in: paris), with: "Dr Martin", reason: .checkup)
        let planned = AppointmentReminderRules.reminders(for: [tomorrow], schedule: NotificationSchedule(),
                                                         prefs: NotificationPreferences(), now: now, calendar: paris)
        #expect(planned.count == 1)
        #expect(planned.first?.id.hasSuffix(".hour") == true)
    }

    // MARK: Store

    /// Written to disk and read back, every list comes back as it was.
    @Test func roundTrip() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "medical-record-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let dentist = CareTeamMember(name: "Dr Smile", role: .dentist, phone: "+1 650 555 0100", email: "smile@example.com")
        let store = MedicalRecordStore(url: url, card: nil)
        store.update {
            $0.conditions = [MedicalCondition(name: "Asthma", since: date(2001, 5, 1))]
            $0.allergies = [Allergy(substance: "Penicillin", reaction: "Hives", severity: .severe)]
            $0.vaccinations = [Vaccination(name: "Tetanus", date: date(2024, 2, 1), dose: "Booster")]
            $0.familyHistory = [FamilyHistoryEntry(relative: .mother, condition: .breastCancer, ageAtOnset: 48)]
            $0.careTeam = [dentist]
            $0.appointments = [Appointment(date: date(2026, 12, 1, hour: 9), with: "Dr Smile", reason: .dental,
                                           notes: "Cleaning", careTeamID: dentist.id)]
        }
        let again = MedicalRecordStore(url: url, card: nil)
        #expect(again.record == store.record)
        #expect(again.record.careTeam.first?.email == "smile@example.com")
    }

    /// A file written by an older build, with lists it did not know missing,
    /// still decodes, and the card is not migrated a second time.
    @Test func decodesWithMissingFields() throws {
        let json = #"{"allergies":[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","substance":"Latex"}],"migratedFromCard":true}"#
        let record = try JSONDecoder.lab.decode(MedicalRecord.self, from: Data(json.utf8))
        #expect(record.allergies.map(\.substance) == ["Latex"])
        #expect(record.conditions.isEmpty)
        #expect(record.appointments.isEmpty)

        var card = HomeMedicalCard()
        card.allergies = "Peanuts"
        var again = record
        again.migrate(from: card)
        #expect(again.allergies.map(\.substance) == ["Latex"])
    }

    /// The store migrates the card it is handed, once.
    @Test func storeMigratesOnFirstOpen() {
        var card = HomeMedicalCard()
        card.allergies = "Penicillin, peanuts"
        let store = MedicalRecordStore(url: nil, card: card)
        #expect(store.allergies.count == 2)
    }
}
