//
//  SleepParts.swift
//  Prism
//

import SwiftUI
import SomaUI
import HealthScoring

/// The night's numbers in three parts, the way the reference design lays them under its
/// hypnogram: the heart, the stages, and the context around the night. One
/// part shows at a time, as a grouped list.
struct SleepNightFacts: View {
    let night: SleepNightSummary?
    let dip: ScorePages.NightDip?
    let inputs: ScoreDetailInputs?
    var calendar: Calendar = .current

    enum Part: String, CaseIterable, Hashable {
        case heart, stages, context
        var title: LocalizedStringResource {
            switch self {
            case .heart: "Heart"
            case .stages: "Stages"
            case .context: "Context"
            }
        }
    }

    struct Fact: Identifiable {
        var id: String { title }
        var symbol: String
        var title: String
        var value: String?
        var tint: Color?
    }

    @State private var part: Part = .heart
    @Environment(\.somaTheme) private var theme

    var body: some View {
        VStack(spacing: theme.metrics.cardSpacing) {
            SomaSegmentedControl(segments: Part.allCases.map { SomaSegment(id: $0, title: $0.title) }, selection: $part)
            SomaCard {
                VStack(spacing: 0) {
                    let facts = facts(part)
                    ForEach(Array(facts.enumerated()), id: \.element.id) { index, fact in
                        if index > 0 {
                            Rectangle()
                                .fill(theme.colors.inkPrimary.color.opacity(theme.metrics.hairlineOpacity))
                                .frame(height: 0.5)
                        }
                        row(fact)
                    }
                }
            }
        }
    }

    private func row(_ fact: Fact) -> some View {
        let metrics = theme.metrics
        return HStack(spacing: metrics.spaceM) {
            Image(systemName: fact.symbol)
                .imageScale(.small)
                .foregroundStyle(fact.tint ?? theme.colors.inkSecondary.color)
                .frame(width: metrics.sleepGlyphSize * 1.5)
            Text(fact.title)
                .somaFont(theme.typography.body)
                .foregroundStyle(theme.colors.inkPrimary.color)
            Spacer(minLength: metrics.spaceS)
            SomaNumber(fact.value, theme.typography.rowValue)
                .foregroundStyle(theme.colors.inkPrimary.color)
                .lineLimit(1)
        }
        .padding(.vertical, metrics.spaceM)
        .accessibilityElement(children: .combine)
    }

