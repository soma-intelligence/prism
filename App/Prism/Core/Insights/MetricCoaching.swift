//
//  MetricCoaching.swift
//  Prism
//
//  What is good for a metric, in plain words: which way is better, the zone
//  that is optimal or typical for this person (by age and sex when known),
//  where their value sits, and a few levers that move it. Keyed by HealthKit
//  identifier, in the unit the data type page shows. Pure: the page hands it
//  a value, a usual band, an age and a sex, and draws what comes back.
//
//  The direction always comes from ``MetricProfile``, so the coaching card
//  never says better where the trends table says worse. Each reference table
//  names its source next to it, and the card writes a short source line.
//
//  Not medical advice: the card says what the ranges are and points to a
//  clinician when a value sits outside a clinical range.
//

import Foundation

/// The coaching for one metric and one value.
nonisolated struct MetricCoachingAdvice: Equatable, Sendable {
    /// Which way is better, as the card's first words.
    enum Direction: Equatable, Sendable {
        case higher, lower, range, trend

        var title: String {
            switch self {
            case .higher: String(localized: "Higher is better")
            case .lower: String(localized: "Lower is better")
            case .range: String(localized: "In a range is best")
            case .trend: String(localized: "Your own trend matters more than the number")
            }
        }
    }

    /// How a zone reads: optimal, worth watching, or out of range.
    enum Tone: Equatable, Sendable { case good, fair, out }

    /// One stretch of the scale, low to high.
    struct Zone: Equatable, Sendable {
        var name: String
        var lower: Double
        var upper: Double
        var tone: Tone
        /// The verdict's end: "Your 58 bpm is <says>."
        var says: String
        /// What a value here usually means, one short sentence.
        var means: String?
    }

    var direction: Direction
    /// The scale, low to high, the zones touching. Empty when there is no
    /// scale yet (a trend metric before its usual band exists).
    var zones: [Zone]
    /// The optimal or typical zone for this person, nil for a trend metric.
    var target: ClosedRange<Double>?
    /// The target in words: "Typical at 30 to 39: 35 to 70 ms."
    var targetLine: String
    /// The sentence on the value, a dash when there is none.
    var verdict: String
    /// The zone the value sits in.
    var zone: Zone?
    /// Where the marker sits on the scale, nil without a value.
    var marker: Double?
    /// The value against the person's own usual band.
    var usualLine: String?
    /// Two or three levers tied to this metric.
    var helps: [String]
    /// A pointer to a clinician, only when the value is out of a clinical
    /// range.
    var clinician: String?
    /// The reference behind the zones, for the card's source line.
    var source: String
}

enum MetricCoaching {
    /// The person the ranges are read for. Nil fields fall back to adult
    /// ranges that hold for either sex.
    nonisolated struct Person: Equatable, Sendable {
        var age: Int?
        var sex: BiologicalSex?
    }

    // Identifiers the card covers.
    static let hrv = "HKQuantityTypeIdentifierHeartRateVariabilitySDNN"
    static let restingHeartRate = "HKQuantityTypeIdentifierRestingHeartRate"
    static let respiratoryRate = "HKQuantityTypeIdentifierRespiratoryRate"
    static let oxygen = "HKQuantityTypeIdentifierOxygenSaturation"
    static let wristTemperature = "HKQuantityTypeIdentifierAppleSleepingWristTemperature"
    /// Apple Health calls VO2 max "Cardio Fitness": one entry covers both.
    static let vo2Max = "HKQuantityTypeIdentifierVO2Max"
    static let recovery = "HKQuantityTypeIdentifierHeartRateRecoveryOneMinute"
    static let walkingSpeed = "HKQuantityTypeIdentifierWalkingSpeed"
    static let steps = "HKQuantityTypeIdentifierStepCount"
    static let activeEnergy = "HKQuantityTypeIdentifierActiveEnergyBurned"
    static let exercise = "HKQuantityTypeIdentifierAppleExerciseTime"
    static let weight = "HKQuantityTypeIdentifierBodyMass"
    static let bodyFat = "HKQuantityTypeIdentifierBodyFatPercentage"
    static let leanMass = "HKQuantityTypeIdentifierLeanBodyMass"
    static let bmi = "HKQuantityTypeIdentifierBodyMassIndex"
    static let glucose = "HKQuantityTypeIdentifierBloodGlucose"
    static let steadiness = "HKQuantityTypeIdentifierAppleWalkingSteadiness"

    static let covered: [String] = [
        hrv, restingHeartRate, respiratoryRate, oxygen, wristTemperature, vo2Max, recovery,
        walkingSpeed, steps, MetricProfile.sleep, activeEnergy, exercise, weight, bodyFat,
        leanMass, bmi, MetricProfile.systolic, MetricProfile.diastolic, glucose, steadiness,
    ]

