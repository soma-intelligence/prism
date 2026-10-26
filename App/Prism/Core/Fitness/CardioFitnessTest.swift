//
//  CardioFitnessTest.swift
//  Prism
//
//  The cardio fitness test: three field tests that estimate VO2 max without a
//  lab, the rules that pick one from what the person carries, the equations,
//  the checks a run has to pass before it is believed, the safety stop and
//  the cues the live screen gives.
//
//  Apple announced a guided VO2 max test for its redesigned Health app on
//  2026-09-09 (iPhone camera plus a heart rate from Apple Watch, AirPods Pro
//  3 or a sensor; walking, then stepping in place faster, then the heart's
//  recovery). Apple has published neither its protocol nor its accuracy, so
//  Soma runs validated field tests instead, and picks the one the person's
//  equipment can measure:
//
//  1. Rockport one mile walk (Kline GM et al., Estimation of VO2max from a
//     one mile track walk, gender, age, and body weight. Med Sci Sports Exerc
//     1987;19:253-259). 343 healthy adults aged 30 to 69. Needs the heart
//     rate at the end of the mile, so it is the choice with a heart rate
//     stream. Standard error about 5 mL/kg/min.
//  2. Six minute walk (Burr JF et al., The 6 minute walk test as a predictor
//     of objectively measured aerobic fitness in healthy working aged adults.
//     Phys Sportsmed 2011;39:133-139). 44 healthy adults, R squared 0.724.
//     Distance alone, from the phone's step counter, so it is the choice
//     without a watch. Cahalin 1996 was left out: it was built on 45 people
//     in advanced heart failure (peak VO2 12 mL/kg/min) and reads a healthy
//     walker far too low.
//  3. Queens College three minute step test (McArdle WD et al., Reliability
//     and interrelationships between maximal oxygen intake, physical work
//     capacity and step test scores in college women. Med Sci Sports
//     1972;4:182-186). A 41.3 cm step, 24 steps a minute for men and 22 for
//     women, the recovery pulse 5 to 20 seconds after. The closest validated
//     test to Apple's stepping one, and it runs indoors with a pulse counted
//     by hand when there is no sensor. Standard error about 16 percent.
//
//  An estimate for the person's own information, never a diagnosis.
//

import Foundation

// MARK: - The protocols

nonisolated enum CardioTestProtocol: String, Codable, CaseIterable, Sendable, Identifiable, Hashable {
    case rockportWalk, sixMinuteWalk, stepTest

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rockportWalk: "One mile walk"
        case .sixMinuteWalk: "Six minute walk"
        case .stepTest: "Three minute step test"
        }
    }

    /// The test's published name and source, for the result's footnote.
    var source: String {
        switch self {
        case .rockportWalk: "Rockport walk test, Kline 1987"
        case .sixMinuteWalk: "Six minute walk test, Burr 2011"
        case .stepTest: "Queens College step test, McArdle 1972"
        }
    }

    var symbol: String {
        switch self {
        case .rockportWalk: "figure.walk.motion"
        case .sixMinuteWalk: "figure.walk"
        case .stepTest: "figure.stairs"
        }
    }

    /// What the person does, in a line.
    var summary: String {
        switch self {
        case .rockportWalk: "Walk one mile as fast as you can, without running. Needs your heart rate at the end."
        case .sixMinuteWalk: "Walk as far as you can in six minutes at a brisk pace. Your iPhone counts the distance."
        case .stepTest: "Step up and down a 41 cm step to a beat for three minutes, then read your pulse."
        }
    }

    /// The heart rate the equation reads: at the end of the mile, or in
    /// recovery after the steps.
    var needsHeartRate: Bool { self != .sixMinuteWalk }

    /// Distance from the step counter.
    var needsDistance: Bool { self != .stepTest }

    var needsWeight: Bool { self != .stepTest }

    /// The step test's cadence differs by sex, and every equation has a sex
    /// term, so all three need it.
    var needsSex: Bool { true }

    /// How long the test runs, or nil when a distance ends it.
    var plannedSeconds: TimeInterval? {
        switch self {
        case .rockportWalk: nil
        case .sixMinuteWalk: 360
        case .stepTest: 180
        }
    }

    /// The distance that ends the test, in metres, or nil when the clock does.
    var targetMetres: Double? { self == .rockportWalk ? CardioUnits.metresPerMile : nil }

    /// The ages the equation was built on. Outside them the estimate stands
    /// but its range widens.
    var cohortAges: ClosedRange<Int> {
        switch self {
        case .rockportWalk: 30...69
        case .sixMinuteWalk: 18...65
        case .stepTest: 18...30
        }
    }
}

