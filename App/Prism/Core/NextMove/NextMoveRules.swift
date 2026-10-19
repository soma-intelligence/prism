//
//  NextMoveRules.swift
//  Prism
//
//  The rules Soma has the data for. A rule whose signal Soma cannot
//  fill yet (sun, travel) is left out rather than registered dead.
//

import Foundation
import SomaUI

enum NextMoveRules {
    static let catalog: [any NextMoveRule] = [
        SleepDebtRule(),
        LateNightRule(),
        StressDownshiftRule(),
        RestingHeartRateRule(),
        RecoveryDeficitRule(),
        IllnessWatchRule(),
        MovementGapRule(),
        HydrationGapRule(),
        CaffeineRule(),
        ProteinGapRule(),
        EnergyDeficitRule(),
        EveningCheckInRule(),
    ]
}

/// Last night came in short of this person's usual: go to bed earlier.
struct SleepDebtRule: NextMoveRule {
    let id = "sleepDebt"
    let domain = NextMoveDomain.sleep
    let requiredSignals: [NextMoveSignal] = [.sleepDuration, .sleepNeed]

    static let minimumDebtMinutes = 30
    private let fullDebtMinutes = 150.0

    func evaluate(_ ctx: NextMoveContext) -> NextMoveCandidate? {
        guard ctx.isNearBedtime(lead: 3),
              let slept = ctx.sleepSeconds, let need = ctx.sleepNeedSeconds else { return nil }
        let debt = Int((need - slept) / 60)
        guard debt >= Self.minimumDebtMinutes else { return nil }

        let impact = NextMoveImpact(
            severity: NextMoveImpact.severity(deviation: Double(debt), full: fullDebtMinutes),
            leverage: NextMoveLeverage.sleepDebt,
            timeliness: NextMoveImpact.timeliness(minutesLeft: ctx.minutesLeftToday, windowMinutes: 10 * 60)
        )
        let earlier = NextMoveAsk.sleepEarlier(minutes: debt)
        return NextMoveCandidate(
            id: "sleepDebt.extendTonight",
            domain: domain,
            tier: debt >= 90 ? .urgent : .improve,
            impact: impact,
            title: "Bed \(earlier) minutes earlier",
            message: "Last night came in \(NextMoveContext.span(minutes: debt)) under your usual. An earlier night gives most of it back.",
            evidence: [NextMoveEvidence(
                label: "Asleep against your usual",
                value: "\(NextMoveContext.span(minutes: Int(slept / 60))) of \(NextMoveContext.span(minutes: Int(need / 60)))"
            )],
            aspect: .sleep,
            door: .lastNight,
            actionTitle: "See last night",
            window: NextMoveWindow(startHour: 14, endHour: 0)
        )
    }
}

/// Well past the usual bedtime and still up.
struct LateNightRule: NextMoveRule {
    let id = "lateNight"
    let domain = NextMoveDomain.circadian
    let requiredSignals: [NextMoveSignal] = [.habitualBedtime]

    private let minimumLateMinutes = 45
    private let severeLateMinutes = 180

    func evaluate(_ ctx: NextMoveContext) -> NextMoveCandidate? {
        guard let bed = ctx.habitualBedHour, let hours = ctx.hoursUntilBedtime else { return nil }
        let late = Int((-hours * 60).rounded())
        guard late >= minimumLateMinutes, late <= 12 * 60 else { return nil }

        let impact = NextMoveImpact(
            severity: max(45, NextMoveImpact.severity(
                deviation: Double(late - minimumLateMinutes),
                full: Double(severeLateMinutes - minimumLateMinutes)
            )),
            leverage: NextMoveLeverage.lateNight,
            timeliness: 100
        )
        return NextMoveCandidate(
            id: "lateNight.lightsOut",
            domain: domain,
            tier: .improve,
            impact: impact,
            title: "Lights out now",
            message: "You’re \(NextMoveContext.span(minutes: late)) past your usual bedtime. Every minute now comes off tomorrow morning.",
            evidence: [NextMoveEvidence(label: "Usual bedtime", value: NextMoveContext.clock(hour: bed))],
            aspect: .sleep,
            door: .lastNight,
            actionTitle: "See last night",
            window: NextMoveWindow(startHour: 23, endHour: 5)
        )
    }
}

/// A stressed day with no calm in it yet: breathe.
struct StressDownshiftRule: NextMoveRule {
    let id = "stressDownshift"
    let domain = NextMoveDomain.stress
    let requiredSignals: [NextMoveSignal] = [.stressScore]

