//
//  AskModel.swift
//  Prism
//

import Foundation
import SomaUI

/// The numbers Ask may answer from: today's page as the Pulse tab worked it
/// out, and nothing else. No network, no model.
struct AskFacts: Equatable, Sendable {
    /// Heart rate variability this morning, in whole ms.
    var variability: String?
    var variabilityTrend: SomaTrend?
    /// Last night asleep, as the clock reads it: 7:12.
    var sleep: String?
    var sleepTrend: SomaTrend?
    /// The latest resting heart rate, in whole bpm.
    var resting: String?
    /// The first move Today offers, if any.
    var move: AskMove?
    /// How the person says they are: resting or unwell holds training back.
    var status: ActivityStatus = .training

    init(
        variability: String? = nil,
        variabilityTrend: SomaTrend? = nil,
        sleep: String? = nil,
        sleepTrend: SomaTrend? = nil,
        resting: String? = nil,
        move: AskMove? = nil,
        status: ActivityStatus = .training
    ) {
        self.variability = variability
        self.variabilityTrend = variabilityTrend
        self.sleep = sleep
        self.sleepTrend = sleepTrend
        self.resting = resting
        self.move = move
        self.status = status
    }

    /// The Apple Health identifier the variability reading comes from.
    static let variabilityMetric = "HKQuantityTypeIdentifierHeartRateVariabilitySDNN"

    /// Today's facts. `today.mind` is the Mind score, not a variability in
    /// ms, so the reading is passed in from Apple Health rather than taken from
    /// the score; the Mind score's direction follows recovery, which the
    /// variability drives, so it stands for the reading's trend. Sleep is the
    /// sleep card's clock time, not the Sleep score.
    init(today: PulseToday?, variability: String? = nil, status: ActivityStatus = .training) {
        self.init(
            variability: variability,
            variabilityTrend: variability == nil ? nil : today?.mind.trend,
            sleep: today?.sleepCard.value,
            sleepTrend: today?.sleep.trend,
            resting: today?.heartCard.value,
            move: today?.moves.first.map { AskMove(aspect: $0.aspect, title: $0.title, reason: $0.reason) },
            status: status
        )
    }
}

struct AskMove: Equatable, Sendable {
    var aspect: SomaAspect
    var title: String
    var reason: String
}

/// What a suggestion is about.
enum AskTopic: String, Sendable {
    case mind
    case sleep
    case training
}

/// One row under "From today".
struct AskSuggestion: Equatable, Identifiable, Sendable {
    var id: AskTopic { topic }
    var topic: AskTopic
    var question: String
    var aspect: SomaAspect
}

/// Soma's side of one turn.
struct AskAnswer: Equatable, Sendable {
    var lead: String
    var rest: String?
    /// How many of today's readings the answer read.
    var signals: Int
    /// What the readings were, for the line under the answer.
    var sources: [String]
    var move: AskMove?
    var followUps: [AskSuggestion]
    /// True when the question was not one Ask can answer without a model.
    var isModelMissing: Bool

    /// "From Apple Health: HRV, resting heart rate and sleep."
    var sourceLine: String? {
        guard !sources.isEmpty else { return nil }
        return "From Apple Health: \(sources.formatted(.list(type: .and)))."
    }
}

/// Questions and answers built from the numbers on the phone.
///
/// Until a conversation model is connected, Ask answers the three questions it
/// offers, from today's readings, and says plainly that anything else waits
/// for the model. It never invents a figure: a reading the store does not hold
/// turns the answer into what would fill it.
enum Ask {
    static func suggestions(_ facts: AskFacts) -> [AskSuggestion] {
        let mind = facts.variability.map { "Why is my HRV \($0) ms today?" } ?? "What is my HRV saying today?"
        let sleep = facts.variabilityTrend == .down ? "Can tonight bring my HRV back?" : "How did last night\u{2019}s sleep do?"
        return [
            AskSuggestion(topic: .mind, question: mind, aspect: .mind),
            AskSuggestion(topic: .sleep, question: sleep, aspect: .sleep),
            AskSuggestion(topic: .training, question: "Can I train hard tomorrow?", aspect: .activity),
        ]
    }

    /// The suggestion `question` names, compared without case, spacing or
    /// the kind of apostrophe typed.
    static func topic(of question: String, in suggestions: [AskSuggestion]) -> AskTopic? {
        let asked = normalized(question)
        return suggestions.first { normalized($0.question) == asked }?.topic
    }

    static func answer(to question: String, facts: AskFacts) -> AskAnswer {
        let offered = suggestions(facts)
        guard let topic = topic(of: question, in: offered) else {
            return AskAnswer(
                lead: "The conversation model isn\u{2019}t connected yet.",
                rest: "For now I answer the questions under From today, from the numbers on this phone. Nothing you type leaves it.",
                signals: 0, sources: [], move: nil, followUps: offered, isModelMissing: true
            )
        }
        let others = offered.filter { $0.topic != topic }
        switch topic {
        case .mind: return mind(facts, followUps: others)
        case .sleep: return sleep(facts, followUps: others)
        case .training: return training(facts, followUps: others)
        }
    }