// MARK: - Who and what

/// What the person carries, read before the test.
nonisolated struct CardioTestEquipment: Sendable, Equatable {
    /// A live heart rate: Apple Watch, AirPods Pro 3 or a chest strap.
    var heartRateStream: Bool
    /// The iPhone's step counter, with Motion & Fitness allowed.
    var stepCounter: Bool
    /// The live test runs on an iPhone only: a Mac or a headset cannot be
    /// carried on a walk or a step.
    var canRunLive: Bool
}

nonisolated enum CardioTestChoice {
    /// The tests this equipment can measure, best first.
    static func available(_ equipment: CardioTestEquipment) -> [CardioTestProtocol] {
        guard equipment.canRunLive else { return [] }
        var tests: [CardioTestProtocol] = []
        if equipment.stepCounter {
            if equipment.heartRateStream { tests.append(.rockportWalk) }
            tests.append(.sixMinuteWalk)
        }
        // The pulse can be counted by hand, so the step test needs nothing.
        tests.append(.stepTest)
        return tests
    }

    /// The one to suggest: the mile with a heart rate stream, the six minute
    /// walk on the phone alone, the step test when the phone cannot count.
    static func recommended(_ equipment: CardioTestEquipment) -> CardioTestProtocol? {
        available(equipment).first
    }

    /// Why a test is suggested, or why it is not on offer.
    static func reason(_ test: CardioTestProtocol, _ equipment: CardioTestEquipment) -> String {
        switch test {
        case .rockportWalk:
            if !equipment.heartRateStream { return "Needs a heart rate from Apple Watch, AirPods Pro 3 or a chest strap." }
            if !equipment.stepCounter { return "Needs the iPhone's step counter (Motion & Fitness)." }
            return "The most studied walking test. Your sensor reads the heart rate."
        case .sixMinuteWalk:
            if !equipment.stepCounter { return "Needs the iPhone's step counter (Motion & Fitness)." }
            return equipment.heartRateStream ? "Shorter, and no heart rate needed." : "No watch needed: the iPhone counts the distance."
        case .stepTest:
            return equipment.heartRateStream ? "Indoors, three minutes, with your heart rate after." : "Indoors, three minutes. You count your pulse by hand after."
        }
    }
}

/// The person as the equations read them.
nonisolated struct CardioTestPerson: Sendable, Equatable {
    enum Field: String, Sendable, Equatable, CaseIterable {
        case age, sex, weight

        var title: String {
            switch self {
            case .age: "age"
            case .sex: "sex"
            case .weight: "weight"
            }
        }
    }

    var age: Int?
    var sex: LabSex?
    var weightKg: Double?
    /// Resting heart rate, for the six minute walk. Nil uses the population
    /// value and widens the range.
    var restingHeartRate: Double?

    /// What the test still needs to know.
    func missing(for test: CardioTestProtocol) -> [Field] {
        var fields: [Field] = []
        if !CardioFitnessTest.validAge(age) { fields.append(.age) }
        if test.needsSex, sex == nil { fields.append(.sex) }
        if test.needsWeight, !CardioFitnessTest.validWeight(weightKg) { fields.append(.weight) }
        return fields
    }
}

// MARK: - Units

