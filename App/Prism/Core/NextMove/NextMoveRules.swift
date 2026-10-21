//
//  NextMoveRules.swift
//  Prism
//
//  The rules Soma has the data for. A rule whose signal Soma cannot
//  fill yet (sun, travel) is left out rather than registered dead.
//
//  Every rule names the parts of the person's own day it speaks in, and
//  phrases itself for that part: a short night is a plan for the day in the
//  morning and an earlier bedtime only in the evening.
//

import Foundation
import SomaUI

enum NextMoveRules {
    static let catalog: [any NextMoveRule] = [
        SleepDebtRule(),
        BedtimeRule(),
        LateNightRule(),
        StressDownshiftRule(),
        RestingHeartRateRule(),
        RecoveryDeficitRule(),
        LowVariabilityRule(),
        IllnessWatchRule(),
        ReadyToTrainRule(),
        MovementGapRule(),
        HydrationGapRule(),
        CaffeineRule(),
        ProteinGapRule(),
        EnergyDeficitRule(),
        EveningCheckInRule(),
    ]
}

/// Last night came in short of this person's usual. In the morning that is a
/// plan for the day; in the evening, an earlier bedtime tonight. Never a
/// bedtime in the morning.
struct SleepDebtRule: NextMoveRule {
    let id = "sleepDebt"
    let domain = NextMoveDomain.sleep
    let requiredSignals: [NextMoveSignal] = [.sleepDuration, .sleepNeed]

    /// The smallest shortfall worth an earlier night.
    static let minimumDebtMinutes = 30
    /// The smallest shortfall worth changing the day's plan for.
    static let easeDebtMinutes = 45
    private let fullDebtMinutes = 150.0

    func evaluate(_ ctx: NextMoveContext) -> NextMoveCandidate? {
        guard let slept = ctx.sleepSeconds, let need = ctx.sleepNeedSeconds,
              let debt = ctx.sleepDebtMinutes, debt >= Self.minimumDebtMinutes else { return nil }
        let sleptText = NextMoveContext.span(minutes: Int(slept / 60))
        let debtText = NextMoveContext.span(minutes: debt)
        let evidence = [NextMoveEvidence(
            label: "Asleep against your usual",
            value: "\(sleptText) of \(NextMoveContext.span(minutes: Int(need / 60)))"
        )]
        let why = "Slept \(sleptText), \(debtText) under your usual"
        let confidence = NextMoveImpact.confidence(samples: ctx.sleepNights, minimum: 3, full: 10)
        let severity = NextMoveImpact.severity(deviation: Double(debt), full: fullDebtMinutes)

        switch ctx.part {
        case .morning, .midday:
            guard debt >= Self.easeDebtMinutes else { return nil }
            let coffee = ctx.habitualBedHour.map { _ in
                ", keep coffee before \(NextMoveContext.quarterClock(hour: ctx.caffeineCutoffHour))"
            } ?? ""
            return NextMoveCandidate(
                id: "sleepDebt.easyDay",
                domain: domain,
                tier: debt >= 90 ? .urgent : .improve,
                impact: NextMoveImpact(severity: severity, leverage: NextMoveLeverage.sleepDebt, timeliness: 100, confidence: confidence),
                title: "Easy day after a short night",
                message: "You slept \(sleptText), \(debtText) under your usual. Get daylight early\(coffee), and save hard training for another day.",
                evidence: evidence,
                aspect: .sleep,
                door: .lastNight,
                actionTitle: "See last night",
                orbWord: "Go easy",
                why: why,
                stance: .ease,
                parts: [.morning, .midday]
            )
        case .evening:
            let earlier = NextMoveAsk.sleepEarlier(minutes: debt)
            var title = "An early night tonight"
            var orbWord = "Bed early"
            if let base = ctx.bestBedHour ?? ctx.habitualBedHour {
                let target = base - Double(earlier) / 60
                // Past the target already: the move is now, not a time.
                if ctx.hoursUntil(clockHour: target) > 12 {
                    title = "Head to bed now"
                    orbWord = "Bed now"
                } else {
                    title = "In bed by \(NextMoveContext.quarterClock(hour: target))"
                }
            }
            return NextMoveCandidate(
                id: "sleepDebt.extendTonight",
                domain: domain,
                tier: debt >= 90 ? .urgent : .improve,
                impact: NextMoveImpact(severity: severity, leverage: NextMoveLeverage.sleepDebt, timeliness: 100, confidence: confidence),
                title: title,
                message: "Last night came in \(debtText) under your usual. An earlier night tonight gives most of it back.",
                evidence: evidence,
                aspect: .sleep,
                door: .lastNight,
                actionTitle: "See last night",
                orbWord: orbWord,
                why: why,
                parts: [.evening]
            )
        case .afternoon, .night:
            return nil
        }
    }
}