    static let highStress = 60
    static let urgentStress = 80
    private let calmMinutes = 5.0

    func evaluate(_ ctx: NextMoveContext) -> NextMoveCandidate? {
        guard let stress = ctx.stressScore else { return nil }
        let peaks = ctx.stressPeaks ?? 0
        guard stress >= Self.highStress || peaks >= 2,
              (ctx.mindfulMinutes ?? 0) < calmMinutes else { return nil }

        let severity = NextMoveImpact.severity(
            deviation: Double(max(stress - Self.highStress, 0)),
            full: Double(100 - Self.highStress)
        )
        let impact = NextMoveImpact(severity: max(40, severity), leverage: NextMoveLeverage.stressDownshift, timeliness: 100)
        var evidence = [NextMoveEvidence(label: "Stress today", value: "\(stress) of 100")]
        if peaks > 0 {
            evidence.append(NextMoveEvidence(label: "Stress peaks", value: "\(peaks)"))
        }
        let why = peaks >= 2
            ? "\(peaks) stress peaks since you woke, stress at \(stress)."
            : "Stress is at \(stress) today."
        return NextMoveCandidate(
            id: "stressDownshift.breathe",
            domain: domain,
            tier: stress >= Self.urgentStress ? .urgent : .improve,
            impact: impact,
            title: "Breathe for 10 minutes",
            message: "\(why) Four in, six out is the quickest way back.",
            evidence: evidence,
            aspect: .mind,
            door: .breathe,
            actionTitle: "Start",
            window: NextMoveWindow(startHour: 10, endHour: 21)
        )
    }
}

/// Resting heart rate well above its usual: ease off.
struct RestingHeartRateRule: NextMoveRule {
    let id = "restingHeartRate"
    let domain = NextMoveDomain.recovery
    let requiredSignals: [NextMoveSignal] = [.restingHeartRate, .restingHeartRateBaseline]

    static let minimumRise = 5.0
    static let urgentRise = 10.0

    func evaluate(_ ctx: NextMoveContext) -> NextMoveCandidate? {
        guard let rate = ctx.restingHeartRate, let usual = ctx.restingHeartRateBaseline, usual > 0 else { return nil }
        let rise = rate - usual
        guard rise >= Self.minimumRise else { return nil }

        let impact = NextMoveImpact(
            severity: max(40, NextMoveImpact.severity(deviation: rise, full: Self.urgentRise * 2)),
            leverage: NextMoveLeverage.restingHeartRate,
            timeliness: 100
        )
        return NextMoveCandidate(
            id: "restingHeartRate.easeOff",
            domain: domain,
            tier: rise >= Self.urgentRise ? .urgent : .improve,
            impact: impact,
            title: "Keep today easy",
            message: "Resting heart rate is \(Int(rise.rounded())) above your usual. An easy day and a full night usually bring it down.",
            evidence: [NextMoveEvidence(
                label: "Resting heart rate",
                value: "\(Int(rate.rounded())) against \(Int(usual.rounded())) bpm"
            )],
            aspect: .heart,
            door: .restingHeart,
            actionTitle: "See your heart"
        )
    }
}

/// Recovery well under this person's own usual.
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

        let impact = NextMoveImpact(
            severity: NextMoveImpact.severity(deviation: Double(gap), full: fullGap),
            leverage: NextMoveLeverage.recoveryDeficit,
            timeliness: NextMoveImpact.timeliness(minutesLeft: ctx.minutesLeftToday, windowMinutes: 14 * 60)
        )
        var evidence = [NextMoveEvidence(label: "Recovery against your usual", value: "\(score) of \(usual)")]
        if let hrv = ctx.hrv, let base = ctx.hrvBaseline {
            evidence.append(NextMoveEvidence(label: "HRV", value: "\(Int(hrv.rounded())) against \(Int(base.rounded())) ms"))
        }
        return NextMoveCandidate(
            id: "recoveryDeficit.easyDay",
            domain: domain,
            tier: gap >= urgentGap ? .urgent : .improve,
            impact: impact,
            title: "An easy day",
            message: "Recovery is \(gap) under your usual. Keep the effort light and the evening early.",
            evidence: evidence,
            aspect: .heart,
            door: .restingHeart,
            actionTitle: "See your heart"
        )
    }
}

