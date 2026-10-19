//
//  EnergyPage.swift
//  Prism
//

import SwiftUI
import SomaUI
import HealthScoring
import HealthExportCore

/// The energy bank: the battery at the level now, what sleep
/// charged and the day drained, the day as one coloured curve over its
/// night, workouts and peak window, the events that moved it, and the links
/// to its history and how it is built.
///
/// Words are kept to labels and one short line of coaching; a missing value
/// is a dash or an empty track.
struct EnergyPage: View {
    @Environment(HealthDashboard.self) private var health
    @State private var inputs: ScoreDetailInputs?
    @State private var showsInfo = false
    @State private var showsHistory = false

    var body: some View {
        let scores = health.scores
        let page = ScorePages.energy(scores)

        ScorePageScaffold(aspect: .mind, title: "Energy") {
            EnergyBankColumn(scores: scores, inputs: inputs, page: page,
                             showsHistory: { showsHistory = true }, showsInfo: { showsInfo = true })
        }
        .scoreInputs([.today, .nights], into: $inputs)
        .sheet(isPresented: $showsInfo) { EnergyInfoSheet(page: page) }
        .sheet(isPresented: $showsHistory) { EnergyHistorySheet(scores: scores) }
    }
}

/// The page's column, drawn from the scores and the inputs alone so it can
/// be drawn without Health behind it. Its cards land straight in the
/// scaffold's column.
struct EnergyBankColumn: View {
    let scores: SomaScores?
    let inputs: ScoreDetailInputs?
    let page: ScorePages.Energy
    var showsHistory: () -> Void = {}
    var showsInfo: () -> Void = {}

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let day = EnergyDay(scores: scores, inputs: inputs, page: page)

        Group {
            EnergyHero(page: page, versusYesterday: day.versusYesterday)
                .padding(.top, theme.metrics.heroTopPadding)
            HStack(spacing: theme.metrics.cardSpacing) {
                SomaBankDelta(value: page.charged, title: "Charged")
                SomaBankDelta(value: page.drained, title: "Drained")
            }
            if page.lead.value != nil {
                EnergyCoaching(text: page.lead.headline, level: page.lead.value)
            }
            SomaCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Today")
                            .somaFont(theme.typography.cardTitle)
                            .foregroundStyle(theme.colors.inkPrimary.color)
                        Spacer()
                        EnergyHigh(level: page.high, at: page.highAt)
                    }
                    SomaBankDayChart(points: day.points, bands: day.bands, now: day.now, ticks: day.ticks)
                }
            }
            SomaCard {
                VStack(alignment: .leading, spacing: 0) {
                    Text("What moved it")
                        .somaFont(theme.typography.cardTitle)
                        .foregroundStyle(theme.colors.inkPrimary.color)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.bottom, 2)
                    ScoreRows(day.entries) { entry in
                        SomaBankEntryRow(mark: entry.mark, symbol: entry.symbol, title: entry.title,
                                         span: entry.span, points: entry.points, scale: day.scale)
                    }
                }
            }
            EnergyLinks(peak: day.peakDetail, stress: scores?.stress,
                        showsHistory: showsHistory, showsInfo: showsInfo)
        }
    }
}

// MARK: - Head

/// The battery, then where sleep charged it to and when, and the morning's
/// charge against yesterday's.
private struct EnergyHero: View {
    let page: ScorePages.Energy
    let versusYesterday: Int?

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let type = theme.typography
        let colors = theme.colors