/// In the evening, when this person's longest nights usually begin.
struct BedtimeRule: NextMoveRule {
    let id = "bedtime"
    let domain = NextMoveDomain.sleep
    let requiredSignals: [NextMoveSignal] = []

    func evaluate(_ ctx: NextMoveContext) -> NextMoveCandidate? {
        guard let best = ctx.bestBedHour, let latest = ctx.bestBedLatestHour,
              ctx.hoursUntil(clockHour: best) <= 12 else { return nil }
        let target = NextMoveContext.quarterClock(hour: best)
        let before = NextMoveContext.clock(hour: (latest * 4).rounded(.up) / 4)
        return NextMoveCandidate(
            id: "bedtime.usual",
            domain: domain,
            tier: .maintain,
            impact: NextMoveImpact(severity: 60, leverage: NextMoveLeverage.bedtime, timeliness: 100),
            title: "In bed by \(target)",
            message: "Your longest nights this month started before \(before).",
            evidence: [NextMoveEvidence(label: "Your longest nights began", value: "before \(before)")],
            aspect: .sleep,
            door: .lastNight,
            actionTitle: "See last night",
            orbWord: "Wind down",
            why: "Your longest nights began before \(before)",
            parts: [.evening]
        )
    }
}

/// Well past the usual bedtime and still up. Said in the first hours of the
/// night only: close to the usual wake, getting up is the better move.
struct LateNightRule: NextMoveRule {
    let id = "lateNight"
    let domain = NextMoveDomain.circadian
    let requiredSignals: [NextMoveSignal] = [.habitualBedtime]

    private let minimumLateMinutes = 45
    private let latestLateMinutes = 4 * 60
    private let severeLateMinutes = 180
    private let minimumHoursBeforeWake = 2.0

    func evaluate(_ ctx: NextMoveContext) -> NextMoveCandidate? {
        guard let bed = ctx.habitualBedHour,
              let past = ctx.day.hoursPastBedtime(at: ctx.now, calendar: ctx.calendar) else { return nil }
        let late = Int((past * 60).rounded())
        guard late >= minimumLateMinutes, late <= latestLateMinutes,
              ctx.day.hoursUntilWake(at: ctx.now, calendar: ctx.calendar) >= minimumHoursBeforeWake else { return nil }

        let impact = NextMoveImpact(
            severity: max(45, NextMoveImpact.severity(
                deviation: Double(late - minimumLateMinutes),
                full: Double(severeLateMinutes - minimumLateMinutes)
            )),
            leverage: NextMoveLeverage.lateNight,
            timeliness: 100
        )
        let lateText = NextMoveContext.span(minutes: late)
        return NextMoveCandidate(
            id: "lateNight.lightsOut",
            domain: domain,
            tier: .improve,
            impact: impact,
            title: "Lights out now",
            message: "You’re \(lateText) past your usual bedtime. Every minute now comes off tomorrow morning.",
            evidence: [NextMoveEvidence(label: "Usual bedtime", value: NextMoveContext.clock(hour: bed))],
            aspect: .sleep,
            door: .lastNight,
            actionTitle: "See last night",
            orbWord: "Lights out",
            why: "\(lateText) past your usual \(NextMoveContext.clock(hour: bed)) bedtime",
            parts: [.night]
        )
    }
}

/// A stressed day, or a heart raised at rest within the last hour and a half,
/// with no calm in it yet: breathe.
struct StressDownshiftRule: NextMoveRule {
    let id = "stressDownshift"
    let domain = NextMoveDomain.stress
    let requiredSignals: [NextMoveSignal] = []

    static let highStress = 60
    static let urgentStress = 80
    /// How long a single peak stays worth answering.
    static let recentPeak: TimeInterval = 90 * 60
    private let calmMinutes = 5.0

