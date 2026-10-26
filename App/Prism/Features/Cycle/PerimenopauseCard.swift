//
//  PerimenopauseCard.swift
//  Prism
//

import SwiftUI
import SomaUI

/// Signs of the menopause transition on the cycle page: what the record is
/// consistent with, in a sentence, and each sign behind it as a row. Never a
/// diagnosis: every stage says "consistent with" and sends the person to a
/// clinician, who can weigh what the phone cannot.
///
/// Drawn only when there is something to say: a stage past `.none`, or a
/// symptom that comes up often.
struct PerimenopauseCard: View {
    let assessment: PerimenopauseAssessment

    @Environment(\.somaTheme) private var theme

    /// Whether the card has anything to show.
    static func shows(_ assessment: PerimenopauseAssessment) -> Bool {
        switch assessment.stage {
        case .earlyTransition?, .lateTransition?, .postmenopause?: true
        case .none?, nil: assessment.signs.contains { sign in
            if case .variableCycles = sign { return false }
            return true
        }
        }
    }

    var body: some View {
        VStack(spacing: theme.metrics.cardSpacing) {
            MetricTextCard(eyebrow: "Menopause transition", lead: lead, rest: rest)
            if !rows.isEmpty {
                HomeRowsCard("Signs", caption: "From your cycles, symptoms and wrist temperature") {
                    ForEach(rows, id: \.name) { row in
                        HomeValueRow(name: row.name, detail: row.detail, value: row.value)
                    }
                }
            }
        }
    }

    // MARK: Words (for the owner to review)

    private var lead: String {
        switch assessment.stage {
        case .earlyTransition?: "Your cycles show signs consistent with the early menopause transition."
        case .lateTransition?: "Your record shows signs consistent with the late menopause transition."
        case .postmenopause?: "Twelve months without a period is consistent with postmenopause."
        case .none?, nil: "Some symptoms come up often this month."
        }
    }

    private var rest: String {
        let others = "Pregnancy, breastfeeding, contraception, thyroid changes, stress and some medicines change cycles too."
        let clinician = "A clinician can tell you what it means for you."
        switch assessment.stage {
        case .earlyTransition?:
            return "Your cycle length now varies by a week or more from one cycle to the next. \(others) \(clinician)"
        case .lateTransition?:
            return "Sixty days or more passed without a period. If you could be pregnant, a test is the first step. \(others) \(clinician)"
        case .postmenopause?:
            // ACOG: any bleeding after menopause is checked by a clinician.
            return "Bleeding after a year without a period should always be checked by a clinician. \(clinician)"
        case .none?, nil:
            return "Hot flashes and night sweats are common in the years around menopause and have other causes too. A clinician can help if they get in the way of your days or nights."
        }
    }

    private struct Row {
        var name: String
        var detail: String?
        var value: String
    }

    private var rows: [Row] {
        assessment.signs.map { sign in
            switch sign {
            case .variableCycles(let count):
                Row(name: "Cycles off your usual", detail: "A week or more longer or shorter, in the last ten", value: "\(count)")
            case .longGap(let days):
                Row(name: "Longest gap", detail: "Days between two periods", value: "\(days) days")
            case .monthsWithoutPeriod(let months):
                Row(name: "Since your last period", detail: nil, value: "\(months) months")
            case .hotFlashes(let days):
                Row(name: "Hot flashes", detail: "Days logged in the last 30", value: "\(days)")
            case .nightSweats(let nights, let warm):
                Row(name: "Night sweats",
                    detail: warm > 0 ? "\(warm) with a warmer wrist than usual" : "Nights logged in the last 30",
                    value: "\(nights)")
            }
        }
    }
}

#Preview("Perimenopause") {
    SomaPageScroll {
        PerimenopauseCard(assessment: PerimenopauseAssessment(
            stage: .earlyTransition,
            signs: [.variableCycles(count: 3), .hotFlashes(days: 6), .nightSweats(nights: 4, warmNights: 3)]
        ))
        .padding()
    }
}
