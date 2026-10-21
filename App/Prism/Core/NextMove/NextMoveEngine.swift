//
//  NextMoveEngine.swift
//  Prism
//
//  The Next Best Action engine. Plain values and pure functions: a rule reads a context built from
//  what Health and the person's own logs hold, and proposes one move with the
//  number that asked for it, for the parts of the person's own day it fits.
//  The arbiter gates, settles contradictions, rests what was already said,
//  collapses by domain and ranks; with nothing worth saying it says so.
//

import Foundation
import SomaUI

/// How urgent a move is. A higher tier wins over a lower one whatever the
/// impact.
enum NextMoveTier: Int, Comparable, Sendable, CaseIterable {
    /// Nothing wrong; protect what already works.
    case maintain
    /// A real gap worth closing today.
    case improve
    /// Acting today matters.
    case urgent

    static func < (lhs: NextMoveTier, rhs: NextMoveTier) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// What a move is about. At most one rule per domain reaches the ranking, so
/// two sleep rules never compete for the one card.
enum NextMoveDomain: String, Sendable, CaseIterable {
    case sleep, recovery, activity, stress, intake, nutrition, circadian, vitals, ritual
}

/// One input a rule depends on. The evidence gate rejects a rule whose
/// signals are missing before it runs.
enum NextMoveSignal: Sendable, CaseIterable {
    case sleepDuration, sleepNeed
    case recoveryScore, recoveryObjective
    case restingHeartRate, restingHeartRateBaseline
    case stressScore, stressPeaks
    case heartRateVariability
    case exercise, exerciseUsual
    case water, waterTarget
    case caffeine
    case protein, proteinUsual
    case dietaryEnergy, energyBurned
    case respiratoryRate, respiratoryRateBaseline
    case habitualBedtime
    case eveningCheckIn
}

/// Which way a move pushes the day. Effort and ease never reach the card
/// together: an easy day wins.
enum NextMoveStance: Sendable {
    case effort, ease, neutral
}

/// Severity, leverage, timeliness and confidence, each 0 to 100, and the
/// rank they make.
///
/// Severity is how far a signal sits from this person's own usual, and
/// confidence how much that usual and the reading can be trusted: a fresh
/// reading against a month of days scores higher than yesterday's against a
/// handful.
struct NextMoveImpact: Equatable, Sendable {
    let severity: Int
    let leverage: Int
    let timeliness: Int
    let confidence: Int
    let score: Int

    init(severity: Int, leverage: Int, timeliness: Int, confidence: Int = 100) {
        self.severity = Self.clamp(severity)
        self.leverage = Self.clamp(leverage)
        self.timeliness = Self.clamp(timeliness)
        self.confidence = Self.clamp(confidence)
        let product = self.severity * self.leverage * self.timeliness * self.confidence
        score = product > 0 ? max(1, product / 1_000_000) : 0
    }

    /// Confidence in a usual read from `samples` days or nights: 70 at the
    /// fewest the rule accepts, all of it from `full` on, and a fifth less
    /// when the reading is not from today.
    /// An unknown count (a context built by hand) is taken as enough.
    static func confidence(samples: Int?, minimum: Int, full: Int, isFresh: Bool = true) -> Int {
        guard let samples else { return isFresh ? 100 : 80 }
        guard samples >= minimum else { return 0 }
        let span = max(1, full - minimum)
        let base = 70 + 30 * min(samples - minimum, span) / span
        return isFresh ? base : base * 4 / 5
    }

    /// How far a value has gone, as a share of the distance that counts as
    /// all the way.
    static func severity(deviation: Double, full: Double) -> Int {
        guard full > 0, deviation > 0 else { return 0 }
        return clamp(Int((deviation / full * 100).rounded()))
    }

    /// How much of the window is left to act in.
    static func timeliness(minutesLeft: Int, windowMinutes: Int) -> Int {
        guard windowMinutes > 0, minutesLeft > 0 else { return 0 }
        return clamp(Int((Double(min(minutesLeft, windowMinutes)) / Double(windowMinutes) * 100).rounded()))
    }

    static func clamp(_ value: Int) -> Int { min(100, max(0, value)) }
}

/// How much acting on a domain tends to move the day.
enum NextMoveLeverage {
    static let sleepDebt = 100
    static let lateNight = 95
    static let bedtime = 60
    static let readyToTrain = 66
    static let lowVariability = 78
    static let illnessWatch = 96
    static let recoveryDeficit = 90
    static let restingHeartRate = 86
    static let movementGap = 80
    static let checkIn = 74
    static let stressDownshift = 70
    static let proteinGap = 62
    static let caffeineCeiling = 58
    static let hydrationGap = 52
    static let energyDeficit = 48
}

/// The size of what a move asks for, rounded to a step a person can act on.
enum NextMoveAsk {
    static func water(ml shortfall: Int) -> Int { clamp(shortfall, step: 100, floor: 100, ceiling: 1000) }
    static func protein(grams shortfall: Int) -> Int { clamp(shortfall, step: 5, floor: 5, ceiling: 60) }
    static func energy(kcal shortfall: Int) -> Int { clamp(shortfall, step: 50, floor: 50, ceiling: 800) }
    static func movement(minutes shortfall: Int) -> Int { clamp(shortfall, step: 5, floor: 10, ceiling: 60) }
    /// How much earlier to sleep after a short night: half the debt, in
    /// quarter hours, between a quarter hour and an hour.
    static func sleepEarlier(minutes debt: Int) -> Int { clamp(debt / 2, step: 15, floor: 15, ceiling: 60) }