    func evaluate(_ ctx: NextMoveContext) -> NextMoveCandidate? {
        let stress = ctx.stressScore
        let peaks = ctx.stressPeaks ?? 0
        let recent = ctx.lastPeakEnd.map { ctx.now.timeIntervalSince($0) <= Self.recentPeak && $0 <= ctx.now } ?? false
        guard (stress ?? 0) >= Self.highStress || peaks >= 2 || recent,
              (ctx.mindfulMinutes ?? 0) < calmMinutes else { return nil }

        var evidence: [NextMoveEvidence] = []
        if let stress { evidence.append(NextMoveEvidence(label: "Stress today", value: "\(stress) of 100")) }
        if peaks > 0 { evidence.append(NextMoveEvidence(label: "Stress peaks", value: "\(peaks)")) }

        let why: String
        if recent, let end = ctx.lastPeakEnd, let above = ctx.lastPeakAbove {
            let start = ctx.clock(ctx.lastPeakStart ?? end)
            why = "Heart \(Int(above.rounded())) above resting at \(start), while still"
            evidence.append(NextMoveEvidence(label: "Latest peak", value: "\(start), +\(Int(above.rounded())) bpm"))
        } else if peaks >= 2 {
            why = "\(peaks) stress peaks since you woke"
        } else if let stress {
            why = "Stress at \(stress) today"
        } else {
            why = "A stress peak since you woke"
        }

        let severity = NextMoveImpact.severity(
            deviation: Double(max((stress ?? 0) - Self.highStress, 0)),
            full: Double(100 - Self.highStress)
        )
        return NextMoveCandidate(
            id: "stressDownshift.breathe",
            domain: domain,
            tier: (stress ?? 0) >= Self.urgentStress ? .urgent : .improve,
            impact: NextMoveImpact(severity: max(recent ? 60 : 40, severity), leverage: NextMoveLeverage.stressDownshift, timeliness: 100),
            title: "Breathe for 10 minutes",
            message: "\(why). Four in, six out is the quickest way back.",
            evidence: evidence,
            aspect: .mind,
            door: .breathe,
            actionTitle: "Start",
            orbWord: "Slow down",
            why: why,
            parts: NextMoveDayPart.daytime
        )
    }
}

/// Resting heart rate well above its usual: an easy day, or an easy evening.
struct RestingHeartRateRule: NextMoveRule {
    let id = "restingHeartRate"
    let domain = NextMoveDomain.recovery
    let requiredSignals: [NextMoveSignal] = [.restingHeartRate, .restingHeartRateBaseline]

    static let minimumRise = 5.0
    static let urgentRise = 10.0

    func evaluate(_ ctx: NextMoveContext) -> NextMoveCandidate? {
        guard let rate = ctx.restingHeartRate, let usual = ctx.restingHeartRateBaseline, usual > 0 else { return nil }
        // Compared in whole beats, as the heart card prints it, so a card that
        // reads "5 above your usual" and the move it asks for agree.
        let rise = (rate - usual).rounded()
        guard rise >= Self.minimumRise else { return nil }
        let evening = ctx.part == .evening

        let impact = NextMoveImpact(
            severity: max(40, NextMoveImpact.severity(deviation: rise, full: Self.urgentRise * 2)),
            leverage: NextMoveLeverage.restingHeartRate,
            timeliness: 100,
            confidence: NextMoveImpact.confidence(
                samples: ctx.restingHeartRateDays, minimum: 5, full: 21, isFresh: ctx.restingHeartRateIsToday
            )
        )
        let riseText = "\(Int(rise.rounded()))"
        return NextMoveCandidate(
            id: evening ? "restingHeartRate.easyEvening" : "restingHeartRate.easeOff",
            domain: domain,
            tier: rise >= Self.urgentRise ? .urgent : .improve,
            impact: impact,
            title: evening ? "Keep tonight easy" : "Keep today easy",
            message: evening
                ? "Resting heart rate is \(riseText) above your usual. A calm evening and a full night usually bring it down."
                : "Resting heart rate is \(riseText) above your usual. An easy day and a full night usually bring it down.",
            evidence: [NextMoveEvidence(
                label: "Resting heart rate",
                value: "\(Int(rate.rounded())) against \(Int(usual.rounded())) bpm"
            )],
            aspect: .heart,
            door: .restingHeart,
            actionTitle: "See your heart",
            orbWord: "Ease off",
            why: "Resting heart rate \(riseText) above your usual",
            stance: .ease,
            parts: NextMoveDayPart.awake
        )
    }
}

