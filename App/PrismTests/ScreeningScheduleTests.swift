//
//  ScreeningScheduleTests.swift
//  PrismTests
//

import Foundation
import Testing
@testable import Prism

/// The screening calendar: a due date per item from age, sex, risk answers
/// and the last time it was done, and the morning reminders built on it.
@Suite("Tools: Screening schedule")
struct ScreeningScheduleTests {

    typealias Schedule = SomaTools.ScreeningSchedule
    typealias Due = SomaTools.ScreeningDue
    typealias Ledger = SomaTools.ScreeningLedger

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

    func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0, in calendar: Calendar? = nil) -> Date {
        (calendar ?? utc).date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    var now: Date { date(2026, 10, 24, hour: 12) }

    func profile(born: Date?, sex: BiologicalSex?) -> SomaProfile {
        var profile = SomaProfile()
        profile.birthday = born
        profile.sex = sex
        return profile
    }

    func due(_ id: String, born: Date?, sex: BiologicalSex? = .male, ledger: Ledger = Ledger()) -> Due? {
        Schedule.due(for: profile(born: born, sex: sex), ledger: ledger, now: now, calendar: utc)
            .first { $0.item.id == id }
    }

    // MARK: Start ages and cadences

    /// USPSTF 2021: colorectal screening from 45.
    @Test func colorectalStartsAt45() {
        let at44 = due("colorectal", born: date(1982, 3, 10))
        #expect(at44?.state == .later)
        #expect(at44?.dueDate == date(2027, 3, 10))

        let at45 = due("colorectal", born: date(1981, 3, 10))
        #expect(at45?.state == .overdue)
        #expect(at45?.dueDate == date(2026, 3, 10))
    }

    /// USPSTF 2024: mammography every two years from 40 to 74, women only.
    @Test func mammographyBiennial40to74() {
        let born = date(1976, 5, 1)
        var ledger = Ledger()
        ledger.log(itemID: "mammography", performedOn: date(2025, 3, 1))
        let recent = due("mammography", born: born, sex: .female, ledger: ledger)
        #expect(recent?.state == .done)
        #expect(recent?.dueDate == date(2027, 3, 1))
        #expect(recent?.lastDone == date(2025, 3, 1))

        var old = Ledger()
        old.log(itemID: "mammography", performedOn: date(2024, 9, 1))
        let late = due("mammography", born: born, sex: .female, ledger: old)
        #expect(late?.state == .overdue)
        #expect(late?.dueDate == date(2026, 9, 1))

        #expect(due("mammography", born: born, sex: .male) == nil)
        #expect(due("mammography", born: date(1951, 5, 1), sex: .female) == nil)

        let at39 = due("mammography", born: date(1987, 3, 2), sex: .female)
        #expect(at39?.state == .later)
        #expect(at39?.dueDate == date(2027, 3, 2))
    }

    /// USPSTF 2018: cytology every three years from 21 to 29, HPV testing
    /// every five years from 30 to 65.
    @Test func cervicalByAge() {
        var ledger = Ledger()
        ledger.log(itemID: "cervical", performedOn: date(2025, 1, 15))

        let at25 = due("cervical", born: date(2001, 6, 1), sex: .female, ledger: ledger)
        #expect(at25?.dueDate == date(2028, 1, 15))

        let at40 = due("cervical", born: date(1986, 6, 1), sex: .female, ledger: ledger)
        #expect(at40?.dueDate == date(2030, 1, 15))

        // Done at 29 on cytology: three years, even though 30 has passed since.
        var young = Ledger()
        young.log(itemID: "cervical", performedOn: date(2026, 1, 15))
        let doneAt29 = due("cervical", born: date(1996, 6, 1), sex: .female, ledger: young)
        #expect(doneAt29?.dueDate == date(2029, 1, 15))

        #expect(due("cervical", born: date(1956, 6, 1), sex: .female) == nil)
        let at20 = due("cervical", born: date(2006, 6, 1), sex: .female)
        #expect(at20?.state == .later)
        #expect(at20?.dueDate == date(2027, 6, 1))
    }

    /// The lung CT is gated on the tobacco answer: never due without it.
    @Test func lungCTNeedsSmokingHistory() {
        let born = date(1966, 2, 1)
        #expect(due("lungCT", born: born) == nil)

        var never = Ledger()
        never.answer(flag: .tobaccoEverSmoker, isPresent: false)
        #expect(due("lungCT", born: born, ledger: never) == nil)

        var smoker = Ledger()
        smoker.answer(flag: .tobaccoEverSmoker, isPresent: true)
        #expect(due("lungCT", born: born, ledger: smoker)?.state == .overdue)
    }

    @Test func doneResetsInterval() {
        let born = date(1976, 2, 1)
        #expect(due("bloodPressure", born: born)?.state == .overdue)

        var ledger = Ledger()
        ledger.log(itemID: "bloodPressure", performedOn: date(2026, 10, 1))
        ledger.log(itemID: "colorectal", performedOn: date(2026, 10, 1))
        let pressure = due("bloodPressure", born: born, ledger: ledger)
        #expect(pressure?.state == .done)
        #expect(pressure?.dueDate == date(2027, 10, 1))
        #expect(due("colorectal", born: born, ledger: ledger)?.dueDate == date(2036, 10, 1))

        // Once in a lifetime: done, and nothing comes back.
        ledger.log(itemID: "hepatitisC", performedOn: date(2020, 1, 1))
        let hepatitis = due("hepatitisC", born: born, ledger: ledger)
        #expect(hepatitis?.state == .done)
        #expect(hepatitis?.dueDate == nil)
    }

    @Test func familyHistoryMovesEarlier() {
        let born = date(1988, 1, 1)
        let general = due("colorectal", born: born)
        #expect(general?.state == .later)
        #expect(general?.dueDate == date(2033, 1, 1))

        var ledger = Ledger()
        ledger.answer(flag: .familyColorectal, isPresent: true, earliestDiagnosisAge: 45)
        let family = due("colorectal", born: born, ledger: ledger)
        #expect(family?.state == .overdue)
        #expect(family?.dueDate == date(2023, 1, 1))

        // The cadence shortens too: five years, not ten.
        ledger.log(itemID: "colorectal", performedOn: date(2025, 6, 1))
        #expect(due("colorectal", born: born, ledger: ledger)?.dueDate == date(2030, 6, 1))
    }

    @Test func soonInsideNinetyDays() {
        var ledger = Ledger()
        ledger.log(itemID: "bloodPressure", performedOn: date(2025, 12, 1))
        let soon = due("bloodPressure", born: date(1976, 2, 1), ledger: ledger)
        #expect(soon?.state == .soon)
        #expect(soon?.dueDate == date(2026, 12, 1))
    }

    // MARK: A profile without the answers

    @Test func noBirthdayGivesNothingAndAsks() {
        #expect(Schedule.due(for: profile(born: nil, sex: .male), ledger: Ledger(), now: now, calendar: utc).isEmpty)
        let missing = Schedule.missing(profile(born: nil, sex: nil))
        #expect(missing.age && missing.sex)
        let answered = Schedule.missing(profile(born: date(1980, 1, 1), sex: .female))
        #expect(!answered.age && !answered.sex)
    }

    /// "Other, or prefer not to say" keeps only the items for everyone, and
    /// the page does not ask again.
    @Test func otherSexKeepsOnlyUniversalItems() {
        let list = Schedule.due(for: profile(born: date(1976, 5, 1), sex: .other), ledger: Ledger(), now: now, calendar: utc)
        #expect(!list.isEmpty)
        #expect(list.allSatisfy { $0.item.eligibility == .any })
        #expect(!Schedule.missing(profile(born: date(1976, 5, 1), sex: .other)).sex)
    }

    /// Discuss items and items past their stop age never enter the calendar.
    @Test func discussItemsNeverEnterTheCalendar() {
        let list = Schedule.due(for: profile(born: date(1970, 1, 1), sex: .male), ledger: Ledger(), now: now, calendar: utc)
        #expect(list.allSatisfy { $0.item.tier == .recommended })
    }

    /// The profile wins; what the page asked fills only its gaps; Health's
    /// age is the last resort.
    @Test func resolvedProfileFillsOnlyTheGaps() {
        let base = profile(born: date(1980, 1, 1), sex: .female)
        let kept = Schedule.resolved(base, askedSex: "male", askedBirthday: date(1990, 1, 1), healthAgeYears: 20, now: now, calendar: utc)
        #expect(kept.birthday == date(1980, 1, 1))
        #expect(kept.sex == .female)

        let filled = Schedule.resolved(profile(born: nil, sex: nil), askedSex: "male", askedBirthday: date(1990, 1, 1), healthAgeYears: 20, now: now, calendar: utc)
        #expect(filled.birthday == date(1990, 1, 1))
        #expect(filled.sex == .male)

        let fromHealth = Schedule.resolved(profile(born: nil, sex: nil), askedSex: nil, askedBirthday: nil, healthAgeYears: 50.5, now: now, calendar: utc)
        #expect(fromHealth.age(on: now, calendar: utc) == 50)
    }

    // MARK: Reminders

    let bloodPressure = SomaTools.ScreeningCatalog.item(id: "bloodPressure")!

    /// A reminder at 9:00 on 2026-11-01 in New York stays at 9:00 local, the
    /// day the clocks go back, and stays at 9:00 wherever the phone travels.
    @Test func reminderStaysLocalAcrossDST() throws {
        let newYork = calendar("America/New_York")
        let today = date(2026, 9, 15, hour: 12, in: newYork)
        let dueDate = date(2026, 11, 1, in: newYork)
        let entry = Due(item: bloodPressure, dueDate: dueDate, state: .later, lastDone: nil)
        let planned = ScreeningReminderRules.reminders(for: [entry], optedIn: ["bloodPressure": today],
                                                       schedule: NotificationSchedule(), prefs: NotificationPreferences(),
                                                       now: today, calendar: newYork)
        #expect(planned.count == 2)
        #expect(planned.allSatisfy { $0.kind == .screeningDue })
        #expect(planned.allSatisfy { SomaNotificationKind.kind(forIdentifier: $0.id) == .screeningDue })
        // A tap opens the Screening Ledger, not the inbox.
        #expect(planned.allSatisfy { $0.link == .screeningLedger })

        let fires = planned.compactMap { NotificationPlanner.nextFire($0.trigger, after: today, calendar: newYork) }.sorted()
        #expect(fires.count == 2)
        // Thirty days before, under daylight saving time: 9:00 is 13:00 UTC.
        #expect(fires[0] == date(2026, 10, 2, hour: 13))
        // The day itself, after the clocks went back: 9:00 is 14:00 UTC.
        #expect(fires[1] == date(2026, 11, 1, hour: 14))
        for fire in fires {
            #expect(newYork.component(.hour, from: fire) == 9)
            #expect(newYork.component(.minute, from: fire) == 0)
        }

        // The trigger is a wall clock time, not an instant: in Paris the same
        // request fires at 9:00 in Paris.
        let paris = calendar("Europe/Paris")
        let inParis = try #require(NotificationPlanner.nextFire(planned[0].trigger, after: today, calendar: paris))
        #expect(paris.component(.hour, from: inParis) == 9)
    }

    @Test func remindersAreOptInPerItem() {
        let entry = Due(item: bloodPressure, dueDate: date(2027, 1, 10), state: .later, lastDone: nil)
        #expect(ScreeningReminderRules.reminders(for: [entry], optedIn: [:], schedule: NotificationSchedule(),
                                                 prefs: NotificationPreferences(), now: now, calendar: utc).isEmpty)

        var off = NotificationSchedule()
        off.screeningReminders = false
        #expect(ScreeningReminderRules.reminders(for: [entry], optedIn: ["bloodPressure": now], schedule: off,
                                                 prefs: NotificationPreferences(), now: now, calendar: utc).isEmpty)

        var silent = NotificationSchedule()
        silent.isEnabled = false
        #expect(ScreeningReminderRules.reminders(for: [entry], optedIn: ["bloodPressure": now], schedule: silent,
                                                 prefs: NotificationPreferences(), now: now, calendar: utc).isEmpty)
    }

    /// Inside thirty days only the day itself is left; past due, one word the
    /// next morning after the switch was turned on, and never again.
    @Test func lateOrCloseKeepsWhatIsStillAhead() {
        let close = Due(item: bloodPressure, dueDate: date(2026, 11, 5), state: .soon, lastDone: nil)
        let planned = ScreeningReminderRules.reminders(for: [close], optedIn: ["bloodPressure": now], schedule: NotificationSchedule(),
                                                       prefs: NotificationPreferences(), now: now, calendar: utc)
        #expect(planned.count == 1)
        #expect(planned.first.flatMap { NotificationPlanner.nextFire($0.trigger, after: now, calendar: utc) } == date(2026, 11, 5, hour: 9))

        let late = Due(item: bloodPressure, dueDate: date(2026, 3, 1), state: .overdue, lastDone: nil)
        let nudge = ScreeningReminderRules.reminders(for: [late], optedIn: ["bloodPressure": now], schedule: NotificationSchedule(),
                                                     prefs: NotificationPreferences(), now: now, calendar: utc)
        #expect(nudge.count == 1)
        #expect(nudge.first.flatMap { NotificationPlanner.nextFire($0.trigger, after: now, calendar: utc) } == date(2026, 10, 25, hour: 9))

        let weekLater = date(2026, 10, 31, hour: 12)
        #expect(ScreeningReminderRules.reminders(for: [late], optedIn: ["bloodPressure": now], schedule: NotificationSchedule(),
                                                 prefs: NotificationPreferences(), now: weekLater, calendar: utc).isEmpty)

        let done = Due(item: bloodPressure, dueDate: nil, state: .done, lastDone: date(2020, 1, 1))
        #expect(ScreeningReminderRules.reminders(for: [done], optedIn: ["bloodPressure": now], schedule: NotificationSchedule(),
                                                 prefs: NotificationPreferences(), now: now, calendar: utc).isEmpty)
    }

    /// A morning that falls inside quiet hours waits for them to end.
    @Test func quietHoursMoveTheMorning() {
        var prefs = NotificationPreferences()
        prefs.quietFrom = ClockTime(hour: 22)
        prefs.quietUntil = ClockTime(hour: 10)
        let entry = Due(item: bloodPressure, dueDate: date(2026, 11, 5), state: .soon, lastDone: nil)
        let planned = ScreeningReminderRules.reminders(for: [entry], optedIn: ["bloodPressure": now], schedule: NotificationSchedule(),
                                                       prefs: prefs, now: now, calendar: utc)
        #expect(planned.first.flatMap { NotificationPlanner.nextFire($0.trigger, after: now, calendar: utc) } == date(2026, 11, 5, hour: 10))
    }

    // MARK: Stored files from an older build

    @Test func screeningSwitchDecodesFromAnOlderFile() throws {
        let old = try JSONDecoder().decode(NotificationSchedule.self, from: Data(#"{"dataAlerts":false}"#.utf8))
        #expect(old.screeningReminders == true)
        #expect(old.dataAlerts == false)
    }

    @Test func ledgerWithoutRemindersDecodes() throws {
        let old = try JSONDecoder().decode(Ledger.self, from: Data(#"{"records":[],"riskAnswers":[]}"#.utf8))
        #expect(old.reminders.isEmpty)

        var ledger = Ledger()
        ledger.setReminder(true, itemID: "colorectal", now: now)
        let back = try JSONDecoder().decode(Ledger.self, from: JSONEncoder().encode(ledger))
        #expect(back.reminders["colorectal"] == now)
        ledger.setReminder(false, itemID: "colorectal", now: now)
        #expect(ledger.reminders.isEmpty)
    }
}
