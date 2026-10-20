//
//  RecoveryPage.swift
//  Prism
//

import SwiftUI
import SomaUI

/// Recovery: the gauge, what it means for the day, the four signals it leans
/// on against your usual, the readiness tank and the one move that fits.
///
/// Pushed from the Mind page, the Heart page and Trends. The score
/// and its terms come from ``SomaScores``; the usual bands from a month of
/// HRV, resting heart rate, sleep and breathing.
struct RecoveryPage: View {
    @Environment(HealthDashboard.self) private var health
    @State private var inputs: ScoreDetailInputs?
    @State private var sheet: Sheet?

    enum Sheet: String, Identifiable {
        case built, history
        var id: String { rawValue }
    }

    var body: some View {
        let page = ScorePages.recovery(health.scores, inputs)

        ScorePageScaffold(aspect: .heart, title: "Recovery") {
            ScoreStage(aspect: .heart, lead: page.lead, series: health.scores?.recoverySeries ?? [])
            ScoreHead(page.lead)
            ScoreUsualCard(title: "What recovery leans on", aspect: .heart, lines: page.lines)
            SomaChartCard(eyebrow: "Readiness", value: page.lead.value.map { "\($0)" }, unit: "of 100",
                          note: page.readinessNote) {
                ScoreTank(level: page.lead.value, word: page.lead.word, aspect: .mind)
            }
            ScoreLinks(links: [
                ScoreLink(title: "How your score is built") { sheet = .built },
            ])
            ScorePageLinks(routes: [(.stress, "Stress today", health.scores?.stress.map(String.init)),
                                    (.sleep, "Last night’s sleep", health.scores?.sleep.map(String.init))])
            if let move = page.move {
                ScoreMoveCard(move: move, aspect: .heart)
            }
        }
        .scoreInputs([.heart, .breathing], into: $inputs)
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .built: RecoveryBuiltSheet(page: page)
            case .history: ScoreHistorySheet(kind: .recovery, scores: health.scores)
            }
        }
    }
}
