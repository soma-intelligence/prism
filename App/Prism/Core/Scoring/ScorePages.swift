//
//  ScorePages.swift
//  Prism
//

import Foundation
import HealthExportCore
import HealthScoring

/// The words and numbers of each score page, worked out from ``SomaScores``
/// and ``ScoreDetailInputs``. Pure, so every sentence a page says is tested
/// against the numbers it says it about.
///
/// A page before its gate says so: the score is nil, the headline says what
/// fills it, and every line under it is a dash.
nonisolated enum ScorePages {

    // MARK: - Shared

    /// The head of a score page: the gauge's value and word, the change
    /// under it, and the two part sentence under the gauge.
    struct Lead: Equatable, Sendable {
        var value: Int?
        /// The top of the scale.
        var scale: Int = 100
        var word: String?
        /// "6 below yesterday", "Target 42 to 58 today".
        var change: String?
        var changeTrend: Trend?
        /// Where today's value should land on the same scale: strain's target
        /// for the day, or the person's usual band for the other scores.
        /// Drawn on the gauge as a thin arc.
        var range: ClosedRange<Double>? = nil
        var headline: String
        /// The first sentence of the reason, in the primary ink.
        var reason: String
        /// What follows it, in the secondary ink.
        var aside: String?
    }

    enum Trend: Sendable { case up, down }

    /// A move the page offers at its foot.
    struct Move: Equatable, Sendable {
        var eyebrow: String
        var title: String
        var detail: String
        /// When the reminder should fire, as a clock hour today (or tonight).
        var remindAt: Double?
    }

    static func usual(_ values: [Double?], floor: Double) -> ScoringUsual? {
        ScoringUsual.of(values, spreadFloor: floor)
    }

    // MARK: - Recovery

    struct Recovery: Equatable, Sendable {
        var lead: Lead
        var lines: [ScoreMath.UsualLine]
        var readinessNote: String
        var move: Move?
        /// The terms, for the explanation sheet.
        var terms: [Term]
        var missing: [String]

        struct Term: Equatable, Identifiable, Sendable {
            var id: String { title }
            var title: String
            var detail: String
            var points: Double
            /// The most the term can add or take: the engine's per term caps
            /// (28 for HRV, 20 for resting heart rate, 16 for sleep) and the
            /// balanced model's 4 point rest credit.
            var cap: Double = 16
        }
    }

    static func recovery(_ scores: SomaScores?, _ inputs: ScoreDetailInputs?) -> Recovery {
        let value = scores?.recovery
        let series = scores?.recoverySeries ?? []
        let yesterday = ScoreMath.previous(series)
        var lead = Lead(value: value, headline: "", reason: "")
        // The usual band, the same one the Today dial draws, so the
        // gauge and the dial agree on where the score should sit.
        lead.range = InsightEngine.interpret(scores?.detail.recovery ?? [], policy: .score).band
        if let value {
            lead.word = recoveryWord(value)
            if let yesterday {
                let delta = Double(value) - yesterday
                lead.change = abs(delta) < 1 ? "Level with yesterday"
                    : "\(Int(abs(delta).rounded())) \(delta > 0 ? "above" : "below") yesterday"
                lead.changeTrend = abs(delta) < 1 ? nil : (delta > 0 ? .up : .down)
            }
            // A high score that fell a long way overnight, or sits on a
            // resting heart rate above usual, is still a green light, but not
            // the unqualified one: the reason under it names those signals,
            // and a headline that ignored them read as a contradiction.
            let rhr = scores?.recoveryTerms.first { $0.kind == .rhr }
            let fell = yesterday.map { Double(value) - $0 <= -10 } ?? false
            let restingUp = rhr.flatMap { term in term.value.flatMap { v in term.baseline.map { v - $0 >= 2 } } } ?? false
            switch ScoreMath.Band(value) {
            case .high where fell: lead.headline = "High recovery, lower than yesterday."
            case .high where restingUp: lead.headline = "High recovery, resting heart rate above usual."
            case .high: lead.headline = "High recovery. A hard session fits today."
            case .middle: lead.headline = "Moderate recovery. Keep training moderate."
            case .low: lead.headline = "Low recovery. Keep today easy."
            }
        } else {
            lead.headline = "Recovery needs seven nights."
            lead.reason = "Soma has \(scores?.nightsRecorded ?? 0) of the seven nights it reads your usual from."
            lead.aside = "Wear your watch to bed and the score appears on the eighth morning."
        }

        let terms = scores?.recoveryTerms ?? []
        let hrvTerm = terms.first { $0.kind == .hrv }
        let rhrTerm = terms.first { $0.kind == .rhr }
        if value != nil {
            var parts: [String] = []
            if let hrv = hrvTerm?.value, let base = hrvTerm?.baseline {
                parts.append("HRV is \(Int(hrv.rounded())) against your \(Int(base.rounded())) baseline")
            }
            if let rhr = rhrTerm?.value, let base = rhrTerm?.baseline {
                let delta = Int((rhr - base).rounded())
                parts.append(delta == 0 ? "your resting heart rate sits on its usual"
                             : "your resting heart rate sits \(abs(delta)) \(delta > 0 ? "above" : "below") usual")
            }
            lead.reason = parts.isEmpty ? "Scored from last night’s sleep alone." : parts.joined(separator: " and ") + "."
            if let sleep = scores?.sleep {
                lead.aside = "Sleep scored \(sleep) last night."
            }
        }

        let hrvUsual = usual(inputs?.hrv ?? [], floor: ScoringUsual.Floor.hrvMilliseconds)
        let restingUsual = usual(inputs?.resting ?? [], floor: ScoringUsual.Floor.restingHR)
        let sleepHours = scores?.detail.sleepHours.suffix(30) ?? []
        let breathing = inputs?.respiratory ?? []
        let lines = [
            ScoreMath.usualLine(title: "HRV", value: hrvTerm?.value ?? ScoreMath.latest(inputs?.hrv ?? []),
                                usual: hrvUsual, worse: .lower, format: { ScoreMath.number($0) }, unit: " ms"),
            ScoreMath.usualLine(title: "Resting heart rate",
                                value: rhrTerm?.value ?? ScoreMath.latest(inputs?.resting ?? []),
                                usual: restingUsual, worse: .higher, format: { ScoreMath.number($0) }, unit: " bpm"),
            ScoreMath.usualLine(title: "Sleep", value: sleepHours.last ?? nil,
                                usual: usual(Array(sleepHours.dropLast()), floor: ScoringUsual.Floor.sleepHours),
                                worse: .lower, format: ScoreMath.hoursMinutes),
            ScoreMath.usualLine(title: "Breathing", value: breathing.last ?? nil,
                                usual: usual(Array(breathing.dropLast()), floor: ScoringUsual.Floor.respiratoryRate),
                                worse: .either, format: { ScoreMath.number($0, decimals: 1) }, unit: " /min"),
        ]

        let target = scores?.strainTarget
        let note: String
        let move: Move?
        switch value.map(ScoreMath.Band.init) {
        case .high?:
            note = "Enough for a hard session today."
            move = Move(eyebrow: "Today", title: "Train in your target band",
                        detail: target.map { "Strain \($0.lowerBound) to \($0.upperBound) is what today can carry." }
                            ?? "Today can carry a hard session.", remindAt: nil)
        case .middle?:
            note = "Enough for an easy session today."
            move = Move(eyebrow: "Today", title: "A 30 minute walk after dinner",
                        detail: "Easy pace, in heart rate zone 2.", remindAt: 19.5)
        case .low?:
            note = "Keep today light and sleep early."
            move = Move(eyebrow: "Tonight", title: "An early night",
                        detail: "Recovery is low: an extra hour of sleep helps most tonight.", remindAt: 21.5)
        case nil:
            note = "Recovery appears after seven nights with your watch."
            move = nil
        }

        let named: [SomaScores.RecoveryTerm.Kind: String] = [
            .hrv: "HRV", .rhr: "Resting heart rate", .sleep: "Sleep", .rest: "Yesterday’s strain",
        ]
        let explained = terms.map { term -> Recovery.Term in
            let detail: String
            switch term.kind {
            case .hrv:
                detail = term.value.flatMap { v in term.baseline.map { "\(Int(v.rounded())) ms against \(Int($0.rounded())) usual" } } ?? "No reading"
            case .rhr:
                detail = term.value.flatMap { v in term.baseline.map { "\(Int(v.rounded())) bpm against \(Int($0.rounded())) usual" } } ?? "No reading"
            case .sleep:
                detail = term.value.map { "Sleep score \(Int($0.rounded()))" } ?? "No night"
            case .rest:
                detail = "A light day yesterday gives some back"
            }
            let caps: [SomaScores.RecoveryTerm.Kind: Double] = [.hrv: 28, .rhr: 20, .sleep: 16, .rest: 4]
            return Recovery.Term(title: named[term.kind] ?? "", detail: detail, points: term.points,
                                 cap: caps[term.kind] ?? 16)
        }
        let missing = (value == nil ? [] : scores?.recoveryMissing ?? []).compactMap { named[$0] }

        return Recovery(lead: lead, lines: lines, readinessNote: note, move: move, terms: explained, missing: missing)
    }

    static func recoveryWord(_ value: Int) -> String {
        switch ScoreMath.Band(value) {
        case .high: "Recovered"
        case .middle: "Partly recovered"
        case .low: "Run down"
        }
    }

    // MARK: - Strain

    struct Strain: Equatable, Sendable {
        var lead: Lead
        var activeEnergy: String?
        var steps: String?
        var standHours: String?
        var zones: [Zone]
        /// The seven day load, its productive band, and the load over the
        /// last sixty days.
        var load: Double?
        var loadBand: ClosedRange<Double>?
        var loadSeries: [Double?]
        var loadNote: String
        var lines: [ScoreMath.UsualLine]
        var workout: String?
        var workoutDetail: String?
        var move: Move?

        struct Zone: Equatable, Identifiable, Sendable {
            var id: Int
            var bpm: String
            var minutes: Double
        }
    }

    static func strain(_ scores: SomaScores?, _ inputs: ScoreDetailInputs?, calendar: Calendar = .current) -> Strain {
        let value = scores?.strain
        let target = scores?.strainTarget
        var lead = Lead(value: value, headline: "", reason: "")
        lead.word = value.map(strainWord)
        lead.change = target.map { "Target \($0.lowerBound) to \($0.upperBound) today" }
        lead.range = target.map { Double($0.lowerBound)...Double($0.upperBound) }
        if let value {
            if let target {
                if value < target.lowerBound {
                    lead.headline = "Below today’s target, with room to spare."
                    lead.reason = "\(target.lowerBound - value) more points would carry you into the \(target.lowerBound) to \(target.upperBound) band."
                } else if value <= target.upperBound {
                    lead.headline = "Inside today’s target."
                    lead.reason = "The day has carried what recovery said it could."
                } else {
                    lead.headline = "Past today’s target."
                    lead.reason = "More load today costs tomorrow more than it builds."
                }
                if let recovery = scores?.recovery { lead.aside = "Recovery is \(recovery), which sets the band." }
            } else {
                lead.headline = value < 34 ? "A light load so far." : value < 67 ? "A moderate load so far." : "A high load today."
                lead.reason = "The target band appears once recovery has seven nights."
            }
        } else {
            lead.headline = "No movement recorded today yet."
            lead.reason = "Strain counts your heart rate zones and active energy from the moment you wake."
        }

        // Heart rate zones today, on the engine's zone edges.
        let maxHR = SomaScoringEngine.maxHeartRate(ageYears: inputs?.age)
        var seconds = Array(repeating: 0.0, count: 5)
        let beats = inputs?.todayHeartRate ?? []
        for (index, beat) in beats.enumerated() {
            let next = index + 1 < beats.count ? beats[index + 1].start : nil
            let span = next.map { min(300, $0.timeIntervalSince(beat.start)) } ?? 60
            let ratio = beat.value / maxHR
            guard ratio >= 0.5 else { continue }
            let zone = min(4, Int((ratio - 0.5) * 10))
            seconds[zone] += span
        }
        let zones: [Strain.Zone] = beats.isEmpty ? [] : (0..<5).map { index in
            let low = Int((maxHR * (0.5 + Double(index) * 0.1)).rounded())
            let high = Int((maxHR * (0.6 + Double(index) * 0.1)).rounded()) - 1
            return Strain.Zone(id: index + 1, bpm: "\(low) to \(index == 4 ? Int(maxHR) : high) bpm",
                               minutes: seconds[index] / 60)
        }

        // Training load: the last seven days of TRIMP against the productive
        // band, 0.8 to 1.3 times the chronic 28 day week.
        let trimp = scores?.detail.trimp ?? []
        func weekLoad(endingAt end: Int) -> Double? {
            guard end >= 7, end <= trimp.count else { return nil }
            let week = trimp[(end - 7)..<end].compactMap { $0 }
            return week.count >= 4 ? week.reduce(0, +) / Double(week.count) * 7 : nil
        }
        let loadSeries = (max(7, trimp.count - 60)...max(7, trimp.count)).map { weekLoad(endingAt: $0) }
        let load = weekLoad(endingAt: trimp.count)
        let chronic = trimp.count >= 28 ? ScoreMath.mean(trimp.suffix(28)).map { $0 * 7 } : nil
        let band = chronic.map { ($0 * 0.8)...($0 * 1.3) }
        let loadNote: String = {
            guard let load, let band else { return "Needs a month of days to set your productive band." }
            if load < band.lowerBound { return "Under your productive band, \(Int(band.lowerBound)) to \(Int(band.upperBound))." }
            if load > band.upperBound { return "Over your productive band, \(Int(band.lowerBound)) to \(Int(band.upperBound))." }
            return "In your productive band, \(Int(band.lowerBound)) to \(Int(band.upperBound))."
        }()

        let strainSeries = scores?.detail.strain ?? []
        let weekStrain = ScoreMath.mean(strainSeries.suffix(7))
        let hrr = inputs?.heartRecovery ?? []
        let lines = [
            ScoreMath.usualLine(title: "Strain, daily average", value: weekStrain,
                                usual: usual(Array(strainSeries.suffix(30)), floor: ScoringUsual.Floor.scorePoints),
                                worse: .neither, format: { ScoreMath.number($0) }),
            ScoreMath.usualLine(title: "Training load, 7 days", value: load,
                                usual: band.map { ScoringUsual(center: ($0.lowerBound + $0.upperBound) / 2, low: $0.lowerBound, high: $0.upperBound, count: 28) },
                                worse: .either, format: { ScoreMath.number($0) },
                                empty: "Fills in after a month of days"),
            ScoreMath.usualLine(title: "Heart rate recovery", value: ScoreMath.latest(hrr),
                                usual: usual(hrr, floor: 2), worse: .lower,
                                format: { ScoreMath.number($0) }, unit: " bpm",
                                empty: "Read after a workout with Apple Watch"),
        ]

        let today = calendar.startOfDay(for: inputs?.now ?? Date())
        let latestWorkout = inputs?.workouts.last { $0.start >= today }
        let workout = latestWorkout.map {
            "\(FitnessActivities.name($0.code)) at \(ScoreMath.clock($0.start, calendar: calendar))"
        }
        let workoutDetail = latestWorkout.map { ScoreMath.duration(hours: $0.end.timeIntervalSince($0.start) / 3600) }

        var move: Move?
        if let value, let target, value < target.lowerBound {
            move = Move(eyebrow: "Tonight", title: "A 30 minute walk after dinner",
                        detail: "Brings today toward \(target.lowerBound) without asking anything of tomorrow.",
                        remindAt: 19.5)
        } else if let value, let target, value > target.upperBound {
            move = Move(eyebrow: "Tonight", title: "Stretch, then an early night",
                        detail: "The load is in. Sleep is where it turns into fitness.", remindAt: 21.5)
        }

        return Strain(
            lead: lead,
            activeEnergy: inputs?.activeEnergy.map { ScoreMath.number($0) },
            steps: inputs?.steps.map { ScoreMath.number($0) },
            standHours: inputs?.standHours.map { "\($0)" },
            zones: zones,
            load: load, loadBand: band, loadSeries: loadSeries, loadNote: loadNote,
            lines: lines, workout: workout, workoutDetail: workoutDetail, move: move)
    }

    static func strainWord(_ value: Int) -> String {
        switch ScoreMath.Band(value) {
        case .high: "Hard"
        case .middle: "Moderate"
        case .low: "Light"
        }
    }

    // MARK: - Stress

    struct Stress: Equatable, Sendable {
        var lead: Lead
        var line: [ScoringStressPoint]
        var highest: String?
        var lowest: String?
        var average: String?
        var peaks: [Date]
        var peaksNote: String
        /// Minutes in each band since waking: low, moderate, high.
        var bandMinutes: [Double]?
        var wakeTime: Date?
        var lines: [ScoreMath.UsualLine]
        var usual: Double?
    }

    static let stressBands = (moderate: 34.0, high: 67.0)

    static func stress(_ scores: SomaScores?, _ inputs: ScoreDetailInputs?, calendar: Calendar = .current) -> Stress {
        let value = scores?.stress
        let history = scores?.detail.stress ?? []
        let usualStress = ScoreMath.median(history.suffix(30).dropLast())
        var lead = Lead(value: value, headline: "", reason: "")
        // The usual band, the same one the Today dial draws, so the
        // gauge and the dial agree on where the score should sit.
        lead.range = InsightEngine.interpret(scores?.detail.stress ?? [], policy: .score).band
        lead.word = value.map(stressWord)
        if let value, let usualStress {
            let delta = Int((Double(value) - usualStress).rounded())
            lead.change = delta == 0 ? "On your usual" : "\(abs(delta)) \(delta > 0 ? "above" : "below") your usual"
            lead.changeTrend = delta == 0 ? nil : (delta > 0 ? .up : .down)
        }

        let now = inputs?.now ?? Date()
        let today = calendar.startOfDay(for: now)
        let terms = scores?.recoveryTerms ?? []
        let hrvTerm = terms.first { $0.kind == .hrv }
        let rhrTerm = terms.first { $0.kind == .rhr }
        var excluded = inputs?.recordedNights ?? []
        excluded += (inputs?.workouts ?? []).map { ScoringNightWindow(start: $0.start, end: $0.end) }
        let line = ScoringIntradayStress.line(
            heartRate: inputs?.todayHeartRate ?? [], dayStart: today, now: now, excluded: excluded,
            hrv: hrvTerm?.value, hrvBaseline: hrvTerm?.baseline,
            restingHR: rhrTerm?.value ?? rhrTerm?.baseline,
            maxHR: SomaScoringEngine.maxHeartRate(ageYears: inputs?.age))
        let values = line.map(\.value)

        // A peak is a half hour in the high band that stands above both
        // neighbours.
        var peaks: [Date] = []
        for index in line.indices where line[index].value >= stressBands.high {
            let before = index > 0 ? line[index - 1].value : 0
            let after = index + 1 < line.count ? line[index + 1].value : 0
            if line[index].value >= before && line[index].value >= after { peaks.append(line[index].start) }
        }
        let peakTimes = peaks.map { ScoreMath.clock($0, calendar: calendar) }
        let peaksNote: String
        switch peaks.count {
        case 0: peaksNote = line.isEmpty ? "The line draws from your heart rate through the day." : "No half hour reached the high band."
        case 1: peaksNote = "At \(peakTimes[0]). Sleep and workouts are left out of the line."
        default: peaksNote = "At \(peakTimes.dropLast().joined(separator: ", ")) and \(peakTimes.last!). Sleep and workouts are left out of the line."
        }

        if let value {
            if peaks.count >= 2 {
                lead.headline = "\(peaks.count) rises in pulse at rest today."
            } else if ScoreMath.Band(value) == .high {
                lead.headline = "Stress above your usual today."
            } else if ScoreMath.Band(value) == .low {
                lead.headline = "Stress under your usual so far."
            } else {
                lead.headline = "Stress in your usual range."
            }
            var reason: [String] = []
            if let hrv = hrvTerm?.value, let base = hrvTerm?.baseline {
                let delta = Int((hrv - base).rounded())
                reason.append(delta == 0 ? "HRV started on its baseline" : "HRV started \(abs(delta)) \(delta < 0 ? "under" : "over") your baseline")
            }
            if let rhr = rhrTerm?.value, let base = rhrTerm?.baseline {
                let delta = Int((rhr - base).rounded())
                if delta != 0 { reason.append("resting heart rate \(abs(delta)) \(delta > 0 ? "above" : "below") usual") }
            }
            lead.reason = reason.isEmpty ? "Scored from this morning’s heart readings." : reason.joined(separator: ", ") + "."
            lead.aside = "Stress reads how loaded the system is, not your mood."
        } else {
            lead.headline = "Stress needs seven days of heart readings."
            lead.reason = "It sets your HRV and resting heart rate against your own baseline."
            lead.aside = "Wear your watch through the day and night."
        }

        let wake = (inputs?.nights.last ?? nil).flatMap { calendar.isDate($0.end, inSameDayAs: now) ? $0.end : nil }
        let awake = line.filter { wake == nil || $0.start >= wake! }
        let bandMinutes: [Double]? = awake.isEmpty ? nil : [
            Double(awake.filter { $0.value < stressBands.moderate }.count * 30),
            Double(awake.filter { $0.value >= stressBands.moderate && $0.value < stressBands.high }.count * 30),
            Double(awake.filter { $0.value >= stressBands.high }.count * 30),
        ]

        let lines = [
            ScoreMath.usualLine(title: "HRV", value: hrvTerm?.value,
                                usual: usual(inputs?.hrv ?? [], floor: ScoringUsual.Floor.hrvMilliseconds),
                                worse: .lower, format: { ScoreMath.number($0) }, unit: " ms"),
            ScoreMath.usualLine(title: "Resting heart rate", value: rhrTerm?.value,
                                usual: usual(inputs?.resting ?? [], floor: ScoringUsual.Floor.restingHR),
                                worse: .higher, format: { ScoreMath.number($0) }, unit: " bpm"),
        ]

        return Stress(
            lead: lead, line: line,
            highest: values.max().map { ScoreMath.number($0) },
            lowest: values.min().map { ScoreMath.number($0) },
            average: ScoreMath.mean(values.map(Optional.some)).map { ScoreMath.number($0) },
            peaks: peaks, peaksNote: peaksNote, bandMinutes: bandMinutes, wakeTime: wake,
            lines: lines, usual: usualStress)
    }

    static func stressWord(_ value: Int) -> String {
        switch ScoreMath.Band(value) {
        case .high: "High"
        case .middle: "Moderate"
        case .low: "Low"
        }
    }

    // MARK: - Sleep

    struct Sleep: Equatable, Sendable {
        var lead: Lead
        var lines: [ScoreMath.UsualLine]
        var asleep: String?
        var stagesNote: String
        var stages: [ScoringStageRun]
        var debt: String?
        var dip: String?
        var breathing: String?
        var sound: String?
        var move: Move?
        var parts: [ScoringSleepPart]
    }

    static func sleep(_ scores: SomaScores?, _ inputs: ScoreDetailInputs?, calendar: Calendar = .current) -> Sleep {
        let value = scores?.sleep
        let detail = scores?.detail ?? SomaScores.Detail()
        let series = scores?.sleepSeries ?? []
        var lead = Lead(value: value, headline: "", reason: "")
        // The usual band, the same one the Today dial draws, so the
        // gauge and the dial agree on where the score should sit.
        lead.range = InsightEngine.interpret(scores?.detail.sleep ?? [], policy: .score).band
        lead.word = value.map(sleepWord)
        if let value, let lastWeek = ScoreMath.mean(series.dropLast().suffix(7)) {
            let delta = Int((Double(value) - lastWeek).rounded())
            lead.change = delta == 0 ? "Level with last week" : "\(abs(delta)) \(delta > 0 ? "above" : "below") last week"
            lead.changeTrend = delta == 0 ? nil : (delta > 0 ? .up : .down)
        }

        let stages = detail.lastNightStages
        let deepRuns = stages.filter { $0.stage == "deep" }
        let wakes = stages.filter { $0.stage == "awake" }
        let asleepHours = detail.sleepHours.last ?? nil
        if value != nil {
            if let firstDeep = deepRuns.first, let longest = deepRuns.max(by: { $0.end.timeIntervalSince($0.start) < $1.end.timeIntervalSince($1.start) }),
               longest == firstDeep {
                lead.headline = "Most of your deep sleep came early."
            } else if (asleepHours ?? 0) < (scores?.sleepNeedHours ?? 8) - 1 {
                lead.headline = "Under your sleep need."
            } else if wakes.count >= 4 {
                lead.headline = "Enough hours, woken \(wakes.count) times."
            } else {
                lead.headline = "Close to your need, few wakings."
            }
            var reason: [String] = []
            if let asleepHours { reason.append("\(ScoreMath.hoursMinutes(asleepHours)) asleep against your \(ScoreMath.hoursMinutes(scores?.sleepNeedHours ?? 8)) need") }
            if let first = deepRuns.first { reason.append("the first deep sleep came at \(ScoreMath.clock(first.start, calendar: calendar))") }
            lead.reason = reason.isEmpty ? "Scored from last night." : reason.joined(separator: ", ").scoreCapitalized + "."
            lead.aside = wakes.isEmpty ? nil : (wakes.count == 1 ? "You woke once." : "You woke \(wakes.count) times.")
        } else {
            lead.headline = "Your sleep score needs seven nights."
            lead.reason = "Soma has \(scores?.nightsRecorded ?? 0) of the seven nights it reads your usual from."
            lead.aside = "Wear your watch to bed; the score appears on the eighth morning."
        }

        let hours = Array(detail.sleepHours.suffix(31))
        let deep = Array(detail.deepHours.suffix(31))
        let rem = Array(detail.remHours.suffix(31))
        var latency: Double?
        if let inBed = inputs?.inBedStart, let first = stages.first(where: { $0.stage != "awake" }) {
            let minutes = first.start.timeIntervalSince(inBed) / 60
            if minutes >= 0 && minutes < 180 { latency = minutes }
        }
        let wakeTimes = wakes.prefix(2).map { ScoreMath.clock($0.start, calendar: calendar) }
        var lines = [
            ScoreMath.usualLine(title: "Asleep", value: hours.last ?? nil,
                                usual: usual(Array(hours.dropLast()), floor: ScoringUsual.Floor.sleepHours),
                                worse: .lower, format: ScoreMath.hoursMinutes),
            ScoreMath.usualLine(title: "Deep sleep", value: deep.last ?? nil,
                                usual: usual(Array(deep.dropLast()), floor: 0.1), worse: .lower, format: ScoreMath.hoursMinutes),
            ScoreMath.usualLine(title: "REM", value: rem.last ?? nil,
                                usual: usual(Array(rem.dropLast()), floor: 0.1), worse: .lower, format: ScoreMath.hoursMinutes),
        ]
        lines.append(ScoreMath.UsualLine(
            title: "Woke up", detail: stages.isEmpty ? "Needs a night with stages" : (wakeTimes.isEmpty ? "not once" : wakeTimes.joined(separator: " and ")),
            value: stages.isEmpty ? nil : "\(wakes.count)", position: nil, band: nil, isOff: wakes.count >= 4))
        lines.append(ScoreMath.UsualLine(
            title: "Fell asleep in", detail: latency == nil ? "Needs time in bed from your tracker" : "from getting into bed",
            value: latency.map { "\(Int($0.rounded())) min" }, position: nil, band: nil, isOff: (latency ?? 0) > 30))

        let asleepText = asleepHours.map(ScoreMath.hoursMinutes)
        let stagesNote: String = {
            guard let night = detail.lastNight, !stages.isEmpty else { return "Last night’s stages draw here once your watch records them." }
            return "Asleep at \(ScoreMath.clock(night.start, calendar: calendar)), up at \(ScoreMath.clock(night.end, calendar: calendar)). Deep sleep came in \(countWord(deepRuns.count)) \(deepRuns.count == 1 ? "block" : "blocks"), REM in \(countWord(stages.filter { $0.stage == "rem" }.count))."
        }()

        let dip = nightDip(scores, inputs)?.today
        let breathing = inputs?.respiratory.last ?? nil
        let sound = inputs?.nightSound.last ?? nil
        let bed = ScoreMath.median(detail.bedHour.suffix(14))
        let move = bed.map { bed in
            Move(eyebrow: "Tonight", title: "Lights out by \(ScoreMath.clock(bed - 0.25))",
                 detail: "Your bedtime last night against your usual one.", remindAt: bed - 0.75)
        }

        return Sleep(
            lead: lead, lines: lines, asleep: asleepText, stagesNote: stagesNote, stages: stages,
            debt: scores?.sleepDebtHours.map { ScoreMath.duration(hours: $0) },
            dip: dip.map { "\(Int($0.percent.rounded()))%" },
            breathing: breathing.map { "\(ScoreMath.number($0, decimals: 1)) /min" },
            sound: sound.map { "\(Int($0.rounded())) dB" },
            move: move, parts: detail.sleepParts)
    }

    static func sleepWord(_ value: Int) -> String {
        switch value {
        case 80...: "Restored"
        case 60..<80: "Fair"
        default: "Short"
        }
    }

    static func countWord(_ count: Int) -> String {
        ["no", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine"][min(count, 9)]
    }

    // MARK: - Sleep debt

    struct Debt: Equatable, Sendable {
        var value: String?
        var need: String
        var headline: String
        var reason: String
        var rows: [ScoreMath.TrendRow]
    }

    static func debt(_ scores: SomaScores?) -> Debt {
        let detail = scores?.detail ?? SomaScores.Detail()
        let need = ScoreMath.duration(hours: scores?.sleepNeedHours ?? 8)
        guard let debt = scores?.sleepDebtHours else {
            return Debt(value: nil, need: need, headline: "Sleep debt needs seven nights.",
                        reason: "It adds up what each night fell short of the \(need) you need.", rows: [])
        }
        let before = detail.sleepDebtHours.dropLast(3).last ?? nil
        let headline: String
        switch debt {
        case ..<0.25: headline = "Under 15 minutes behind."
        case ..<2: headline = "Under 2 hours behind."
        case ..<5: headline = "2 to 5 hours behind."
        default: headline = "Over 5 hours behind."
        }
        var reason = "You need about \(need) a night."
        if let before {
            let delta = (debt - before) * 60
            if abs(delta) >= 5 {
                reason += " It is \(Int(abs(delta).rounded())) minutes \(delta < 0 ? "smaller" : "larger") than three nights ago."
            }
        }
        let rows = ScoreMath.trendRows(detail.sleepDebtHours, deadBand: 10.0 / 60, higherIsWorse: true,
                                       words: ("Growing", "Shrinking", "Steady"),
                                       format: { ScoreMath.duration(hours: $0) })
        return Debt(value: ScoreMath.duration(hours: debt), need: need, headline: headline, reason: reason, rows: rows)
    }

    // MARK: - Night dip

    struct NightDip: Equatable, Sendable {
        var today: ScoringNightDip?
        var usualPercent: Double?
        /// The dip per night, oldest first, up to fourteen.
        var nights: [Double?]
        var headline: String
        var reason: String
        var restingHR: Double?
        var causes: [ScoreMath.UsualLine]
    }

    static func nightDip(_ scores: SomaScores?, _ inputs: ScoreDetailInputs?) -> NightDip? {
        let restingBase = ScoreMath.latest(scores?.detail.restingBaseline ?? [])
            ?? ScoreMath.median(inputs?.resting ?? [])
        let today = ScoringNightDip.reading(samples: inputs?.lastNightBeats ?? [], restingHR: restingBase)
        let perNight = (inputs?.nightHeartRate ?? []).map { ScoringNightDip.percent(meanSleepingHR: $0, restingHR: restingBase) }
        let nights = Array(perNight.suffix(14))
        let usualDip = ScoreMath.median(perNight.dropLast())
        guard today != nil || nights.contains(where: { $0 != nil }) else {
            return inputs == nil ? nil : NightDip(today: nil, usualPercent: nil, nights: nights,
                                                  headline: "Night dip needs your watch at night.",
                                                  reason: "It sets your sleeping heart rate against your resting baseline.",
                                                  restingHR: restingBase, causes: [])
        }
        var headline = "Your heart dipped as it usually does."
        var reason = "A fall of 10 to 20 percent below resting is the healthy range."
        if let today {
            if let usualDip, today.percent < usualDip - 2 {
                headline = "Your heart dipped less than usual last night."
                reason = "Late meals, alcohol, a warm room or a hard evening session are the usual reasons."
            } else if let usualDip, today.percent > usualDip + 2 {
                headline = "A deeper dip than usual."
                reason = "Your heart slowed further below resting than it usually does."
            }
        }
        let breathing = inputs?.respiratory ?? []
        let causes = [
            ScoreMath.usualLine(title: "Breathing", value: breathing.last ?? nil,
                                usual: usual(Array(breathing.dropLast()), floor: ScoringUsual.Floor.respiratoryRate),
                                worse: .higher, format: { ScoreMath.number($0, decimals: 1) }, unit: " /min"),
            ScoreMath.usualLine(title: "Sound", value: inputs?.nightSound.last ?? nil,
                                usual: usual(Array((inputs?.nightSound ?? []).dropLast()), floor: 2),
                                worse: .higher, format: { ScoreMath.number($0) }, unit: " dB",
                                empty: "Read by your watch or phone overnight"),
        ]
        return NightDip(today: today, usualPercent: usualDip, nights: nights, headline: headline, reason: reason,
                        restingHR: restingBase, causes: causes)
    }

    // MARK: - Breathing

    struct Breathing: Equatable, Sendable {
        var value: Double?
        var usual: ScoringUsual?
        var headline: String
        var reason: String
        var signals: [Signal]
        var inRange: Int
        var rows: [ScoreMath.TrendRow]

        struct Signal: Equatable, Identifiable, Sendable {
            var id: String { title }
            var title: String
            var values: [Double?]
            var usual: ScoringUsual?
            var latest: String?
            var inRange: Bool?
        }
    }

    static func breathing(_ inputs: ScoreDetailInputs?) -> Breathing {
        let series = inputs?.respiratory ?? []
        let value = series.last ?? nil
        let usualBand = usual(Array(series.dropLast()), floor: ScoringUsual.Floor.respiratoryRate)
        var run = 0
        if let usualBand {
            for night in series.reversed() {
                guard let night, night > usualBand.high else { break }
                run += 1
            }
        }
        let headline: String
        let reason: String
        if let value, let usualBand {
            if run >= 2 {
                headline = "Above your range for \(countWord(run)) nights running."
                reason = "Illness, alcohol, allergies or altitude are the usual reasons. Take it easy until it settles."
            } else if usualBand.contains(value) {
                headline = "Inside your usual range."
                reason = "Breathing barely moves night to night, so this is the quiet you want."
            } else {
                headline = value > usualBand.high ? "A little above your range last night." : "A little below your range last night."
                reason = "One night is a note, not a pattern."
            }
        } else if value != nil {
            headline = "Your range needs seven nights."
            reason = "Breathing rate is counted while you sleep."
        } else {
            headline = "No breathing rate last night."
            reason = "Apple Watch counts it while you sleep."
        }

        func signal(_ title: String, _ values: [Double?], floor: Double, format: (Double) -> String) -> Breathing.Signal {
            let band = usual(Array(values.dropLast()), floor: floor)
            let latest = values.last ?? nil
            return Breathing.Signal(title: title, values: Array(values.suffix(14)), usual: band,
                                    latest: latest.map(format), inRange: latest.flatMap { l in band.map { $0.contains(l) } })
        }
        let temperature = inputs?.wristTemperature ?? []
        let tempCenter = ScoreMath.median(temperature.dropLast())
        let signals = [
            signal("Asleep HR", inputs?.nightHeartRate ?? [], floor: ScoringUsual.Floor.restingHR) { ScoreMath.number($0) },
            signal("HRV", inputs?.hrv ?? [], floor: ScoringUsual.Floor.hrvMilliseconds) { ScoreMath.number($0) },
            signal("Breathing", series, floor: ScoringUsual.Floor.respiratoryRate) { ScoreMath.number($0, decimals: 1) },
            signal("Skin temp", temperature.map { v in v.flatMap { v in tempCenter.map { v - $0 } } },
                   floor: ScoringUsual.Floor.wristTemperature) { ScoreMath.signed($0, decimals: 1) },
        ]
        return Breathing(value: value, usual: usualBand, headline: headline, reason: reason, signals: signals,
                         inRange: signals.filter { $0.inRange == true }.count,
                         rows: ScoreMath.trendRows(series, deadBand: 0.3, higherIsWorse: true))
    }

    // MARK: - Energy

    struct Energy: Equatable, Sendable {
        var lead: Lead
        var lastNight: Int?
        var opened: Int?
        var openedAt: Date?
        var charged: Int?
        var drained: Int?
        var high: Int?
        var highAt: Date?
        var ledger: [Entry]
        var move: Move?

        struct Entry: Equatable, Identifiable, Sendable {
            var id: String { title }
            var title: String
            var span: String
            var points: Int
        }
    }

    static func energy(_ scores: SomaScores?, calendar: Calendar = .current) -> Energy {
        let curve = scores?.energyCurve ?? []
        let now = scores?.energy
        let wake = scores?.detail.lastNight.flatMap { night in
            curve.contains { $0.date <= night.end } ? night.end : nil
        }
        let before = curve.first
        let open = wake.flatMap { wake in curve.min { abs($0.date.timeIntervalSince(wake)) < abs($1.date.timeIntervalSince(wake)) } }
        let highPoint = curve.filter { wake == nil || $0.date >= wake! }.max { $0.level < $1.level }
        let lastNight = before.map { Int($0.level.rounded()) }
        let opened = open.map { Int($0.level.rounded()) }
        var charged: Int?
        var drained: Int?
        if let opened, let lastNight { charged = opened - lastNight }
        if let now, let opened { drained = now - opened }

        var lead = Lead(value: now, headline: "", reason: "")
        lead.word = now.map(energyWord)
        if let now {
            switch ScoreMath.Band(now) {
            case .high: lead.headline = "High for this time of day."
            case .middle: lead.headline = "Moderate for this time of day."
            case .low: lead.headline = "Low. An early night refills it."
            }
            var reason: [String] = []
            if let charged { reason.append("Sleep put \(charged) back overnight") }
            if let opened { reason.append("the bank opened at \(opened)") }
            lead.reason = reason.isEmpty ? "The bank now." : reason.joined(separator: " and ").scoreCapitalized + "."
            if let drained, let openedAt = open?.date {
                lead.aside = "The day has drawn it \(drained < 0 ? "down \(-drained)" : "up \(drained)") since \(ScoreMath.clock(openedAt, calendar: calendar))."
            }
        } else {
            lead.headline = "The energy bank needs a night."
            lead.reason = "It opens each morning at what sleep put back, and spends through the day."
        }

        // Where it went: the waking curve cut into sleep, morning, afternoon
        // and evening.
        var ledger: [Energy.Entry] = []
        if let before, let open, open.date > before.date {
            ledger.append(.init(title: "Sleep", span: "\(ScoreMath.clock(before.date, calendar: calendar)) to \(ScoreMath.clock(open.date, calendar: calendar))",
                                points: Int((open.level - before.level).rounded())))
        }
        if let open, let last = curve.last {
            let day = calendar.startOfDay(for: last.date)
            let cuts: [(String, Int, Int)] = [("Morning", 0, 12), ("Afternoon", 12, 17), ("Evening", 17, 24)]
            for (title, from, to) in cuts {
                let start = max(open.date, calendar.date(byAdding: .hour, value: from, to: day) ?? day)
                let end = min(last.date, calendar.date(byAdding: .hour, value: to, to: day) ?? day)
                guard end > start,
                      let a = curve.min(by: { abs($0.date.timeIntervalSince(start)) < abs($1.date.timeIntervalSince(start)) }),
                      let b = curve.min(by: { abs($0.date.timeIntervalSince(end)) < abs($1.date.timeIntervalSince(end)) }),
                      b.date > a.date else { continue }
                let isNow = end == last.date
                ledger.append(.init(title: isNow && title != "Morning" ? "\(title) so far" : title,
                                    span: "\(ScoreMath.clock(start, calendar: calendar)) to \(isNow ? "now" : ScoreMath.clock(end, calendar: calendar))",
                                    points: Int((b.level - a.level).rounded())))
            }
        }

        let bed = ScoreMath.median(scores?.detail.bedHour.suffix(14) ?? [])
        let move = bed.map { bed in
            Move(eyebrow: "Tonight", title: "Screens off by \(ScoreMath.clock(bed - 0.75))",
                 detail: "A calm last hour lets sleep put more back.", remindAt: bed - 0.75)
        }

        return Energy(lead: lead, lastNight: lastNight, opened: opened, openedAt: open?.date, charged: charged,
                      drained: drained, high: highPoint.map { Int($0.level.rounded()) }, highAt: highPoint?.date,
                      ledger: ledger, move: move)
    }

    static func energyWord(_ value: Int) -> String {
        switch ScoreMath.Band(value) {
        case .high: "Full"
        case .middle: "Easy"
        case .low: "Low"
        }
    }

    // MARK: - Peak window

    struct Peak: Equatable, Sendable {
        var day: ScoringPeakDay?
        var headline: String
        var reason: String
        var aside: String?
    }

    static func peak(_ scores: SomaScores?, _ inputs: ScoreDetailInputs?, calendar: Calendar = .current) -> Peak {
        let now = inputs?.now ?? Date()
        guard let inputs, let day = ScoringPeakDay.resolve(nights: inputs.recordedNights, now: now, calendar: calendar) else {
            return Peak(day: nil, headline: "Your peak window needs three nights.",
                        reason: "It models your alertness from when you sleep and wake.",
                        aside: "Wear your watch to bed and it draws on the fourth morning.")
        }
        let nowHour = day.nowHour
        let headline: String
        if let training = day.training, nowHour < training.end {
            headline = nowHour >= training.start ? "Training window, now until \(ScoreMath.clock(training.end))"
                : "Train between \(ScoreMath.clock(training.start)) and \(ScoreMath.clock(training.end))"
        } else if let deep = day.deepWork, nowHour < deep.end {
            headline = "Deep work until \(ScoreMath.clock(deep.end))"
        } else {
            headline = "Wind down at \(ScoreMath.clock(day.windDownHour))"
        }
        var reason = day.peakHour.map { "Your alertness peaks at \($0 == nowHour ? "now" : ScoreMath.clock($0))" } ?? "Your alertness curve"
        switch day.chronotype {
        case .morning?: reason += ", as it does for a body clock that leans to mornings."
        case .evening?: reason += ", as it does for a body clock that leans to evenings."
        default: reason += "."
        }
        let aside = scores?.recovery.map { "With recovery at \($0), \(ScoreMath.Band($0) == .high ? "a hard session fits" : "keep today’s session easy")." }
        return Peak(day: day, headline: headline, reason: reason, aside: aside)
    }
}

extension String {
    /// The string with its first letter in capitals.
    nonisolated var scoreCapitalized: String {
        prefix(1).uppercased() + dropFirst()
    }
}