/// Two or three of the night's signals moved together, the way they do when
/// something is coming on.
struct IllnessWatchRule: NextMoveRule {
    let id = "illnessWatch"
    let domain = NextMoveDomain.vitals
    let requiredSignals: [NextMoveSignal] = []

    static let respiratoryDeviation = 0.05
    static let temperatureRise = 0.3
    static let heartRateRise = 3.0

    func evaluate(_ ctx: NextMoveContext) -> NextMoveCandidate? {
        var moved: [NextMoveEvidence] = []
        var severities: [Int] = []

        if let temperature = ctx.wristTemperature, let base = ctx.wristTemperatureBaseline {
            let rise = temperature - base
            if rise >= Self.temperatureRise {
                moved.append(NextMoveEvidence(label: "Wrist temperature", value: String(format: "+%.1f °C", rise)))
                severities.append(NextMoveImpact.severity(deviation: rise, full: 1.0))
            }
        }
        if let rate = ctx.respiratoryRate, let base = ctx.respiratoryRateBaseline, base > 0 {
            let fraction = (rate - base) / base
            if fraction >= Self.respiratoryDeviation {
                moved.append(NextMoveEvidence(label: "Breathing", value: String(format: "%.1f against %.1f", rate, base)))
                severities.append(NextMoveImpact.severity(deviation: fraction, full: 0.20))
            }
        }
        if let rate = ctx.restingHeartRate, let base = ctx.restingHeartRateBaseline, base > 0 {
            let rise = rate - base
            if rise >= Self.heartRateRise {
                moved.append(NextMoveEvidence(label: "Resting heart rate", value: "\(Int(rate.rounded())) against \(Int(base.rounded())) bpm"))
                severities.append(NextMoveImpact.severity(deviation: rise, full: 15))
            }
        }
        guard moved.count >= 2 else { return nil }

        let severity = severities.reduce(0, +) / severities.count
        return NextMoveCandidate(
            id: "illnessWatch.easeToday",
            domain: domain,
            tier: .urgent,
            impact: NextMoveImpact(severity: max(50, severity), leverage: NextMoveLeverage.illnessWatch, timeliness: 100),
            title: "Keep tonight light",
            message: "\(moved.count) of last night’s signals moved together. That’s often the first sign of a cold, so rest counts more than training today.",
            evidence: moved,
            aspect: .heart,
            door: .checkIn,
            actionTitle: "Check in"
        )
    }
}

/// Less exercise than this person usually has by this time of day: walk.
struct MovementGapRule: NextMoveRule {
    let id = "movementGap"
    let domain = NextMoveDomain.activity
    let requiredSignals: [NextMoveSignal] = [.exercise, .exerciseUsual]

    private let cutoffHour = 21

    func evaluate(_ ctx: NextMoveContext) -> NextMoveCandidate? {
        guard let done = ctx.exerciseMinutes, let usual = ctx.exerciseUsualByNow, usual > 0 else { return nil }
        let shortfall = usual - done
        guard shortfall >= max(10, usual * 0.3) else { return nil }

        let minutes = NextMoveAsk.movement(minutes: Int(shortfall.rounded()))
        let impact = NextMoveImpact(
            severity: NextMoveImpact.severity(deviation: shortfall, full: usual),
            leverage: NextMoveLeverage.movementGap,
            timeliness: NextMoveImpact.timeliness(minutesLeft: ctx.minutesLeft(untilHour: cutoffHour), windowMinutes: 10 * 60)
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
            window: NextMoveWindow(startHour: 11, endHour: 21)
        )
    }
}

/// Behind on water with the afternoon running out.
struct HydrationGapRule: NextMoveRule {
    let id = "hydrationGap"
    let domain = NextMoveDomain.intake
    let requiredSignals: [NextMoveSignal] = [.water, .waterTarget]

    private let minimumShortfall = 400
    private let cutoffHour = 20

    func evaluate(_ ctx: NextMoveContext) -> NextMoveCandidate? {
        guard let water = ctx.waterMl, let target = ctx.waterTargetMl, target > 0 else { return nil }
        let shortfall = target - water
        guard shortfall >= minimumShortfall else { return nil }

        let impact = NextMoveImpact(
            severity: NextMoveImpact.severity(deviation: Double(shortfall), full: Double(target)),
            leverage: NextMoveLeverage.hydrationGap,
            timeliness: NextMoveImpact.timeliness(minutesLeft: ctx.minutesLeft(untilHour: cutoffHour), windowMinutes: 8 * 60)
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
            window: NextMoveWindow(startHour: 12, endHour: 20)
        )
    }
}

