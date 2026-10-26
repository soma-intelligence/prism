//
//  MedicalRecord.swift
//  Prism
//
//  The person's own medical record: conditions, allergies, vaccinations,
//  family history, the care team and appointments, as lists rather than the
//  medical card's free text. Typed in by the person and kept on this phone;
//  it is their notes, not a clinic's file, and nothing here is a diagnosis.
//
//  Every stored field is optional or defaulted on decode, so a field added
//  later cannot wipe a record already written.
//

import Foundation
import Observation

// MARK: - Entries

/// A condition the person lives with, in their words.
nonisolated struct MedicalCondition: Codable, Equatable, Sendable, Identifiable {
    var id = UUID()
    var name: String
    var since: Date?
    var notes: String?
}

/// An allergy: what to, what it does, and how bad it gets.
nonisolated struct Allergy: Codable, Equatable, Sendable, Identifiable {
    nonisolated enum Severity: String, Codable, Sendable, CaseIterable, Identifiable {
        case mild, moderate, severe

        var id: String { rawValue }

        var title: String {
            switch self {
            case .mild: String(localized: "Mild")
            case .moderate: String(localized: "Moderate")
            case .severe: String(localized: "Severe")
            }
        }
    }

    var id = UUID()
    var substance: String
    var reaction: String?
    var severity: Severity?
}

/// One dose of a vaccine.
nonisolated struct Vaccination: Codable, Equatable, Sendable, Identifiable {
    var id = UUID()
    var name: String
    var date: Date
    /// "First dose", "Booster": as the card from the clinic says it.
    var dose: String?
}

/// A relative and what they had, the way a doctor asks for it.
nonisolated struct FamilyHistoryEntry: Codable, Equatable, Sendable, Identifiable {
    nonisolated enum Relative: String, Codable, Sendable, CaseIterable, Identifiable {
        case mother, father, sister, brother, child, grandparent, auntOrUncle, cousin

        var id: String { rawValue }

        /// Parents, siblings and children: the relatives the screening
        /// guidelines count.
        var isFirstDegree: Bool {
            switch self {
            case .mother, .father, .sister, .brother, .child: true
            case .grandparent, .auntOrUncle, .cousin: false
            }
        }

        var title: String {
            switch self {
            case .mother: String(localized: "Mother")
            case .father: String(localized: "Father")
            case .sister: String(localized: "Sister")
            case .brother: String(localized: "Brother")
            case .child: String(localized: "Child")
            case .grandparent: String(localized: "Grandparent")
            case .auntOrUncle: String(localized: "Aunt or uncle")
            case .cousin: String(localized: "Cousin")
            }
        }
    }

    /// The conditions a screening reads, plus anything else in the person's
    /// words (`note`).
    nonisolated enum Condition: String, Codable, Sendable, CaseIterable, Identifiable {
        case colorectalCancer, breastCancer, ovarianCancer, prostateCancer, melanoma
        case osteoporosis, heartAttackOrStroke, type2Diabetes, other

        var id: String { rawValue }

        var title: String {
            switch self {
            case .colorectalCancer: String(localized: "Colorectal cancer")
            case .breastCancer: String(localized: "Breast cancer")
            case .ovarianCancer: String(localized: "Ovarian cancer")
            case .prostateCancer: String(localized: "Prostate cancer")
            case .melanoma: String(localized: "Melanoma")
            case .osteoporosis: String(localized: "Osteoporosis or hip fracture")
            case .heartAttackOrStroke: String(localized: "Heart attack or stroke")
            case .type2Diabetes: String(localized: "Type 2 diabetes")
            case .other: String(localized: "Something else")
            }
        }

        /// The screening flag this condition answers, nil for one no
        /// screening reads.
        var riskFlag: SomaTools.ScreeningRiskFlag? {
            switch self {
            case .colorectalCancer: .familyColorectal
            case .breastCancer, .ovarianCancer: .familyBreastOvarian
            case .prostateCancer: .familyProstate
            case .melanoma: .familyMelanoma
            case .osteoporosis: .familyOsteoporosis
            case .heartAttackOrStroke: .familyEarlyCardiac
            case .type2Diabetes: .familyDiabetes
            case .other: nil
            }
        }
    }

    var id = UUID()
    var relative: Relative
    var condition: Condition
    /// Age when it was found, when known.
    var ageAtOnset: Int?
    /// What it was, for `.other`, or anything worth adding.
    var note: String?
}