/// Recovery well under this person's own usual: the day's load, said while
/// the day is still ahead.
struct RecoveryDeficitRule: NextMoveRule {
    let id = "recoveryDeficit"
    let domain = NextMoveDomain.recovery
    let requiredSignals: [NextMoveSignal] = [.recoveryScore, .recoveryObjective]

    static let minimumGap = 8
    private let fullGap = 40.0
    private let urgentGap = 25

    func evaluate(_ ctx: NextMoveContext) -> NextMoveCandidate? {
        guard let score = ctx.recoveryScore, let usual = ctx.recoveryObjective else { return nil }
        let gap = usual - score
        guard gap >= Self.minimumGap else { return nil }

        var evidence = [NextMoveEvidence(label: "Recovery against your usual", value: "\(score) of \(usual)")]
        if let hrv = ctx.hrv, let base = ctx.hrvBaseline {
            evidence.append(NextMoveEvidence(label: "HRV", value: "\(Int(hrv.rounded())) against \(Int(base.rounded())) ms"))
        }
        return NextMoveCandidate(
            id: "recoveryDeficit.easyDay",
            domain: domain,
            tier: gap >= urgentGap ? .urgent : .improve,
            impact: NextMoveImpact(
                severity: NextMoveImpact.severity(deviation: Double(gap), full: fullGap),
                leverage: NextMoveLeverage.recoveryDeficit,
                timeliness: 100
            ),
            title: "An easy day",
            message: "Recovery is \(gap) under your usual. Keep the effort light and the evening early.",
            evidence: evidence,
            aspect: .heart,
            door: .restingHeart,
            actionTitle: "See your heart",
            orbWord: "Easy day",
            why: "Recovery \(score), \(gap) under your usual",
            stance: .ease,
            parts: [.morning, .midday]
        )
    }
}

/// Heart rate variability well under this person's usual: a gentler pace.
struct LowVariabilityRule: NextMoveRule {
    let id = "lowVariability"
    let domain = NextMoveDomain.recovery
    let requiredSignals: [NextMoveSignal] = [.heartRateVariability]

    /// The share of the usual under which HRV counts as low.
    static let share = 0.9
    private let fullDrop = 0.3

    func evaluate(_ ctx: NextMoveContext) -> NextMoveCandidate? {
        guard let hrv = ctx.hrv, let usual = ctx.hrvBaseline, usual > 0, hrv <= usual * Self.share else { return nil }
        let drop = (usual - hrv) / usual
        let now = Int(hrv.rounded())
        let base = Int(usual.rounded())
        return NextMoveCandidate(
            id: "lowVariability.gently",
            domain: domain,
            tier: .improve,
            impact: NextMoveImpact(
                severity: max(40, NextMoveImpact.severity(deviation: drop, full: fullDrop)),
                leverage: NextMoveLeverage.lowVariability,
                timeliness: 100
            ),
            title: "Go gently today",
            message: "HRV is \(now) ms, under your usual \(base). Slow breathing and an easy pace help it come back.",
            evidence: [NextMoveEvidence(label: "HRV", value: "\(now) against \(base) ms")],
            aspect: .mind,
            door: .breathe,
            actionTitle: "Start",
            orbWord: "Slow down",
            why: "HRV \(now) ms against your usual \(base)",
            stance: .ease,
            parts: NextMoveDayPart.daytime
        )
    }
}

/// Two or three of the night's signals moved together, the way they do when
/// the body is under strain.
struct IllnessWatchRule: NextMoveRule {
    let id = "illnessWatch"
    let domain = NextMoveDomain.vitals
    let requiredSignals: [NextMoveSignal] = []

    static let respiratoryDeviation = 0.05
    static let temperatureRise = 0.3
    static let heartRateRise = 3.0