nonisolated enum CardioUnits {
    static let metresPerMile = 1_609.344
    static let kilogramsPerPound = 0.453_592_37

    static func miles(fromMetres metres: Double) -> Double { metres / metresPerMile }
    static func metres(fromMiles miles: Double) -> Double { miles * metresPerMile }
    static func kilometres(fromMetres metres: Double) -> Double { metres / 1_000 }
    static func pounds(fromKilograms kilograms: Double) -> Double { kilograms / kilogramsPerPound }
    static func kilograms(fromPounds pounds: Double) -> Double { pounds * kilogramsPerPound }
    static func minutes(_ seconds: TimeInterval) -> Double { seconds / 60 }

    /// A duration as minutes and seconds: "6:00", "14:32".
    static func clock(_ seconds: TimeInterval) -> String {
        let whole = max(0, Int(seconds.rounded(.down)))
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }

    /// "0.62 mi" or "1.00 km": two decimals, in the person's measures.
    static func distance(_ metres: Double, measures: MeasureSystem) -> String {
        let value = measures == .imperial ? miles(fromMetres: metres) : kilometres(fromMetres: metres)
        return String(format: "%.2f", value) + (measures == .imperial ? " mi" : " km")
    }

    /// Minutes a kilometre or a mile: "9:45 /km". Nil before any distance.
    static func pace(metres: Double, seconds: TimeInterval, measures: MeasureSystem) -> String? {
        guard metres > 20, seconds > 0 else { return nil }
        let unit = measures == .imperial ? metresPerMile : 1_000
        return clock(seconds / metres * unit) + (measures == .imperial ? " /mi" : " /km")
    }

    /// A weight in the person's measures, one decimal: "78.5 kg", "173.1 lb".
    static func weight(_ kilograms: Double, measures: MeasureSystem) -> String {
        measures == .imperial
            ? String(format: "%.1f lb", pounds(fromKilograms: kilograms))
            : String(format: "%.1f kg", kilograms)
    }
}

// MARK: - The equations

nonisolated enum CardioEquations {
    /// Kline 1987, the generalised mL/kg/min equation:
    /// 132.853 minus 0.0769 weight (lb) minus 0.3877 age plus 6.315 for a man
    /// minus 3.2649 time (min) minus 0.1565 heart rate at the end of the mile.
    static func rockport(weightPounds: Double, age: Double, male: Bool, minutes: Double, heartRate: Double) -> Double {
        132.853 - 0.0769 * weightPounds - 0.3877 * age + 6.315 * (male ? 1 : 0) - 3.2649 * minutes - 0.1565 * heartRate
    }

    /// Burr 2011: 70.161 plus 0.023 distance (m) minus 0.276 weight (kg)
    /// minus 6.79 for a woman minus 0.193 resting heart rate minus 0.191 age.
    static func sixMinuteWalk(metres: Double, weightKg: Double, female: Bool, restingHeartRate: Double, age: Double) -> Double {
        70.161 + 0.023 * metres - 0.276 * weightKg - 6.79 * (female ? 1 : 0) - 0.193 * restingHeartRate - 0.191 * age
    }

    /// McArdle 1972: men 111.33 minus 0.42 recovery pulse, women 65.81 minus
    /// 0.1847 recovery pulse, the pulse counted 5 to 20 seconds after.
    static func queensCollege(recoveryHeartRate: Double, male: Bool) -> Double {
        male ? 111.33 - 0.42 * recoveryHeartRate : 65.81 - 0.1847 * recoveryHeartRate
    }
}

// MARK: - A run

/// One reading over the test, at seconds from its start.
nonisolated struct CardioSample: Sendable, Equatable, Codable {
    var time: TimeInterval
    var value: Double
}

/// Why a run ended before its end.
nonisolated enum CardioStop: String, Sendable, Codable, CaseIterable, Identifiable {
    case chestPain, dizziness, breathless, heartRateCeiling, personChose

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chestPain: "Chest pain or pressure"
        case .dizziness: "Dizzy or light headed"
        case .breathless: "Unusually short of breath"
        case .heartRateCeiling: "Heart rate too high"
        case .personChose: "I just want to stop"
        }
    }

    /// A stop the body asked for, which gets the safety screen.
    var isSymptom: Bool { self != .personChose }
}

/// Where the heart rate the equation reads came from.
nonisolated enum CardioHeartRateSource: String, Sendable, Codable {
    case sensor, counted
}

/// Everything the live test recorded.
nonisolated struct CardioRun: Sendable, Equatable {
    var test: CardioTestProtocol
    var startedAt: Date
    /// Seconds from the start to the moment the test ended.
    var elapsed: TimeInterval
    /// Metres since the start, cumulative, oldest first.
    var distance: [CardioSample] = []
    /// Beats a minute, oldest first. Samples after `elapsed` are recovery.
    var heartRate: [CardioSample] = []
    /// Beats a minute from a pulse counted by hand, for a run without a
    /// sensor reading where the equation needs one.
    var countedPulse: Double?
    var stop: CardioStop?
    var isSimulated = false

    var endedAt: Date { startedAt.addingTimeInterval(elapsed) }
    var metres: Double? { distance.last?.value }
}

