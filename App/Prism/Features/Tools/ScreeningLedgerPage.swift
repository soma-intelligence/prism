//
//  ScreeningLedgerPage.swift
//  Prism
//

import SwiftUI
import SomaUI

/// Screening Ledger: the checks recommended for the person's age and sex, which
/// are due, which are done and when they come back, and the ones worth raising
/// with a doctor.
///
/// A screening catalog and due engine, on United States Preventive
/// Services Task Force cadences; a family history answer moves a start age or
/// a cadence the way the guidelines say. The record stays on the phone.
struct ScreeningLedgerPage: View {
    @Environment(HealthDashboard.self) private var health
    @Environment(\.somaTheme) private var theme
    @State private var recording: SomaTools.ScreeningItem?
    @State private var history = false
    /// True while the two questions (date of birth, sex) are open on this
    /// visit. Set once, on the first appearance that found one missing, so
    /// the rows stay put while the person answers them.
    @State private var asking = false

    private var model: ToolsModel { .shared }
    private var store: ToolsStore { .shared }

    var body: some View {
        let record = store.record.screening
        let now = model.current.now
        let profile = ScreeningReminders.profile(now: now)
        let ledger = ScreeningReminders.ledger
        let schedule = SomaTools.ScreeningSchedule.due(for: profile, ledger: ledger, now: now)
        let sex = SomaTools.ScreeningSchedule.eligibility(profile.sex)
        let age = profile.age(on: now).flatMap { $0 > 0 ? $0 : nil }
        let statuses = age.map { ledger.statuses(age: $0, sex: sex, today: now, birthday: profile.birthday) } ?? []
        let due = statuses.filter { $0.item.tier == .recommended && $0.isDue }
        let done = statuses.filter { $0.lastDone != nil && !$0.isDue }
        let discuss = statuses.filter { $0.item.tier == .discuss }
        let missing = SomaTools.ScreeningSchedule.missing(profile)

        ToolPage(ToolKind.screeningLedger.title) {
            if let age {
                ToolHero(eyebrow: "\(due.count) due · \(done.count) done",
                         headline: due.isEmpty ? "Nothing is due." : "\(ToolFormat.capitalized(ToolFormat.words(due.count))) screening\(due.count == 1 ? " is" : "s are") due.",
                         lead: due.first.map { "\($0.item.title) matters most at \(age)\($0.lastDone == nil ? ", and it has never been recorded" : "")." }
                            ?? "Everything recommended for your age is recorded.",
                         rest: missing.sex ? "Say your sex below and the list narrows to what applies." : nil)
            } else {
                ToolHero(headline: "The ledger needs your age.",
                         lead: "Add your date of birth below. It stays on this phone.",
                         rest: nil)
            }
            ToolStats([
                SomaStat("Due", value: age == nil ? nil : "\(due.count)"),
                SomaStat("Done", value: age == nil ? nil : "\(done.count)"),
                SomaStat("Ask about", value: age == nil ? nil : "\(discuss.count)"),
            ])

            if asking {
                questions(record)
            }

            if age != nil {
                ToolEyebrow("Your screening year")
                ScreeningCalendarView(dues: schedule, now: now)
            }

            if !due.isEmpty {
                ToolEyebrow("Due now")
                statusGroup(due, tone: .danger, ledger: record.ledger)
            }
            if !done.isEmpty {
                ToolEyebrow("Done, and when it comes back")
                statusGroup(done, tone: .plain, ledger: record.ledger)
            }
            let rest = statuses.filter { status in !due.contains { $0.id == status.id } && !done.contains { $0.id == status.id } && status.item.tier == .recommended }
            if !rest.isEmpty {
                ToolEyebrow("Later")
                statusGroup(rest, tone: .plain, ledger: record.ledger)
            }
            if !discuss.isEmpty {
                ToolEyebrow("Worth raising with your doctor")
                statusGroup(discuss, tone: .plain, ledger: record.ledger)
            }

            ToolButtonRow(title: "Family history",
                          detail: "\(ledger.riskAnswers.count) of \(SomaTools.ScreeningRiskFlag.allCases.count) answered") { history = true }
            ToolFootnote("US guidelines. Not medical advice.")
            ToolLinkRow(title: "About Screening Ledger", detail: nil, value: ToolRoute.intro(.screeningLedger))
        }
        .sheet(item: $recording) { item in
            ScreeningRecordSheet(item: item, canRemind: schedule.contains { $0.id == item.id })
        }
        .sheet(isPresented: $history) { ScreeningHistorySheet() }
        .task {
            store.markOpened(.screeningLedger)
            await model.load(health)
            let after = SomaTools.ScreeningSchedule.missing(ScreeningReminders.profile(now: model.current.now))
            if after.age || after.sex { asking = true }
            await ScreeningReminders.sync()
        }
        .onChange(of: store.record.screening) { Task { await ScreeningReminders.sync() } }
        .onChange(of: MedicalRecordStore.shared.familyHistory) { Task { await ScreeningReminders.sync() } }
    }

