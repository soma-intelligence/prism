//
//  NextMoveEngine.swift
//  Prism
//
//  The Next Best Action engine. Plain values and pure functions: a rule reads a context built from
//  what Health and the person's own logs hold, and proposes one move with the
//  number that asked for it. The arbiter gates, collapses by domain and ranks.
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
    case exercise, exerciseUsual
    case water, waterTarget
    case caffeine
    case protein, proteinUsual
    case dietaryEnergy, energyBurned
    case respiratoryRate, respiratoryRateBaseline
    case habitualBedtime
    case eveningCheckIn
}

/// The hours a move is worth reading. Outside them it leaves the race.
///
/// An end before the start wraps past midnight: 23 to 5 is the night.
struct NextMoveWindow: Equatable, Sendable {
    var startHour: Int
    var endHour: Int

    func contains(hour: Int) -> Bool {
        if startHour == endHour { return true }
        if startHour < endHour { return hour >= startHour && hour < endHour }
        return hour >= startHour || hour < endHour
    }
}

/// Severity, leverage and timeliness, each 0 to 100, and the rank they make.
struct NextMoveImpact: Equatable, Sendable {
    let severity: Int
    let leverage: Int
    let timeliness: Int
    let score: Int

    init(severity: Int, leverage: Int, timeliness: Int) {
        self.severity = Self.clamp(severity)
        self.leverage = Self.clamp(leverage)
        self.timeliness = Self.clamp(timeliness)
        let product = self.severity * self.leverage * self.timeliness
        score = product > 0 ? max(1, product / 10_000) : 0
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
    static func sleepEarlier(minutes debt: Int) -> Int { clamp(debt, step: 5, floor: 15, ceiling: 90) }

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
    /// What the orb and the card say: short, an instruction.
    var title: String
    /// Why, in one or two sentences, the first one carrying the number.
    var message: String
    var evidence: [NextMoveEvidence]
    /// The aspect whose orb wears the move.
    var aspect: SomaAspect
    var door: NextMoveDoor
    var actionTitle: String
    var window: NextMoveWindow?
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
/// first. Evidence, actionability, timing and
/// contradiction gates, then one candidate per domain, then tier, impact and id.
struct NextMoveArbiter {
    let rules: [any NextMoveRule]

    init(rules: [any NextMoveRule] = NextMoveRules.catalog) {
        self.rules = rules
    }

    /// Moves that advise more effort. Never offered while recovery is
    /// well under the person's own usual.
    static let effortIDs: Set<String> = ["movementGap.walk"]

    func rank(_ ctx: NextMoveContext) -> [NextMoveCandidate] {
        let admitted = rules
            .filter { rule in rule.requiredSignals.allSatisfy(ctx.has) }
            .compactMap { rule in rule.evaluate(ctx) }
            .filter { !$0.evidence.isEmpty && $0.impact.score > 0 }
            .filter { candidate in candidate.expiresAt.map { $0 > ctx.now } ?? true }
            .filter { candidate in candidate.window.map { $0.contains(hour: ctx.hour) } ?? true }
            .filter { !contradicts($0, ctx) }

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

    func winner(_ ctx: NextMoveContext) -> NextMoveCandidate? {
        rank(ctx).first
    }

    private func contradicts(_ candidate: NextMoveCandidate, _ ctx: NextMoveContext) -> Bool {
        guard Self.effortIDs.contains(candidate.id),
              let recovery = ctx.recoveryScore, let objective = ctx.recoveryObjective else { return false }
        return objective - recovery >= RecoveryDeficitRule.minimumGap
    }

    static func isHigher(_ lhs: NextMoveCandidate, _ rhs: NextMoveCandidate) -> Bool {
        if lhs.tier != rhs.tier { return lhs.tier > rhs.tier }
        if lhs.impact.score != rhs.impact.score { return lhs.impact.score > rhs.impact.score }
        return lhs.id < rhs.id
    }
}