/// Why a run cannot be believed, and what to do about it.
nonisolated enum CardioRunProblem: Error, Equatable, Sendable {
    case stoppedForSafety(CardioStop)
    case stoppedEarly
    case tooShort(needed: TimeInterval, got: TimeInterval)
    case noDistance
    case distanceShort(neededMetres: Double, gotMetres: Double)
    case distanceGap(seconds: TimeInterval)
    case looksLikeRunning
    case noHeartRate
    case heartRateGap(seconds: TimeInterval)
    case implausibleHeartRate(Double)
    case missingProfile([CardioTestPerson.Field])

    var title: String {
        switch self {
        case .stoppedForSafety: "Stopped for your safety"
        case .stoppedEarly: "Stopped before the end"
        case .tooShort: "Too short to read"
        case .noDistance: "No distance counted"
        case .distanceShort: "Short of the mile"
        case .distanceGap: "The phone lost count"
        case .looksLikeRunning: "That was a run"
        case .noHeartRate: "No heart rate"
        case .heartRateGap: "The heart rate dropped out"
        case .implausibleHeartRate: "A heart rate that does not fit"
        case .missingProfile: "A detail is missing"
        }
    }

    var message: String {
        switch self {
        case .stoppedForSafety:
            return "No estimate from this run. Rest, and let a doctor know about what you felt before you try again."
        case .stoppedEarly:
            return "The equation needs the whole test. Rest and start again when you feel ready."
        case .tooShort(let needed, let got):
            return "The test lasts \(CardioUnits.clock(needed)), this run \(CardioUnits.clock(got)). The equation reads the whole test."
        case .noDistance:
            return "The iPhone counted no steps. Keep it in a pocket or in your hand, and check Motion & Fitness is on for Soma in Settings."
        case .distanceShort(let needed, let got):
            return "The phone counted \(Int(got.rounded())) of \(Int(needed.rounded())) metres. Walk the whole mile, then stop."
        case .distanceGap(let seconds):
            return "No distance came in for \(Int(seconds.rounded())) seconds, so the total cannot be trusted. Keep the phone on you and keep walking."
        case .looksLikeRunning:
            return "The pace was a run. These equations are built on walking: walk as fast as you can, with one foot always on the ground."
        case .noHeartRate:
            return "The equation needs your heart rate at the end. Wear Apple Watch or a strap, or count your pulse when asked."
        case .heartRateGap(let seconds):
            return "The last heart rate came \(Int(seconds.rounded())) seconds before the end. Count your pulse by hand next time, or keep the watch snug."
        case .implausibleHeartRate(let bpm):
            return "\(Int(bpm.rounded())) beats a minute is outside what a test like this produces. Count again, or try with a sensor."
        case .missingProfile(let fields):
            return "The equation needs your \(fields.map(\.title).joined(separator: " and "))."
        }
    }

    /// A problem a counted pulse can still rescue.
    var pulseCanRescue: Bool {
        switch self {
        case .noHeartRate, .heartRateGap: true
        default: false
        }
    }
}

// MARK: - The estimate

nonisolated struct CardioEstimate: Sendable, Equatable {
    var test: CardioTestProtocol
    var date: Date
    /// mL/kg/min.
    var vo2Max: Double
    var low: Double
    var high: Double
    var metres: Double?
    var seconds: TimeInterval
    var heartRate: Double?
    var heartRateSource: CardioHeartRateSource?
    /// What widened the range, in a few words each.
    var caveats: [String]

    /// "about 38 to 48".
    var rangeText: String { "\(Int(low.rounded())) to \(Int(high.rounded()))" }
}

