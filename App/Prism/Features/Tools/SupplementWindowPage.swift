//
//  SupplementWindowPage.swift
//  Prism
//

import SwiftUI
import SomaUI

/// Supplement Window: each supplement placed around the wake time where it
/// absorbs best, what is taken today, and what is left.
///
/// A timing catalog: fat-soluble vitamins with a meal, magnesium before
/// bed, iron away from calcium and zinc, creatine at any meal. The slots hang
/// off the person's habitual wake time from their nights.
struct SupplementWindowPage: View {
    @Environment(HealthDashboard.self) private var health
    @Environment(\.somaTheme) private var theme
    @State private var adding = false
    @State private var reminded = false

    private var model: ToolsModel { .shared }
    private var store: ToolsStore { .shared }

    var body: some View {
        let day = ToolDay(inputs: model.current, cups: TrackLogStore.shared.caffeineCups, sleepNeedHours: health.scores?.sleepNeedHours)
        let items = store.record.supplements
        let plan = SomaTools.SupplementTimingEngine.plan(forSelectedIDs: items.map(\.id))
        let wakeMinutes = day.habitualWakeHour.map { Int(($0 * 60).rounded()) }
        let wake = SomaTools.SupplementTimingEngine.wake(on: day.inputs.now, wakeMinutes: wakeMinutes, calendar: day.calendar)
        let lines = items.map { line(for: $0, wake: wake, calendar: day.calendar) }
        let left = lines.filter { $0.taken == nil }.sorted { $0.time < $1.time }
        let next = left.first { $0.time > day.inputs.now } ?? left.first

        ToolPage(ToolKind.supplementWindow.title) {
            if items.isEmpty {
                ToolHero(eyebrow: "Nothing on the list",
                         headline: "Add what you take, and it finds each one a time.",
                         lead: "Each supplement is placed from your wake time and your meals, where it absorbs best.",
                         rest: "Nothing buzzes unless you ask it to.")
            } else {
                ToolHero(eyebrow: "\(lines.count - left.count) of \(lines.count) taken",
                         headline: next.map { "\($0.item.name) is \(left.count == 1 ? "the one" : "next") left, at \(ToolFormat.clock($0.time))." } ?? "Everything is taken today.",
                         lead: "Each supplement is placed from your \(ToolFormat.clock(wake)) wake and your meals, where it absorbs best.",
                         rest: plan.conflicts.first.map { conflict in
                             SomaTools.SupplementTimingEngine.conflictSentence(conflict) { id in
                                 items.first { $0.id == id }?.name ?? id
                             }
                         })
                SomaCard {
                    VStack(alignment: .leading, spacing: theme.metrics.cardHeaderSpacing) {
                        Text("Your day")
                            .somaFont(theme.typography.eyebrow)
                            .foregroundStyle(theme.colors.inkSecondary.color)
                        ToolSlotRail(slots: plan.slots.map { slot in
                            let time = SomaTools.SupplementTimingEngine.time(for: slot.slot, wake: wake, calendar: day.calendar)
                            let taken = lines.filter { slot.entryIDs.contains($0.item.id) }.allSatisfy { $0.taken != nil }
                            return ToolSlotRail.Slot(label: slot.slot.label, time: ToolFormat.clock(time), isDone: taken)
                        })
                    }
                }
            }

            ToolEyebrow("Your supplements")
            if !items.isEmpty {
                SomaCard {
                    VStack(alignment: .leading, spacing: theme.metrics.cardHeaderSpacing) {
                        ForEach(Array(lines.enumerated()), id: \.element.item.id) { index, line in
                            if index > 0 { ToolHairline() }
                            Button { toggle(line) } label: {
                                ToolRowView(row: ToolRow(title: "\(line.item.name)\(line.item.dose.isEmpty ? "" : ", \(line.item.dose)")",
                                                         detail: line.slotLabel,
                                                         value: line.taken.map { "Taken \(ToolFormat.clock($0))" } ?? ToolFormat.clock(line.time)),
                                            aspect: .gut)
                                    .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            ToolButtonRow(title: "Add a supplement", detail: nil) { adding = true }
            if let next {
                ToolNextCard(eyebrow: "Next", aspect: .gut, title: "\(next.item.name) at \(ToolFormat.clock(next.time))",
                             detail: "One nudge at the time, then quiet.",
                             actionTitle: reminded ? "Reminder set" : "Remind me",
                             action: {
                                 Task {
                                     reminded = await ToolNotifier.remind(id: "supplement-\(next.item.id)", title: next.item.name,
                                                                          body: next.slotLabel, at: next.time)
                                 }
                             })
            }
            ToolLinkRow(title: "About Supplement Window", detail: nil, value: ToolRoute.intro(.supplementWindow))
        }
        .sheet(isPresented: $adding) { SupplementAddSheet() }
        .task {
            store.markOpened(.supplementWindow)
            await model.load(health)
        }
    }

    struct Line {
        var item: SupplementItem
        var time: Date
        var slotLabel: String
        var taken: Date?
    }

    private func line(for item: SupplementItem, wake: Date, calendar: Calendar) -> Line {
        let entry = SomaTools.SupplementTimingCatalog.entry(id: item.id)
        let slot = entry?.preferredSlot ?? .withBreakfast
        let taken = store.record.taken[item.id]?.last { calendar.isDateInToday($0) }
        return Line(item: item, time: SomaTools.SupplementTimingEngine.time(for: slot, wake: wake, calendar: calendar),
                    slotLabel: slot.label, taken: taken)
    }

    private func toggle(_ line: Line) {
        let calendar = Calendar.current
        store.update { record in
            var moments = record.taken[line.item.id] ?? []
            if line.taken != nil {
                moments.removeAll { calendar.isDateInToday($0) }
            } else {
                moments.append(Date())
            }
            record.taken[line.item.id] = Array(moments.suffix(60))
        }
    }
}

/// The day's slots on one rail: filled when taken, a ring when still to come.
struct ToolSlotRail: View {
    struct Slot: Identifiable {
        var id: String { label }
        var label: String
        var time: String
        var isDone: Bool
    }

    let slots: [Slot]

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let hue = theme.aspects[.gut].identity.color
        let dot = theme.metrics.chartDotDiameter + 4
        HStack(alignment: .top, spacing: 0) {
            ForEach(slots) { slot in
                VStack(spacing: 4) {
                    Text(slot.time)
                    Circle()
                        .strokeBorder(hue, lineWidth: 2)
                        .background(Circle().fill(slot.isDone ? hue : .clear))
                        .frame(width: dot, height: dot)
                    Text(slot.label)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
                .accessibilityValue(slot.isDone ? "Taken" : "To come")
            }
        }
        .somaFont(theme.typography.caption)
        .foregroundStyle(theme.colors.inkSecondary.color)
    }
}

/// Adding a supplement from the timing catalog.
struct SupplementAddSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.somaTheme) private var theme
    @State private var chosen: String?
    @State private var dose = ""

    private var store: ToolsStore { .shared }

    var body: some View {
        let listed = Set(store.record.supplements.map(\.id))
        let entries = SomaTools.SupplementTimingCatalog.all.filter { $0.id != "coffee" }
        NavigationStack {
            ListScaffold(eyebrow: "Supplement Window", title: "Add a supplement") {
                ToolSettingsGroup(rows: entries.map { entry in
                    .choice(listed.contains(entry.id) ? "\(entry.name), on your list" : entry.name,
                            chosen == entry.id, { chosen = entry.id })
                })
                if let chosen, let entry = SomaTools.SupplementTimingCatalog.entry(id: chosen) {
                    ToolNoteCard(title: entry.preferredSlot.label, lead: entry.reason)
                }
                SomaCard {
                    TextField("Dose, such as 200 mg", text: $dose)
                        .somaFont(theme.typography.body)
                }
                if !listed.isEmpty {
                    ToolEyebrow("On your list")
                    ToolSettingsGroup(rows: store.record.supplements.map { item in
                        .choice("Remove \(item.name)", false, { store.update { $0.supplements.removeAll { $0.id == item.id } } })
                    })
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        if let chosen, let entry = SomaTools.SupplementTimingCatalog.entry(id: chosen), !listed.contains(chosen) {
                            store.update { $0.supplements.append(SupplementItem(id: entry.id, name: entry.name, dose: dose)) }
                        }
                        dismiss()
                    }
                    .disabled(chosen == nil)
                }
            }
        }
    }
}