/// Someone who looks after the person's health.
nonisolated struct CareTeamMember: Codable, Equatable, Sendable, Identifiable {
    nonisolated enum Role: String, Codable, Sendable, CaseIterable, Identifiable {
        case primaryCare, dentist, gynecologist, cardiologist, dermatologist, eyeDoctor, therapist, specialist, other

        var id: String { rawValue }

        var title: String {
            switch self {
            case .primaryCare: String(localized: "Primary care")
            case .dentist: String(localized: "Dentist")
            case .gynecologist: String(localized: "Gynecologist")
            case .cardiologist: String(localized: "Cardiologist")
            case .dermatologist: String(localized: "Dermatologist")
            case .eyeDoctor: String(localized: "Eye doctor")
            case .therapist: String(localized: "Therapist")
            case .specialist: String(localized: "Specialist")
            case .other: String(localized: "Other")
            }
        }

        var symbol: String {
            switch self {
            case .primaryCare: "stethoscope"
            case .dentist: "mouth"
            case .gynecologist: "figure.stand.dress"
            case .cardiologist: "heart"
            case .dermatologist: "hand.raised"
            case .eyeDoctor: "eye"
            case .therapist: "brain.head.profile"
            case .specialist: "cross.case"
            case .other: "person"
            }
        }
    }

    var id = UUID()
    var name: String
    var role: Role
    var phone: String?
    var email: String?
}

/// A visit booked with someone.
nonisolated struct Appointment: Codable, Equatable, Sendable, Identifiable {
    nonisolated enum Reason: String, Codable, Sendable, CaseIterable, Identifiable {
        case checkup, followUp, dental, screening, vaccination, test, other

        var id: String { rawValue }

        var title: String {
            switch self {
            case .checkup: String(localized: "Checkup")
            case .followUp: String(localized: "Follow up")
            case .dental: String(localized: "Teeth")
            case .screening: String(localized: "Screening")
            case .vaccination: String(localized: "Vaccine")
            case .test: String(localized: "Test or scan")
            case .other: String(localized: "Other")
            }
        }
    }

    var id = UUID()
    var date: Date
    /// Who the visit is with: a name, a clinic.
    var with: String
    var reason: Reason
    var notes: String?
    /// The care team member it is with, when it is one of them.
    var careTeamID: UUID?
    /// The two reminders, the evening before and an hour before. On unless
    /// the person turns them off on the appointment.
    var remind = true

    init(id: UUID = UUID(), date: Date, with: String, reason: Reason, notes: String? = nil,
         careTeamID: UUID? = nil, remind: Bool = true) {
        self.id = id
        self.date = date
        self.with = with
        self.reason = reason
        self.notes = notes
        self.careTeamID = careTeamID
        self.remind = remind
    }

    private enum CodingKeys: String, CodingKey { case id, date, with, reason, notes, careTeamID, remind }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        date = try c.decode(Date.self, forKey: .date)
        with = try c.decodeIfPresent(String.self, forKey: .with) ?? ""
        reason = (try? c.decodeIfPresent(Reason.self, forKey: .reason)) ?? .other
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        careTeamID = try c.decodeIfPresent(UUID.self, forKey: .careTeamID)
        remind = try c.decodeIfPresent(Bool.self, forKey: .remind) ?? true
    }
}

// MARK: - The record