nonisolated enum CardioFitnessTest {
    /// A pedometer stall longer than this mid walk is a lost count. Core
    /// Motion reports every few seconds while steps come.
    static let maxDistanceGap: TimeInterval = 45
    /// The end heart rate is the median of the readings in this window
    /// before the finish (Kline used the last quarter's heart rate).
    static let endHeartRateWindow: TimeInterval = 20
    /// A last sensor reading older than this at the finish is not the end
    /// heart rate.
    static let maxHeartRateAge: TimeInterval = 30
    /// The step test's recovery count: 5 to 20 seconds after stepping.
    static let recoveryWindow: ClosedRange<TimeInterval> = 5...20
    /// A clock that stopped this close to the end counts as a full test.
    static let clockSlack: TimeInterval = 2
    /// The mile counted this close to its end is a mile (the phone's own
    /// distance is an estimate from the stride).
    static let distanceSlack = 0.01
    /// Slower than this is not a walk: 7.5 km/h for six minutes, a mile in
    /// under eight minutes.
    static let maxSixMinuteMetres = 750.0
    static let minMileSeconds: TimeInterval = 8 * 60
    static let minSixMinuteMetres = 50.0
    static let plausibleHeartRate: ClosedRange<Double> = 40...220
    /// Burr's cohort: the resting heart rate assumed when none is known, the
    /// one ``BiologicalAge`` centres its norm on.
    static func assumedRestingHeartRate(_ sex: LabSex) -> Double { sex == .male ? 68 : 72 }
    /// Kline 1987 reports a standard error near 5 mL/kg/min. Burr 2011 gives
    /// R squared 0.724 without a standard error in its abstract; 5 is that
    /// share of a typical spread of 9 mL/kg/min. McArdle 1972: 16 percent.
    static let rockportError = 5.0
    static let sixMinuteError = 5.0
    static let stepTestRelativeError = 0.16
    /// Outside the cohort's ages the range widens by half.
    static let outsideCohortWidening = 1.5

    static func validAge(_ age: Int?) -> Bool { age.map { (15...100).contains($0) } ?? false }
    static func validWeight(_ kilograms: Double?) -> Bool { kilograms.map { (30...300).contains($0) } ?? false }

    /// The run read through its test's equation, or the reason it cannot be.
    static func evaluate(_ run: CardioRun, person: CardioTestPerson) -> Result<CardioEstimate, CardioRunProblem> {
        if let stop = run.stop {
            return .failure(stop.isSymptom ? .stoppedForSafety(stop) : .stoppedEarly)
        }
        let missing = person.missing(for: run.test)
        guard missing.isEmpty, let age = person.age, let sex = person.sex else {
            return .failure(.missingProfile(missing))
        }
        switch run.test {
        case .rockportWalk: return rockport(run, age: age, sex: sex, person: person)
        case .sixMinuteWalk: return sixMinute(run, age: age, sex: sex, person: person)
        case .stepTest: return step(run, age: age, sex: sex)
        }
    }

    private static func rockport(_ run: CardioRun, age: Int, sex: LabSex, person: CardioTestPerson) -> Result<CardioEstimate, CardioRunProblem> {
        let target = CardioUnits.metresPerMile
        guard let metres = run.metres, metres > 0 else { return .failure(.noDistance) }
        guard metres >= target * (1 - distanceSlack) else {
            return .failure(.distanceShort(neededMetres: target, gotMetres: metres))
        }
        if let gap = distanceGap(run) { return .failure(.distanceGap(seconds: gap)) }
        guard run.elapsed >= minMileSeconds else { return .failure(.looksLikeRunning) }
        let heart: (bpm: Double, source: CardioHeartRateSource)
        switch endHeartRate(run) {
        case .success(let reading): heart = reading
        case .failure(let problem): return .failure(problem)
        }
        let weight = person.weightKg ?? 0
        let value = CardioEquations.rockport(weightPounds: CardioUnits.pounds(fromKilograms: weight), age: Double(age),
                                             male: sex == .male, minutes: CardioUnits.minutes(run.elapsed), heartRate: heart.bpm)
        var caveats: [String] = []
        var error = rockportError
        if !run.test.cohortAges.contains(age) {
            error *= outsideCohortWidening
            caveats.append("Built on adults aged 30 to 69")
        }
        if heart.source == .counted { caveats.append("Pulse counted by hand") }
        return .success(estimate(run, value: value, error: error, metres: metres, heart: heart, caveats: caveats))
    }

    private static func sixMinute(_ run: CardioRun, age: Int, sex: LabSex, person: CardioTestPerson) -> Result<CardioEstimate, CardioRunProblem> {
        let planned = run.test.plannedSeconds ?? 360
        guard run.elapsed >= planned - clockSlack else { return .failure(.tooShort(needed: planned, got: run.elapsed)) }
        guard let metres = run.metres, metres >= minSixMinuteMetres else { return .failure(.noDistance) }
        if let gap = distanceGap(run) { return .failure(.distanceGap(seconds: gap)) }
        guard metres <= maxSixMinuteMetres else { return .failure(.looksLikeRunning) }
        var caveats: [String] = []
        var error = sixMinuteError
        let resting: Double
        if let known = person.restingHeartRate, plausibleHeartRate.contains(known) {
            resting = known
        } else {
            resting = assumedRestingHeartRate(sex)
            // A resting rate 10 beats off moves the estimate by about 2.
            error = (error * error + pow(0.193 * 10, 2)).squareRoot()
            caveats.append("Typical resting heart rate assumed")
        }
        if !run.test.cohortAges.contains(age) {
            error *= outsideCohortWidening
            caveats.append("Built on working age adults")
        }
        let value = CardioEquations.sixMinuteWalk(metres: metres, weightKg: person.weightKg ?? 0, female: sex == .female,
                                                  restingHeartRate: resting, age: Double(age))
        return .success(estimate(run, value: value, error: error, metres: metres, heart: nil, caveats: caveats))
    }

    private static func step(_ run: CardioRun, age: Int, sex: LabSex) -> Result<CardioEstimate, CardioRunProblem> {
        let planned = run.test.plannedSeconds ?? 180
        guard run.elapsed >= planned - clockSlack else { return .failure(.tooShort(needed: planned, got: run.elapsed)) }
        let heart: (bpm: Double, source: CardioHeartRateSource)
        switch recoveryHeartRate(run) {
        case .success(let reading): heart = reading
        case .failure(let problem): return .failure(problem)
        }
        let value = CardioEquations.queensCollege(recoveryHeartRate: heart.bpm, male: sex == .male)
        var caveats: [String] = []
        var error = value * stepTestRelativeError
        if !run.test.cohortAges.contains(age) {
            error *= outsideCohortWidening
            caveats.append("Built on college students")
        }
        if heart.source == .counted { caveats.append("Pulse counted by hand") }
        return .success(estimate(run, value: value, error: error, metres: nil, heart: heart, caveats: caveats))
    }

    private static func estimate(_ run: CardioRun, value: Double, error: Double, metres: Double?,
                                 heart: (bpm: Double, source: CardioHeartRateSource)?, caveats: [String]) -> CardioEstimate {
        // A walk too slow for the equation's range would read under zero.
        let floored = max(value, 5)
        return CardioEstimate(test: run.test, date: run.endedAt, vo2Max: floored, low: max(floored - error, 1), high: floored + error,
                              metres: metres, seconds: run.elapsed, heartRate: heart?.bpm, heartRateSource: heart?.source,
                              caveats: caveats)
    }

    /// The longest stretch inside the test with no new distance, when it
    /// passes the limit. The start counts as a reading at zero, and the end
    /// as one at the last total.
    static func distanceGap(_ run: CardioRun) -> TimeInterval? {
        let inside = run.distance.filter { $0.time <= run.elapsed + clockSlack }
        var times = [0.0]
        var last = 0.0
        for sample in inside where sample.value > last {
            times.append(sample.time)
            last = sample.value
        }
        // The finish of a mile is the moment the last metre was counted.
        if run.test.plannedSeconds != nil { times.append(run.elapsed) }
        let gaps = zip(times, times.dropFirst()).map { $1 - $0 }
        guard let worst = gaps.max(), worst > maxDistanceGap else { return nil }
        return worst
    }

    /// The heart rate at the end of the mile: the median of the sensor's
    /// last readings, else a pulse counted by hand.
    static func endHeartRate(_ run: CardioRun) -> Result<(bpm: Double, source: CardioHeartRateSource), CardioRunProblem> {
        let before = run.heartRate.filter { $0.time <= run.elapsed + clockSlack }
        let window = before.filter { $0.time >= run.elapsed - endHeartRateWindow }.map(\.value)
        if !window.isEmpty {
            let bpm = median(window)
            guard plausibleHeartRate.contains(bpm) else { return .failure(.implausibleHeartRate(bpm)) }
            return .success((bpm, .sensor))
        }
        if let counted = run.countedPulse {
            guard plausibleHeartRate.contains(counted) else { return .failure(.implausibleHeartRate(counted)) }
            return .success((counted, .counted))
        }
        if let last = before.last, run.elapsed - last.time > maxHeartRateAge {
            return .failure(.heartRateGap(seconds: run.elapsed - last.time))
        }
        return .failure(.noHeartRate)
    }

    /// The step test's recovery pulse: the sensor's mean 5 to 20 seconds
    /// after the last step, else a pulse counted by hand.
    static func recoveryHeartRate(_ run: CardioRun) -> Result<(bpm: Double, source: CardioHeartRateSource), CardioRunProblem> {
        let window = run.heartRate.filter {
            $0.time >= run.elapsed + recoveryWindow.lowerBound && $0.time <= run.elapsed + recoveryWindow.upperBound
        }.map(\.value)
        if !window.isEmpty {
            let bpm = window.reduce(0, +) / Double(window.count)
            guard plausibleHeartRate.contains(bpm) else { return .failure(.implausibleHeartRate(bpm)) }
            return .success((bpm, .sensor))
        }
        if let counted = run.countedPulse {
            guard plausibleHeartRate.contains(counted) else { return .failure(.implausibleHeartRate(counted)) }
            return .success((counted, .counted))
        }
        return .failure(run.heartRate.isEmpty ? .noHeartRate : .heartRateGap(seconds: recoveryWindow.upperBound))
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }
}