        VStack(spacing: 14) {
            SomaBankBattery(level: page.lead.value)
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Image(systemName: "bolt.fill")
                        .somaFont(type.caption)
                        .foregroundStyle(colors.statusNormal.color)
                    Text(verbatim: page.opened.map { "\($0)%" } ?? "-")
                        .somaFont(type.captionValue)
                        .foregroundStyle(colors.inkPrimary.color)
                    if let at = page.openedAt {
                        Text(verbatim: ScoreMath.clock(at))
                            .somaFont(type.captionValue)
                            .foregroundStyle(colors.inkSecondary.color)
                    }
                }
                .accessibilityElement(children: .combine)
                if let versusYesterday, versusYesterday != 0 {
                    HStack(spacing: theme.metrics.trendMarkSpacing) {
                        SomaTrendMark(trend: versusYesterday > 0 ? .up : .down)
                        Text(verbatim: "\(abs(versusYesterday))")
                            .somaFont(type.captionValue)
                            .foregroundStyle(colors.inkPrimary.color)
                        Text("vs yesterday")
                            .somaFont(type.caption)
                            .foregroundStyle(colors.inkSecondary.color)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// The one line of coaching, its glyph in the colour of the level.
private struct EnergyCoaching: View {
    let text: String
    let level: Int?

    @Environment(\.somaTheme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .somaFont(theme.typography.callout)
                .foregroundStyle(SomaEnergyRamp.standard.value(at: Double(level ?? 0) / 100).color)
            Text(verbatim: text)
                .somaFont(theme.typography.callout)
                .foregroundStyle(theme.colors.inkPrimary.color)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// The day's high and when, set small beside the chart's title.
private struct EnergyHigh: View {
    let level: Int?
    let at: Date?

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let type = theme.typography
        let colors = theme.colors
        HStack(spacing: 4) {
            Text("High")
                .somaFont(type.caption)
                .foregroundStyle(colors.inkSecondary.color)
            Text(verbatim: level.map(String.init) ?? "-")
                .somaFont(type.captionValue)
                .foregroundStyle(level.map { SomaEnergyRamp.standard.value(at: Double($0) / 100).color }
                                 ?? colors.inkSecondary.color)
            if let at {
                Text(verbatim: ScoreMath.clock(at))
                    .somaFont(type.captionValue)
                    .foregroundStyle(colors.inkSecondary.color)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Links

/// History, how the bank is built, the peak window and stress, as one group
/// of small rows.
private struct EnergyLinks: View {
    let peak: String?
    let stress: Int?
    let showsHistory: () -> Void
    let showsInfo: () -> Void

    private enum Row: String, Identifiable {
        case history, info, peak, stress
        var id: String { rawValue }
    }

    var body: some View {
        SomaBrowseGroup([Row.history, .info, .peak, .stress]) { row in
            switch row {
            case .history:
                SomaBrowseRow(symbol: "chart.bar.fill", title: "History", action: showsHistory)
            case .info:
                SomaBrowseRow(symbol: "info.circle", title: "How it’s built", action: showsInfo)
            case .peak:
                NavigationLink(value: ScoreRoute.peakWindow) {
                    SomaBrowseRow(symbol: "sparkles", title: "Peak window", detail: peak ?? "-")
                }
                .buttonStyle(.plain)
            case .stress:
                NavigationLink(value: ScoreRoute.stress) {
                    SomaBrowseRow(symbol: "waveform.path.ecg", title: "Stress", detail: stress.map(String.init) ?? "-")
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - The day, worked out

/// The page's day: the curve placed on a span that starts at last night's
/// bedtime (or midnight) and ends at tonight's midnight, the bands behind
/// it, the time axis, and the events that moved the bank.
nonisolated struct EnergyDay {
    struct Entry: Identifiable {
        var id: String { "\(title)\(span ?? "")" }
        var mark: SomaBankMark
        var symbol: String
        var title: String
        var span: String?
        var points: Int?
    }

    var points: [SomaBankDayChart.Point] = []
    var bands: [SomaBankDayChart.Band] = []
    var now: Double?
    var ticks: [SomaBankDayChart.Tick] = []
    var entries: [Entry] = []
    var versusYesterday: Int?
    var peakDetail: String?

    /// The largest move in the list, which fills a bar.
    var scale: Int {
        max(10, entries.compactMap { $0.points.map(abs) }.max() ?? 0)
    }

    init(scores: SomaScores?, inputs: ScoreDetailInputs?, page: ScorePages.Energy, calendar: Calendar = .current) {
        let curve = scores?.energyCurve ?? []
        let clock = inputs?.now ?? curve.last?.date ?? Date()
        let dayStart = calendar.startOfDay(for: curve.last?.date ?? clock)
        let dayEnd = dayStart.addingTimeInterval(86_400)
        let night = scores?.detail.lastNight
        let from = [dayStart, curve.first?.date, night?.start].compactMap { $0 }.min() ?? dayStart
        let length = max(1, dayEnd.timeIntervalSince(from))
        func x(_ date: Date) -> Double { date.timeIntervalSince(from) / length }
        func level(near date: Date) -> Double? {
            guard let point = curve.min(by: { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }),
                  abs(point.date.timeIntervalSince(date)) <= 30 * 60 else { return nil }
            return point.level
        }

        points = curve.map { SomaBankDayChart.Point(x: x($0.date), level: $0.level) }
        if let last = curve.last { now = x(last.date) }

        if from < dayStart {
            ticks.append(.init(x: 0, label: ScoreMath.clock(from, calendar: calendar)))
        } else {
            ticks.append(.init(x: x(dayStart), label: "00:00"))
        }
        for hour in [6, 12, 18] {
            let date = dayStart.addingTimeInterval(Double(hour) * 3600)
            ticks.append(.init(x: x(date), label: ScoreMath.clock(date, calendar: calendar)))
        }

        if let night, night.end > from {
            bands.append(.init(mark: .sleep, start: x(max(night.start, from)), end: x(night.end), symbol: "moon.stars.fill"))
        }

        let workouts = (inputs?.workouts ?? []).filter { $0.end > from && $0.start < dayEnd }
        var moved: [Entry] = []
        for workout in workouts {
            let activity = FitnessActivities.activity(Int(workout.value))
            bands.append(.init(mark: .workout, start: x(max(workout.start, from)), end: x(workout.end), symbol: activity.symbol))
            let delta: Int? = {
                guard let a = level(near: workout.start), let b = level(near: workout.end) else { return nil }
                return Int((b - a).rounded())
            }()
            moved.append(Entry(mark: .workout, symbol: activity.symbol, title: activity.name,
                               span: "\(ScoreMath.clock(workout.start, calendar: calendar)) to \(ScoreMath.clock(workout.end, calendar: calendar))",
                               points: delta))
        }

        if let peak = ScorePages.peak(scores, inputs, calendar: calendar).day, let deep = peak.deepWork {
            bands.append(.init(mark: .peak, start: x(dayStart.addingTimeInterval(deep.start * 3600)),
                               end: x(dayStart.addingTimeInterval(deep.end * 3600)), symbol: "sparkles"))
            peakDetail = "\(ScoreMath.clock(deep.start)) to \(ScoreMath.clock(deep.end))"
        }

        for entry in page.ledger {
            if entry.title == "Sleep" {
                entries.append(Entry(mark: .sleep, symbol: "moon.stars.fill", title: entry.title,
                                     span: entry.span, points: entry.points))
                entries += moved
                moved = []
            } else {
                let symbol = entry.title.hasPrefix("Morning") ? "sunrise.fill"
                    : entry.title.hasPrefix("Afternoon") ? "sun.max.fill" : "sunset.fill"
                entries.append(Entry(mark: .day, symbol: symbol, title: entry.title, span: entry.span, points: entry.points))
            }
        }
        entries += moved
        if entries.isEmpty {
            entries = [Entry(mark: .sleep, symbol: "moon.stars.fill", title: "Sleep", span: nil, points: nil),
                       Entry(mark: .day, symbol: "sun.max.fill", title: "Day", span: nil, points: nil)]
        }

        let mornings = scores?.detail.energyMorning ?? []
        if mornings.count >= 2, let today = mornings[mornings.count - 1], let yesterday = mornings[mornings.count - 2] {
            versusYesterday = Int((today - yesterday).rounded())
        }
    }
}

// MARK: - History

/// The bank over the last month: each day from its evening low to its
/// morning high.
struct EnergyHistorySheet: View {
    let scores: SomaScores?

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let detail = scores?.detail ?? SomaScores.Detail()
        let mornings = Array(detail.energyMorning.suffix(30))
        let ends = Array(detail.energyEnd.suffix(30))
        let count = min(mornings.count, ends.count)
        let days = (0..<count).map { SomaBankHistory.Day(high: mornings[$0], low: ends[$0]) }
        let type = theme.typography
        let colors = theme.colors

        ScoreSheet(eyebrow: "Energy", title: "Last 30 days") {
            HStack(spacing: theme.metrics.cardSpacing) {
                EnergyAverage(title: "Morning", value: ScoreMath.mean(mornings))
                EnergyAverage(title: "Evening", value: ScoreMath.mean(ends))
            }
            SomaCard {
                VStack(spacing: 8) {
                    SomaBankHistory(days: days.isEmpty ? Array(repeating: .init(high: nil, low: nil), count: 30) : days)
                    HStack {
                        Text("30 days ago")
                        Spacer()
                        Text("Today")
                    }
                    .somaFont(type.caption)
                    .foregroundStyle(colors.inkSecondary.color)
                }
            }
        }
    }
}

/// One average over the month, coloured by its level.
private struct EnergyAverage: View {
    let title: LocalizedStringResource
    let value: Double?

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let colors = theme.colors
        let metrics = theme.metrics
        VStack(spacing: 4) {
            Text(verbatim: value.map { "\(Int($0.rounded()))" } ?? "-")
                .somaFont(theme.typography.bankDelta)
                .foregroundStyle(value.map { SomaEnergyRamp.standard.value(at: $0 / 100).color } ?? colors.inkSecondary.color)
            Text(title)
                .somaFont(theme.typography.caption)
                .foregroundStyle(colors.inkSecondary.color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, metrics.cardPadding)
        .background(RoundedRectangle(cornerRadius: metrics.cardCornerRadius, style: .continuous)
            .fill(colors.surface.color))
        .accessibilityElement(children: .combine)
    }
}
