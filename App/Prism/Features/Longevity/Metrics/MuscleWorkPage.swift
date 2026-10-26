//
//  MuscleWorkPage.swift
//  Prism
//

import SwiftUI
import SomaUI

/// Which muscle groups thirty days of sessions loaded: the session days on
/// the metric stage, a figure with each
/// region's share, the six groups in a table, and the routine for the group
/// that got the least.
///
/// The arithmetic is ``MuscleWork``:
/// each session weighed by its heart rate zones and split by its activity.
/// The weight of logged sets is not read: there is no set log yet, so the
/// volume column is left out rather than shown as zeros.
struct MuscleWorkPage: View {
    enum Measure: String, CaseIterable, Hashable {
        case share, work, sessions

        var title: LocalizedStringResource {
            switch self {
            case .share: "Share"
            case .work: "Work"
            case .sessions: "Sessions"
            }
        }
    }

    @Environment(HealthDashboard.self) private var health
    @Environment(\.somaTheme) private var theme

    @State private var history: FitnessHistory?
    @State private var measure: Measure = .share

    private var words: MetricWords { MetricWords() }
    static let days = 30

    var body: some View {
        let workouts = history?.workouts ?? []
        let work = MuscleWork(workouts: workouts)
        let hasWork = work.totalPoints > 0
        let lead = MetricLead.override(health.status)
        let least = TrainingRoutines.leastWorked(work)

        TabPartScaffold(
            aspect: .body,
            eyebrow: "Last \(Self.days) days, \(work.totalSessions) \(work.totalSessions == 1 ? "session" : "sessions")",
            title: lead?.title ?? headline(work),
            reason: lead?.reason ?? reason(work),
            stats: []
        ) {
            AspectStage(
                aspect: .body,
                lead: SomaMetricLead(
                    caption: "Last \(Self.days) days",
                    value: history == nil ? nil : "\(work.totalSessions)",
                    unit: work.totalSessions == 1 ? "session" : "sessions",
                    meaning: hasWork ? nil : "No sessions yet"
                ),
                values: Self.minutes(workouts, now: history?.now ?? .now),
                unit: "min",
                scale: nil,
                higherIsBetter: nil,
                format: { MetricWords().whole($0) }
            )
            SomaSegmentedControl(
                segments: Measure.allCases.map { SomaSegment(id: $0, title: $0.title) },
                selection: $measure
            )
            SomaCard {
                VStack(alignment: .leading, spacing: theme.metrics.chartLabelGap * 2) {
                    Text(figureTitle)
                        .somaFont(theme.typography.cardTitle)
                        .foregroundStyle(theme.colors.inkPrimary.color)
                    if let value = figureValue(work) {
                        Text(hasWork ? "\(value) in the legs" : value)
                            .somaFont(theme.typography.callout)
                            .foregroundStyle(theme.colors.inkSecondary.color)
                    }
                    BodySilhouette(changes: regionLabels(work))
                }
            }
            .accessibilityHint(Text(figureNote(hasWork)))
            groupTable(work)
            if let least, hasWork {
                TileLink(value: MetricRoute.sessionPreview(least.routine.id)) {
                    SomaActionCard(
                        eyebrow: "Next strength session",
                        title: least.routine.name,
                        detail: "\(least.routine.summary) got \(Int((least.share * 100).rounded()))% of the work; this session is theirs.",
                        actionTitle: nil
                    ) {
                        PulseMiniOrb(aspect: .body, diameter: theme.metrics.miniOrbDiameter)
                    }
                }
            }
        }
        .navigationTitle("Muscle work")
        .task { history = await health.fitnessHistory(days: Self.days) }
        .somaRefreshable { history = await health.fitnessHistory(days: Self.days) }
    }

    private var figureTitle: String {
        switch measure {
        case .share: "Share of the work"
        case .work: "Work points"
        case .sessions: "Sessions that loaded it"
        }
    }

