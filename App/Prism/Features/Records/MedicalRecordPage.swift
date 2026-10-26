//
//  MedicalRecordPage.swift
//  Prism
//

import SwiftUI
import SomaUI

/// The person's medical record, in the order a doctor asks for it: what is
/// booked, conditions, allergies, vaccinations, family history and who looks
/// after them. Each section adds in one tap and each row opens to edit.
///
/// Opened from the account sheet (under the Vault), from Health records and
/// from the medical card. Typed in by the person and kept on this phone: it
/// is their notes, not a clinic's file, and the page says so.
struct MedicalRecordPage: View {
    @Environment(\.somaTheme) private var theme
    @State private var editor: MedicalRecordEditor?

    private var store: MedicalRecordStore { .shared }

    var body: some View {
        let record = store.record
        let now = Date()
        let upcoming = record.upcoming(now: now)
        let past = record.past(now: now)

        ListScaffold(eyebrow: "Kept on this phone", title: "Medical record") {
            HomeReason(lead(record, upcoming: upcoming))

            SomaBrowseGroup([SettingsItem(id: "report")]) { _ in
                NavigationLink(value: GlobalRoute.doctorReport) {
                    SomaBrowseRow(symbol: "doc.text", title: String(localized: "Report for my doctor"),
                                  detail: String(localized: "A PDF of this record and what Soma holds"))
                }
                .buttonStyle(.plain)
            }

            section("Appointments", rows: upcoming.map { appointmentRow($0, record: record) },
                    add: "Add appointment") { editor = .appointment(nil) }

            section("Conditions", rows: record.conditions.map { condition in
                RecordRow(id: condition.id, title: condition.name,
                          detail: condition.since.map { "Since \(Self.monthYear($0))" } ?? condition.notes,
                          value: nil) { editor = .condition(condition) }
            }, add: "Add condition") { editor = .condition(nil) }

            section("Allergies", rows: record.allergies.map { allergy in
                RecordRow(id: allergy.id, title: allergy.substance,
                          detail: allergy.reaction,
                          value: allergy.severity?.title) { editor = .allergy(allergy) }
            }, add: "Add allergy") { editor = .allergy(nil) }

            section("Vaccinations", rows: record.vaccinations.sorted { $0.date > $1.date }.map { shot in
                RecordRow(id: shot.id, title: shot.name, detail: shot.dose,
                          value: Self.day(shot.date)) { editor = .vaccination(shot) }
            }, add: "Add vaccination") { editor = .vaccination(nil) }

            section("Family history", rows: record.familyHistory.map { entry in
                RecordRow(id: entry.id, title: entry.relative.title,
                          detail: entry.condition == .other ? (entry.note ?? entry.condition.title) : entry.condition.title,
                          value: entry.ageAtOnset.map { "At \($0)" }) { editor = .family(entry) }
            }, add: "Add a relative",
                    footnote: record.screeningRiskFlags.isEmpty ? nil : "Parents, siblings and children here start some screenings earlier in the Screening ledger.") {
                editor = .family(nil)
            }

            section("Care team", rows: record.careTeam.map { member in
                RecordRow(id: member.id, title: member.name, detail: member.role.title,
                          value: member.phone) { editor = .member(member) }
            }, add: "Add someone") { editor = .member(nil) }

            if !past.isEmpty {
                section("Past appointments", rows: past.prefix(10).map { appointmentRow($0, record: record) })
            }

            if let note = record.cardNote {
                SettingsSection("From your medical card") {
                    SomaCard {
                        Text(note)
                            .somaFont(theme.typography.body)
                            .foregroundStyle(theme.colors.inkSecondary.color)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            SettingsFootnote("Your own notes, not a medical file. Nothing here leaves this phone, and none of it is a diagnosis.")
        }
        .sheet(item: $editor) { $0.sheet }
    }

    /// One sentence over the sections: what is next, or what fills the page.
    private func lead(_ record: MedicalRecord, upcoming: [Appointment]) -> String {
        if let next = upcoming.first {
            let who = next.with.homeNonEmpty ?? next.reason.title
            return "Next: \(who), \(Self.day(next.date)) at \(ScoreMath.clock(next.date)). Everything else a doctor asks first is below."
        }
        if record.isEmpty {
            return "Add what a doctor asks first: conditions, allergies, vaccines, family history and who looks after you."
        }
        return "Nothing booked. Everything a doctor asks first is below."
    }

    private func appointmentRow(_ appointment: Appointment, record: MedicalRecord) -> RecordRow {
        let who = appointment.with.homeNonEmpty ?? record.member(appointment.careTeamID)?.name ?? appointment.reason.title
        return RecordRow(id: appointment.id, title: who,
                         detail: "\(appointment.reason.title) \u{00B7} \(Self.day(appointment.date))",
                         value: ScoreMath.clock(appointment.date)) { editor = .appointment(appointment) }
    }

    @ViewBuilder
    private func section(_ title: LocalizedStringKey, rows: [RecordRow], add: String? = nil,
                         footnote: LocalizedStringKey? = nil, onAdd: @escaping () -> Void = {}) -> some View {
        SettingsSection(title) {
            SomaBrowseGroup(rows + (add.map { [RecordRow(id: UUID(), title: $0, detail: nil, value: nil, isAdd: true, action: onAdd)] } ?? []),
                            hasGlyphs: false) { row in
                Button(action: row.action) {
                    if row.isAdd {
                        SettingsLine(row.title) {
                            Image(systemName: "plus")
                                .foregroundStyle(theme.colors.accent.color)
                        }
                    } else {
                        SettingsLine(row.title, detail: row.detail) {
                            if let value = row.value {
                                Text(value)
                                    .somaFont(theme.typography.rowValue)
                                    .foregroundStyle(theme.colors.inkSecondary.color)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
                .buttonStyle(SettingsRowPressStyle())
            }
            if let footnote { SettingsFootnote(footnote) }
        }
    }

    static func day(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).year())
    }

    static func monthYear(_ date: Date) -> String {
        date.formatted(.dateTime.month(.wide).year())
    }
}

/// One line of a section, or the line that adds to it.
private struct RecordRow: Identifiable {
    let id: UUID
    let title: String
    let detail: String?
    let value: String?
    var isAdd = false
    let action: () -> Void
}

// MARK: - Editors

/// What the page has open: a new entry when the value is nil, else that one.
enum MedicalRecordEditor: Identifiable {
    case condition(MedicalCondition?)
    case allergy(Allergy?)
    case vaccination(Vaccination?)
    case family(FamilyHistoryEntry?)
    case member(CareTeamMember?)
    case appointment(Appointment?)

    var id: String {
        switch self {
        case .condition(let entry): "condition." + (entry?.id.uuidString ?? "new")
        case .allergy(let entry): "allergy." + (entry?.id.uuidString ?? "new")
        case .vaccination(let entry): "vaccination." + (entry?.id.uuidString ?? "new")
        case .family(let entry): "family." + (entry?.id.uuidString ?? "new")
        case .member(let entry): "member." + (entry?.id.uuidString ?? "new")
        case .appointment(let entry): "appointment." + (entry?.id.uuidString ?? "new")
        }
    }

    @ViewBuilder
    var sheet: some View {
        switch self {
        case .condition(let entry): ConditionSheet(entry: entry)
        case .allergy(let entry): AllergySheet(entry: entry)
        case .vaccination(let entry): VaccinationSheet(entry: entry)
        case .family(let entry): FamilyHistorySheet(entry: entry)
        case .member(let entry): CareTeamSheet(entry: entry)
        case .appointment(let entry): AppointmentSheet(appointment: entry)
        }
    }
}

/// Replaces the entry with the same id, or adds it.
private func upsert<T: Identifiable>(_ entry: T, in list: inout [T]) {
    if let index = list.firstIndex(where: { $0.id == entry.id }) {
        list[index] = entry
    } else {
        list.append(entry)
    }
}

/// The text of an optional field, nil when it holds nothing but spaces.
private func optional(_ text: String) -> String? {
    text.homeNonEmpty?.trimmingCharacters(in: .whitespacesAndNewlines)
}

private struct ConditionSheet: View {
    let entry: MedicalCondition?
    @State private var name = ""
    @State private var since: Date?
    @State private var notes = ""

    var body: some View {
        HomeInputSheet(title: entry == nil ? "Add condition" : "Condition", actionTitle: "Save",
                       isEnabled: name.homeNonEmpty != nil, action: save) {
            HomeTextField(title: "Condition", text: $name, prompt: "Asthma")
            ToolSettingsGroup(rows: [.date(String(localized: "Since"), $since)])
            HomeTextField(title: "Notes", text: $notes, prompt: "Optional")
            if let entry {
                RecordRemoveButton("Remove condition") { MedicalRecordStore.shared.update { $0.conditions.removeAll { $0.id == entry.id } } }
            }
        }
        .onAppear {
            guard let entry else { return }
            name = entry.name
            since = entry.since
            notes = entry.notes ?? ""
        }
    }

    private func save() {
        var condition = entry ?? MedicalCondition(name: "")
        condition.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        condition.since = since
        condition.notes = optional(notes)
        MedicalRecordStore.shared.update { upsert(condition, in: &$0.conditions) }
    }
}

private struct AllergySheet: View {
    let entry: Allergy?
    @State private var substance = ""
    @State private var reaction = ""
    @State private var severity: Allergy.Severity?

    var body: some View {
        HomeInputSheet(title: entry == nil ? "Add allergy" : "Allergy", actionTitle: "Save",
                       isEnabled: substance.homeNonEmpty != nil, action: save) {
            HomeTextField(title: "Allergic to", text: $substance, prompt: "Penicillin")
            HomeTextField(title: "Reaction", text: $reaction, prompt: "Hives")
            RecordChoice(title: "How bad", options: Allergy.Severity.allCases, label: \.title, selection: $severity)
            if let entry {
                RecordRemoveButton("Remove allergy") { MedicalRecordStore.shared.update { $0.allergies.removeAll { $0.id == entry.id } } }
            }
        }
        .onAppear {
            guard let entry else { return }
            substance = entry.substance
            reaction = entry.reaction ?? ""
            severity = entry.severity
        }
    }

    private func save() {
        var allergy = entry ?? Allergy(substance: "")
        allergy.substance = substance.trimmingCharacters(in: .whitespacesAndNewlines)
        allergy.reaction = optional(reaction)
        allergy.severity = severity
        MedicalRecordStore.shared.update { upsert(allergy, in: &$0.allergies) }
    }
}

private struct VaccinationSheet: View {
    let entry: Vaccination?
    @State private var name = ""
    @State private var date = Date()
    @State private var dose = ""

    var body: some View {
        HomeInputSheet(title: entry == nil ? "Add vaccination" : "Vaccination", actionTitle: "Save",
                       isEnabled: name.homeNonEmpty != nil, action: save) {
            HomeTextField(title: "Vaccine", text: $name, prompt: "Influenza")
            ToolSettingsGroup(rows: [.date(String(localized: "Given on"), Binding(get: { date }, set: { date = $0 ?? date }))])
            HomeTextField(title: "Dose", text: $dose, prompt: "Booster")
            if let entry {
                RecordRemoveButton("Remove vaccination") { MedicalRecordStore.shared.update { $0.vaccinations.removeAll { $0.id == entry.id } } }
            }
        }
        .onAppear {
            guard let entry else { return }
            name = entry.name
            date = entry.date
            dose = entry.dose ?? ""
        }
    }

    private func save() {
        var shot = entry ?? Vaccination(name: "", date: date)
        shot.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        shot.date = date
        shot.dose = optional(dose)
        MedicalRecordStore.shared.update { upsert(shot, in: &$0.vaccinations) }
    }
}

private struct FamilyHistorySheet: View {
    let entry: FamilyHistoryEntry?
    @State private var relative: FamilyHistoryEntry.Relative?
    @State private var condition: FamilyHistoryEntry.Condition?
    @State private var age = ""
    @State private var note = ""

    var body: some View {
        HomeInputSheet(title: entry == nil ? "Add a relative" : "Family history", actionTitle: "Save",
                       isEnabled: relative != nil && condition != nil, action: save) {
            RecordChoice(title: "Who", options: FamilyHistoryEntry.Relative.allCases, label: \.title, selection: $relative)
            RecordChoice(title: "What they had", options: FamilyHistoryEntry.Condition.allCases, label: \.title, selection: $condition)
            HomeTextField(title: "Age when it was found", text: $age, prompt: "52")
#if os(iOS)
                .keyboardType(.numberPad)
#endif
            HomeTextField(title: condition == .other ? "What it was" : "Notes", text: $note, prompt: "Optional")
            if let entry {
                RecordRemoveButton("Remove relative") { MedicalRecordStore.shared.update { $0.familyHistory.removeAll { $0.id == entry.id } } }
            }
        }
        .onAppear {
            guard let entry else { return }
            relative = entry.relative
            condition = entry.condition
            age = entry.ageAtOnset.map(String.init) ?? ""
            note = entry.note ?? ""
        }
    }

    private func save() {
        guard let relative, let condition else { return }
        var row = entry ?? FamilyHistoryEntry(relative: relative, condition: condition)
        row.relative = relative
        row.condition = condition
        row.ageAtOnset = Int(age.trimmingCharacters(in: .whitespaces)).flatMap { (0...120).contains($0) ? $0 : nil }
        row.note = optional(note)
        MedicalRecordStore.shared.update { upsert(row, in: &$0.familyHistory) }
    }
}

private struct CareTeamSheet: View {
    let entry: CareTeamMember?
    @State private var name = ""
    @State private var role: CareTeamMember.Role?
    @State private var phone = ""
    @State private var email = ""

    var body: some View {
        HomeInputSheet(title: entry == nil ? "Add someone" : "Care team", actionTitle: "Save",
                       isEnabled: name.homeNonEmpty != nil && role != nil, action: save) {
            HomeTextField(title: "Name", text: $name, prompt: "Dr Maya Chen")
            RecordChoice(title: "Role", options: CareTeamMember.Role.allCases, label: \.title, selection: $role)
            HomeTextField(title: "Phone", text: $phone, prompt: "+1 650 555 0100")
#if os(iOS)
                .keyboardType(.phonePad)
#endif
            HomeTextField(title: "Email", text: $email, prompt: "Optional")
#if os(iOS)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
#endif
            if let entry {
                RecordRemoveButton("Remove from care team") { MedicalRecordStore.shared.update { $0.careTeam.removeAll { $0.id == entry.id } } }
            }
        }
        .onAppear {
            guard let entry else { return }
            name = entry.name
            role = entry.role
            phone = entry.phone ?? ""
            email = entry.email ?? ""
        }
    }

    private func save() {
        guard let role else { return }
        var member = entry ?? CareTeamMember(name: "", role: role)
        member.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        member.role = role
        member.phone = optional(phone)
        member.email = optional(email)
        MedicalRecordStore.shared.update { upsert(member, in: &$0.careTeam) }
    }
}

// MARK: - Fields

/// One choice among an enum's cases, as the sheets' chips.
struct RecordChoice<Value: Hashable>: View {
    let title: String
    let options: [Value]
    let label: (Value) -> String
    @Binding var selection: Value?

    init(title: String, options: [Value], label: @escaping (Value) -> String, selection: Binding<Value?>) {
        self.title = title
        self.options = options
        self.label = label
        self._selection = selection
    }

    var body: some View {
        HomeChipGroup(
            title: title,
            options: options.map(label),
            chosen: Binding(
                get: { selection.map { [label($0)] } ?? [] },
                set: { chosen in selection = options.first { chosen.contains(label($0)) } }
            ),
            single: true
        )
    }
}

/// The destructive line at the foot of an editor.
struct RecordRemoveButton: View {
    let title: String
    let action: () -> Void

    @Environment(\.dismiss) private var dismiss

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(role: .destructive) {
            action()
            dismiss()
        } label: {
            Text(title)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }
}

#Preview("Medical record") {
    NavigationStack { MedicalRecordPage() }
}