    /// The two answers the schedule needs when the profile and Apple Health
    /// hold neither, asked once and kept with the ledger on this phone.
    @ViewBuilder
    private func questions(_ record: ScreeningRecord) -> some View {
        let rows = questionRows(record)
        if !rows.isEmpty {
            ToolEyebrow("About you")
            ToolSettingsGroup(rows: rows)
        }
    }

    private func questionRows(_ record: ScreeningRecord) -> [ToolSettingsGroup.Row] {
        let base = SomaProfileStore.shared.profile
        var rows: [ToolSettingsGroup.Row] = []
        if base.birthday == nil && model.current.ageYears == nil {
            rows.append(.date("Date of birth", Binding(get: { store.record.screening.birthday },
                                                       set: { born in store.update { $0.screening.birthday = born } })))
        }
        if base.sex == nil {
            rows += BiologicalSex.allCases.map { sex in
                .choice(sex.title, record.sex == sex.rawValue, { store.update { $0.screening.sex = sex.rawValue } })
            }
        }
        return rows
    }

    private func statusGroup(_ list: [SomaTools.ScreeningDueEngine.Status], tone: ToolTone, ledger: SomaTools.ScreeningLedger) -> some View {
        SomaCard {
            VStack(alignment: .leading, spacing: theme.metrics.cardHeaderSpacing) {
                ForEach(Array(list.enumerated()), id: \.element.id) { index, status in
                    if index > 0 { ToolHairline() }
                    Button { recording = status.item } label: {
                        ToolRowView(row: ToolRow(
                            title: status.item.title,
                            detail: Self.detail(status, remindsOf: ledger.remindsOf(status.item.id)),
                            value: SomaTools.ScreeningDueEngine.statusText(status) { $0.formatted(.dateTime.month(.wide).year()) },
                            tone: status.isDue ? tone : .plain), aspect: .heart)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// The row's second line, with the reminder named when one is on.
    static func detail(_ status: SomaTools.ScreeningDueEngine.Status, remindsOf: Bool) -> String? {
        let line = SomaTools.ScreeningDueEngine.subline(status) { $0.formatted(.dateTime.month(.wide).year()) }
        guard remindsOf else { return line }
        let reminder = String(localized: "Reminder on")
        return line.map { $0 + " \u{00B7} " + reminder } ?? reminder
    }
}

/// The screening reminders as the phone holds them: the screenings the person
/// asked about on the ledger, re-derived whole whenever the ledger, the
/// profile or the switch changes, so what is pending always matches the page.
/// Outside the planner's managed set, like the pollen alert.
@MainActor
enum ScreeningReminders {
    /// The profile the ledger reads: the person's own, with the answers the
    /// ledger asked for and Apple Health's age filling its gaps.
    static func profile(now: Date = Date()) -> SomaProfile {
        let record = ToolsStore.shared.record.screening
        return SomaTools.ScreeningSchedule.resolved(
            SomaProfileStore.shared.profile, askedSex: record.sex, askedBirthday: record.birthday,
            healthAgeYears: ToolsModel.shared.current.ageYears, now: now)
    }

    /// The ledger the schedule reads: the answers given here, with the
    /// family history written in the medical record folded in, and the Lab's
    /// calcium scores and bone scans counted as done.
    static var ledger: SomaTools.ScreeningLedger {
        ToolsStore.shared.record.screening.ledger.withFamilyHistory(MedicalRecordStore.shared.screeningRisks)
            .withResults(FunctionalResultStore.shared.screeningRecords)
    }

    /// - Parameter asking: true when a person just turned a reminder on: the
    ///   notification permission is asked then, in context, if it never was.
    static func sync(asking: Bool = false) async {
        let notifications = SomaNotifications.shared
        if asking {
            await notifications.apply(asking: true)
        } else {
            await notifications.refreshAuthorization()
        }
        let now = Date()
        let ledger = Self.ledger
        let planned = ScreeningReminderRules.reminders(
            for: SomaTools.ScreeningSchedule.due(for: profile(now: now), ledger: ledger, now: now),
            optedIn: ledger.reminders, schedule: notifications.schedule,
            prefs: notifications.settings.notifications, now: now)
        let scheduler = notifications.scheduler
        let stale = await scheduler.pendingIdentifiers().filter { $0.hasPrefix(ScreeningReminderRules.prefix) }
        await scheduler.remove(stale)
        guard notifications.isOn else { return }
        for item in planned {
            try? await scheduler.add(item)
        }
    }
}


/// Recording that a screening was done.
struct ScreeningRecordSheet: View {
    let item: SomaTools.ScreeningItem
    /// False for a screening that can never come due (a discuss item, or one
    /// gated on an unanswered risk), which has nothing to remind of.
    var canRemind = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.somaTheme) private var theme
    @State private var date = Date()

    private var store: ToolsStore { .shared }

    var body: some View {
        let past = store.record.screening.ledger.records(for: item.id)
        NavigationStack {
            ListScaffold(eyebrow: "Screening Ledger", title: LocalizedStringResource(stringLiteral: item.title)) {
                ToolNoteCard(lead: item.evidence, foot: item.citation)
                if canRemind {
                    ToolSettingsGroup(rows: [
                        .toggle("Remind me", Binding(
                            get: { store.record.screening.ledger.remindsOf(item.id) },
                            set: { on in
                                store.update { $0.screening.ledger.setReminder(on, itemID: item.id) }
                                Task { await ScreeningReminders.sync(asking: on) }
                            }))
                    ])
                    ToolFootnote("At \(ScreeningReminderRules.morning.text), \(ScreeningReminderRules.leadDays) days before it comes due and on the day.")
                }
                SomaCard {
                    DatePicker(selection: $date, in: ...Date(), displayedComponents: .date) {
                        Text("Done on")
                            .somaFont(theme.typography.body)
                            .foregroundStyle(theme.colors.inkPrimary.color)
                    }
                }
                if !past.isEmpty {
                    ToolEyebrow("Recorded")
                    ToolSettingsGroup(rows: past.map { done in
                        .choice("Remove \(done.performedOn.formatted(date: .long, time: .omitted))", false, {
                            store.update { $0.screening.ledger.delete(recordID: done.id) }
                        })
                    })
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Record") {
                        store.update { $0.screening.ledger.log(itemID: item.id, performedOn: date) }
                        dismiss()
                    }
                }
            }
        }
    }
}

/// The family history questions that move a cadence.
struct ScreeningHistorySheet: View {
    @Environment(\.dismiss) private var dismiss

    private var store: ToolsStore { .shared }

    var body: some View {
        let ledger = ScreeningReminders.ledger
        let fromRecord = MedicalRecordStore.shared.screeningRiskFlags
        NavigationStack {
            ListScaffold(eyebrow: "Screening Ledger", title: "Family history") {
                ToolReason(lead: "Each yes can start a screening earlier or bring it back sooner.",
                           rest: fromRecord.isEmpty ? nil : "Relatives in your medical record count here too, and keep their answer on.")
                ToolSettingsGroup(rows: SomaTools.ScreeningRiskFlag.allCases.map { flag in
                    .toggle(flag.label, Binding(get: { ledger.answer(for: flag)?.isPresent ?? false },
                                                set: { on in store.update { $0.screening.ledger.answer(flag: flag, isPresent: on) } }))
                })
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