    func evaluate(_ ctx: NextMoveContext) -> NextMoveCandidate? {
        var moved: [NextMoveEvidence] = []
        var names: [String] = []
        var severities: [Int] = []

        if let temperature = ctx.wristTemperature, let base = ctx.wristTemperatureBaseline {
            let rise = temperature - base
            if rise >= Self.temperatureRise {
                moved.append(NextMoveEvidence(label: "Wrist temperature", value: String(format: "+%.1f °C", rise)))
                names.append("wrist temperature")
                severities.append(NextMoveImpact.severity(deviation: rise, full: 1.0))
            }
        }
        if let rate = ctx.respiratoryRate, let base = ctx.respiratoryRateBaseline, base > 0 {
            let fraction = (rate - base) / base
            if fraction >= Self.respiratoryDeviation {
                moved.append(NextMoveEvidence(label: "Breathing", value: String(format: "%.1f against %.1f", rate, base)))
                names.append("breathing")
                severities.append(NextMoveImpact.severity(deviation: fraction, full: 0.20))
            }
        }
        if let rate = ctx.restingHeartRate, let base = ctx.restingHeartRateBaseline, base > 0 {
            let rise = rate - base
            if rise >= Self.heartRateRise {
                moved.append(NextMoveEvidence(label: "Resting heart rate", value: "\(Int(rate.rounded())) against \(Int(base.rounded())) bpm"))
                names.append("resting heart rate")
                severities.append(NextMoveImpact.severity(deviation: rise, full: 15))
            }
        }
        guard moved.count >= 2 else { return nil }

        let severity = severities.reduce(0, +) / severities.count
        let evening = ctx.part == .evening
        let list = names.count == 2 ? names.joined(separator: " and ") : names.dropLast().joined(separator: ", ") + " and " + names[names.count - 1]
        return NextMoveCandidate(
            id: evening ? "illnessWatch.easeTonight" : "illnessWatch.easeToday",
            domain: domain,
            tier: .urgent,
            impact: NextMoveImpact(severity: max(50, severity), leverage: NextMoveLeverage.illnessWatch, timeliness: 100),
            title: evening ? "An early, easy night" : "Rest over training today",
            message: "\(moved.count) of last night’s signals moved together. When they do, rest counts more than training, and a full night helps most.",
            evidence: moved,
            aspect: .heart,
            door: .checkIn,
            actionTitle: "Check in",
            orbWord: "Rest up",
            why: "\(list.prefix(1).uppercased() + list.dropFirst()) up together last night",
            stance: .ease,
            parts: NextMoveDayPart.awake
        )
    }
}

/// Recovery above this person's usual, nothing asking for ease, and no
/// workout yet: a good day for the hard session, said while it can be had.
struct ReadyToTrainRule: NextMoveRule {
    let id = "readyToTrain"
    let domain = NextMoveDomain.activity
    let requiredSignals: [NextMoveSignal] = [.recoveryScore, .recoveryObjective]

    static let minimumLead = 5
    static let minimumScore = 60

    func evaluate(_ ctx: NextMoveContext) -> NextMoveCandidate? {
        guard let score = ctx.recoveryScore, let usual = ctx.recoveryObjective,
              score - usual >= Self.minimumLead, score >= Self.minimumScore,
              !ctx.asksForEase, (ctx.workoutsToday ?? 0) == 0, (ctx.exerciseMinutes ?? 0) < 20 else { return nil }
        let lead = score - usual
        return NextMoveCandidate(
            id: "readyToTrain.push",
            domain: domain,
            tier: .maintain,
            impact: NextMoveImpact(
                severity: max(50, NextMoveImpact.severity(deviation: Double(lead), full: 20)),
                leverage: NextMoveLeverage.readyToTrain,
                timeliness: 100
            ),
            title: "A good day to train",
            message: "Recovery is \(score), above your usual \(usual). If a hard session is on your list, today suits it.",
            evidence: [NextMoveEvidence(label: "Recovery against your usual", value: "\(score) of \(usual)")],
            aspect: .activity,
            door: .restingHeart,
            actionTitle: "See your heart",
            orbWord: "Train today",
            why: "Recovery \(score), \(lead) above your usual",
            stance: .effort,
            parts: [.morning, .midday]
        )
    }
}

/// Less exercise than this person usually has by this time of day, and no
/// workout yet: walk.
struct MovementGapRule: NextMoveRule {
    let id = "movementGap"
    let domain = NextMoveDomain.activity
    let requiredSignals: [NextMoveSignal] = [.exercise, .exerciseUsual]

