//
//  PeakWindowPage.swift
//  Prism
//

import SwiftUI
import SomaUI
import HealthScoring

/// The peak window: alertness now on a modelled curve, the day's windows for
/// deep work and training, the caffeine cutoff and wind down, and the day on
/// a clock.
///
/// The curve is the SAFTE model over your own recorded nights, phased by your
/// chronotype when two free day nights allow it. The week ahead against your
/// calendar is left out: Soma reads no calendar.
struct PeakWindowPage: View {
    @Environment(HealthDashboard.self) private var health
    @Environment(\.somaTheme) private var theme
    @State private var inputs: ScoreDetailInputs?

    var body: some View {
        let page = ScorePages.peak(health.scores, inputs)
        let day = page.day

        ScorePageScaffold(aspect: .mind, title: "Peak window") {
            ScoreFigure(value: day?.now.map { "\(Int($0.rounded()))" }, unit: "alertness now, of 100")
                .padding(.top, theme.metrics.heroTopPadding)
            ScoreHead(headline: page.headline, reason: page.reason, aside: page.aside)
            SomaCard {
                VStack(alignment: .leading, spacing: 8) {
                    SomaCardHeader("Today’s curve", caption: "Predicted alertness")
                    if let day {
                        ScoreDayLine(
                            points: day.curve.enumerated().map { index, point in
                                (Double(index) * 10 / 1440, point.level)
                            },
                            aspect: .mind, range: 40...100, solidUntil: day.nowHour / 24,
                            windows: [day.deepWork.map { ScoreDayLine.Window(title: "Deep work", start: $0.start / 24, end: $0.end / 24, aspect: .mind) },
                                      day.training.map { ScoreDayLine.Window(title: "Training", start: $0.start / 24, end: $0.end / 24, aspect: .activity) }]
                                .compactMap { $0 },
                            labels: ["00", "06", "12", "18", "24"])
                    } else {
                        ScoreEmptyPlot(message: "The curve draws from your last three nights.")
                    }
                }
            }
            ScoreLinks(links: [
                ScoreLink(title: "Deep work", detail: day?.deepWork.map { "\(ScoreMath.clock($0.start)) to \(ScoreMath.clock($0.end))" } ?? "-"),
                ScoreLink(title: "Training", detail: day?.training.map { "\(ScoreMath.clock($0.start)) to \(ScoreMath.clock($0.end))" } ?? "-"),
                ScoreLink(title: "Caffeine cutoff", detail: day.map { ScoreMath.clock($0.caffeineCutoffHour) } ?? "-"),
                ScoreLink(title: "Wind down", detail: day.map { ScoreMath.clock($0.windDownHour) } ?? "-"),
            ])
            if let day {
                SomaChartCard(eyebrow: "Rhythm", value: ScoreMath.clock(day.windDownHour), unit: "wind down",
                              note: "Usual sleep window \(ScoreMath.clock(day.bedHour)) to \(ScoreMath.clock(day.wakeHour)). Morning light before 09:00 keeps it early.") {
                    ScoreClockRing(sleepStart: day.bedHour, sleepEnd: day.wakeHour, windDown: day.windDownHour, now: day.nowHour)
                        .padding(.vertical, theme.metrics.spaceS)
                }
                ScoreMoveCard(move: ScorePages.Move(eyebrow: "Tonight", title: "Wind down at \(ScoreMath.clock(day.windDownHour))",
                                                    detail: "An hour before your usual bedtime.", remindAt: day.windDownHour),
                              aspect: .mind)
            }
            ScoreFootnote(text: "Built on your last \(day?.nights ?? 0) nights. A model, not a measurement.")
        }
        .scoreInputs([.nights], into: $inputs)
    }
}