/// Caffeine past the day's ceiling, or the last call before bed coming up.
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
        if let mg = ctx.caffeineMg, mg > Self.ceilingMg {
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
                window: NextMoveWindow(startHour: 10, endHour: 18)
            )
        }

        guard let bed = ctx.habitualBedHour, (ctx.caffeineMg ?? 0) > 0 else { return nil }
        let lastCallHour = (bed - Self.clearHours + 24).truncatingRemainder(dividingBy: 24)
        guard let lastCall = ctx.calendar.date(
            bySettingHour: Int(lastCallHour), minute: Int((lastCallHour - lastCallHour.rounded(.down)) * 60),
            second: 0, of: ctx.now
        ) else { return nil }
        let hoursLeft = lastCall.timeIntervalSince(ctx.now) / 3600
        guard hoursLeft > 0, hoursLeft <= leadHours else { return nil }

        let label = NextMoveContext.clock(hour: lastCallHour)
        return NextMoveCandidate(
            id: "caffeine.lastCall",
            domain: domain,
            tier: .improve,
            impact: NextMoveImpact(
                severity: 100,
                leverage: NextMoveLeverage.caffeineCeiling,
                timeliness: max(30, NextMoveImpact.timeliness(minutesLeft: Int((leadHours - hoursLeft) * 60), windowMinutes: Int(leadHours * 60)))
            ),
            title: "Last coffee by \(label)",
            message: "Eight hours before your usual bedtime, so it’s gone by the time you sleep.",
            evidence: [NextMoveEvidence(label: "Last call", value: label)],
            aspect: .gut,
            door: .quickAdd,
            actionTitle: "See today’s log",
            window: NextMoveWindow(startHour: 10, endHour: 18),
            expiresAt: lastCall
        )
    }
}

/// Protein well short of what this person usually eats in a day.
struct ProteinGapRule: NextMoveRule {
    let id = "proteinGap"
    let domain = NextMoveDomain.nutrition
    let requiredSignals: [NextMoveSignal] = [.protein, .proteinUsual]

    private let minimumShortfall = 25
    private let cutoffHour = 21

    func evaluate(_ ctx: NextMoveContext) -> NextMoveCandidate? {
        guard let protein = ctx.proteinGrams, let usual = ctx.proteinUsualGrams, usual > 0 else { return nil }
        let shortfall = usual - protein
        guard shortfall >= minimumShortfall else { return nil }

        let impact = NextMoveImpact(
            severity: NextMoveImpact.severity(deviation: Double(shortfall), full: Double(usual)),
            leverage: NextMoveLeverage.proteinGap,
            timeliness: NextMoveImpact.timeliness(minutesLeft: ctx.minutesLeft(untilHour: cutoffHour), windowMinutes: 9 * 60)
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
            window: NextMoveWindow(startHour: 12, endHour: 21)
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
            window: NextMoveWindow(startHour: 17, endHour: 22)
        )
    }
}

/// The evening check-in, while it is still worth answering.
struct EveningCheckInRule: NextMoveRule {
    let id = "eveningCheckIn"
    let domain = NextMoveDomain.ritual
    let requiredSignals: [NextMoveSignal] = [.eveningCheckIn]

    static let eveningHour = 19

    func evaluate(_ ctx: NextMoveContext) -> NextMoveCandidate? {
        guard ctx.hour >= Self.eveningHour, !ctx.checkedInToday else { return nil }
        return NextMoveCandidate(
            id: "eveningCheckIn.answer",
            domain: domain,
            tier: .maintain,
            impact: NextMoveImpact(
                severity: 60,
                leverage: NextMoveLeverage.checkIn,
                timeliness: NextMoveImpact.timeliness(minutesLeft: ctx.minutesLeftToday, windowMinutes: (24 - Self.eveningHour) * 60)
            ),
            title: "Check in before bed",
            message: "Three taps on energy, stress and body. Your feeling sits beside the numbers, and tomorrow’s plan reads both.",
            evidence: [NextMoveEvidence(label: "Evening check-in", value: "Not yet")],
            aspect: .mind,
            door: .checkIn,
            actionTitle: "Check in",
            window: NextMoveWindow(startHour: Self.eveningHour, endHour: 0)
        )
    }
}
