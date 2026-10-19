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
struct TrackDoseView: View {
    let supplementID: UUID?

    @Environment(\.somaTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var unit = TrackDoseUnit.grams
    @State private var amount = 0.0
    @State private var time = Date.now
    @State private var loaded = false

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
                VStack(spacing: metrics.cardSpacing * 0.75) {
                    TextField("Name, as on the label", text: $name)
                        .somaFont(type.body)
                        .foregroundStyle(colors.inkPrimary.color)
                        .padding(.horizontal, metrics.cardPadding)
                        .frame(minHeight: metrics.minimumTapTarget + metrics.cardSpacing)
                        .background(RoundedRectangle(cornerRadius: metrics.cardCornerRadius, style: .continuous).fill(colors.surface.color))
                    HStack(spacing: metrics.cardSpacing * 0.5) {
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
                    DatePicker(selection: $time, displayedComponents: .hourAndMinute) {
                        Text("Usually taken at")
                            .somaFont(type.body)
                            .foregroundStyle(colors.inkPrimary.color)
                    }
                    .tint(colors.accent.color)
                }
            }

            dayLine

            TrackNote(lead: "Kept in Soma. Apple Health has no place for a supplement.")
        } footer: {
            SomaActionButton(actionTitle) { save() }
                .disabled(amount <= 0 || (supplement == nil && name.trimmingCharacters(in: .whitespaces).isEmpty))
        }
        .onAppear(perform: load)
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
                                VStack(spacing: metrics.scoreLabelSpacing * 2) {
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
            log.addSupplement(name: name, amount: amount, unit: unit, minute: minute, startedOn: now)
        }
        dismiss()
    }
}

#if DEBUG
#Preview("Dose") {
    NavigationStack { TrackDoseView(supplementID: nil) }
}
#endif