    func evaluate(_ ctx: NextMoveContext) -> NextMoveCandidate? {
        guard let done = ctx.exerciseMinutes, let usual = ctx.exerciseUsualByNow, usual > 0,
              (ctx.workoutsToday ?? 0) == 0 else { return nil }
        let shortfall = usual - done
        guard shortfall >= max(10, usual * 0.3) else { return nil }

        let minutes = NextMoveAsk.movement(minutes: Int(shortfall.rounded()))
        let impact = NextMoveImpact(
            severity: NextMoveImpact.severity(deviation: shortfall, full: usual),
            leverage: NextMoveLeverage.movementGap,
            timeliness: NextMoveImpact.timeliness(minutesLeft: ctx.minutesLeft(beforeBedtime: 3), windowMinutes: 10 * 60)
        )
        return NextMoveCandidate(
            id: "movementGap.walk",
            domain: domain,
            tier: .improve,
            impact: impact,
            title: "Walk for \(minutes) minutes",
            message: "\(Int(done.rounded())) min of exercise so far. By now you usually have \(Int(usual.rounded())).",
            evidence: [NextMoveEvidence(label: "Exercise by now", value: "\(Int(done.rounded())) of \(Int(usual.rounded())) min")],
            aspect: .activity,
            door: .walk(minutes: minutes),
            actionTitle: "Start",
            orbWord: "Move now",
            why: "\(Int(done.rounded())) of your usual \(Int(usual.rounded())) min of exercise by now",
            stance: .effort,
            parts: [.midday, .afternoon]
        )
    }
}

/// Behind on water with the day running out.
struct HydrationGapRule: NextMoveRule {
    let id = "hydrationGap"
    let domain = NextMoveDomain.intake
    let requiredSignals: [NextMoveSignal] = [.water, .waterTarget]

    private let minimumShortfall = 400

    func evaluate(_ ctx: NextMoveContext) -> NextMoveCandidate? {
        guard let water = ctx.waterMl, let target = ctx.waterTargetMl, target > 0 else { return nil }
        let shortfall = target - water
        guard shortfall >= minimumShortfall else { return nil }

        let impact = NextMoveImpact(
            severity: NextMoveImpact.severity(deviation: Double(shortfall), full: Double(target)),
            leverage: NextMoveLeverage.hydrationGap,
            timeliness: NextMoveImpact.timeliness(minutesLeft: ctx.minutesLeft(beforeBedtime: 3), windowMinutes: 8 * 60)
        )
        let ask = NextMoveAsk.water(ml: shortfall)
        return NextMoveCandidate(
            id: "hydrationGap.drink",
            domain: domain,
            tier: .improve,
            impact: impact,
            title: "Drink \(ask) ml",
            message: "\(HomeFormat.litres(water)) of \(HomeFormat.litres(target)) so far today.",
            evidence: [NextMoveEvidence(label: "Water today", value: "\(water) of \(target) ml")],
            aspect: .gut,
            door: .quickAdd,
            actionTitle: "Add water",
            orbWord: "Drink water",
            why: "\(HomeFormat.litres(water)) of \(HomeFormat.litres(target)) of water so far",
            parts: [.midday, .afternoon]
        )
    }
}

/// Caffeine past the day's ceiling, the last call before the cut off, or a
/// late cup to wind down after. Each only on its side of the cut off.
struct CaffeineRule: NextMoveRule {
    let id = "caffeine"
    let domain = NextMoveDomain.circadian
    let requiredSignals: [NextMoveSignal] = []

    /// The daily amount the EFSA and the FDA both name for healthy adults.
    static let ceilingMg = 400
    /// Hours before bed after which caffeine still sits in the blood.
    static let clearHours = 8.0
    private let leadHours = 3.0