    /// The coaching for a metric, or nil for one the catalog does not cover.
    ///
    /// - Parameters:
    ///   - value: the value in the page's unit (percent as 0 to 100, sleep in
    ///     hours, a daily total as a recent day's average); systolic for blood
    ///     pressure.
    ///   - secondary: diastolic, for blood pressure.
    ///   - usual: the person's own rolling band.
    static func advice(
        for identifier: String,
        value: Double?,
        secondary: Double? = nil,
        usual: ClosedRange<Double>?,
        age: Int?,
        sex: BiologicalSex?
    ) -> MetricCoachingAdvice? {
        let person = Person(age: age, sex: sex)
        guard let spec = spec(identifier, person: person, usual: usual) else { return nil }
        let direction = direction(for: identifier, preferring: spec.neutral)

        var marker = value
        var zone: MetricCoachingAdvice.Zone?
        var verdict = "-"
        var clinician: String?
        if let value {
            // Blood pressure is graded by whichever number earns the higher
            // category, so the marker sits in that category's zone.
            if spec.isPressure, let category = pressureCategory(systolic: value, diastolic: secondary ?? 0) {
                marker = category.marker(systolic: value)
            }
            zone = marker.flatMap { zoneIndex($0, in: spec.zones) }.map { spec.zones[$0] }
            let phrase = spec.isPressure ? "\(VaultFormat.number(value))/\(secondary.map(VaultFormat.number) ?? "-")" : spec.phrase(value)
            if let zone {
                verdict = String(localized: "Your \(phrase) is \(zone.says).")
                // Off the person's own usual, that says more than the
                // zone's general meaning, and the hero above already flags it.
                if let usual, !spec.readsUsual, !spec.isPressure, !usual.contains(value) {
                    let words = spec.range(usual)
                    verdict += " " + (value < usual.lowerBound
                        ? String(localized: "It is under your own usual of \(words).")
                        : String(localized: "It is over your own usual of \(words)."))
                } else if let means = zone.means {
                    verdict += " " + means
                }
            } else {
                verdict = spec.noScale(phrase)
            }
            clinician = spec.clinician(value, secondary)
        }

        return MetricCoachingAdvice(
            direction: direction,
            zones: spec.zones,
            target: spec.target,
            targetLine: spec.targetLine,
            verdict: verdict,
            zone: zone,
            marker: value == nil ? nil : marker,
            usualLine: spec.readsUsual ? nil : usualLine(value, usual: usual, spec: spec),
            helps: spec.helps,
            clinician: clinician,
            source: spec.source
        )
    }

    /// Which way is better, read off ``MetricProfile``: a metric the app
    /// calls better when rising is "higher", when falling "lower". A metric
    /// with no good way is "in a range" when it has a fixed band, else
    /// whatever the catalog prefers (a range or the person's own trend).
    static func direction(for identifier: String, preferring neutral: MetricCoachingAdvice.Direction = .trend) -> MetricCoachingAdvice.Direction {
        let profile = MetricProfile.of(identifier)
        switch profile.risingIsGood {
        case true: return .higher
        case false: return .lower
        default: return profile.referenceBand == nil ? neutral : .range
        }
    }

    // MARK: - Reference tables

    /// Typical Apple Watch SDNN by age, in ms: roughly the middle half of
    /// healthy adults. Short recording SDNN averages about 50 ms with a range
    /// of 32 to 93 ms (Nunan et al., Pacing Clin Electrophysiol 2010) and falls
    /// with every decade (Umetani et al., J Am Coll Cardiol 1998). Sex moves
    /// it little next to age, so the bands hold for both.
    static func hrvBand(age: Int?) -> ClosedRange<Double> {
        guard let age else { return 30...65 }
        switch age {
        case ..<30: return 40...80
        case 30..<40: return 35...70
        case 40..<50: return 30...60
        case 50..<60: return 25...50
        case 60..<70: return 20...45
        default: return 18...40
        }
    }

    /// VO2 max percentiles (25th, 50th, 75th) in ml/kg/min by age and sex,
    /// from the FRIEND registry's treadmill tests (Kaminsky et al., Mayo Clin
    /// Proc 2015), the reference ACSM uses. Under 20 reads as the twenties,
    /// 80 and up as the seventies. Without an age the forties stand in for
    /// adults; without a sex, the mean of the two.
    static func vo2Percentiles(age: Int?, sex: BiologicalSex?) -> (low: Double, middle: Double, high: Double) {
        let decade = min(max(((age ?? 45) / 10) - 2, 0), 5)
        let men: [(Double, Double, Double)] = [
            (40.1, 48.0, 55.2), (35.9, 42.4, 49.2), (31.9, 37.8, 45.0),
            (27.1, 32.6, 39.7), (23.7, 28.2, 34.5), (20.4, 24.4, 30.4),
        ]
        let women: [(Double, Double, Double)] = [
            (30.5, 37.6, 44.7), (25.3, 30.9, 36.1), (22.1, 27.7, 32.4),
            (19.9, 24.4, 28.4), (17.2, 22.5, 25.8), (15.6, 20.5, 22.9),
        ]
        switch sex {
        case .male: return men[decade]
        case .female: return women[decade]
        default:
            let m = men[decade], w = women[decade]
            return ((m.0 + w.0) / 2, (m.1 + w.1) / 2, (m.2 + w.2) / 2)
        }
    }