// MARK: - Counted pulse

nonisolated enum CardioPulse {
    /// The count lasts fifteen seconds, read as beats a minute.
    static let countSeconds: TimeInterval = 15

    static func beatsPerMinute(beatsIn15Seconds beats: Int) -> Double { Double(beats) * 60 / countSeconds }
}

// MARK: - Where it sits

/// A VO2 max against the person's age and sex.
///
/// The norms are the ones ``BiologicalAge`` scores against (ACSM, by decade,
/// a mean and a spread), so the result page, the biological age and the
/// fitness age never disagree on what a reading is worth.
nonisolated struct CardioFitnessBand: Sendable, Equatable {
    /// 1 to 99.
    var percentile: Int
    var word: String
    /// "women in their 40s".
    var group: String

    static func make(vo2Max: Double, age: Int, sex: LabSex) -> CardioFitnessBand {
        let z = BiologicalAge.vo2MaxZ(vo2Max, age: age, sex: sex)
        let share = 0.5 * (1 + erf(z / 2.0.squareRoot()))
        let percentile = min(max(Int((share * 100).rounded()), 1), 99)
        let word = switch percentile {
        case ..<20: "Lower than most"
        case ..<40: "Below the middle"
        case ..<60: "Around the middle"
        case ..<80: "Above the middle"
        default: "Higher than most"
        }
        let decade = min(max(age / 10 * 10, 20), 70)
        let people = sex == .male ? "men" : "women"
        let group = decade >= 70 ? "\(people) 70 and over" : "\(people) in their \(decade)s"
        return CardioFitnessBand(percentile: percentile, word: word, group: group)
    }
}

