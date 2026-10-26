//
//  MindAssessment.swift
//  Prism
//
//  The questionnaires doctors use, answered on the phone: PHQ-9 for mood
//  and GAD-7 for anxiety, and for connection the three item UCLA
//  loneliness scale and one item on purpose (`MindConnection.swift`). Plain
//  values, so the scoring and the bands are tested without a store or a
//  view.
//
//  Both were developed by Drs. Robert L. Spitzer, Janet B. W. Williams, Kurt
//  Kroenke and colleagues with an educational grant from Pfizer Inc., and
//  need no permission to reproduce, translate, display or distribute. The
//  items are the official English wording, word for word, apart from two
//  dashes in PHQ-9 items 6 and 8 that the repository's style rule forbids:
//  a comma and a colon stand where they were.
//

import Foundation

/// A scored questionnaire: its items, the answers each item takes, and how
/// the answers add up.
nonisolated enum MindInstrument: String, Codable, CaseIterable, Sendable, Identifiable {
    case phq9, gad7
    /// Three item UCLA loneliness scale, see ``LonelinessScore``.
    case ucla3
    /// One item on purpose in life, see ``MindPurpose``.
    case purpose

    var id: String { rawValue }

    /// The name doctors use.
    var title: String {
        switch self {
        case .phq9: "PHQ-9"
        case .gad7: "GAD-7"
        case .ucla3: "Loneliness"
        case .purpose: "Purpose"
        }
    }

    /// What it asks about, in a word.
    var subject: String {
        switch self {
        case .phq9: "Mood"
        case .gad7: "Anxiety"
        case .ucla3: "Connection"
        case .purpose: "Meaning"
        }
    }

    /// The question every item answers.
    var stem: String {
        switch self {
        case .phq9: "Over the last 2 weeks, how often have you been bothered by any of the following problems?"
        case .gad7: "Over the last 2 weeks, how often have you been bothered by the following problems?"
        case .ucla3: LonelinessScore.stem
        case .purpose: MindPurpose.stem
        }
    }

    var items: [String] {
        switch self {
        case .phq9: [
            "Little interest or pleasure in doing things",
            "Feeling down, depressed, or hopeless",
            "Trouble falling or staying asleep, or sleeping too much",
            "Feeling tired or having little energy",
            "Poor appetite or overeating",
            "Feeling bad about yourself, or that you are a failure or have let yourself or your family down",
            "Trouble concentrating on things, such as reading the newspaper or watching television",
            "Moving or speaking so slowly that other people could have noticed? Or the opposite: being so fidgety or restless that you have been moving around a lot more than usual",
            "Thoughts that you would be better off dead or of hurting yourself in some way",
        ]
        case .gad7: [
            "Feeling nervous, anxious or on edge",
            "Not being able to stop or control worrying",
            "Worrying too much about different things",
            "Trouble relaxing",
            "Being so restless that it is hard to sit still",
            "Becoming easily annoyed or irritable",
            "Feeling afraid as if something awful might happen",
        ]
        case .ucla3: LonelinessScore.items
        case .purpose: [MindPurpose.item]
        }
    }

    /// The answers, lowest first; an answer is its index.
    var options: [String] {
        switch self {
        case .phq9, .gad7: ["Not at all", "Several days", "More than half the days", "Nearly every day"]
        case .ucla3: LonelinessScore.options
        case .purpose: MindPurpose.options
        }
    }

    var maxAnswer: Int { options.count - 1 }

    /// The total with every item at its top answer.
    var maxScore: Int { minScore + items.count * maxAnswer }

    /// The total with every item at its first answer: UCLA counts its
    /// answers from 1, so three answers start at 3; the purpose item reads
    /// 1 to 6.
    var minScore: Int {
        switch self {
        case .phq9, .gad7: 0
        case .ucla3: LonelinessScore.minimum
        case .purpose: 1
        }
    }

    /// The total of a whole set of answers. Nil while any item is missing or
    /// off the scale: nothing is scored on half a questionnaire.
    func score(_ answers: [Int]) -> Int? {
        guard answers.count == items.count, answers.allSatisfy({ (0...maxAnswer).contains($0) }) else { return nil }
        return minScore + answers.reduce(0, +)
    }

    /// Where one band ends and the next begins, for the history chart.
    var cutPoints: [Int] {
        switch self {
        case .phq9: [5, 10, 15, 20]
        case .gad7: [5, 10, 15]
        case .ucla3: [LonelinessScore.lonely]
        case .purpose: []
        }
    }

    /// The band a total falls in; nil for the connection questionnaires,
    /// which have no severity bands.
    ///
    /// PHQ-9: 5, 10, 15 and 20 (Kroenke, Spitzer and Williams, J Gen Intern
    /// Med 2001). GAD-7: 5, 10 and 15 (Spitzer, Kroenke, Williams and Löwe,
    /// Arch Intern Med 2006), with no moderately severe band.
    func severity(_ score: Int) -> MindSeverity? {
        switch self {
        case .phq9:
            switch score {
            case ..<5: .minimal
            case ..<10: .mild
            case ..<15: .moderate
            case ..<20: .moderatelySevere
            default: .severe
            }
        case .gad7:
            switch score {
            case ..<5: .minimal
            case ..<10: .mild
            case ..<15: .moderate
            default: .severe
            }
        case .ucla3, .purpose:
            nil
        }
    }
}

