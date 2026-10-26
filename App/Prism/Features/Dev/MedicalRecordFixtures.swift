//
//  MedicalRecordFixtures.swift
//  Prism
//
//  A filled medical record for screenshots on a simulator, behind the launch
//  argument `-record.fixture YES`. The store then keeps memory only: nothing
//  is written, and the person's own record is never touched. Development
//  only.
//

#if DEBUG
import Foundation

enum MedicalRecordFixtures {
    /// The defaults key behind `-record.fixture YES`.
    nonisolated static let launchKey = "record.fixture"

    nonisolated static var isOn: Bool { UserDefaults.standard.bool(forKey: launchKey) }

    private static func days(_ days: Double, hour: Int = 9, minute: Int = 0) -> Date {
        let calendar = Calendar.current
        let day = calendar.date(byAdding: .day, value: Int(days), to: calendar.startOfDay(for: Date())) ?? Date()
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }

    static func record() -> MedicalRecord {
        let doctor = CareTeamMember(name: "Dr Maya Chen", role: .primaryCare, phone: "+1 650 555 0142")
        let dentist = CareTeamMember(name: "Dr Paul Okafor", role: .dentist, phone: "+1 650 555 0187")
        var record = MedicalRecord()
        record.migratedFromCard = true
        record.conditions = [MedicalCondition(name: "Asthma", since: days(-9000))]
        record.allergies = [
            Allergy(substance: "Penicillin", reaction: "Hives", severity: .severe),
            Allergy(substance: "Peanuts", reaction: "Swollen lips", severity: .moderate),
        ]
        record.vaccinations = [
            Vaccination(name: "Influenza", date: days(-30), dose: "2026 to 2027 season"),
            Vaccination(name: "Tetanus, diphtheria", date: days(-800), dose: "Booster"),
        ]
        record.familyHistory = [
            FamilyHistoryEntry(relative: .father, condition: .colorectalCancer, ageAtOnset: 52),
            FamilyHistoryEntry(relative: .mother, condition: .type2Diabetes, ageAtOnset: 61),
        ]
        record.careTeam = [doctor, dentist]
        record.appointments = [
            Appointment(date: days(3, hour: 10, minute: 30), with: dentist.name, reason: .dental,
                        notes: "Cleaning", careTeamID: dentist.id),
            Appointment(date: days(18, hour: 14), with: doctor.name, reason: .checkup, careTeamID: doctor.id),
            Appointment(date: days(-40, hour: 8, minute: 15), with: doctor.name, reason: .vaccination, careTeamID: doctor.id),
        ]
        return record
    }
}
#endif
