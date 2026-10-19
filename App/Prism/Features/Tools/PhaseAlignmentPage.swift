//
//  PhaseAlignmentPage.swift
//  Prism
//

import SwiftUI
import SomaUI

/// Phase Alignment: how well the day keeps time with the body clock, the next
/// window to act on, and the day's seven windows.
///
/// The score is 100 less 25 points for every hour of social jetlag,
/// read from the gap between work-night and free-night mid-sleep, the same
/// arithmetic as its thirty day trend so the two can never disagree. The
/// windows come from the circadian planner, anchored on the phase estimated
/// from the person's own sleep timing (Roenneberg's MSFsc).
struct PhaseAlignmentPage: View {
    @Environment(HealthDashboard.self) private var health
    @Environment(JournalStore.self) private var journal
    @Environment(\.somaTheme) private var theme
    @State private var reminded = false

    private var model: ToolsModel { .shared }
    private var store: ToolsStore { .shared }

    var body: some View {
        let day = ToolDay(inputs: model.current, cups: TrackLogStore.shared.caffeineCups, sleepNeedHours: health.scores?.sleepNeedHours)
        let plan = day.plan
        let score = day.hasEnoughNights ? plan?.alignmentScore : nil
        let trend = SomaTools.CircadianPhaseAlignment.trend(bedHours: day.bedHours, wakeHours: day.wakeHours,
                                                            endingOn: day.inputs.now)
        let average = SomaTools.CircadianPhaseAlignment.baselineAverage(Array(trend.dropLast()))
        let next = plan.flatMap { SomaTools.CircadianPhaseAlignment.nextWindow(after: day.nowHour, in: $0.windows) }

        ToolPage(ToolKind.phaseAlignment.title) {
            ToolGauge(aspect: .sleep, fraction: score.map { Double($0) / 100 }, display: score.map { "\($0)" },
                      state: score.map { bandLabel(SomaTools.CircadianPhaseAlignment.band(score: $0)) } ?? gateLabel(day),
                      delta: deltaLine(score: score, average: average),
                      deltaIsWorse: (score.map(Double.init) ?? 0) < (average ?? 0))

            ToolHero(headline: headline(score), lead: lastNightLine(day), rest: habitLine(day))

            if let plan, let next {
                SomaCard {
                    VStack(alignment: .leading, spacing: theme.metrics.cardHeaderSpacing) {
                        Text("Next window")
                            .somaFont(theme.typography.eyebrow)
                            .textCase(.uppercase)
                            .foregroundStyle(theme.colors.inkSecondary.color)
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(ToolFormat.clock(hour: next.startHour))
                                .somaFont(theme.typography.metric)
                                .foregroundStyle(theme.colors.inkPrimary.color)
                            Text(windowAction(next.kind))
                                .somaFont(theme.typography.callout)
                                .foregroundStyle(theme.colors.inkSecondary.color)
                        }
                        ToolFootnote("In \(ToolFormat.span(hours: next.hoursUntil)). \(chronotypeLine(day))")
                        ToolDayDial(spans: dialSpans(plan), nowHour: day.nowHour,
                                    centre: ToolFormat.clock(hour: next.startHour), caption: windowName(next.kind).lowercased())
                    }
                }
                ToolEyebrow("Your day")
                ToolRowsCard(rows: dayRows(plan, day: day))
            } else {
                ToolEmptyCard(eyebrow: "Next window",
                              message: "The windows of your day appear after seven nights of sleep timing, with at least two free nights among them. \(day.nightCount) recorded so far.")
            }

            SomaChartCard(eyebrow: "Alignment", value: score.map { "\($0)" }, unit: "today",
                          note: average.map { "30 days. Usually around \(Int($0.rounded()))." } ?? "30 days. The line fills in as nights are recorded.") {
                ToolHistoryChart(aspect: .sleep, values: trend, band: average.map { ($0 - 4)...($0 + 4) },
                                 firstLabel: firstDayLabel(days: trend.count, now: day.inputs.now))
            }
            ToolFootnote("An estimate, not a clinical measurement.")

            if let dim = day.window(.lightAvoid) {
                ToolNextCard(eyebrow: "Tonight", aspect: .sleep, title: "Lights low at \(ToolFormat.clock(hour: dim.startHour))",
                             detail: "Dim light before your sleep window.",
                             actionTitle: reminded ? "Reminder set" : "Remind me",
                             action: { remind(dim.startHour) })
            }
            ToolLinkRow(title: "About Phase Alignment", detail: nil, value: ToolRoute.intro(.phaseAlignment))
        }
        .task {
            store.markOpened(.phaseAlignment)
            await model.load(health)
        }
    }

    // MARK: - Words

    private func bandLabel(_ band: SomaTools.CircadianPhaseAlignment.Band) -> String {
        switch band {
        case .aligned: "Mostly aligned"
        case .drift: "Drifting"
        case .misaligned: "Out of step"
        }
    }

    private func gateLabel(_ day: ToolDay) -> String {
        day.hasEnoughNights ? "Needs two free nights" : "\(day.nightCount) of 7 nights"
    }

    private func deltaLine(score: Int?, average: Double?) -> String? {
        guard let score, let average else { return nil }
        let delta = Int((Double(score) - average).rounded())
        guard delta != 0 else { return "Level with your 30-day average" }
        return "\(abs(delta)) \(delta < 0 ? "below" : "above") your 30-day average"
    }

    private func headline(_ score: Int?) -> String {
        guard let score else { return "Your body clock needs a week of nights to read." }
        switch SomaTools.CircadianPhaseAlignment.band(score: score) {
        case .aligned: return "Your day keeps time with your body clock, mostly."
        case .drift: return "Your day is drifting from your body clock."
        case .misaligned: return "Your day and your body clock are out of step."
        }
    }

    private func lastNightLine(_ day: ToolDay) -> String {
        guard let night = day.inputs.lastNight(calendar: day.calendar) else {
            return "No night recorded since yesterday."
        }
        var line = "You fell asleep at \(ToolFormat.clock(night.bed))"
        if let habitual = day.habitualSleepHour {
            let delta = SomaTools.CircadianMath.signedDeltaHours(from: habitual, to: night.bedHour(calendar: day.calendar))
            if abs(delta) >= 0.25 {
                line += ", \(ToolFormat.span(hours: delta)) \(delta > 0 ? "past" : "before") your window"
            } else {
                line += ", right on your window"
            }
        }
        let lateMeals = lateMealNights(day)
        if lateMeals >= 2 { line += ", and dinner ran late \(ToolFormat.words(lateMeals)) nights in four" }
        return line + "."
    }

    private func habitLine(_ day: ToolDay) -> String? {
        guard let light = day.window(.lightSeek) else { return nil }
        return "Morning light before \(ToolFormat.clock(hour: light.endHour)) pulls the clock earlier."
    }

    private func lateMealNights(_ day: ToolDay) -> Int {
        let tagged = journal.dates(tagged: "late-meal")
        let today = day.calendar.startOfDay(for: day.inputs.now)
        return (0..<4).compactMap { day.calendar.date(byAdding: .day, value: -$0, to: today) }.filter { tagged.contains($0) }.count
    }

    private func chronotypeLine(_ day: ToolDay) -> String {
        guard let phase = day.phase else { return "" }
        let kind: String = switch phase.chronotype.category {
        case .morning: "Your clock runs early"
        case .intermediate: "Your clock sits in the middle"
        case .evening: "Your clock runs late"
        }
        guard let sleep = day.habitualSleepHour, let wake = day.habitualWakeHour else { return kind + "." }
        return "\(kind); best sleep \(ToolFormat.clock(hour: sleep)) to \(ToolFormat.clock(hour: wake))."
    }

    private func windowName(_ kind: SomaTools.CircadianWindow.Kind) -> String {
        switch kind {
        case .lightSeek: "Morning light"
        case .lightAvoid: "Dim light"
        case .caffeineCutoff: "Caffeine cutoff"
        case .exercise: "Best workout"
        case .windDown: "Wind down"
        case .sleep: "Sleep window"
        }
    }

    private func windowAction(_ kind: SomaTools.CircadianWindow.Kind) -> String {
        switch kind {
        case .lightSeek: "get outside"
        case .lightAvoid: "dim the lights"
        case .caffeineCutoff: "last cup"
        case .exercise: "move"
        case .windDown: "wind down"
        case .sleep: "lights out"
        }
    }

    private func dayRows(_ plan: SomaTools.CircadianPlan, day: ToolDay) -> [ToolRow] {
        let order: [SomaTools.CircadianWindow.Kind] = [.lightSeek, .caffeineCutoff, .exercise, .lightAvoid, .windDown, .sleep]
        return order.compactMap { kind in
            guard let window = plan.windows.first(where: { $0.kind == kind }) else { return nil }
            let span = window.startHour == window.endHour
                ? "by \(ToolFormat.clock(hour: window.startHour))"
                : "\(ToolFormat.clock(hour: window.startHour)) to \(ToolFormat.clock(hour: window.endHour))"
            var row = ToolRow(title: windowName(kind), value: span)
            switch kind {
            case .lightSeek:
                row.detail = day.inputs.daylightToday.map { "\(Int($0.rounded())) minutes outside today" }
            case .caffeineCutoff:
                if let last = day.doses.last(where: { day.calendar.isDate($0.time, inSameDayAs: day.inputs.now) }) {
                    let after = SomaTools.CircadianMath.signedDeltaHours(from: window.startHour,
                                                                          to: SomaTools.CircadianPhaseAlignment.decimalHour(last.time)) > 0
                    row.detail = "Last cup at \(ToolFormat.clock(last.time))\(after ? ", after it" : "")"
                    row.detailTone = after ? .danger : .plain
                }
            default:
                break
            }
            return row
        }
    }

    private func dialSpans(_ plan: SomaTools.CircadianPlan) -> [ToolDayDial.Span] {
        plan.windows.filter { $0.startHour != $0.endHour && $0.kind != .windDown }.map { window in
            ToolDayDial.Span(id: window.kind.rawValue, start: window.startHour, end: window.endHour,
                             aspect: window.kind == .lightSeek || window.kind == .exercise ? .body : .sleep)
        }
    }

    private func firstDayLabel(days: Int, now: Date) -> String {
        let first = Calendar.current.date(byAdding: .day, value: -(days - 1), to: now) ?? now
        return first.formatted(.dateTime.month(.abbreviated).day())
    }

    private func remind(_ hour: Double) {
        let at = SomaTools.CaffeineWindowEngine.nextOccurrence(ofHour: hour, after: Date())
        Task {
            reminded = await ToolNotifier.remind(id: "phase-dim", title: "Lights low",
                                                 body: "Two hours of dim light before your sleep window.", at: at)
        }
    }
}