/// Everything the record holds, as one Codable value. Pure: the store
/// persists it, this type only computes.
nonisolated struct MedicalRecord: Codable, Equatable, Sendable {
    var conditions: [MedicalCondition] = []
    var allergies: [Allergy] = []
    var vaccinations: [Vaccination] = []
    var familyHistory: [FamilyHistoryEntry] = []
    var careTeam: [CareTeamMember] = []
    var appointments: [Appointment] = []
    /// The medical card's free text as it was when it moved here, kept so
    /// the move loses nothing. Nil when the card held none.
    var cardNote: String?
    /// True once the card's free text was moved, so it moves once.
    var migratedFromCard = false

    init() {}

    private enum CodingKeys: String, CodingKey {
        case conditions, allergies, vaccinations, familyHistory, careTeam, appointments, cardNote, migratedFromCard
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        conditions = (try? c.decodeIfPresent([MedicalCondition].self, forKey: .conditions)) ?? []
        allergies = (try? c.decodeIfPresent([Allergy].self, forKey: .allergies)) ?? []
        vaccinations = (try? c.decodeIfPresent([Vaccination].self, forKey: .vaccinations)) ?? []
        familyHistory = (try? c.decodeIfPresent([FamilyHistoryEntry].self, forKey: .familyHistory)) ?? []
        careTeam = (try? c.decodeIfPresent([CareTeamMember].self, forKey: .careTeam)) ?? []
        appointments = (try? c.decodeIfPresent([Appointment].self, forKey: .appointments)) ?? []
        cardNote = try c.decodeIfPresent(String.self, forKey: .cardNote)
        migratedFromCard = try c.decodeIfPresent(Bool.self, forKey: .migratedFromCard) ?? false
    }

    /// No entry in any list.
    var isEmpty: Bool {
        conditions.isEmpty && allergies.isEmpty && vaccinations.isEmpty && familyHistory.isEmpty
            && careTeam.isEmpty && appointments.isEmpty
    }

    // MARK: Appointments

    /// Appointments still ahead, soonest first.
    func upcoming(now: Date = Date()) -> [Appointment] {
        appointments.filter { $0.date >= now }.sorted { $0.date < $1.date }
    }

    /// Appointments already behind, newest first.
    func past(now: Date = Date()) -> [Appointment] {
        appointments.filter { $0.date < now }.sorted { $0.date > $1.date }
    }

    func member(_ id: UUID?) -> CareTeamMember? {
        guard let id else { return nil }
        return careTeam.first { $0.id == id }
    }

    /// True for a visit for the teeth, or one with the dentist on the team.
    func isDental(_ appointment: Appointment) -> Bool {
        appointment.reason == .dental || member(appointment.careTeamID)?.role == .dentist
    }

    /// The next dental appointment, the visit the mouth page counts down to.
    func nextDentalVisit(now: Date = Date()) -> Date? {
        upcoming(now: now).first(where: isDental)?.date
    }

    // MARK: Screening

    /// The family history as screening answers: one per flag a first degree
    /// relative's condition sets, with the youngest age at onset known.
    ///
    /// Only first degree relatives count, as the flags are worded. A heart
    /// attack or stroke counts only before 55 and only when the age is
    /// known, which is the flag's own question ("before 55"); the engine
    /// must never infer a risk from anything except an explicit answer.
    var screeningRisks: [SomaTools.ScreeningRisk] {
        var risks: [SomaTools.ScreeningRiskFlag: SomaTools.ScreeningRisk] = [:]
        for entry in familyHistory where entry.relative.isFirstDegree {
            guard let flag = entry.condition.riskFlag else { continue }
            if flag == .familyEarlyCardiac {
                guard let age = entry.ageAtOnset, age < 55 else { continue }
            }
            var risk = risks[flag] ?? SomaTools.ScreeningRisk(flag: flag, isPresent: true)
            if let age = entry.ageAtOnset {
                risk.earliestDiagnosisAge = min(risk.earliestDiagnosisAge ?? age, age)
            }
            risks[flag] = risk
        }
        return SomaTools.ScreeningRiskFlag.allCases.compactMap { risks[$0] }
    }

    var screeningRiskFlags: Set<SomaTools.ScreeningRiskFlag> {
        Set(screeningRisks.map(\.flag))
    }

    // MARK: Migration

    /// Moves the medical card's free text into the lists, once. Allergies and
    /// conditions split on commas, semicolons and new lines; the medications
    /// stay with the card. The whole text is kept in `cardNote`, so nothing
    /// typed is lost even where the split guessed wrong.
    @MainActor
    mutating func migrate(from card: HomeMedicalCard) {
        guard !migratedFromCard else { return }
        migratedFromCard = true
        allergies += Self.items(card.allergies).map { Allergy(substance: $0) }
        conditions += Self.items(card.conditions).map { MedicalCondition(name: $0) }
        cardNote = card.recordNote
    }

    /// The pieces of a free text list, without the words that mean none.
    static func items(_ text: String) -> [String] {
        let none: Set<String> = ["none", "none known", "no", "n/a", "nothing", "aucune", "aucun"]
        return text
            .split(whereSeparator: { $0 == "," || $0 == ";" || $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !none.contains($0.lowercased()) }
    }
}

extension SomaTools.ScreeningLedger {
    /// This ledger with the medical record's family history folded into its
    /// risk answers. A yes from the record wins over a no on the ledger and
    /// the youngest age at diagnosis is kept: risk only ever pulls a
    /// screening forward. Records and reminders are untouched.
    nonisolated func withFamilyHistory(_ family: [SomaTools.ScreeningRisk]) -> SomaTools.ScreeningLedger {
        var answers = riskAnswers
        for risk in family where risk.isPresent {
            if let index = answers.firstIndex(where: { $0.flag == risk.flag }) {
                var merged = answers[index]
                let ages = [merged.isPresent ? merged.earliestDiagnosisAge : nil, risk.earliestDiagnosisAge].compactMap { $0 }
                merged.isPresent = true
                merged.earliestDiagnosisAge = ages.min()
                answers[index] = merged
            } else {
                answers.append(risk)
            }
        }
        return SomaTools.ScreeningLedger(records: records, riskAnswers: answers, reminders: reminders)
    }
}

// MARK: - Store

/// The medical record on this phone: one JSON file in Application Support,
/// written atomically with complete protection, never sent anywhere from
/// here. Deleting the account leaves it in place (owner, 2026-10-24).
@MainActor
@Observable
final class MedicalRecordStore {
    static let shared: MedicalRecordStore = {
        #if DEBUG
        if MedicalRecordFixtures.isOn {
            let store = MedicalRecordStore(url: nil, card: nil)
            store.record = MedicalRecordFixtures.record()
            return store
        }
        #endif
        return MedicalRecordStore(url: MedicalRecordStore.defaultURL, card: HomeLog.shared.medical)
    }()

    private(set) var record: MedicalRecord
    private let url: URL?

    /// - Parameters:
    ///   - url: where the record lives. Nil keeps it in memory only, which is
    ///     what previews and tests use.
    ///   - card: the medical card whose free text moves in, once.
    init(url: URL?, card: HomeMedicalCard?) {
        self.url = url
        record = LabFiles.load(MedicalRecord.self, from: url) ?? MedicalRecord()
        if let card, !record.migratedFromCard {
            record.migrate(from: card)
            save()
        }
    }

    nonisolated static var defaultURL: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return base.appending(path: "medical-record.json")
    }

    var conditions: [MedicalCondition] { record.conditions }
    var allergies: [Allergy] { record.allergies }
    var vaccinations: [Vaccination] { record.vaccinations }
    var familyHistory: [FamilyHistoryEntry] { record.familyHistory }
    var careTeam: [CareTeamMember] { record.careTeam }
    var appointments: [Appointment] { record.appointments }
    var screeningRiskFlags: Set<SomaTools.ScreeningRiskFlag> { record.screeningRiskFlags }
    var screeningRisks: [SomaTools.ScreeningRisk] { record.screeningRisks }

    func upcoming(now: Date = Date()) -> [Appointment] { record.upcoming(now: now) }

    /// Applies one change and writes the file. A change to the appointments
    /// re-plans their reminders.
    func update(_ change: (inout MedicalRecord) -> Void) {
        let before = record.appointments
        change(&record)
        save()
        if url != nil, record.appointments != before {
            Task { await AppointmentReminders.sync() }
        }
    }

    private func save() {
        guard let url else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        LabFiles.save(record, to: url)
    }
}