/// The bands of PHQ-9 and GAD-7, as the papers name them.
nonisolated enum MindSeverity: String, Codable, Sendable, Comparable, CaseIterable {
    case minimal, mild, moderate, moderatelySevere, severe

    private var rank: Int { Self.allCases.firstIndex(of: self) ?? 0 }

    static func < (lhs: MindSeverity, rhs: MindSeverity) -> Bool { lhs.rank < rhs.rank }

    var title: String {
        switch self {
        case .minimal: "Minimal"
        case .mild: "Mild"
        case .moderate: "Moderate"
        case .moderatelySevere: "Moderately severe"
        case .severe: "Severe"
        }
    }

    /// One sentence that goes with the band, wherever the score is shown.
    /// Informational: a screening questionnaire is not a diagnosis, and from
    /// moderate up the sentence points to a professional.
    var detail: String {
        switch self {
        case .minimal:
            "Few signs over the last two weeks."
        case .mild:
            "Some signs over the last two weeks. Worth keeping an eye on, and taking again in two weeks."
        case .moderate:
            "Enough signs that talking it over with a doctor or a therapist is a good idea."
        case .moderatelySevere:
            "A level where seeing a doctor or a therapist soon is recommended."
        case .severe:
            "A level where seeing a doctor or a therapist soon is recommended. If you feel unsafe, use the support lines now."
        }
    }

    /// From moderate up, the page offers the way to a professional.
    var suggestsCare: Bool { self >= .moderate }
}

/// One questionnaire, answered or under way. Answers are the option index
/// of each item, in item order: fewer than the items while it is a draft.
nonisolated struct MindAssessment: Codable, Equatable, Sendable, Identifiable {
    var id = UUID()
    var instrument: MindInstrument
    var date: Date
    var answers: [Int]

    var isComplete: Bool { score != nil }

    /// The total, nil for a draft.
    var score: Int? { instrument.score(answers) }

    /// The band, nil for a draft.
    var severity: MindSeverity? { score.flatMap(instrument.severity) }

    /// PHQ-9 item 9 (thoughts of being better off dead or of self harm)
    /// answered above "Not at all". The support lines open before any score,
    /// whatever the total says.
    var needsCrisisCare: Bool {
        instrument == .phq9 && answers.indices.contains(8) && answers[8] > 0
    }

    /// The index of the first item still to answer, nil once complete.
    var nextItem: Int? {
        answers.count < instrument.items.count ? answers.count : nil
    }
}

/// A finished questionnaire as it is shown: the number, what it is out of,
/// the band in a word and the sentence that goes with it. Built here so a
/// score never reaches a view without its words.
nonisolated struct MindAssessmentReading: Equatable, Sendable {
    var value: String
    var unit: String
    var word: String
    var detail: String
}

extension MindAssessment {
    /// Nil for a draft.
    var reading: MindAssessmentReading? {
        guard let score else { return nil }
        switch instrument {
        case .ucla3:
            return LonelinessScore.reading(score)
        case .purpose:
            return MindPurpose.reading(score)
        case .phq9, .gad7:
            break
        }
        guard let severity else { return nil }
        return MindAssessmentReading(value: "\(score)", unit: "of \(instrument.maxScore)", word: severity.title, detail: severity.detail)
    }
}
