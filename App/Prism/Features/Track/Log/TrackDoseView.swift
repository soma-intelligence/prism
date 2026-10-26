//
//  TrackDoseView.swift
//  Prism
//

import SwiftUI
import SomaUI

/// Dose log: the amount is a gauge turned to the dose, and the day's plan
/// runs underneath as a line of stops, taken ones filled.
///
/// Opened on a supplement already on the plan, it logs a dose of it. Opened
/// with none, it adds one to the plan: its name, unit, amount and usual
/// time. The amount and the rhythm are what the person declares, never
/// a number Soma suggests. Kept in ``TrackLogStore``: Apple Health has no
/// type for a supplement.
///
/// Each supplement on the plan can carry a reminder at its usual time, on
/// the days its rhythm calls for, with a "Taken" action that logs the dose
/// from the notification (``MedicationReminders``). The medications in
/// Apple Health's list show beside the plan once the person shares them,
/// and a supplement that meets one of them in ``MedicationInteractions``
/// gets a note. Informational only: no amount is ever proposed.
struct TrackDoseView: View {
    let supplementID: UUID?

    @Environment(\.somaTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var unit = TrackDoseUnit.grams
    @State private var amount = 0.0
    @State private var time = Date.now
    @State private var remindsNew = false
    @State private var loaded = false
    @State private var healthMedications: [HealthMedication] = []

    private let log = TrackLogStore.shared

    private var supplement: TrackSupplement? {
        supplementID.flatMap { id in log.supplements.first { $0.id == id } }
    }

    var body: some View {
        let metrics = theme.metrics
        let type = theme.typography
        let colors = theme.colors

        TrackEntryPage(title: supplement?.name ?? "Add a supplement") {
            if supplement == nil {
                VStack(spacing: metrics.spaceS) {
                    TextField("Name, as on the label", text: $name)
                        .somaFont(type.body)
                        .foregroundStyle(colors.inkPrimary.color)
                        .padding(.horizontal, metrics.cardPadding)
                        .frame(minHeight: metrics.minimumTapTarget + metrics.cardSpacing)
                        .background(RoundedRectangle(cornerRadius: metrics.cardCornerRadius, style: .continuous).fill(colors.surface.color))
                    HStack(spacing: metrics.spaceS) {
                        ForEach(TrackDoseUnit.allCases, id: \.self) { choice in
                            SomaChoiceChip(choice.symbol, isOn: unit == choice) {
                                unit = choice
                                amount = min(amount, choice.range.upperBound)
                            }
                        }
                    }
                }
            }

            SomaArcDial(
                value: $amount,
                range: unit.range,
                step: unit.step,
                style: .gauge(tick: tick, label: tick * 5),
                aspect: .body,
                label: "Amount"
            ) {
                SomaReadout(amount > 0 ? SomaArcDial<EmptyView>.number(amount) : nil, unit: unit.symbol,
                            caption: supplement.map { "Usually \(SomaArcDial<EmptyView>.number($0.amount)) \($0.unit.symbol)" })
            }

            if supplement == nil {
                SomaCard {
                    VStack(spacing: metrics.cardSpacing) {
                        DatePicker(selection: $time, displayedComponents: .hourAndMinute) {
                            Text("Usually taken at")
                                .somaFont(type.body)
                                .foregroundStyle(colors.inkPrimary.color)
                        }
                        .tint(colors.accent.color)
                        // Soma reads the clock on 24 hours, whatever the region.
                        .environment(\.locale, Locale(identifier: "en_GB"))
                        TrackHairline()
                        Toggle(isOn: $remindsNew) {
                            Text("Remind me at that time")
                                .somaFont(type.body)
                                .foregroundStyle(colors.inkPrimary.color)
                        }
                        .toggleStyle(.soma)
                        .tint(colors.accent.color)
                    }
                }
            }

            dayLine

            reminders

            healthList

            ForEach(medicationNotes) { note in
                TrackNote(lead: "\(note.supplement) and \(note.subject).", rest: "\(note.text) Source: \(note.source).")
            }

            TrackNote(lead: "Kept in Soma. Apple Health has no place for a supplement.")
        } footer: {
            SomaActionButton(actionTitle) { save() }
                .disabled(amount <= 0 || (supplement == nil && name.trimmingCharacters(in: .whitespaces).isEmpty))
        }
        .onAppear(perform: load)
        .task { healthMedications = await MedicationHealth.medications() }
    }

    /// The supplements the reminders cover: the one opened, or the whole
    /// plan when the page adds a new one.
    private var reminded: [TrackSupplement] {
        if let supplement { return [supplement] }
        return log.activeSupplements
    }

    /// A switch per supplement: a reminder at its usual time on each day its
    /// rhythm calls for, and when the next one comes.
    @ViewBuilder
    private var reminders: some View {
        let metrics = theme.metrics
        let type = theme.typography
        let colors = theme.colors
        let items = reminded

        if !items.isEmpty {
            VStack(alignment: .leading, spacing: metrics.cardSpacing) {
                TrackEyebrow(supplement == nil ? "Reminders on your plan" : "Reminder")
                SomaCard {
                    VStack(spacing: metrics.cardSpacing) {
                        ForEach(items) { item in
                            Toggle(isOn: Binding(get: { item.reminds == true }, set: { setReminds($0, item) })) {
                                VStack(alignment: .leading, spacing: metrics.spaceXS) {
                                    Text(item.name)
                                        .somaFont(type.body)
                                        .foregroundStyle(colors.inkPrimary.color)
                                    Text(reminderDetail(item))
                                        .somaFont(type.caption)
                                        .foregroundStyle(colors.inkSecondary.color)
                                }
                            }
                            .toggleStyle(.soma)
                            .tint(colors.accent.color)
                            if item.id != items.last?.id { TrackHairline() }
                        }
                    }
                }
                Text("Press and hold a reminder to mark the dose taken without opening Soma.")
                    .somaFont(type.caption)
                    .foregroundStyle(colors.inkSecondary.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// "5 mg at 08:00, next Monday, 08:00", or the time alone while the
    /// reminder is off.
    private func reminderDetail(_ item: TrackSupplement) -> String {
        let usual = "\(SomaArcDial<EmptyView>.number(item.amount)) \(item.unit.symbol) at \(TrackClock.hour(Double(item.minute) / 60))"
        guard item.reminds == true else { return usual }
        guard let next = MedicationSchedule.next(for: item, after: .now) else { return usual }
        let day = TrackClock.day(next)
        return "\(usual), next \(day == "Today" ? "today" : day), \(TrackClock.time(next))"
    }

    private func setReminds(_ reminds: Bool, _ item: TrackSupplement) {
        log.setReminds(reminds, supplement: item.id)
        Task { await MedicationReminders.sync(asking: reminds) }
    }

    /// Apple Health's medications that are not on the plan, and the way to
    /// share them. Adding a supplement, a tap on one fills the name.
    @ViewBuilder
    private var healthList: some View {
        let metrics = theme.metrics
        let type = theme.typography
        let colors = theme.colors
        let onlyInHealth = MedicationList.merged(supplements: log.supplements, health: healthMedications)
            .filter { $0.supplementID == nil }

        VStack(alignment: .leading, spacing: metrics.cardSpacing) {
            TrackEyebrow("In Apple Health")
            SomaCard {
                VStack(spacing: metrics.cardSpacing) {
                    ForEach(onlyInHealth) { entry in
                        Button {
                            if supplement == nil { name = entry.name }
                        } label: {
                            HStack(spacing: metrics.cardSpacing) {
                                Text(entry.name)
                                    .somaFont(type.body)
                                    .foregroundStyle(colors.inkPrimary.color)
                                Spacer()
                                Text(entry.takenToday ? "Taken today" : "Medication")
                                    .somaFont(type.caption)
                                    .foregroundStyle(colors.inkSecondary.color)
                            }
                            .frame(minHeight: metrics.minimumTapTarget)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.somaGlassPressDim)
                        .disabled(supplement != nil)
                        TrackHairline()
                    }
                    Button {
                        Task {
                            try? await HealthAccess.requestMedications()
                            healthMedications = await MedicationHealth.medications()
                        }
                    } label: {
                        Text(onlyInHealth.isEmpty ? "Show my medications" : "Choose which medications to show")
                            .somaFont(type.body)
                            .foregroundStyle(colors.accent.color)
                            .frame(maxWidth: .infinity, minHeight: metrics.minimumTapTarget, alignment: .leading)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.somaGlassPressDim)
                }
            }
            Text("Read only. Their schedules and reminders stay in Health.")
                .somaFont(type.caption)
                .foregroundStyle(colors.inkSecondary.color)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// What a supplement on the plan is worth knowing beside a medication
    /// in Apple Health or on the plan.
    private var medicationNotes: [InteractionNote] {
        let medications = healthMedications.filter { !$0.isArchived }.map(\.name) + log.activeSupplements.map(\.name)
        return MedicationInteractions.notes(for: reminded, markers: [], medications: medications)
    }

    private var actionTitle: String {
        if supplement == nil { return "Add to the plan" }
        return amount > 0 ? "Log \(SomaArcDial<EmptyView>.number(amount)) \(unit.symbol)" : "Log"
    }

    private var tick: Double {
        let span = unit.range.upperBound - unit.range.lowerBound
        return span / 20
    }

    /// Today's plan, in order, as stops on a line.
    private var dayLine: some View {
        let metrics = theme.metrics
        let type = theme.typography
        let colors = theme.colors
        let now = Date.now
        let due = log.activeSupplements.filter { TrackAdherence.isDue($0.cadence, on: now, startedOn: $0.startedOn, calendar: .current) }

        return Group {
            if !due.isEmpty {
                VStack(alignment: .leading, spacing: metrics.cardSpacing) {
                    TrackEyebrow("Today")
                    ZStack(alignment: .top) {
                        Rectangle()
                            .fill(colors.inkPrimary.color.opacity(metrics.browseSeparatorOpacity))
                            .frame(height: 1)
                            .padding(.horizontal, metrics.leadSpacing)
                            .padding(.top, metrics.knobDiameter / 2)
                        HStack(alignment: .top, spacing: 0) {
                            ForEach(due) { item in
                                let taken = log.dose(of: item, on: now)
                                let isCurrent = item.id == supplementID
                                VStack(spacing: metrics.spaceXS) {
                                    ZStack {
                                        if isCurrent {
                                            Circle().strokeBorder(colors.accent.color, lineWidth: 1.5)
                                            Circle().fill(colors.accent.color).padding(metrics.aspectDotSize)
                                        } else if taken != nil {
                                            Circle().fill(colors.inkPrimary.color).padding(metrics.aspectDotSize)
                                        } else {
                                            Circle().strokeBorder(colors.inkSecondary.color, lineWidth: 1.5).padding(metrics.aspectDotSize)
                                        }
                                    }
                                    .frame(width: metrics.knobDiameter, height: metrics.knobDiameter)
                                    .background(Circle().fill(colors.canvas.color))
                                    Text(item.name)
                                        .somaFont(type.tabLabel)
                                        .foregroundStyle(isCurrent ? colors.accent.color : colors.inkPrimary.color)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                    Text(isCurrent ? "Now" : taken.map { TrackClock.time($0.date) } ?? TrackClock.hour(Double(item.minute) / 60))
                                        .somaFont(type.captionValue)
                                        .foregroundStyle(colors.inkSecondary.color)
                                }
                                .frame(maxWidth: .infinity)
                                .accessibilityElement(children: .combine)
                            }
                        }
                    }
                }
            }
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let supplement {
            unit = supplement.unit
            amount = supplement.amount
        }
    }

    private func save() {
        let now = Date.now
        if let supplement {
            log.logDose(name: supplement.name, amount: amount, unit: unit, supplementID: supplement.id, at: now)
        } else {
            let parts = Calendar.current.dateComponents([.hour, .minute], from: time)
            let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            if let added = log.addSupplement(name: name, amount: amount, unit: unit, minute: minute, startedOn: now), remindsNew {
                log.setReminds(true, supplement: added.id)
            }
        }
        // A dose logged drops today's reminder; a new one may add its own.
        Task { await MedicationReminders.sync(asking: remindsNew) }
        dismiss()
    }
}

#if DEBUG
#Preview("Dose") {
    NavigationStack { TrackDoseView(supplementID: nil) }
}
#endif
