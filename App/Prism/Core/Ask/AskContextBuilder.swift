//
//  AskContextBuilder.swift
//  Prism
//

import Foundation

/// The person's numbers, compact, as Ask Soma sends them with a question.
///
/// Scores and the metrics' usual bands and cues, never raw samples: the
/// model gets what the pages show and nothing else, and the function's system
/// prompt forbids any number that is not here. A missing value is left out,
/// so the model can say it is missing rather than guess.
nonisolated struct AskContext: Codable, Equatable, Sendable {
    struct Scores: Codable, Equatable, Sendable {
        var sleep: Int?
        var recovery: Int?
        var strain: Int?
        var stress: Int?
        var energy: Int?
        var sleepDebtHours: Double?
        var nightsRecorded: Int?

        enum CodingKeys: String, CodingKey {
            case sleep, recovery, strain, stress, energy
            case sleepDebtHours = "sleep_debt_hours"
            case nightsRecorded = "nights_recorded"
        }
    }

    struct Metric: Codable, Equatable, Sendable {
        var name: String
        var current: Double?
        var usual: Double?
        var usualLow: Double?
        var usualHigh: Double?
        /// within, above or below the usual band.
        var position: String?
        /// rising, falling or steady over 30 days.
        var direction: String?
        var percentFromUsual: Double?
        /// The short label the page shows: "3 days rising", "12% under usual".
        var cue: String?
        var daysOld: Int?

        enum CodingKeys: String, CodingKey {
            case name, current, usual, position, direction, cue
            case usualLow = "usual_low"
            case usualHigh = "usual_high"
            case percentFromUsual = "percent_from_usual"
            case daysOld = "days_old"
        }
    }

    struct Person: Codable, Equatable, Sendable {
        var age: Int?
        var sex: String?
    }

    var day: String
    var scores: Scores?
    var metrics: [Metric]
    var person: Person?
}

enum AskContextBuilder {
    /// Rounds to what a page shows: one decimal, so the model never quotes
    /// false precision.
    nonisolated static func shown(_ value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        return (value * 10).rounded() / 10
    }

    /// Builds the context from the scores and the metric insights the pages
    /// already hold (`HealthDashboard.scores`, InsightEngine's results).
    nonisolated static func make(
        scores: SomaScores?,
        insights: [(metric: InsightMetric, insight: Insight)],
        profile: SomaProfile? = nil,
        today: Date = Date(),
        calendar: Calendar = .current
    ) -> AskContext {
        let scoreBlock = scores.map {
            AskContext.Scores(
                sleep: $0.sleep, recovery: $0.recovery, strain: $0.strain, stress: $0.stress, energy: $0.energy,
                sleepDebtHours: shown($0.sleepDebtHours), nightsRecorded: $0.nightsRecorded
            )
        }
        let metrics = insights.compactMap { item -> AskContext.Metric? in
            let insight = item.insight
            guard insight.current != nil || insight.usual != nil else { return nil }
            return AskContext.Metric(
                name: item.metric.rawValue,
                current: shown(insight.current),
                usual: shown(insight.usual),
                usualLow: shown(insight.band?.lowerBound),
                usualHigh: shown(insight.band?.upperBound),
                position: insight.position.map(position),
                direction: insight.direction.map(direction),
                percentFromUsual: shown(insight.percent),
                cue: insight.cue,
                daysOld: insight.currentAge
            )
        }
        let person = profile.map { AskContext.Person(age: $0.age(on: today, calendar: calendar), sex: $0.sex?.rawValue) }
        return AskContext(day: CloudSnapshots.dayKey(today, calendar: calendar), scores: scoreBlock, metrics: metrics, person: person)
    }

    nonisolated static func position(_ value: Insight.Position) -> String {
        switch value {
        case .within: "within"
        case .above: "above"
        case .below: "below"
        }
    }

    nonisolated static func direction(_ value: Insight.Direction) -> String {
        switch value {
        case .rising: "rising"
        case .falling: "falling"
        case .steady: "steady"
        }
    }
}
