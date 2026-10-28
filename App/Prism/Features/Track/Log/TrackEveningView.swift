//
//  TrackEveningView.swift
//  Prism
//

import SwiftUI
import SomaUI
import HealthExportCore

/// This evening: one line on what tonight's habits have cost before, how the
/// day went and how it feels, the supplements due before bed with a tick for
/// each, and tonight's tags.
///
/// The line is the Journal's own effect arithmetic over sixty days of Apple
/// Health; ticks log a dose in ``TrackLogStore``; tags go to the Journal.
struct TrackEveningView: View {
    @Environment(\.somaTheme) private var theme
    @Environment(HealthDashboard.self) private var health
    @Environment(JournalStore.self) private var journal

    @State private var effects: [TrackTagEffect] = []
    @State private var opened: TrackRoute?

    private let log = TrackLogStore.shared
    private let calendar = Calendar.current
    /// Supplements taken from this minute of the day on count as before bed.
    private static let eveningFrom = 17 * 60

    var body: some View {
        let metrics = theme.metrics
        let type = theme.typography
        let colors = theme.colors
        let now = Date.now

        TrackEntryPage(title: "This evening", closesWithDone: true) {
            VStack(alignment: .leading, spacing: metrics.spaceM) {
                VStack(alignment: .leading, spacing: metrics.spaceS) {
                    TrackEyebrow("\(now.formatted(.dateTime.weekday(.wide))) \u{00B7} \(TrackClock.time(now))")
                    reason
                }

                SomaCard {
                    VStack(spacing: metrics.cardSpacing) {
                        row("How today went", value: journal.day(now).feeling.map { TrackJournal.feelingLabels[$0] }) { opened = .mood }
                        TrackHairline()
                        row("How you feel", value: log.moods(on: now).last { !$0.isDaily }.map { TrackJournal.feelingLabels[$0.valence] }) { opened = .moodNow }
                    }
                }

                supplements(now: now)

                let tonight = journal.offeredTags.filter { TrackReading.forTag($0.id) != .dayVariability }
                if !tonight.isEmpty {
                    VStack(alignment: .leading, spacing: metrics.spaceS) {
                        TrackEyebrow("Tonight")
                        TrackFlowLayout(spacing: metrics.spaceS) {
                            ForEach(tonight) { tag in
                                SomaChoiceChip(tag.title, isOn: journal.day(now).tags.contains(tag.id), style: .outline) {
                                    journal.toggle(tag.id, on: now)
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(colors.inkPrimary.color)
            .somaFont(type.body)
        } footer: {
            EmptyView()
        }
        .trackEntrySheet(item: $opened)
        .task { await load() }
    }

    private var reason: some View {
        let cost = effects.first { $0.isCost && $0.effect.delta != nil }
        return Group {
            if let cost {
                TrackLeadText(lead: "Go easy on \(cost.title.lowercased()) tonight.",
                              rest: "\(cost.detailText): \(cost.valueText ?? SomaFormat.notMeasured).")
            } else {
                TrackLeadText(lead: "Close the day.",
                              rest: "Tag what happens tonight and Soma learns what each one does to your night.")
            }
        }
    }

    private func row(_ title: String, value: String?, open: @escaping () -> Void) -> some View {
        let metrics = theme.metrics
        let colors = theme.colors
        return Button(action: open) {
            HStack(spacing: metrics.cardSpacing) {
                Text(title)
                    .somaFont(theme.typography.body)
                    .foregroundStyle(colors.inkPrimary.color)
                Spacer()
                SomaNumber(value, theme.typography.body)
                    .foregroundStyle(colors.inkSecondary.color)
                Image(systemName: "chevron.right")
                    .font(.system(size: metrics.browseChevronSize, weight: .semibold))
                    .foregroundStyle(colors.inkSecondary.color)
            }
            .frame(minHeight: metrics.minimumTapTarget * 0.8)
            .contentShape(.rect)
        }
        .buttonStyle(.somaGlassPressDim)
    }

    private func supplements(now: Date) -> some View {
        let metrics = theme.metrics
        let type = theme.typography
        let colors = theme.colors
        let due = log.activeSupplements.filter {
            $0.minute >= Self.eveningFrom && TrackAdherence.isDue($0.cadence, on: now, startedOn: $0.startedOn, calendar: calendar)
        }

        return VStack(alignment: .leading, spacing: metrics.spaceS) {
            HStack {
                TrackEyebrow(due.first.map { "Before bed \u{00B7} \(TrackClock.hour(Double($0.minute) / 60))" } ?? "Before bed")
                Spacer()
                if !due.isEmpty {
                    Text("Tick what you took")
                        .somaFont(type.caption)
                        .foregroundStyle(colors.inkSecondary.color)
                }
            }
            SomaCard {
                VStack(spacing: metrics.cardSpacing) {
                    ForEach(due) { item in
                        let taken = log.dose(of: item, on: now)
                        Button {
                            if let taken {
                                log.removeDose(taken.id)
                            } else {
                                log.logDose(name: item.name, amount: item.amount, unit: item.unit, supplementID: item.id, at: .now)
                            }
                        } label: {
                            HStack(spacing: metrics.cardSpacing) {
                                Text(item.name)
                                    .somaFont(type.body)
                                    .foregroundStyle(colors.inkPrimary.color)
                                Spacer()
                                Text("\(SomaArcDial<EmptyView>.number(item.amount)) \(item.unit.symbol)")
                                    .somaFont(type.rowValue)
                                    .foregroundStyle(colors.inkSecondary.color)
                                SomaRitualCheck(isDone: taken != nil, tone: .dusk)
                            }
                            .frame(minHeight: metrics.minimumTapTarget * 0.8)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.somaGlassPressDim)
                        .accessibilityAddTraits(taken == nil ? [] : .isSelected)
                        TrackHairline()
                    }
                    Button {
                        opened = .dose(nil)
                    } label: {
                        HStack {
                            Text("Add a supplement")
                                .somaFont(type.body)
                                .foregroundStyle(colors.accent.color)
                            Spacer()
                            Image(systemName: "plus")
                                .font(.system(size: metrics.browseGlyphSize, weight: .regular))
                                .foregroundStyle(colors.accent.color)
                        }
                        .frame(minHeight: metrics.minimumTapTarget * 0.8)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.somaGlassPressDim)
                }
            }
        }
    }

    private func load() async {
        guard let source = await health.prepare([]) else { return }
        let inputs = await TrackInputs.read(from: source, now: .now, calendar: calendar)
        let body = TrackBody.make(from: inputs, calendar: calendar)
        let days = Dictionary(journal.loggedDays.map { ($0.date, $0.day) }, uniquingKeysWith: { first, _ in first })
        effects = TrackJournal.effects(tags: journal.tags, days: days, body: body, today: .now, calendar: calendar)
            .filter { TrackReading.forTag($0.id) != .dayVariability }
    }
}

#if DEBUG
#Preview("This evening") {
    NavigationStack { TrackEveningView() }
        .environment(HealthDashboard())
        .environment(JournalStore(url: nil))
}
#endif