    private static func clamp(_ raw: Int, step: Int, floor: Int, ceiling: Int) -> Int {
        min(ceiling, max(floor, (max(0, raw) / step) * step))
    }
}

/// One label and value the card shows as the receipt for the advice. A move
/// without one never reaches the card.
struct NextMoveEvidence: Equatable, Sendable {
    var label: String
    var value: String
}

/// Where a move's one action goes.
enum NextMoveDoor: Equatable, Sendable {
    case breathe
    case walk(minutes: Int)
    case checkIn
    case lastNight
    case restingHeart
    case nutrition
    case logMeal
    case quickAdd
}

/// A rule's proposal. Copy is final: the view only renders it.
struct NextMoveCandidate: Equatable, Sendable {
    var id: String
    var domain: NextMoveDomain
    var tier: NextMoveTier
    var impact: NextMoveImpact
    /// What the card says: short, an instruction.
    var title: String
    /// Why, in one or two sentences, the first one carrying the number.
    var message: String
    var evidence: [NextMoveEvidence]
    /// The aspect whose orb wears the move.
    var aspect: SomaAspect
    var door: NextMoveDoor
    var actionTitle: String
    /// The two words the orb wears.
    var orbWord: String
    /// One plain line from the evidence: what asked for the move.
    var why: String
    var stance: NextMoveStance = .neutral
    /// The parts of the person's day the move is worth reading in.
    var parts: Set<NextMoveDayPart> = NextMoveDayPart.awake
    var expiresAt: Date?
}

/// A pure function from context to an optional move. It never reads a clock
/// or a store: everything arrives in the context.
protocol NextMoveRule: Sendable {
    var id: String { get }
    var domain: NextMoveDomain { get }
    var requiredSignals: [NextMoveSignal] { get }
    func evaluate(_ ctx: NextMoveContext) -> NextMoveCandidate?
}

/// Runs the rules and decides which moves may reach the card, most pressing
/// first.
///
/// Gates, in order: the evidence a rule needs, a receipt and a real impact,
/// the part of the person's day, contradictions (no effort on a day that
/// asks for ease), what this person already acted on, and a rest for advice
/// that has led for hours. Then one candidate per domain, ranked by tier,
/// impact and id. A weak candidate (impact under ``minimumScore``) never
/// leads: the calm default is truer than a cue that barely applies.
struct NextMoveArbiter {
    let rules: [any NextMoveRule]

    init(rules: [any NextMoveRule] = NextMoveRules.catalog) {
        self.rules = rules
    }

    /// The lowest impact a move may lead with, unless it is urgent.
    static let minimumScore = 10

    func rank(_ ctx: NextMoveContext, history: NextMoveHistory = .empty) -> [NextMoveCandidate] {
        let part = ctx.part
        let evaluated = rules
            .filter { rule in rule.requiredSignals.allSatisfy(ctx.has) }
            .compactMap { rule in rule.evaluate(ctx) }
            .filter { !$0.evidence.isEmpty && $0.impact.score > 0 }
            .filter { candidate in candidate.expiresAt.map { $0 > ctx.now } ?? true }
            .filter { $0.parts.contains(part) }
            .filter { $0.tier == .urgent || $0.impact.score >= Self.minimumScore }
            .filter { !history.acted.contains($0.id) }
            .filter { $0.tier == .urgent || !history.isResting($0.id, at: ctx.now) }

        let easing = ctx.asksForEase || evaluated.contains { $0.stance == .ease }
        let admitted = evaluated.filter { !(easing && $0.stance == .effort) }

        var best: [NextMoveDomain: NextMoveCandidate] = [:]
        for candidate in admitted {
            if let incumbent = best[candidate.domain], !Self.isHigher(candidate, incumbent) { continue }
            best[candidate.domain] = candidate
        }
        return best.values.sorted { lhs, rhs in
            if Self.isHigher(lhs, rhs) { return true }
            if Self.isHigher(rhs, lhs) { return false }
            return lhs.domain.rawValue < rhs.domain.rawValue
        }
    }

    func winner(_ ctx: NextMoveContext, history: NextMoveHistory = .empty) -> NextMoveCandidate? {
        rank(ctx, history: history).first
    }

    /// The one cue for now: the winner, or the calm default when nothing is
    /// worth saying.
    func cue(_ ctx: NextMoveContext, history: NextMoveHistory = .empty) -> NextMoveCandidate {
        winner(ctx, history: history) ?? NextMoveSteady.cue(ctx)
    }

    static func isHigher(_ lhs: NextMoveCandidate, _ rhs: NextMoveCandidate) -> Bool {
        if lhs.tier != rhs.tier { return lhs.tier > rhs.tier }
        if lhs.impact.score != rhs.impact.score { return lhs.impact.score > rhs.impact.score }
        return lhs.id < rhs.id
    }
}