nonisolated enum CardioComparison {
    /// How the test sits against Apple Watch's latest estimate, or nil
    /// without one.
    static func againstWatch(test: Double, watch: Double?) -> String? {
        guard let watch, watch > 0 else { return nil }
        let gap = test - watch
        let watchText = String(format: "%.0f", watch)
        if abs(gap) < 2 { return "Close to Apple Watch's \(watchText)" }
        let size = String(format: "%.0f", abs(gap))
        return gap > 0 ? "\(size) above Apple Watch's \(watchText)" : "\(size) below Apple Watch's \(watchText)"
    }
}

// MARK: - Safety

nonisolated enum CardioSafety {
    /// Who should not take the test without a doctor's clearance (ACSM
    /// preparticipation screening, informational).
    static let skipIf = [
        "Chest pain, at rest or with effort",
        "Dizziness or fainting",
        "A heart condition, unless a doctor has cleared you for exercise",
        "Pregnancy",
        "An injury or surgery that makes brisk walking or stepping hard",
    ]

    enum Call: Sendable, Equatable {
        case fine, slowDown, stop
    }

    /// Tanaka H et al., Age predicted maximal heart rate revisited. J Am Coll
    /// Cardiol 2001;37:153-156: 208 minus 0.7 times age.
    static func predictedMaxHeartRate(age: Int) -> Double { 208 - 0.7 * Double(age) }

    /// Readings that must agree before the heart rate stops the test, and the
    /// window they are read over.
    static let sustainedSeconds: TimeInterval = 10
    static let minimumReadings = 2

    /// The share of the predicted maximum a walk should stay under. A walk
    /// is submaximal: past 90 percent the screen asks to slow down, past 95
    /// percent held for ten seconds it stops. The step test's cadence is
    /// fixed, so it is only stopped, at the predicted maximum itself.
    static func limits(_ test: CardioTestProtocol) -> (slowDown: Double?, stop: Double) {
        test == .stepTest ? (nil, 1.0) : (0.90, 0.95)
    }

    /// What the latest heart rate says, at `now` seconds into the test.
    static func assess(_ heartRate: [CardioSample], now: TimeInterval, age: Int?, test: CardioTestProtocol) -> Call {
        guard let age, let latest = heartRate.last, now - latest.time <= sustainedSeconds else { return .fine }
        let ceiling = predictedMaxHeartRate(age: age)
        let limit = limits(test)
        let recent = heartRate.filter { $0.time >= now - sustainedSeconds }
        if recent.count >= minimumReadings, recent.allSatisfy({ $0.value >= limit.stop * ceiling }) { return .stop }
        if let slow = limit.slowDown, latest.value >= slow * ceiling { return .slowDown }
        return .fine
    }
}