// MARK: - Reminders

/// Two reminders an appointment: the evening before at 18:00, and an hour
/// before. Pure, like the screening rules: each one is a wall clock time, so
/// 18:00 stays 18:00 local the day the clocks change.
///
/// The evening one keeps to quiet hours and is skipped inside them; the hour
/// before always comes, since it is for a commitment already made.
nonisolated enum AppointmentReminderRules {
    static let prefix = "soma.appointment."
    static let evening = ClockTime(hour: 18)
    static let leadMinutes = 60

    static func reminders(
        for appointments: [Appointment],
        schedule: NotificationSchedule,
        prefs: NotificationPreferences,
        now: Date,
        calendar: Calendar = .current
    ) -> [PlannedNotification] {
        guard schedule.isEnabled else { return [] }
        var planned: [PlannedNotification] = []
        for appointment in appointments where appointment.remind && appointment.date > now {
            let time = ScoreMath.clock(appointment.date, calendar: calendar)
            let named = appointment.with.trimmingCharacters(in: .whitespacesAndNewlines)
            let who = named.isEmpty ? appointment.reason.title : named
            let what = appointment.reason.title

            if !NotificationPlanner.isQuiet(evening, prefs),
               let dayBefore = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: appointment.date)) {
                var parts = calendar.dateComponents([.year, .month, .day], from: dayBefore)
                parts.hour = evening.hour
                parts.minute = evening.minute
                if let fire = calendar.date(from: parts), fire > now {
                    planned.append(PlannedNotification(
                        id: prefix + appointment.id.uuidString + ".eve",
                        kind: .appointment,
                        title: String(localized: "Tomorrow at \(time): \(who)"),
                        body: String(localized: "\(what). The details are in your medical record."),
                        trigger: .wallClock(parts), link: .medicalRecord))
                }
            }

            if let lead = calendar.date(byAdding: .minute, value: -leadMinutes, to: appointment.date), lead > now {
                let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: lead)
                planned.append(PlannedNotification(
                    id: prefix + appointment.id.uuidString + ".hour",
                    kind: .appointment,
                    title: String(localized: "In an hour: \(who)"),
                    body: String(localized: "\(what) at \(time)."),
                    trigger: .wallClock(parts), link: .medicalRecord))
            }
        }
        return planned
    }
}

/// The appointment reminders as the phone holds them, re-derived whole from
/// the record whenever its appointments change. Outside the planner's
/// managed set, like the screening reminders.
@MainActor
enum AppointmentReminders {
    /// - Parameter asking: true when a person just saved an appointment
    ///   with its reminders on: the notification permission is asked then,
    ///   in context, if it never was.
    static func sync(asking: Bool = false) async {
        let notifications = SomaNotifications.shared
        if asking {
            await notifications.apply(asking: true)
        } else {
            await notifications.refreshAuthorization()
        }
        let planned = AppointmentReminderRules.reminders(
            for: MedicalRecordStore.shared.appointments, schedule: notifications.schedule,
            prefs: notifications.settings.notifications, now: Date())
        let scheduler = notifications.scheduler
        let stale = await scheduler.pendingIdentifiers().filter { $0.hasPrefix(AppointmentReminderRules.prefix) }
        await scheduler.remove(stale)
        guard notifications.isOn else { return }
        for item in planned {
            try? await scheduler.add(item)
        }
    }
}
