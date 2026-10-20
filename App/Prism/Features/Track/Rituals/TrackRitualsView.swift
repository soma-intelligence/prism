//
//  TrackRitualsView.swift
//  Prism
//

import SwiftUI
import SomaUI

/// Track, Rituals: two short routines that bookend the day, a morning one and
/// an evening one, each a few steps to tick.
///
/// One line says what the page is for. Each ritual is a card: today's
/// progress, the last two weeks as a strip of days, the run of days kept, its
/// steps to tick, and one line on what keeping it does for the person, read
/// from Apple Health with ``EffectMath`` (a morning ritual on that evening's
/// HRV, an evening one on the next night's deep sleep). Steps are added,
/// removed and reordered in Customize.
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

    private let store = TrackRitualStore.shared
    private let calendar = Calendar.current

    var body: some View {
        let metrics = theme.metrics
        let today = Date.now

        ScrollView {
            VStack(alignment: .leading, spacing: metrics.leadSpacing * 0.75) {
                TrackLeadText(
                    lead: "Two small routines that bookend your day.",
                    rest: "Tick each step as you go. Soma counts the days you keep and shows what they do for you."
                )
                .padding(.horizontal, metrics.scoreLabelSpacing)

                ForEach(TrackRitualMoment.allCases) { moment in
                    TrackRitualCard(
                        summary: TrackRitualSummary.make(moment, store: store, inputs: inputs, today: today, calendar: calendar),
                        ritual: store.ritual(moment),
                        isDone: { store.isDone($0, on: today) },
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
        .refreshable { inputs = await MindLoad.inputs(health) }
        .task {
            guard inputs == nil else { return }
            inputs = await MindLoad.inputs(health)
        }
        .sheet(isPresented: $breathes) {
            MindBreatheSheet()
        }
    }
}

/// One ritual on its card.
private struct TrackRitualCard: View {
    let summary: TrackRitualSummary
    let ritual: TrackRitual
    let isDone: (TrackRitualStep) -> Bool
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
                        Text("No steps yet. Add a few in Customize.")
                            .somaFont(type.body)
                            .foregroundStyle(colors.inkSecondary.color)
                            .frame(maxWidth: .infinity, minHeight: metrics.ritualStepMinHeight, alignment: .leading)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.somaGlassPressDim)
                } else {
                    VStack(alignment: .leading, spacing: metrics.scoreLabelSpacing * 2) {
                        SomaRitualDays(shares: summary.shares, tone: tone)
                        HStack {
                            Text("Last \(TrackRitualSummary.days) days")
                            Spacer()
                            Text(summary.streakText ?? "\(summary.keptThisWeek) of 7 this week")
                        }
                        .somaFont(type.tabLabel)
                        .foregroundStyle(colors.inkSecondary.color)
                    }

                    VStack(spacing: 0) {
                        ForEach(Array(ritual.steps.enumerated()), id: \.element.id) { index, step in
                            if index > 0 { TrackHairline() }
                            SomaRitualStep(step.title, glyph: step.kind, tone: tone, isDone: isDone(step)) {
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

                    TrackHairline()
                    Text(summary.effectText)
                        .somaFont(type.caption)
                        .foregroundStyle(colors.inkSecondary.color)
                        .fixedSize(horizontal: false, vertical: true)
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