    func evaluate(_ ctx: NextMoveContext) -> NextMoveCandidate? {
        let cutoff = ctx.caffeineCutoffHour
        let cutoffText = NextMoveContext.quarterClock(hour: cutoff)
        // Hours to the cut off, or negative once past it, on the side of the
        // day the person is awake for.
        let sinceWake = ctx.day.hoursSinceWake(at: ctx.now, calendar: ctx.calendar)
        let cutoffSinceWake = NextMoveDay.wrap(cutoff - ctx.day.anchorHour(calendar: ctx.calendar))
        let hoursLeft = cutoffSinceWake - sinceWake

        if ctx.part == .evening {
            return late(ctx, cutoff: cutoff, cutoffText: cutoffText)
        }

        if let mg = ctx.caffeineMg, mg > Self.ceilingMg, hoursLeft > 0 {
            return NextMoveCandidate(
                id: "caffeine.noneLeft",
                domain: domain,
                tier: .improve,
                impact: NextMoveImpact(severity: 100, leverage: NextMoveLeverage.caffeineCeiling, timeliness: 100),
                title: "No more caffeine today",
                message: "\(mg) mg so far, past the 400 mg a day most adults sleep well under.",
                evidence: [NextMoveEvidence(label: "Caffeine today", value: "\(mg) mg")],
                aspect: .gut,
                door: .quickAdd,
                actionTitle: "See today’s log",
                orbWord: "Skip coffee",
                why: "\(mg) mg of caffeine today",
                parts: NextMoveDayPart.daytime
            )
        }

        guard ctx.habitualBedHour != nil, (ctx.caffeineMg ?? 0) > 0,
              hoursLeft > 0, hoursLeft <= leadHours else { return nil }
        return NextMoveCandidate(
            id: "caffeine.lastCall",
            domain: domain,
            tier: .improve,
            impact: NextMoveImpact(
                severity: 100,
                leverage: NextMoveLeverage.caffeineCeiling,
                timeliness: max(30, NextMoveImpact.timeliness(minutesLeft: Int((leadHours - hoursLeft) * 60), windowMinutes: Int(leadHours * 60)))
            ),
            title: "Last coffee by \(cutoffText)",
            message: "Eight hours before your usual bedtime, so it’s gone by the time you sleep.",
            evidence: [NextMoveEvidence(label: "Last call", value: cutoffText)],
            aspect: .gut,
            door: .quickAdd,
            actionTitle: "See today’s log",
            orbWord: "Last coffee",
            why: "Eight hours before your usual bedtime",
            parts: NextMoveDayPart.daytime,
            expiresAt: ctx.now.addingTimeInterval(hoursLeft * 3600)
        )
    }

    /// A cup after the cut off: the evening move is to make room for sleep.
    private func late(_ ctx: NextMoveContext, cutoff: Double, cutoffText: String) -> NextMoveCandidate? {
        guard ctx.habitualBedHour != nil, let last = ctx.lastCaffeine,
              ctx.calendar.isDate(last, inSameDayAs: ctx.now) || ctx.now.timeIntervalSince(last) < 12 * 3600,
              last <= ctx.now else { return nil }
        let lastHour = NextMoveDay.decimalHour(last, calendar: ctx.calendar)
        let lateBy = NextMoveDay.wrap(lastHour - cutoff)
        guard lateBy > 0.25, lateBy < Self.clearHours else { return nil }
        let at = ctx.clock(last)
        return NextMoveCandidate(
            id: "caffeine.late",
            domain: domain,
            tier: .improve,
            impact: NextMoveImpact(
                severity: max(40, NextMoveImpact.severity(deviation: lateBy, full: 4)),
                leverage: NextMoveLeverage.caffeineCeiling,
                timeliness: 100
            ),
            title: "Dim the lights early",
            message: "Your last coffee was at \(at), after your \(cutoffText) cut off. Low light and a calm last hour help sleep come anyway.",
            evidence: [NextMoveEvidence(label: "Last coffee", value: at), NextMoveEvidence(label: "Cut off", value: cutoffText)],
            aspect: .sleep,
            door: .quickAdd,
            actionTitle: "See today’s log",
            orbWord: "Wind down",
            why: "Coffee at \(at), after your \(cutoffText) cut off",
            parts: [.evening]
        )
    }
}

/// Protein well short of what this person usually eats in a day.
struct ProteinGapRule: NextMoveRule {
    let id = "proteinGap"
    let domain = NextMoveDomain.nutrition
    let requiredSignals: [NextMoveSignal] = [.protein, .proteinUsual]

    private let minimumShortfall = 25