    /// Blood pressure categories, ACC/AHA 2017 (Whelton et al., Hypertension
    /// 2018): the higher of the two numbers' categories wins.
    nonisolated enum PressureCategory: Int, Comparable, Sendable {
        case low, normal, elevated, stage1, stage2, crisis

        static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }

        var title: String {
            switch self {
            case .low: String(localized: "Low")
            case .normal: String(localized: "Normal")
            case .elevated: String(localized: "Elevated")
            case .stage1: String(localized: "Stage 1")
            case .stage2: String(localized: "Stage 2")
            case .crisis: String(localized: "Very high")
            }
        }

        /// The systolic the marker sits at: the reading's own, lifted into
        /// the category's zone when the diastolic earned it.
        func marker(systolic: Double) -> Double {
            switch self {
            case .low: min(systolic, 89)
            case .normal: min(max(systolic, 90), 119)
            case .elevated: min(max(systolic, 120), 129)
            case .stage1: min(max(systolic, 130), 139)
            case .stage2, .crisis: max(systolic, 140)
            }
        }
    }

    static func pressureCategory(systolic: Double, diastolic: Double) -> PressureCategory? {
        guard systolic > 0 else { return nil }
        if systolic > 180 || diastolic > 120 { return .crisis }
        if systolic >= 140 || diastolic >= 90 { return .stage2 }
        if systolic >= 130 || diastolic >= 80 { return .stage1 }
        if systolic >= 120 { return .elevated }
        // Under 90/60 reads as low (AHA): worth knowing, often harmless.
        if systolic < 90 || (diastolic > 0 && diastolic < 60) { return .low }
        return .normal
    }

    // MARK: - The catalog

    private typealias Zone = MetricCoachingAdvice.Zone

    private struct Spec {
        /// The direction for a metric ``MetricProfile`` calls neutral.
        var neutral: MetricCoachingAdvice.Direction = .trend
        var zones: [Zone]
        var target: ClosedRange<Double>?
        var targetLine: String
        /// The value with its unit: "37 ms", "7,240 steps a day".
        var phrase: (Double) -> String
        /// A range with its unit: "42 to 55 ms".
        var range: (ClosedRange<Double>) -> String
        var helps: [String]
        var clinician: (Double, Double?) -> String? = { _, _ in nil }
        var source: String
        /// The zones are built from the usual band, so the verdict already
        /// reads against it.
        var readsUsual = false
        var isPressure = false
        /// The verdict when there is no scale yet.
        var noScale: (String) -> String = { _ in String(localized: "A few more readings set your usual range.") }
    }

    private static func zone(_ name: String, _ lower: Double, _ upper: Double, _ tone: MetricCoachingAdvice.Tone,
                             says: String, means: String? = nil) -> Zone {
        Zone(name: name, lower: lower, upper: upper, tone: tone, says: says, means: means)
    }

    private static func number(_ value: Double) -> String { VaultFormat.number(value) }

    /// A value and its unit, the unit left off when it is empty.
    private static func unit(_ unit: String, after: String = "") -> (Double) -> String {
        { value in [number(value), unit].filter { !$0.isEmpty }.joined(separator: " ") + after }
    }

    private static func span(_ unit: String) -> (ClosedRange<Double>) -> String {
        { range in String(localized: "\(number(range.lowerBound)) to \(number(range.upperBound))") + (unit.isEmpty ? "" : " " + unit) }
    }

    /// Hours as "6 h 40 min".
    static func hours(_ value: Double) -> String {
        let minutes = Int((value * 60).rounded())
        let h = minutes / 60, m = minutes % 60
        if m == 0 { return "\(h) h" }
        return h == 0 ? "\(m) min" : "\(h) h \(m) min"
    }

    /// The age words in a target line.
    private static func ageWords(_ person: Person) -> String {
        guard let age = person.age else { return String(localized: "for adults") }
        let low = min(max(age / 10 * 10, 20), 70)
        return low >= 70 ? String(localized: "at 70 and up") : String(localized: "at \(low) to \(low + 9)")
    }

    private static func sexWords(_ person: Person) -> String {
        switch person.sex {
        case .male: String(localized: "men ")
        case .female: String(localized: "women ")
        default: ""
        }
    }

    private static func spec(_ identifier: String, person: Person, usual: ClosedRange<Double>?) -> Spec? {
        switch identifier {
        case hrv:
            let band = hrvBand(age: person.age)
            return Spec(
                zones: [
                    zone(String(localized: "Low"), 0, band.lowerBound, .fair,
                         says: String(localized: "below the usual range \(ageWords(person))"),
                         means: String(localized: "Lower HRV usually means more strain or less recovery.")),
                    zone(String(localized: "Typical"), band.lowerBound, band.upperBound, .good,
                         says: String(localized: "in the usual range \(ageWords(person))"),
                         means: String(localized: "Your own trend says more than one night.")),
                    zone(String(localized: "High"), band.upperBound, band.upperBound * 1.5, .good,
                         says: String(localized: "above the usual range \(ageWords(person))"),
                         means: String(localized: "Higher HRV usually means good recovery.")),
                ],
                target: band,
                targetLine: String(localized: "Typical \(ageWords(person)): \(span("ms")(band))."),
                phrase: unit("ms"), range: span("ms"),
                helps: [
                    String(localized: "A regular bedtime, within 30 minutes"),
                    String(localized: "No alcohol in the evening"),
                    String(localized: "Easy days after hard training"),
                ],
                source: String(localized: "Nunan et al. 2010; Umetani et al. 1998")
            )

        case restingHeartRate:
            // The app's band (``MetricProfile``) is 50 to 70, inside the AHA's
            // 60 to 100 normal; under 50 is common in trained hearts.
            return Spec(
                zones: [
                    zone(String(localized: "Very low"), 30, 40, .out, says: String(localized: "very low for a resting heart"),
                         means: String(localized: "Common in endurance athletes, otherwise worth a check.")),
                    zone(String(localized: "Athletic"), 40, 50, .good, says: String(localized: "in the athletic range"),
                         means: String(localized: "A low resting rate usually reflects a fit heart.")),
                    zone(String(localized: "Optimal"), 50, 70, .good, says: String(localized: "in the optimal range"),
                         means: String(localized: "Lower within this range usually means a fitter heart.")),
                    zone(String(localized: "Normal"), 70, 100, .fair, says: String(localized: "normal, but above the optimal 50 to 70"),
                         means: String(localized: "A resting rate that creeps up can mean strain, short sleep or illness.")),
                    zone(String(localized: "High"), 100, 130, .out, says: String(localized: "above 100, high for rest")),
                ],
                target: 50...70,
                targetLine: String(localized: "Optimal: 50 to 70 bpm. Normal is 60 to 100, lower in trained people."),
                phrase: unit("bpm"), range: span("bpm"),
                helps: [
                    String(localized: "Steady aerobic training, most days"),
                    String(localized: "Less alcohol, especially late"),
                    String(localized: "Enough sleep and water"),
                ],
                clinician: { value, _ in
                    if value > 100 { return String(localized: "A resting rate over 100 is worth raising with a clinician.") }
                    if value < 40 { return String(localized: "Under 40 without endurance training, or with dizziness, is worth a check with a clinician.") }
                    return nil
                },
                source: String(localized: "American Heart Association")
            )

        case respiratoryRate:
            let word = String(localized: "breaths a minute")
            return Spec(
                zones: [
                    zone(String(localized: "Very low"), 6, 10, .out, says: String(localized: "very low")),
                    zone(String(localized: "Low"), 10, 12, .fair, says: String(localized: "a little under the usual 12 to 20")),
                    zone(String(localized: "Normal"), 12, 20, .good, says: String(localized: "in the normal range"),
                         means: String(localized: "A rise of 2 or more over your usual can come before illness.")),
                    zone(String(localized: "High"), 20, 25, .fair, says: String(localized: "above the usual 12 to 20"),
                         means: String(localized: "Strain, heat, alcohol or illness can raise it.")),
                    zone(String(localized: "Very high"), 25, 35, .out, says: String(localized: "very high for rest")),
                ],
                target: 12...20,
                targetLine: String(localized: "Normal at rest: 12 to 20 \(word)."),
                phrase: unit(word), range: span(word),
                helps: [
                    String(localized: "Slow breathing before bed"),
                    String(localized: "Breathe through the nose at night"),
                    String(localized: "Rest when it jumps over your usual"),
                ],
                clinician: { value, _ in
                    value > 25 || value < 10 ? String(localized: "A resting rate outside 10 to 25 that lasts is worth raising with a clinician.") : nil
                },
                source: String(localized: "Adult resting reference range")
            )

        case oxygen:
            return Spec(
                zones: [
                    zone(String(localized: "Low"), 80, 90, .out, says: String(localized: "low")),
                    zone(String(localized: "Below normal"), 90, 95, .fair, says: String(localized: "under the normal 95 to 100"),
                         means: String(localized: "Brief dips at night happen; repeated ones are worth watching.")),
                    zone(String(localized: "Normal"), 95, 100, .good, says: String(localized: "in the normal range")),
                ],
                target: 95...100,
                targetLine: String(localized: "Normal: 95 to 100%."),
                phrase: { "\(number($0))%" }, range: { String(localized: "\(number($0.lowerBound)) to \(number($0.upperBound))%") },
                helps: [
                    String(localized: "Keep the watch snug for readings"),
                    String(localized: "Sleep on your side if you snore"),
                    String(localized: "Ask about sleep apnea if dips repeat"),
                ],
                clinician: { value, _ in
                    value < 90 ? String(localized: "Readings under 90% that repeat are worth raising with a clinician.") : nil
                },
                source: String(localized: "WHO pulse oximetry manual, 2011")
            )

        case wristTemperature:
            // Apple reads wrist temperature against the person's own baseline:
            // the absolute number varies with the wrist and the room.
            var spec = usualSpec(usual, unit: "°C", reach: 1, good: String(localized: "Usual"), below: .fair, above: .fair)
            spec.helps = [
                String(localized: "A cool, dark bedroom"),
                String(localized: "No alcohol or late meals"),
                String(localized: "Rest up when it rises with fatigue"),
            ]
            spec.targetLine = person.sex == .female
                ? String(localized: "Read against your own usual. It rises about 0.3 °C after ovulation.")
                : String(localized: "Read against your own usual: the number itself varies by wrist and room.")
            spec.source = String(localized: "Your own baseline, as Apple reads it")
            return spec

        case vo2Max:
            let p = vo2Percentiles(age: person.age, sex: person.sex)
            let unitWord = "ml/kg/min"
            let who = "\(sexWords(person))\(ageWords(person))"
            return Spec(
                zones: [
                    zone(String(localized: "Low"), p.low * 0.6, p.low, .out, says: String(localized: "in the lowest quarter for \(who)"),
                         means: String(localized: "Low cardio fitness is one of the strongest risks you can change.")),
                    zone(String(localized: "Below average"), p.low, p.middle, .fair, says: String(localized: "below average for \(who)")),
                    zone(String(localized: "Above average"), p.middle, p.high, .good, says: String(localized: "above average for \(who)")),
                    zone(String(localized: "High"), p.high, p.high * 1.3, .good, says: String(localized: "in the top quarter for \(who)"),
                         means: String(localized: "High cardio fitness goes with a longer, healthier life.")),
                ],
                target: p.middle...p.high,
                targetLine: String(localized: "Average for \(who): \(number(p.middle)) \(unitWord). Top quarter from \(number(p.high))."),
                phrase: unit(unitWord), range: span(unitWord),
                helps: [
                    String(localized: "Easy aerobic work, 150 minutes a week"),
                    String(localized: "One interval session a week"),
                    String(localized: "Less body fat raises it per kilo"),
                ],
                source: String(localized: "FRIEND registry (Kaminsky et al. 2015), ACSM")
            )

        case recovery:
            return Spec(
                zones: [
                    zone(String(localized: "Low"), 0, 12, .out, says: String(localized: "slow"),
                         means: String(localized: "After a hard effort, 12 or less is a known warning sign.")),
                    zone(String(localized: "Fair"), 12, 20, .fair, says: String(localized: "fair")),
                    zone(String(localized: "Good"), 20, 60, .good, says: String(localized: "good"),
                         means: String(localized: "A fast drop usually means a fit heart.")),
                ],
                target: 20...60,
                targetLine: String(localized: "Good: a drop of 20 bpm or more in the first minute after a hard effort."),
                phrase: { String(localized: "drop of \(number($0)) bpm") }, range: span("bpm"),
                helps: [
                    String(localized: "Regular aerobic training"),
                    String(localized: "Recovery days between hard ones"),
                    String(localized: "Compare efforts of the same kind"),
                ],
                clinician: { value, _ in
                    value <= 12 ? String(localized: "A drop of 12 or less after hard efforts, on repeat, is worth raising with a clinician.") : nil
                },
                source: String(localized: "Cole et al. 1999, NEJM")
            )

        case walkingSpeed:
            return Spec(
                zones: [
                    zone(String(localized: "Slow"), 0.4, 0.8, .out, says: String(localized: "a slow pace")),
                    zone(String(localized: "Moderate"), 0.8, 1.0, .fair, says: String(localized: "a moderate pace")),
                    zone(String(localized: "Healthy"), 1.0, 1.3, .good, says: String(localized: "a healthy pace"),
                         means: String(localized: "Walking pace tracks health and fitness closely with age.")),
                    zone(String(localized: "Brisk"), 1.3, 1.8, .good, says: String(localized: "a brisk pace")),
                ],
                target: 1.0...1.8,
                targetLine: String(localized: "Healthy: 1.0 m/s or faster. Under 0.8 m/s goes with poorer health."),
                phrase: unit("m/s"), range: span("m/s"),
                helps: [
                    String(localized: "Walk briskly most days"),
                    String(localized: "Leg strength, twice a week"),
                    String(localized: "Balance work, like standing on one leg"),
                ],
                clinician: { value, _ in
                    value < 0.8 ? String(localized: "A usual pace under 0.8 m/s is worth mentioning at your next checkup.") : nil
                },
                source: String(localized: "Studenski et al. 2011, JAMA")
            )

        case steps:
            // Benefits level off around 6,000 to 8,000 a day at 60 and over,
            // 8,000 to 10,000 under 60 (Paluch et al., Lancet Public Health
            // 2022; Banach et al., Eur J Prev Cardiol 2023).
            let older = (person.age ?? 0) >= 60
            let band: ClosedRange<Double> = older ? 6000...8000 : 7000...10000
            let floor: Double = older ? 3000 : 4000
            let word = String(localized: "steps")
            return Spec(
                zones: [
                    zone(String(localized: "Low"), 0, floor, .out, says: String(localized: "low"),
                         means: String(localized: "Every extra 1,000 a day lowers risk the most down here.")),
                    zone(String(localized: "Moderate"), floor, band.lowerBound, .fair, says: String(localized: "under the \(span("")(band)) where the benefits level off")),
                    zone(String(localized: "Active"), band.lowerBound, band.upperBound, .good, says: String(localized: "in the range where the benefits level off")),
                    zone(String(localized: "Very active"), band.upperBound, band.upperBound * 1.6, .good, says: String(localized: "above the range where the benefits level off")),
                ],
                target: band,
                targetLine: String(localized: "Most of the benefit: \(span(word)(band)) a day\(older ? String(localized: " at 60 and over") : "")."),
                phrase: unit(word, after: String(localized: " a day")), range: span(word),
                helps: [
                    String(localized: "A 10 minute walk after meals"),
                    String(localized: "Walking calls and meetings"),
                    String(localized: "Stairs over the lift"),
                ],
                source: String(localized: "Paluch et al. 2022; Banach et al. 2023")
            )

        case MetricProfile.sleep:
            // AASM and Sleep Research Society (2015): 7 hours or more for
            // adults; National Sleep Foundation (2015): 7 to 9 up to 64, 7 to
            // 8 from 65, 8 to 10 for teenagers.
            let age = person.age ?? 30
            let band: ClosedRange<Double> = age < 18 ? 8...10 : age >= 65 ? 7...8 : 7...9
            let night = String(localized: " a night")
            return Spec(
                zones: [
                    zone(String(localized: "Short"), 4, 6, .out, says: String(localized: "short"),
                         means: String(localized: "Short nights show up in mood, appetite and recovery.")),
                    zone(String(localized: "A bit short"), 6, band.lowerBound, .fair, says: String(localized: "just under the \(hours(band.lowerBound)) to \(hours(band.upperBound)) you need")),
                    zone(String(localized: "Enough"), band.lowerBound, band.upperBound, .good, says: String(localized: "in the range you need")),
                    zone(String(localized: "Long"), band.upperBound, band.upperBound + 2, .fair, says: String(localized: "more than most people need"),
                         means: String(localized: "Long nights can mean sleep that does not restore.")),
                ],
                target: band,
                targetLine: String(localized: "Most people \(ageWords(person)) need \(hours(band.lowerBound)) to \(hours(band.upperBound))."),
                phrase: { hours($0) + night }, range: { "\(hours($0.lowerBound)) to \(hours($0.upperBound))" },
                helps: [
                    String(localized: "The same wake time every day"),
                    String(localized: "Caffeine before noon"),
                    String(localized: "Dim lights in the last hour"),
                ],
                source: String(localized: "AASM and SRS 2015; National Sleep Foundation 2015")
            )

        case activeEnergy:
            // No single number fits every body; the person's usual is the
            // yardstick, rising past it is the good way (MetricProfile).
            var spec = usualSpec(usual, unit: "kcal", reach: 0.5, relative: true,
                                 good: String(localized: "Usual"), below: .fair, above: .good, after: String(localized: " a day"))
            spec.targetLine = String(localized: "No single target fits everyone. Beat your usual on most days.")
            spec.helps = [
                String(localized: "Move a little every hour"),
                String(localized: "A brisk walk counts"),
                String(localized: "Strength sessions add up"),
            ]
            spec.source = String(localized: "Your own usual; AHA activity guidelines 2018")
            return spec

        case exercise:
            // WHO 2020: 150 to 300 minutes of moderate activity a week, about
            // 22 to 43 a day.
            let word = "min"
            return Spec(
                zones: [
                    zone(String(localized: "Little"), 0, 10, .out, says: String(localized: "little"),
                         means: String(localized: "Any amount helps; the first minutes count the most.")),
                    zone(String(localized: "Some"), 10, 22, .fair, says: String(localized: "under the 150 minutes a week to aim for")),
                    zone(String(localized: "On target"), 22, 43, .good, says: String(localized: "on target, 150 to 300 minutes a week")),
                    zone(String(localized: "Above target"), 43, 90, .good, says: String(localized: "above the weekly target")),
                ],
                target: 22...43,
                targetLine: String(localized: "Aim for 150 to 300 minutes a week, about 22 to 43 a day."),
                phrase: unit(word, after: String(localized: " a day")), range: span(word),
                helps: [
                    String(localized: "Brisk walking counts"),
                    String(localized: "Bouts of 10 minutes add up"),
                    String(localized: "Two strength sessions a week"),
                ],
                source: String(localized: "WHO physical activity guidelines 2020")
            )

        case weight:
            var spec = usualSpec(usual, unit: "kg", reach: 2, good: String(localized: "Steady"), below: .fair, above: .fair)
            spec.targetLine = String(localized: "No number fits every body. BMI and body fat say more; steady is the goal.")
            spec.helps = [
                String(localized: "Protein at every meal"),
                String(localized: "Strength training twice a week"),
                String(localized: "Weigh in at the same time of day"),
            ]
            spec.source = String(localized: "Your own usual")
            return spec

        case bodyFat:
            // American Council on Exercise categories: athletes and fit
            // people 6 to 17% (men), 14 to 24% (women); average to 24 and
            // 31; essential fat under 6 and 14.
            let (floor, fit, average, top): (Double, Double, Double, Double) = switch person.sex {
            case .male: (6, 18, 25, 40)
            case .female: (14, 25, 32, 50)
            default: (10, 21, 28, 45)
            }
            let who = sexWords(person).isEmpty ? String(localized: "adults") : sexWords(person).trimmingCharacters(in: .whitespaces)
            return Spec(
                zones: [
                    zone(String(localized: "Very low"), floor - 4, floor, .out, says: String(localized: "very low"),
                         means: String(localized: "Too little fat strains hormones and recovery.")),
                    zone(String(localized: "Fit"), floor, fit, .good, says: String(localized: "in the fit range for \(who)")),
                    zone(String(localized: "Average"), fit, average, .fair, says: String(localized: "average for \(who)")),
                    zone(String(localized: "High"), average, top, .out, says: String(localized: "high for \(who)"),
                         means: String(localized: "Fat above this range raises heart and metabolic risk.")),
                ],
                target: floor...fit,
                targetLine: String(localized: "Fit for \(who): \(number(floor)) to \(number(fit))%. Lower is better down to that floor."),
                phrase: { "\(number($0))%" }, range: { "\(number($0.lowerBound)) to \(number($0.upperBound))%" },
                helps: [
                    String(localized: "Strength training twice a week"),
                    String(localized: "Protein at every meal"),
                    String(localized: "Seven hours of sleep or more"),
                ],
                source: String(localized: "American Council on Exercise")
            )

        case leanMass:
            var spec = usualSpec(usual, unit: "kg", reach: 2, good: String(localized: "Usual"), below: .fair, above: .good)
            spec.targetLine = String(localized: "Depends on height and frame. Holding or adding it with age is what counts.")
            spec.helps = [
                String(localized: "Progressive strength training"),
                String(localized: "Protein spread over the day"),
                String(localized: "Enough sleep to rebuild"),
            ]
            spec.source = String(localized: "Your own usual")
            return spec

        case bmi:
            return Spec(
                neutral: .range,
                zones: [
                    zone(String(localized: "Underweight"), 14, 18.5, .out, says: String(localized: "under the healthy range")),
                    zone(String(localized: "Healthy"), 18.5, 25, .good, says: String(localized: "in the healthy range")),
                    zone(String(localized: "Overweight"), 25, 30, .fair, says: String(localized: "above the healthy range"),
                         means: String(localized: "BMI cannot tell muscle from fat; body fat says more.")),
                    zone(String(localized: "Obesity"), 30, 40, .out, says: String(localized: "in the obesity range"),
                         means: String(localized: "BMI cannot tell muscle from fat; body fat says more.")),
                ],
                target: 18.5...24.9,
                targetLine: String(localized: "Healthy: 18.5 to 24.9."),
                phrase: { String(localized: "BMI of \(number($0))") }, range: span(""),
                helps: [
                    String(localized: "Protein and vegetables first"),
                    String(localized: "Strength training twice a week"),
                    String(localized: "Steady sleep and meal times"),
                ],
                clinician: { value, _ in
                    value < 18.5 || value >= 30 ? String(localized: "A BMI under 18.5, or 30 and above, is worth discussing with a clinician.") : nil
                },
                source: String(localized: "WHO adult BMI classes")
            )

        case MetricProfile.systolic, MetricProfile.diastolic:
            return Spec(
                neutral: .range,
                zones: [
                    zone(PressureCategory.low.title, 80, 90, .fair, says: String(localized: "low"),
                         means: String(localized: "Often harmless; dizziness on standing is worth mentioning.")),
                    zone(PressureCategory.normal.title, 90, 120, .good, says: String(localized: "normal, under 120/80")),
                    zone(PressureCategory.elevated.title, 120, 130, .fair, says: String(localized: "elevated"),
                         means: String(localized: "Habits move it most at this stage.")),
                    zone(PressureCategory.stage1.title, 130, 140, .out, says: String(localized: "in stage 1 high blood pressure")),
                    zone(PressureCategory.stage2.title, 140, 180, .out, says: String(localized: "in stage 2 high blood pressure")),
                ],
                target: 90...119,
                targetLine: String(localized: "Normal: under 120/80. Elevated: 120 to 129 over under 80. High: 130/80 or more."),
                phrase: unit("mmHg"), range: span("mmHg"),
                helps: [
                    String(localized: "Less salt, more vegetables"),
                    String(localized: "Regular aerobic activity"),
                    String(localized: "Less alcohol"),
                ],
                clinician: { systolic, diastolic in
                    switch pressureCategory(systolic: systolic, diastolic: diastolic ?? 0) {
                    case .crisis: String(localized: "Over 180/120: retake it after 5 quiet minutes. If it stays there, seek care now.")
                    case .stage2: String(localized: "At 140/90 or more on repeat, see a clinician soon.")
                    case .stage1: String(localized: "Readings at 130/80 or more, on repeat, are worth raising with a clinician.")
                    default: nil
                    }
                },
                source: String(localized: "ACC/AHA guideline 2017"),
                isPressure: true
            )

        case glucose:
            // ADA Standards of Care: fasting 70 to 99 normal, 100 to 125
            // prediabetes, 126 and up diabetes; under 70 is low.
            return Spec(
                neutral: .range,
                zones: [
                    zone(String(localized: "Low"), 40, 70, .out, says: String(localized: "low")),
                    zone(String(localized: "Normal"), 70, 100, .good, says: String(localized: "in the normal fasting range")),
                    zone(String(localized: "Raised"), 100, 126, .fair, says: String(localized: "above the fasting range"),
                         means: String(localized: "After a meal, under 140 is typical.")),
                    zone(String(localized: "High"), 126, 250, .out, says: String(localized: "high for fasting"),
                         means: String(localized: "After a meal, under 140 is typical.")),
                ],
                target: 70...99,
                targetLine: String(localized: "Fasting: 70 to 99 mg/dL. After a meal, under 140."),
                phrase: unit("mg/dL"), range: span("mg/dL"),
                helps: [
                    String(localized: "A short walk after meals"),
                    String(localized: "Fiber and protein before carbs"),
                    String(localized: "Full nights: short ones raise it"),
                ],
                clinician: { value, _ in
                    if value < 70 { return String(localized: "Readings under 70 that repeat are worth raising with a clinician.") }
                    if value >= 126 { return String(localized: "A fasting reading of 126 or more, twice, is worth raising with a clinician.") }
                    if value >= 100 { return String(localized: "Fasting at 100 to 125 on repeat is worth an HbA1c test.") }
                    return nil
                },
                source: String(localized: "ADA Standards of Care")
            )

        case steadiness:
            // Apple's own bands, as ``SteadinessLevel`` reads them.
            return Spec(
                zones: [
                    zone(SteadinessLevel.veryLow.title, 0, SteadinessLevel.lowFloor * 100, .out, says: String(localized: "very low"),
                         means: String(localized: "It goes with a much higher chance of a fall this year.")),
                    zone(SteadinessLevel.low.title, SteadinessLevel.lowFloor * 100, SteadinessLevel.okFloor * 100, .fair, says: String(localized: "low"),
                         means: String(localized: "It goes with a higher chance of a fall this year.")),
                    zone(SteadinessLevel.ok.title, SteadinessLevel.okFloor * 100, 100, .good, says: String(localized: "OK")),
                ],
                target: (SteadinessLevel.okFloor * 100)...100,
                targetLine: String(localized: "OK: 40% and up."),
                phrase: { "\(number($0))%" }, range: { "\(number($0.lowerBound)) to \(number($0.upperBound))%" },
                helps: [
                    String(localized: "Balance work, like standing on one leg"),
                    String(localized: "Leg strength, twice a week"),
                    String(localized: "Supportive shoes and clear floors"),
                ],
                clinician: { value, _ in
                    value < SteadinessLevel.lowFloor * 100 ? String(localized: "Very low steadiness is worth raising with a clinician, who can check balance.") : nil
                },
                source: String(localized: "Apple, Walking Steadiness 2021")
            )

        default:
            return nil
        }
    }

    /// A metric read against the person's own usual band: below, usual,
    /// above. Without a usual band there is no scale yet.
    ///
    /// - Parameters:
    ///   - reach: how far past the band the scale runs, in the unit, or as a
    ///     share of the band's middle when `relative`.
    private static func usualSpec(_ usual: ClosedRange<Double>?, unit word: String, reach: Double, relative: Bool = false,
                                  good: String, below: MetricCoachingAdvice.Tone, above: MetricCoachingAdvice.Tone,
                                  after: String = "") -> Spec {
        let range = span(word)
        var zones: [Zone] = []
        if let usual {
            let pad = relative ? (usual.lowerBound + usual.upperBound) / 2 * reach : reach
            let words = range(usual)
            zones = [
                zone(String(localized: "Below usual"), max(0, usual.lowerBound - pad), usual.lowerBound, below,
                     says: String(localized: "under your usual of \(words)")),
                zone(good, usual.lowerBound, usual.upperBound, .good, says: String(localized: "within your usual of \(words)")),
                zone(String(localized: "Above usual"), usual.upperBound, usual.upperBound + pad, above,
                     says: String(localized: "over your usual of \(words)")),
            ]
        }
        return Spec(
            zones: zones, target: usual,
            targetLine: "",
            phrase: unit(word, after: after), range: range,
            helps: [], source: "",
            readsUsual: true
        )
    }

    /// The zone holding `value`: the first whose top it sits under, the
    /// ends taking whatever falls off the scale.
    static func zoneIndex(_ value: Double, in zones: [MetricCoachingAdvice.Zone]) -> Int? {
        guard !zones.isEmpty else { return nil }
        return zones.firstIndex { value < $0.upper } ?? zones.count - 1
    }

    private static func usualLine(_ value: Double?, usual: ClosedRange<Double>?, spec: Spec) -> String? {
        guard let usual else { return nil }
        let words = spec.range(usual)
        guard let value, !spec.isPressure else { return String(localized: "Your usual: \(words).") }
        if value < usual.lowerBound { return String(localized: "Under your usual of \(words).") }
        if value > usual.upperBound { return String(localized: "Over your usual of \(words).") }
        return String(localized: "Within your usual of \(words).")
    }
}