    // MARK: Topics

    private static func mind(_ facts: AskFacts, followUps: [AskSuggestion]) -> AskAnswer {
        guard let hrv = facts.variability else {
            return AskAnswer(
                lead: "I have no heart rate variability from today yet.",
                rest: "Your watch measures it while you rest, most nights. Once one lands, this answer reads from it.",
                signals: 0, sources: [], move: nil, followUps: followUps, isModelMissing: false
            )
        }
        let restingLine = facts.resting.map { " Resting heart rate reads \($0) bpm." } ?? ""
        let lead: String
        let rest: String
        switch facts.variabilityTrend {
        case .down:
            lead = "Your HRV is \(hrv) ms, below your usual."
            rest = "A short night, a late meal, alcohol or hard training the day before can each lower it. Your Journal shows which of those you logged." + restingLine
        case .up:
            lead = "Your HRV is \(hrv) ms, above your usual."
            rest = "Higher than usual tends to follow full nights and easy days." + restingLine
        case nil:
            lead = "Your HRV is \(hrv) ms, close to your usual."
            rest = "Nothing stands out today." + restingLine
        }
        var sources = ["HRV"]
        if facts.resting != nil { sources.append("resting heart rate") }
        return AskAnswer(lead: lead, rest: rest, signals: sources.count, sources: sources,
                         move: facts.move, followUps: followUps, isModelMissing: false)
    }

    private static func sleep(_ facts: AskFacts, followUps: [AskSuggestion]) -> AskAnswer {
        guard let slept = facts.sleep else {
            return AskAnswer(
                lead: "I have no sleep from last night.",
                rest: "Wear your watch to bed and I can read your nights.",
                signals: 0, sources: [], move: nil, followUps: followUps, isModelMissing: false
            )
        }
        let lead: String
        switch facts.sleepTrend {
        case .down: lead = "You slept \(slept) last night, less than usual."
        case .up: lead = "You slept \(slept) last night, more than usual."
        case nil: lead = "You slept \(slept) last night, about your usual."
        }
        let rest = facts.variabilityTrend == .down
            ? "A full night is the surest way to bring HRV back. An early, dim evening helps it most."
            : "Keep the same bedtime tonight and it should hold."
        var sources = ["sleep"]
        if facts.variabilityTrend == .down { sources.insert("HRV", at: 0) }
        return AskAnswer(lead: lead, rest: rest, signals: sources.count, sources: sources,
                         move: facts.move, followUps: followUps, isModelMissing: false)
    }

    private static func training(_ facts: AskFacts, followUps: [AskSuggestion]) -> AskAnswer {
        if facts.variability == nil, facts.sleep == nil, facts.status.holdsTrainingBack {
            return AskAnswer(
                lead: "I\u{2019}d keep tomorrow easy.",
                rest: facts.status == .unwell
                    ? "You marked yourself unwell, and recovery comes first. Change your status on Pulse when you feel better."
                    : "You are on a planned rest, so a low day costs nothing. Change your status on Pulse when you start again.",
                signals: 0, sources: [], move: nil, followUps: followUps, isModelMissing: false
            )
        }
        guard facts.variability != nil || facts.sleep != nil else {
            return AskAnswer(
                lead: "I can\u{2019}t tell yet.",
                rest: "Apple Health holds no HRV or sleep for today, and those are what readiness is read from.",
                signals: 0, sources: [], move: nil, followUps: followUps, isModelMissing: false
            )
        }
        var sources: [String] = []
        if facts.variability != nil { sources.append("HRV") }
        if facts.sleep != nil { sources.append("sleep") }

        var strains: [String] = []
        if facts.status.holdsTrainingBack {
            strains.append(facts.status == .unwell ? "you marked yourself unwell" : "you are on a planned rest")
        }
        if facts.variabilityTrend == .down { strains.append("your HRV is below your usual") }
        if facts.sleepTrend == .down { strains.append("last night was short") }

        if !strains.isEmpty {
            let reason = strains.formatted(.list(type: .and))
            return AskAnswer(
                lead: "I\u{2019}d keep tomorrow easy.",
                rest: "Today \(reason). See how tonight goes and ask again in the morning.",
                signals: sources.count, sources: sources, move: nil, followUps: followUps, isModelMissing: false
            )
        }
        let readings = [facts.variability.map { "HRV at \($0) ms" }, facts.sleep.map { "\($0) of sleep" }]
            .compactMap { $0 }
            .formatted(.list(type: .and))
        return AskAnswer(
            lead: "Your readings support a hard session.",
            rest: "\(readings.prefix(1).uppercased())\(readings.dropFirst()) sit at or above your usual. Ask again tomorrow morning, after tonight\u{2019}s sleep.",
            signals: sources.count, sources: sources, move: nil, followUps: followUps, isModelMissing: false
        )
    }

    static func normalized(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: "?!. "))
    }
}