// MARK: - Cues

nonisolated struct CardioCue: Sendable, Equatable, Identifiable {
    enum Kind: Sendable, Equatable {
        case start, halfway, minuteLeft, end
    }

    var id: String
    var kind: Kind
    /// What is spoken, when spoken cues are on. The haptic plays either way.
    var spoken: String
    /// Seconds into the test, or nil when a distance triggers it.
    var atSeconds: TimeInterval?
    var atMetres: Double?
}

nonisolated enum CardioCuePlan {
    static func cues(for test: CardioTestProtocol) -> [CardioCue] {
        switch test {
        case .rockportWalk:
            let mile = CardioUnits.metresPerMile
            return [
                CardioCue(id: "start", kind: .start, spoken: "Go. Walk as fast as you can, without running.", atSeconds: 0),
                CardioCue(id: "half", kind: .halfway, spoken: "Halfway. Keep the pace.", atMetres: mile / 2),
                CardioCue(id: "end", kind: .end, spoken: "One mile. Stop and stand still.", atMetres: mile),
            ]
        case .sixMinuteWalk:
            return [
                CardioCue(id: "start", kind: .start, spoken: "Go. Walk briskly, as far as you can.", atSeconds: 0),
                CardioCue(id: "half", kind: .halfway, spoken: "Halfway. Three minutes left.", atSeconds: 180),
                CardioCue(id: "minute", kind: .minuteLeft, spoken: "One minute left.", atSeconds: 300),
                CardioCue(id: "end", kind: .end, spoken: "Stop. Stay where you are.", atSeconds: 360),
            ]
        case .stepTest:
            return [
                CardioCue(id: "start", kind: .start, spoken: "Go. Up, up, down, down, with the beat.", atSeconds: 0),
                CardioCue(id: "half", kind: .halfway, spoken: "Halfway.", atSeconds: 90),
                CardioCue(id: "minute", kind: .minuteLeft, spoken: "One minute left.", atSeconds: 120),
                CardioCue(id: "end", kind: .end, spoken: "Stop. Stand still. Your pulse is read in five seconds.", atSeconds: 180),
            ]
        }
    }

    /// The cues reached and not yet given.
    static func due(_ cues: [CardioCue], seconds: TimeInterval, metres: Double, given: Set<String>) -> [CardioCue] {
        cues.filter { cue in
            guard !given.contains(cue.id) else { return false }
            if let at = cue.atSeconds { return seconds >= at }
            if let at = cue.atMetres { return metres >= at }
            return false
        }
    }

    /// The step test's metronome: four beats a step (up, up, down, down),
    /// 24 steps a minute for men and 22 for women.
    static func beatsPerMinute(_ sex: LabSex) -> Double { sex == .male ? 96 : 88 }
}

// MARK: - Progress

nonisolated enum CardioProgress {
    /// 0 to 1 through the test.
    static func fraction(_ test: CardioTestProtocol, seconds: TimeInterval, metres: Double) -> Double {
        if let target = test.targetMetres { return min(max(metres / target, 0), 1) }
        guard let planned = test.plannedSeconds, planned > 0 else { return 0 }
        return min(max(seconds / planned, 0), 1)
    }

    static func isComplete(_ test: CardioTestProtocol, seconds: TimeInterval, metres: Double) -> Bool {
        if let target = test.targetMetres { return metres >= target }
        return seconds >= (test.plannedSeconds ?? .infinity)
    }

    /// The six minute walk's distance at this pace by the end, for the pace
    /// cue. Nil before a minute.
    static func projectedMetres(_ test: CardioTestProtocol, seconds: TimeInterval, metres: Double) -> Double? {
        guard test == .sixMinuteWalk, seconds >= 60, let planned = test.plannedSeconds else { return nil }
        return metres / seconds * planned
    }
}