    func evaluate(_ ctx: NextMoveContext) -> NextMoveCandidate? {
        guard let protein = ctx.proteinGrams, let usual = ctx.proteinUsualGrams, usual > 0 else { return nil }
        let shortfall = usual - protein
        guard shortfall >= minimumShortfall else { return nil }

        let impact = NextMoveImpact(
            severity: NextMoveImpact.severity(deviation: Double(shortfall), full: Double(usual)),
            leverage: NextMoveLeverage.proteinGap,
            timeliness: NextMoveImpact.timeliness(minutesLeft: ctx.minutesLeft(beforeBedtime: 2), windowMinutes: 9 * 60)
        )
        return NextMoveCandidate(
            id: "proteinGap.eat",
            domain: domain,
            tier: .improve,
            impact: impact,
            title: "\(NextMoveAsk.protein(grams: shortfall)) g of protein at dinner",
            message: "\(protein) g so far; your days usually reach \(usual) g.",
            evidence: [NextMoveEvidence(label: "Protein today", value: "\(protein) of \(usual) g")],
            aspect: .gut,
            door: .logMeal,
            actionTitle: "Log a meal",
            orbWord: "Eat protein",
            why: "\(protein) of your usual \(usual) g of protein",
            parts: [.afternoon, .evening]
        )
    }
}

/// Eaten far less than burned on a big day.
struct EnergyDeficitRule: NextMoveRule {
    let id = "energyDeficit"
    let domain = NextMoveDomain.nutrition
    let requiredSignals: [NextMoveSignal] = [.dietaryEnergy, .energyBurned]

    private let deficitShare = 0.66
    private let minimumBurn = 1_400
    private let minimumShortfall = 350

    func evaluate(_ ctx: NextMoveContext) -> NextMoveCandidate? {
        guard let eaten = ctx.dietaryEnergyKcal, eaten > 0,
              let burned = ctx.energyBurnedKcal, burned >= minimumBurn else { return nil }
        let floor = Int(Double(burned) * deficitShare)
        let shortfall = floor - eaten
        guard shortfall >= minimumShortfall else { return nil }

        return NextMoveCandidate(
            id: "energyDeficit.eat",
            domain: domain,
            tier: .improve,
            impact: NextMoveImpact(
                severity: NextMoveImpact.severity(deviation: Double(shortfall), full: Double(floor)),
                leverage: NextMoveLeverage.energyDeficit,
                timeliness: 100
            ),
            title: "Eat \(NextMoveAsk.energy(kcal: shortfall)) kcal more",
            message: "\(eaten) kcal eaten against \(burned) burned. A proper dinner keeps tomorrow’s energy up.",
            evidence: [NextMoveEvidence(label: "Eaten against burned", value: "\(eaten) of \(burned) kcal")],
            aspect: .gut,
            door: .logMeal,
            actionTitle: "Log a meal",
            orbWord: "Eat well",
            why: "\(eaten) kcal eaten against \(burned) burned",
            parts: [.evening]
        )
    }
}

/// The evening check-in, while it is still worth answering.
struct EveningCheckInRule: NextMoveRule {
    let id = "eveningCheckIn"
    let domain = NextMoveDomain.ritual
    let requiredSignals: [NextMoveSignal] = [.eveningCheckIn]

    func evaluate(_ ctx: NextMoveContext) -> NextMoveCandidate? {
        guard ctx.checkedInToday == false else { return nil }
        return NextMoveCandidate(
            id: "eveningCheckIn.answer",
            domain: domain,
            tier: .maintain,
            impact: NextMoveImpact(
                severity: 60,
                leverage: NextMoveLeverage.checkIn,
                timeliness: NextMoveImpact.timeliness(
                    minutesLeft: ctx.minutesLeft(beforeBedtime: 0),
                    windowMinutes: Int(NextMoveDay.eveningHours * 60)
                )
            ),
            title: "Check in before bed",
            message: "Three taps on energy, stress and body. Your feeling sits beside the numbers, and tomorrow’s plan reads both.",
            evidence: [NextMoveEvidence(label: "Evening check-in", value: "Not yet")],
            aspect: .mind,
            door: .checkIn,
            actionTitle: "Check in",
            orbWord: "Check in",
            why: "Today’s check-in is still open",
            parts: [.evening]
        )
    }
}
