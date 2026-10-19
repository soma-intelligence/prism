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

    private var model: ToolsModel { .shared }
    private var store: ToolsStore { .shared }

    var body: some View {
        let record = store.record.screening
        let sex = record.sex.flatMap(SomaTools.ScreeningEligibility.from(profileSex:))
        let age = model.current.ageYears.map { Int($0) }
        let statuses = age.map { record.ledger.statuses(age: $0, sex: sex, today: model.current.now) } ?? []
        let due = statuses.filter { $0.item.tier == .recommended && $0.isDue }
        let done = statuses.filter { $0.lastDone != nil && !$0.isDue }
        let discuss = statuses.filter { $0.item.tier == .discuss }

        ToolPage(ToolKind.screeningLedger.title) {
            if let age {
                ToolHero(eyebrow: "\(due.count) due · \(done.count) done",
                         headline: due.isEmpty ? "Nothing is due." : "\(ToolFormat.capitalized(ToolFormat.words(due.count))) screening\(due.count == 1 ? " is" : "s are") due.",
                         lead: due.first.map { "\($0.item.title) matters most at \(age)\($0.lastDone == nil ? ", and it has never been recorded" : "")." }
                            ?? "Everything recommended for your age is recorded.",
                         rest: record.sex == nil ? "Say your sex below and the list narrows to what applies." : nil)
            } else {
                ToolHero(headline: "The ledger needs your age.",
                         lead: "It reads your date of birth from Apple Health, and none is set there.",
                         rest: "Add it in the Health app under your profile.")
            }
            ToolStats([
                SomaStat("Due", value: age == nil ? nil : "\(due.count)"),
                SomaStat("Done", value: age == nil ? nil : "\(done.count)"),
                SomaStat("Ask about", value: age == nil ? nil : "\(discuss.count)"),
            ])

            if record.sex == nil {
                ToolSettingsGroup(rows: [
                    .choice("Female", false, { store.update { $0.screening.sex = "female" } }),
                    .choice("Male", false, { store.update { $0.screening.sex = "male" } }),
                ])
            }

            if !due.isEmpty {
                ToolEyebrow("Due now")
                statusGroup(due, tone: .danger)
            }
            if !done.isEmpty {
                ToolEyebrow("Done, and when it comes back")
                statusGroup(done, tone: .plain)
            }
            let rest = statuses.filter { status in !due.contains { $0.id == status.id } && !done.contains { $0.id == status.id } && status.item.tier == .recommended }
            if !rest.isEmpty {
                ToolEyebrow("Later")
                statusGroup(rest, tone: .plain)
            }
            if !discuss.isEmpty {
                ToolEyebrow("Worth raising with your doctor")
                statusGroup(discuss, tone: .plain)
            }

            ToolButtonRow(title: "Family history",
                          detail: "\(record.ledger.riskAnswers.count) of \(SomaTools.ScreeningRiskFlag.allCases.count) answered") { history = true }
            ToolFootnote("US guidelines. Not medical advice.")
            ToolLinkRow(title: "About Screening Ledger", detail: nil, value: ToolRoute.intro(.screeningLedger))
        }
        .sheet(item: $recording) { item in ScreeningRecordSheet(item: item) }
        .sheet(isPresented: $history) { ScreeningHistorySheet() }
        .task {
            store.markOpened(.screeningLedger)
            await model.load(health)
        }
    }

    private func statusGroup(_ list: [SomaTools.ScreeningDueEngine.Status], tone: ToolTone) -> some View {
        SomaCard {
            VStack(alignment: .leading, spacing: theme.metrics.cardHeaderSpacing) {
                ForEach(Array(list.enumerated()), id: \.element.id) { index, status in
                    if index > 0 { ToolHairline() }
                    Button { recording = status.item } label: {
                        ToolRowView(row: ToolRow(
                            title: status.item.title,
                            detail: SomaTools.ScreeningDueEngine.subline(status) { $0.formatted(.dateTime.month(.wide).year()) },
                            value: SomaTools.ScreeningDueEngine.statusText(status) { $0.formatted(.dateTime.month(.wide).year()) },
                            tone: status.isDue ? tone : .plain), aspect: .heart)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}


/// Recording that a screening was done.
struct ScreeningRecordSheet: View {
    let item: SomaTools.ScreeningItem

    @Environment(\.dismiss) private var dismiss
    @Environment(\.somaTheme) private var theme
    @State private var date = Date()

    private var store: ToolsStore { .shared }

    var body: some View {
        let past = store.record.screening.ledger.records(for: item.id)
        NavigationStack {
            ListScaffold(eyebrow: "Screening Ledger", title: LocalizedStringResource(stringLiteral: item.title)) {
                ToolNoteCard(lead: item.evidence, foot: item.citation)
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
        let ledger = store.record.screening.ledger
        NavigationStack {
            ListScaffold(eyebrow: "Screening Ledger", title: "Family history") {
                ToolReason(lead: "Each yes can start a screening earlier or bring it back sooner.", rest: nil)
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