    private func facts(_ part: Part) -> [Fact] {
        let heart = SomaHealthHue.heart.color
        switch part {
        case .heart:
            let beats = (inputs?.lastNightBeats ?? []).map(\.value).filter { $0 > 0 }
            let today = dip?.today
            return [
                Fact(symbol: "heart.fill", title: "Average heart rate",
                     value: today.map { "\(ScoreMath.number($0.meanSleepingHR)) bpm" }, tint: heart),
                Fact(symbol: "heart.fill", title: "Heart rate range",
                     value: beats.min().flatMap { low in beats.max().map { "\(ScoreMath.number(low)) to \(ScoreMath.number($0)) bpm" } },
                     tint: heart),
                Fact(symbol: "arrow.down.heart.fill", title: "Lowest at",
                     value: today.map { ScoreMath.clock($0.lowestAt, calendar: calendar) }, tint: heart),
                Fact(symbol: "chart.line.downtrend.xyaxis", title: "Night dip",
                     value: today.map { "\(Int($0.percent.rounded()))%" }, tint: heart),
            ]
        case .stages:
            let asleep = night?.asleep ?? 0
            return [SomaSleepStage.awake, .rem, .core, .deep].map { stage in
                let seconds = night?.stages[stage]
                let share = stage == .awake ? (night?.inBed ?? 0) : asleep
                let value = seconds.map { seconds in
                    let percent = share > 0 ? " · \(Int((seconds / share * 100).rounded()))%" : ""
                    return SleepTrends.hm(seconds / 3600) + percent
                }
                return Fact(symbol: "circle.fill", title: String(localized: stage.title), value: value, tint: stage.color(theme))
            }
        case .context:
            let stages = night?.runs ?? []
            let wakes = stages.filter { $0.stage == .awake && $0.start > (night?.bed ?? .distantPast) }.count
            var latency: String?
            if let inBed = inputs?.inBedStart, let first = stages.first(where: { $0.stage != .awake }) {
                let minutes = first.start.timeIntervalSince(inBed) / 60
                if minutes >= 0 && minutes < 180 { latency = SomaFormat.duration(minutes * 60) as String }
            }
            let temperature = inputs?.wristTemperature ?? []
            let center = ScoreMath.median(temperature.dropLast())
            let lastTemp = temperature.last ?? nil
            return [
                Fact(symbol: "moon.stars.fill", title: "Bedtime", value: night.map { ScoreMath.clock($0.bed, calendar: calendar) }),
                Fact(symbol: "sunrise.fill", title: "Wake time", value: night.map { ScoreMath.clock($0.wake, calendar: calendar) }),
                Fact(symbol: "hourglass", title: "Fell asleep in", value: latency),
                Fact(symbol: "eye.fill", title: "Woke up", value: night == nil ? nil : (wakes == 1 ? "Once" : "\(wakes) times")),
                Fact(symbol: "lungs.fill", title: "Breathing",
                     value: (inputs?.respiratory.last ?? nil).map { "\(ScoreMath.number($0, decimals: 1)) /min" }),
                Fact(symbol: "thermometer.medium", title: "Wrist temperature",
                     value: lastTemp.flatMap { t in center.map { "\(ScoreMath.signed(t - $0, decimals: 1)) °C" } }),
                Fact(symbol: "ear.fill", title: "Sound",
                     value: (inputs?.nightSound.last ?? nil).map { "\(Int($0.rounded())) dB" }),
            ]
        }
    }
}

/// The trend list: a row a reading, the reference design's card with the status under the
/// value and the month on the trailing edge. A row with somewhere to go
/// opens it.
struct SleepTrendList: View {
    let rows: [SleepTrends.Row]
    let open: (SleepTrends.Target) -> Void

    @Environment(\.somaTheme) private var theme

    var body: some View {
        // A reading never recorded is left out rather than drawn as a card
        // of dashes, and with nothing recorded the heading goes too.
        let shown = rows.filter { $0.value != nil || $0.values.contains { $0 != nil } }
        if !shown.isEmpty {
            VStack(alignment: .leading, spacing: theme.metrics.cardSpacing) {
                ScoreSectionTitle(text: "Trends")
                // Two tiles a row where the width holds them.
                SomaCardColumns {
                    ForEach(shown) { row in
                        let view = SomaTrendRow(LocalizedStringResource(stringLiteral: row.title), value: row.value,
                                                status: status(row.status), values: row.values, band: row.band,
                                                hue: hue(row), chart: row.chart == .bars ? .bars : .line,
                                                symbol: row.symbol, prominent: true, opens: row.target != nil)
                        if row.target == .night {
                            TileLink(value: ScoreRoute.sleep) { view }
                        } else if let target = row.target {
                            Button { open(target) } label: { view.contentShape(.rect) }
                                .buttonStyle(.somaGlassPress)
                        } else {
                            view
                        }
                    }
                }
            }
            // The whole list spans the page, so its tiles tile rather than
            // stacking in one of the score page's columns.
            .somaColumnSpan(.full)
        }
    }

    private func status(_ status: SleepTrends.Status) -> SomaReadingStatus {
        switch status {
        case .normal: .normal
        case .above: .above
        case .below: .below
        case .earlier: .worded("Earlier than usual", .neutral)
        case .later: .worded("Later than usual", .neutral)
        case .debt: .worded("Debt", .watch)
        case .noDebt: .worded("No debt", .good)
        case .none: .none
        }
    }

    private func hue(_ row: SleepTrends.Row) -> SomaHealthHue? {
        switch row.title {
        case "Heart rate dip": .heart
        case "Breathing": .respiratory
        default: .sleep
        }
    }
}
