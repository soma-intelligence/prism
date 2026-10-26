//
//  ScoreHistorySheet.swift
//  Prism
//

import SwiftUI
import SomaUI
import HealthScoring

/// A score over time: the sentence, a range of two weeks to three months, the
/// days as bars (or, for stress, as stems from your usual), the trend table,
/// what to read next and what the score is.
///
/// Three months is as far back as the engine reads, so the range stops there
/// rather than drawing a half empty year.
struct ScoreHistorySheet: View {
    enum Kind: String {
        case recovery, strain, stress, sleep

        var title: String {
            switch self {
            case .recovery: "Recovery"
            case .strain: "Strain"
            case .stress: "Stress"
            case .sleep: "Sleep"
            }
        }

        var aspect: SomaAspect {
            switch self {
            case .recovery: .heart
            case .strain: .activity
            case .stress: .mind
            case .sleep: .sleep
            }
        }

        var higherIsWorse: Bool { self == .stress }
    }

    enum Range: Int, CaseIterable, Hashable {
        case twoWeeks = 14, month = 30, quarter = 90

        var title: LocalizedStringResource {
            switch self {
            case .twoWeeks: "2 weeks"
            case .month: "1 month"
            case .quarter: "3 months"
            }
        }
    }

    let kind: Kind
    let scores: SomaScores?

    @State private var range: Range = .twoWeeks
    @State private var reader: ScoreReader?

    @Environment(\.somaTheme) private var theme

    private var series: [Double?] {
        let detail = scores?.detail ?? SomaScores.Detail()
        switch kind {
        case .recovery: return detail.recovery
        case .strain: return detail.strain
        case .stress: return detail.stress
        case .sleep: return detail.sleep
        }
    }

    private var today: Int? {
        switch kind {
        case .recovery: scores?.recovery
        case .strain: scores?.strain
        case .stress: scores?.stress
        case .sleep: scores?.sleep
        }
    }

    var body: some View {
        let series = series
        let length = range.rawValue
        let month = Array(series.suffix(31).dropLast())
        let usual = ScoringUsual.of(month, spreadFloor: ScoringUsual.Floor.scorePoints)
        let weekMean = ScoreMath.mean(series.suffix(7))
        let monthAgo = ScoreMath.mean(series.dropLast(28).suffix(7))

        ScoreSheet(eyebrow: "\(kind.title) · \(today.map(String.init) ?? "-")", title: "\(kind.title) over time") {
            ScoreParagraph(lead: lead(weekMean: weekMean, monthAgo: monthAgo),
                           rest: usual.map { "Usually \(Int($0.low.rounded())) to \(Int($0.high.rounded()))." })
            SomaSegmentedControl(segments: Range.allCases.map { SomaSegment(id: $0, title: $0.title) }, selection: $range)
            SomaCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text(kind == .stress ? "Stress against your usual" : "Daily \(kind.title.lowercased())")
                        .somaFont(theme.typography.eyebrow)
                        .foregroundStyle(theme.colors.inkSecondary.color)
                    if series.allSatisfy({ $0 == nil }) {
                        ScoreEmptyPlot(message: "Days draw here once the score has seven nights behind it.")
                    } else if kind == .stress, let center = usual?.center {
                        ScoreFigure(value: today.map { ScoreMath.signed(Double($0) - center) }, unit: "today")
                        Text("Usual \(Int(center.rounded()))")
                            .somaFont(theme.typography.caption)
                            .foregroundStyle(theme.colors.inkSecondary.color)
                        ScoreDayPager(days: series.count, length: length) { indices, labels, _ in
                            VStack(spacing: theme.metrics.spaceS) {
                                ScoreStems(deviations: ScoreDayPager<EmptyView>.slice(series, indices).map { $0.map { $0 - center } },
                                           aspect: kind.aspect)
                                ScoreAxis(labels: labels)
                            }
                        }
                    } else {
                        ScoreFigure(value: today.map(String.init), unit: "today")
                        ScoreDayPager(days: series.count, length: length) { indices, labels, endsToday in
                            ScoreDayBars(values: ScoreDayPager<EmptyView>.slice(series, indices), aspect: kind.aspect,
                                         band: usual.map { $0.low...$0.high }, labels: labels, endsToday: endsToday)
                        }
                    }
                }
            }
            ScoreTrendCard(caption: "Last data today", rows: ScoreMath.trendRows(series, deadBand: 2,
                                                                                   higherIsWorse: kind.higherIsWorse),
                           note: "Each row compares 7 day averages.")
            if !reading.isEmpty {
                ScoreSectionTitle(text: "Read more")
                ScoreLinks(links: reading.map { item in
                    ScoreLink(title: item.title, detail: item.detail) { item.open() }
                })
            }
            ScoreAbout(lead: about.lead, rest: about.rest, symbol: "info.circle.fill", hue: SomaHealthHue(kind.aspect))
        }
        .sheet(item: $reader) { $0.sheet(stress: scores?.stress) }
    }

    private func lead(weekMean: Double?, monthAgo: Double?) -> String {
        guard let weekMean else { return "\(kind.title) draws here once it has a week of days." }
        let average = Int(weekMean.rounded())
        guard let monthAgo else { return "The 7 day average is \(average)." }
        let delta = weekMean - monthAgo
        if abs(delta) < 2 { return "The 7 day average is \(average), about where it was a month ago." }
        return "The 7 day average is \(average), \(delta > 0 ? "up" : "down") from \(Int(monthAgo.rounded())) a month ago."
    }

    private var reading: [(title: String, detail: String?, open: () -> Void)] {
        switch kind {
        case .stress:
            return [("Reading your stress score", "4 min", { reader = .stressArticle }),
                    ("How stress is measured", nil, { reader = .stressMeasured })]
        case .recovery:
            return [(PulseArticles.heartRateVariability.title, "4 min", { reader = .article(PulseArticles.heartRateVariability) })]
        case .sleep:
            return [(PulseArticles.deepSleep.title, "3 min", { reader = .article(PulseArticles.deepSleep) })]
        case .strain:
            return []
        }
    }

    private var about: (lead: String, rest: String) {
        switch kind {
        case .recovery:
            ("How ready you are for load, 0 to 100.",
             "HRV, resting heart rate and sleep, against your own usual.")
        case .strain:
            ("The load your heart carried, 0 to 100.",
             "Against your own history. A week outside your band is worth a look.")
        case .stress:
            ("Your body’s load, not your mood.",
             "This morning’s HRV and resting heart rate against your baseline.")
        case .sleep:
            ("Six parts of the night, against your need.",
             "Duration, efficiency, deep, REM, wakings and the heart rate dip.")
        }
    }
}

/// Something to read from a score page, opened as a sheet.
enum ScoreReader: Identifiable, Hashable {
    case article(PulseArticle)
    case stressArticle
    case stressMeasured

    var id: String {
        switch self {
        case .article(let article): article.id
        case .stressArticle: "stress-article"
        case .stressMeasured: "stress-measured"
        }
    }

    @ViewBuilder
    func sheet(stress: Int?) -> some View {
        switch self {
        case .article(let article): ScoreArticleSheet(article: article)
        case .stressArticle: StressArticleSheet(stress: stress)
        case .stressMeasured: StressMeasuredSheet(stress: stress)
        }
    }
}

/// An Explore piece opened from a score page, with the Done a sheet needs.
struct ScoreArticleSheet: View {
    let article: PulseArticle

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            PulseArticleReader(article: article)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}
