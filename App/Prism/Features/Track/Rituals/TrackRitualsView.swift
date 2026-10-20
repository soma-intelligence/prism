//
//  TrackRitualsView.swift
//  Prism
//

import SwiftUI
import SomaUI
import HealthExportCore

/// Track, Rituals: two short routines that bookend the day, a morning one and
/// an evening one, each a few steps to tick.
///
/// No sentences: each ritual is a card with today's progress, the last two
/// weeks as a strip of days, the run of days kept with what keeping it does
/// for the person beside it (``EffectMath``: a morning ritual on that
/// evening's HRV, an evening one on the next night's deep sleep, shown only
/// once there is one), and its steps. Steps Apple Health can see tick
/// themselves (``TrackRitualDetection``) and wear a small heart; the person
/// can still untick them. Steps are added, removed and reordered in
/// Customize.
///
/// It draws no navigation chrome: the Track page embeds it under its own top
/// bar. Needs `HealthDashboard`, `JournalStore` and `AppRouter` in the
/// environment.
struct TrackRitualsView: View {
    @Environment(HealthDashboard.self) private var health
    @Environment(AppRouter.self) private var router
    @Environment(\.somaTheme) private var theme

    @State private var inputs: MindInputs?
    @State private var breathes = false

    /// How many days back Health's ticks are read: the strip and the effect.
    private static let detectionDays = TrackRitualSummary.effectDays

    private let store = TrackRitualStore.shared
    private let calendar = Calendar.current

    var body: some View {
        let metrics = theme.metrics
        let today = Date.now

        SomaPageScroll {
            VStack(alignment: .leading, spacing: metrics.leadSpacing * 0.75) {
                ForEach(TrackRitualMoment.allCases) { moment in
                    TrackRitualCard(
                        summary: TrackRitualSummary.make(moment, store: store, inputs: inputs, today: today, calendar: calendar),
                        ritual: store.ritual(moment),
                        isDone: { store.isDone($0, on: today) },
                        isFromHealth: { store.isFromHealth($0, on: today) },
                        toggle: { step in
                            store.toggle(step, on: today)
                        },
                        breathe: { breathes = true },
                        edit: { router.trackSection = .customize }
                    )
                }

                HStack {
                    Spacer()
                    Button {
                        router.trackSection = .customize
                    } label: {
                        SomaQuietPill("Edit rituals", systemImage: "slider.horizontal.3")
                    }
                    .buttonStyle(.somaGlassPressDim)
                    Spacer()
                }

                ToolsEntryTile()

                MindHealthStatus(status: health.status)
            }
            .padding(.horizontal, metrics.pagePadding)
            .padding(.top, metrics.cardSpacing)
            .padding(.bottom, metrics.pagePadding)
            .frame(maxWidth: metrics.pageMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(theme.colors.canvas.color.ignoresSafeArea())
        .refreshable { await load() }
        .task {
            guard inputs == nil else { return }
            await load()
        }
        .sheet(isPresented: $breathes) {
            MindBreatheSheet()
        }
    }
}

extension TrackRitualsView {
    /// Reads Health once for the effects and for the steps it can tick.
    private func load() async {
        let read = await MindLoad.inputs(health)
        inputs = read
        guard let source = await health.prepare(TrackRitualSignals.Metric.all) else { return }
        let now = Date.now
        var signals = await TrackRitualSignals.read(from: source, inputs: read, stepDays: TrackRitualSummary.days,
                                                    now: now, calendar: calendar)
        // Water poured in the Journal counts even when Health was not
        // allowed to keep it.
        signals.water += TrackLogStore.shared.drinks
            .filter { $0.drink == .water && $0.ml > 0 }
            .compactMap { entry in
                HealthMetricCatalog.metric(for: TrackRitualSignals.Metric.water).map {
                    HealthReading(metric: $0.identifier, value: entry.ml, unit: $0.unit, start: entry.date, end: entry.date)
                }
            }
        let start = calendar.startOfDay(for: now)
        let days = (0..<Self.detectionDays).compactMap { calendar.date(byAdding: .day, value: -$0, to: start) }
        store.setDetected(TrackRitualDetection.detected(store.rituals, days: days, signals: signals,
                                                        now: now, calendar: calendar))
    }
}

/// One ritual on its card.
private struct TrackRitualCard: View {
    let summary: TrackRitualSummary
    let ritual: TrackRitual
    let isDone: (TrackRitualStep) -> Bool
    let isFromHealth: (TrackRitualStep) -> Bool
    let toggle: (TrackRitualStep) -> Void
    let breathe: () -> Void
    let edit: () -> Void

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics
        let type = theme.typography
        let colors = theme.colors
        let tone = summary.moment.tone

        SomaCard {
            VStack(alignment: .leading, spacing: metrics.cardSpacing) {
                HStack(alignment: .center, spacing: metrics.browseRowSpacing) {
                    SomaTrackGlyph(summary.moment.glyph, tone: tone, style: .row)
                    Text(summary.moment.title)
                        .somaFont(type.title)
                        .foregroundStyle(colors.inkPrimary.color)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: metrics.cardSpacing)
                    Text(summary.progressText)
                        .somaFont(type.rowValue)
                        .monospacedDigit()
                        .foregroundStyle(summary.isKeptToday ? tone.color : colors.inkSecondary.color)
                        .contentTransition(.numericText())
                }

                if ritual.steps.isEmpty {
                    Button(action: edit) {
                        Text("Add a step")
                            .somaFont(type.body)
                            .foregroundStyle(colors.inkSecondary.color)
                            .frame(maxWidth: .infinity, minHeight: metrics.ritualStepMinHeight, alignment: .leading)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.somaGlassPressDim)
                } else {
                    VStack(alignment: .leading, spacing: metrics.scoreLabelSpacing * 3) {
                        SomaRitualDays(shares: summary.shares, tone: tone)
                        if summary.keptText != nil || summary.effectText != nil {
                            HStack {
                                if let kept = summary.keptText {
                                    Text(kept)
                                        .foregroundStyle(colors.inkSecondary.color)
                                }
                                Spacer()
                                if let effect = summary.effectText {
                                    Text(effect)
                                        .foregroundStyle(tone.color)
                                }
                            }
                            .somaFont(type.tabLabel)
                            .lineLimit(1)
                        }
                    }

                    VStack(spacing: 0) {
                        ForEach(Array(ritual.steps.enumerated()), id: \.element.id) { index, step in
                            if index > 0 { TrackHairline() }
                            SomaRitualStep(step.title, glyph: step.kind, tone: tone, isDone: isDone(step),
                                           isFromHealth: isFromHealth(step)) {
                                toggle(step)
                            } trailing: {
                                if step.kind == .breathe && !isDone(step) {
                                    Button(action: breathe) {
                                        Text("Start")
                                            .somaFont(type.callout)
                                            .foregroundStyle(colors.inkPrimary.color)
                                            .padding(.horizontal, metrics.quietPillPadding * 0.75)
                                            .frame(minHeight: metrics.quietPillHeight * 0.8)
                                            .background(Capsule().fill(colors.surfaceRecessed.color))
                                            .contentShape(.capsule)
                                    }
                                    .buttonStyle(.somaGlassPress)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

#Preview("Track, Rituals") {
    NavigationStack {
        TrackRitualsView()
    }
    .environment(HealthDashboard())
    .environment(AppRouter())
    .environment(JournalStore(url: nil))
}