    /// Minutes of sessions a day, the last thirty, today last; a day with
    /// none is empty rather than zero.
    static func minutes(_ workouts: [FitnessWorkout], now: Date, calendar: Calendar = .current) -> [Double?] {
        let today = calendar.startOfDay(for: now)
        let byDay = Dictionary(grouping: workouts) { calendar.startOfDay(for: $0.start) }
            .mapValues { $0.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) } / 60 }
        return (0..<days).map { index in
            calendar.date(byAdding: .day, value: index - (days - 1), to: today).flatMap { byDay[$0] }
        }
    }

    private func figureValue(_ work: MuscleWork) -> String? {
        switch measure {
        case .share: work.share(FitnessActivities.MuscleGroup.legs).map { "\(Int(($0 * 100).rounded()))%" }
        case .work: work.totalPoints > 0 ? words.whole(work.points[.legs] ?? 0) : nil
        case .sessions: work.totalPoints > 0 ? "\(work.sessions[.legs] ?? 0)" : nil
        }
    }

    private func figureNote(_ hasWork: Bool) -> String {
        hasWork
            ? "Every session weighted by its effort. The watch can’t tell left from right, so each side takes half."
            : "Workouts from the last \(Self.days) days fill the figure."
    }

    /// Right arm, left arm, trunk, right leg, left leg.
    private func regionLabels(_ work: MuscleWork) -> [String?] {
        guard work.totalPoints > 0 else { return Array(repeating: nil, count: 5) }
        func text(_ region: MuscleWork.Region, halved: Bool) -> String? {
            let groups: [FitnessActivities.MuscleGroup] = switch region {
            case .arms: [.arms]
            case .legs: [.legs]
            case .trunk: [.chest, .back, .core, .shoulders]
            }
            let divisor = halved ? 2.0 : 1.0
            switch measure {
            case .share:
                return work.share(region).map { "\(Int(($0 / divisor * 100).rounded()))%" }
            case .work:
                return words.whole(groups.reduce(0) { $0 + (work.points[$1] ?? 0) } / divisor)
            case .sessions:
                return "\(groups.map { work.sessions[$0] ?? 0 }.max() ?? 0)"
            }
        }
        let arm = text(.arms, halved: true)
        let leg = text(.legs, halved: true)
        return [arm, arm, text(.trunk, halved: false), leg, leg]
    }

    private func groupTable(_ work: MuscleWork) -> some View {
        let type = theme.typography
        let colors = theme.colors
        let column = theme.metrics.metricColumnWidth

        return SomaCard {
            VStack(alignment: .leading, spacing: theme.metrics.spaceS) {
                Text("By muscle group")
                    .somaFont(type.eyebrow)
                    .foregroundStyle(colors.inkSecondary.color)
                Grid(alignment: .leading, horizontalSpacing: theme.metrics.metricColumnSpacing, verticalSpacing: theme.metrics.bodyRowSpacing) {
                    GridRow {
                        Text("")
                        Text("Share").frame(width: column, alignment: .trailing)
                        Text("Sessions").frame(width: column, alignment: .trailing)
                        Text("Work").frame(width: column, alignment: .trailing)
                    }
                    .somaFont(type.caption)
                    .foregroundStyle(colors.inkSecondary.color)
                    ForEach(work.ranked) { group in
                        GridRow {
                            Text(group.title)
                                .somaFont(type.body)
                                .foregroundStyle(colors.inkPrimary.color)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(work.share(group).map { "\(Int(($0 * 100).rounded()))%" } ?? "-")
                                .foregroundStyle(colors.inkPrimary.color)
                                .frame(width: column, alignment: .trailing)
                            Text(work.totalPoints > 0 ? "\(work.sessions[group] ?? 0)" : "-")
                                .foregroundStyle(colors.inkSecondary.color)
                                .frame(width: column, alignment: .trailing)
                            Text(work.totalPoints > 0 ? words.whole(work.points[group] ?? 0) : "-")
                                .foregroundStyle(colors.inkSecondary.color)
                                .frame(width: column, alignment: .trailing)
                        }
                        .somaFont(type.rowValue)
                    }
                }
            }
        }
    }

    private func headline(_ work: MuscleWork) -> String {
        guard history != nil else { return "Reading your sessions." }
        guard let top = work.ranked.first, let share = work.share(top) else { return "No sessions to count yet." }
        return "Your \(top.title.lowercased()) did \(Int((share * 100).rounded()))% of the work."
    }

    private func reason(_ work: MuscleWork) -> String {
        guard work.totalPoints > 0 else {
            return "Every workout in Health loads some muscles more than others. A month of them shows where the work went."
        }
        let ranked = work.ranked
        let second = ranked.dropFirst().first
        var text = "Walks, runs and rides load the legs most"
        if let second, let share = work.share(second) {
            text += "; \(second.title.lowercased()) follows at \(Int((share * 100).rounded()))%."
        } else {
            text += "."
        }
        if let last = ranked.last, let share = work.share(last), share < 0.1 {
            text += " \(last.title) got the least."
        }
        if work.unattributed > 0 {
            text += " \(work.unattributed) \(work.unattributed == 1 ? "session had" : "sessions had") no split to count."
        }
        return text
    }
}

#Preview("Muscle work") {
    NavigationStack { MuscleWorkPage() }
        .environment(HealthDashboard())
}
