//
//  NextMoveSteady.swift
//  Prism
//

import Foundation
import SomaUI

/// The calm default: what the orb says when no rule has anything worth
/// saying. It names what is going well, and only what was measured; with
/// nothing measured it claims nothing.
enum NextMoveSteady {
    static func cue(_ ctx: NextMoveContext) -> NextMoveCandidate {
        let part = ctx.part
        let going = goingWell(ctx)
        let night = part == .night
        let title = night ? "Rest well" : "A steady day"
        let message: String = {
            if night { return "Nothing needs doing now. Sleep is the move." }
            guard let first = going.first else { return "Nothing stands out from your usual right now." }
            return "\(first.sentence). Nothing else asks for a change."
        }()
        return NextMoveCandidate(
            id: "steady.\(part.rawValue)",
            domain: .ritual,
            tier: .maintain,
            impact: NextMoveImpact(severity: 0, leverage: 0, timeliness: 0),
            title: title,
            message: message,
            evidence: going.map(\.evidence),
            aspect: aspect(for: part),
            door: night ? .lastNight : .checkIn,
            actionTitle: night ? "See last night" : "Check in",
            orbWord: night ? "Rest well" : "Steady day",
            why: night ? "" : (going.first?.sentence ?? ""),
            parts: [part]
        )
    }

    static func aspect(for part: NextMoveDayPart) -> SomaAspect {
        switch part {
        case .morning: .body
        case .midday: .activity
        case .afternoon: .mind
        case .evening, .night: .sleep
        }
    }

    struct Going {
        var sentence: String
        var evidence: NextMoveEvidence
    }

    /// The readings sitting at or better than this person's usual, strongest
    /// first. Each is said only when both the reading and its usual exist.
    static func goingWell(_ ctx: NextMoveContext) -> [Going] {
        var found: [Going] = []
        if let slept = ctx.sleepSeconds, let need = ctx.sleepNeedSeconds, slept >= need - 20 * 60 {
            let span = NextMoveContext.span(minutes: Int(slept / 60))
            found.append(Going(
                sentence: slept >= need + 20 * 60 ? "Slept \(span), over your usual" : "Slept \(span), about your usual",
                evidence: NextMoveEvidence(label: "Asleep against your usual", value: "\(span) of \(NextMoveContext.span(minutes: Int(need / 60)))")
            ))
        }
        if let recovery = ctx.recoveryScore, let usual = ctx.recoveryObjective, recovery >= usual {
            found.append(Going(
                sentence: "Recovery \(recovery), at or above your usual",
                evidence: NextMoveEvidence(label: "Recovery against your usual", value: "\(recovery) of \(usual)")
            ))
        }
        if let rate = ctx.restingHeartRate, let usual = ctx.restingHeartRateBaseline, rate - usual < 2 {
            let gap = Int((usual - rate).rounded())
            found.append(Going(
                sentence: gap >= 2 ? "Resting heart rate \(gap) below your usual" : "Resting heart rate at your usual",
                evidence: NextMoveEvidence(label: "Resting heart rate", value: "\(Int(rate.rounded())) against \(Int(usual.rounded())) bpm")
            ))
        }
        if let done = ctx.exerciseMinutes, let usual = ctx.exerciseUsualByNow, usual > 0, done >= usual {
            found.append(Going(
                sentence: "\(Int(done.rounded())) min of exercise, ahead of your usual",
                evidence: NextMoveEvidence(label: "Exercise by now", value: "\(Int(done.rounded())) of \(Int(usual.rounded())) min")
            ))
        }
        return found
    }
}
