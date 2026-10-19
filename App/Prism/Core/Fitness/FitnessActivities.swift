//
//  FitnessActivities.swift
//  Prism
//

import Foundation

/// Every workout type Apple Health codes, as Soma names and weighs it.
///
/// Each type has a name, a glyph, a MET and the muscle groups a session loads,
/// and in what share. It is kept as plain Swift so the pure engines read it off
/// the main actor and the tests read it without a bundle. Keyed by the raw value of
/// `HKWorkoutActivityType`, which is what a workout reading carries as its
/// value.
nonisolated enum FitnessActivities {
    /// One activity type.
    struct Activity: Sendable, Equatable {
        let raw: Int
        let name: String
        let symbol: String
        /// Metabolic equivalent, when the catalog carries one.
        let met: Double?
        /// Muscle group to its share of a session's work, summing to 1.
        /// Empty for a type that is deliberately left unattributed.
        let shares: [MuscleGroup: Double]
    }

    /// The six groups muscle work is counted in.
    enum MuscleGroup: String, CaseIterable, Sendable, Identifiable {
        case legs = "Legs", core = "Core", back = "Back", arms = "Arms", shoulders = "Shoulders", chest = "Chest"

        var id: String { rawValue }
        var title: String { rawValue }
    }

    /// Walking and running, the types a distance is read for.
    static let onFoot: Set<Int> = [37, 52, 24]
    /// Traditional and functional strength training.
    static let strength: Set<Int> = [50, 20]

    static func activity(_ raw: Int) -> Activity {
        table[raw] ?? Activity(raw: raw, name: "Workout", symbol: "figure.mixed.cardio", met: nil, shares: [:])
    }

    static func name(_ raw: Int) -> String { activity(raw).name }

    static let table: [Int: Activity] = [
        1: Activity(raw: 1, name: "American football", symbol: "figure.american.football", met: nil, shares: [.arms: 0.1, .chest: 0.05, .core: 0.2, .legs: 0.5, .shoulders: 0.15]),
        2: Activity(raw: 2, name: "Archery", symbol: "figure.archery", met: nil, shares: [.arms: 0.2, .back: 0.3, .core: 0.1, .shoulders: 0.4]),
        3: Activity(raw: 3, name: "Aussie football", symbol: "figure.australian.football", met: nil, shares: [.arms: 0.1, .core: 0.2, .legs: 0.55, .shoulders: 0.15]),
        4: Activity(raw: 4, name: "Badminton", symbol: "figure.badminton", met: nil, shares: [.arms: 0.2, .core: 0.15, .legs: 0.4, .shoulders: 0.25]),
        5: Activity(raw: 5, name: "Baseball", symbol: "figure.baseball", met: nil, shares: [.arms: 0.2, .core: 0.25, .legs: 0.3, .shoulders: 0.25]),
        6: Activity(raw: 6, name: "Basketball", symbol: "figure.basketball", met: 6.5, shares: [.arms: 0.1, .core: 0.2, .legs: 0.55, .shoulders: 0.15]),
        7: Activity(raw: 7, name: "Bowling", symbol: "figure.bowling", met: nil, shares: [.arms: 0.35, .core: 0.2, .legs: 0.2, .shoulders: 0.25]),
        8: Activity(raw: 8, name: "Boxing", symbol: "figure.boxing", met: 9.0, shares: [.arms: 0.25, .core: 0.25, .legs: 0.2, .shoulders: 0.3]),
        9: Activity(raw: 9, name: "Climbing", symbol: "figure.climbing", met: 8.0, shares: [.arms: 0.3, .back: 0.3, .core: 0.25, .legs: 0.15]),
        10: Activity(raw: 10, name: "Cricket", symbol: "figure.cricket", met: nil, shares: [.arms: 0.2, .core: 0.25, .legs: 0.35, .shoulders: 0.2]),
        11: Activity(raw: 11, name: "Cross training", symbol: "figure.cross.training", met: 6.0, shares: [.arms: 0.15, .back: 0.15, .core: 0.2, .legs: 0.35, .shoulders: 0.15]),
        12: Activity(raw: 12, name: "Curling", symbol: "figure.curling", met: nil, shares: [.arms: 0.15, .core: 0.25, .legs: 0.4, .shoulders: 0.2]),
        13: Activity(raw: 13, name: "Cycling", symbol: "figure.outdoor.cycle", met: 7.5, shares: [.core: 0.15, .legs: 0.85]),
        16: Activity(raw: 16, name: "Elliptical", symbol: "figure.elliptical", met: 5.0, shares: [.arms: 0.2, .core: 0.15, .legs: 0.65]),
        17: Activity(raw: 17, name: "Equestrian", symbol: "figure.equestrian.sports", met: nil, shares: [.back: 0.2, .core: 0.35, .legs: 0.45]),
        18: Activity(raw: 18, name: "Fencing", symbol: "figure.fencing", met: nil, shares: [.arms: 0.25, .core: 0.2, .legs: 0.45, .shoulders: 0.1]),
        19: Activity(raw: 19, name: "Fishing", symbol: "figure.fishing", met: nil, shares: [.arms: 0.4, .back: 0.3, .core: 0.1, .shoulders: 0.2]),
        20: Activity(raw: 20, name: "Strength", symbol: "figure.strengthtraining.functional", met: 5.0, shares: [.arms: 0.1, .back: 0.2, .chest: 0.1, .core: 0.2, .legs: 0.25, .shoulders: 0.15]),
        21: Activity(raw: 21, name: "Golf", symbol: "figure.golf", met: 4.5, shares: [.back: 0.2, .core: 0.35, .legs: 0.2, .shoulders: 0.25]),
        22: Activity(raw: 22, name: "Gymnastics", symbol: "figure.gymnastics", met: nil, shares: [.arms: 0.2, .back: 0.1, .core: 0.3, .legs: 0.2, .shoulders: 0.2]),
        23: Activity(raw: 23, name: "Handball", symbol: "figure.handball", met: nil, shares: [.arms: 0.15, .core: 0.2, .legs: 0.45, .shoulders: 0.2]),
        24: Activity(raw: 24, name: "Hike", symbol: "figure.hiking", met: 6.0, shares: [.core: 0.2, .legs: 0.8]),
        25: Activity(raw: 25, name: "Hockey", symbol: "figure.hockey", met: nil, shares: [.arms: 0.15, .core: 0.2, .legs: 0.55, .shoulders: 0.1]),
        26: Activity(raw: 26, name: "Hunting", symbol: "figure.hunting", met: nil, shares: [.back: 0.2, .core: 0.2, .legs: 0.6]),
        27: Activity(raw: 27, name: "Lacrosse", symbol: "figure.lacrosse", met: nil, shares: [.arms: 0.15, .core: 0.2, .legs: 0.45, .shoulders: 0.2]),
        28: Activity(raw: 28, name: "Martial arts", symbol: "figure.martial.arts", met: 9.0, shares: [.arms: 0.2, .core: 0.3, .legs: 0.35, .shoulders: 0.15]),
        29: Activity(raw: 29, name: "Mind & body", symbol: "figure.mind.and.body", met: 2.5, shares: [.back: 0.25, .core: 0.4, .legs: 0.2, .shoulders: 0.15]),
        31: Activity(raw: 31, name: "Paddle sports", symbol: "oar.2.crossed", met: nil, shares: [.arms: 0.25, .back: 0.3, .core: 0.2, .shoulders: 0.25]),
        32: Activity(raw: 32, name: "Play", symbol: "figure.play", met: nil, shares: [.arms: 0.2, .core: 0.25, .legs: 0.55]),
        33: Activity(raw: 33, name: "Recovery", symbol: "figure.cooldown", met: nil, shares: [.back: 0.3, .core: 0.35, .legs: 0.2, .shoulders: 0.15]),
        34: Activity(raw: 34, name: "Racquetball", symbol: "figure.racquetball", met: nil, shares: [.arms: 0.2, .core: 0.15, .legs: 0.4, .shoulders: 0.25]),
        35: Activity(raw: 35, name: "Rowing", symbol: "figure.rower", met: 7.0, shares: [.arms: 0.15, .back: 0.3, .core: 0.1, .legs: 0.45]),
        36: Activity(raw: 36, name: "Rugby", symbol: "figure.rugby", met: nil, shares: [.arms: 0.15, .core: 0.2, .legs: 0.5, .shoulders: 0.15]),
        37: Activity(raw: 37, name: "Run", symbol: "figure.run", met: 9.8, shares: [.core: 0.25, .legs: 0.75]),
        38: Activity(raw: 38, name: "Sailing", symbol: "sailboat.fill", met: nil, shares: [.arms: 0.3, .back: 0.3, .core: 0.25, .legs: 0.15]),
        39: Activity(raw: 39, name: "Skating", symbol: "figure.skating", met: nil, shares: [.back: 0.1, .core: 0.2, .legs: 0.7]),
        40: Activity(raw: 40, name: "Snow sports", symbol: "snowflake", met: nil, shares: [.back: 0.1, .core: 0.25, .legs: 0.65]),
        41: Activity(raw: 41, name: "Soccer", symbol: "figure.soccer", met: 7.0, shares: [.core: 0.2, .legs: 0.7, .shoulders: 0.1]),
        42: Activity(raw: 42, name: "Softball", symbol: "figure.softball", met: nil, shares: [.arms: 0.2, .core: 0.25, .legs: 0.3, .shoulders: 0.25]),
        43: Activity(raw: 43, name: "Squash", symbol: "figure.squash", met: nil, shares: [.arms: 0.2, .core: 0.15, .legs: 0.4, .shoulders: 0.25]),
        44: Activity(raw: 44, name: "Stair climb", symbol: "figure.stair.stepper", met: 8.0, shares: [.core: 0.2, .legs: 0.8]),
        45: Activity(raw: 45, name: "Surfing", symbol: "figure.surfing", met: nil, shares: [.back: 0.25, .core: 0.3, .legs: 0.2, .shoulders: 0.25]),
        46: Activity(raw: 46, name: "Swim", symbol: "figure.pool.swim", met: 7.0, shares: [.back: 0.3, .core: 0.2, .legs: 0.2, .shoulders: 0.3]),
        47: Activity(raw: 47, name: "Table tennis", symbol: "figure.table.tennis", met: nil, shares: [.arms: 0.35, .core: 0.2, .legs: 0.2, .shoulders: 0.25]),
        48: Activity(raw: 48, name: "Tennis", symbol: "figure.tennis", met: 7.0, shares: [.arms: 0.2, .core: 0.15, .legs: 0.4, .shoulders: 0.25]),
        49: Activity(raw: 49, name: "Track & field", symbol: "figure.track.and.field", met: nil, shares: [.core: 0.2, .legs: 0.7, .shoulders: 0.1]),
        50: Activity(raw: 50, name: "Strength", symbol: "figure.strengthtraining.traditional", met: 5.0, shares: [.arms: 0.15, .back: 0.2, .chest: 0.2, .core: 0.1, .legs: 0.2, .shoulders: 0.15]),
        51: Activity(raw: 51, name: "Volleyball", symbol: "figure.volleyball", met: nil, shares: [.arms: 0.1, .core: 0.2, .legs: 0.45, .shoulders: 0.25]),
        52: Activity(raw: 52, name: "Walk", symbol: "figure.walk", met: 3.5, shares: [.core: 0.2, .legs: 0.8]),
        53: Activity(raw: 53, name: "Water fitness", symbol: "figure.water.fitness", met: nil, shares: [.arms: 0.15, .core: 0.25, .legs: 0.35, .shoulders: 0.25]),
        54: Activity(raw: 54, name: "Water polo", symbol: "figure.waterpolo", met: nil, shares: [.arms: 0.2, .core: 0.25, .legs: 0.25, .shoulders: 0.3]),
        55: Activity(raw: 55, name: "Water sports", symbol: "figure.surfing", met: nil, shares: [.arms: 0.2, .back: 0.3, .core: 0.25, .shoulders: 0.25]),
        56: Activity(raw: 56, name: "Wrestling", symbol: "figure.wrestling", met: nil, shares: [.arms: 0.15, .back: 0.2, .core: 0.3, .legs: 0.25, .shoulders: 0.1]),
        57: Activity(raw: 57, name: "Yoga", symbol: "figure.yoga", met: 3.0, shares: [.back: 0.2, .core: 0.35, .legs: 0.25, .shoulders: 0.2]),
        58: Activity(raw: 58, name: "Barre", symbol: "figure.barre", met: 3.5, shares: [.core: 0.35, .legs: 0.45, .shoulders: 0.2]),
        59: Activity(raw: 59, name: "Core", symbol: "figure.core.training", met: 4.0, shares: [.back: 0.2, .core: 0.7, .shoulders: 0.1]),
        60: Activity(raw: 60, name: "XC ski", symbol: "figure.skiing.crosscountry", met: nil, shares: [.arms: 0.2, .back: 0.25, .core: 0.1, .legs: 0.45]),
        61: Activity(raw: 61, name: "Downhill ski", symbol: "figure.skiing.downhill", met: 5.5, shares: [.back: 0.05, .core: 0.25, .legs: 0.7]),
        62: Activity(raw: 62, name: "Flexibility", symbol: "figure.flexibility", met: 2.5, shares: [.back: 0.3, .core: 0.2, .legs: 0.3, .shoulders: 0.2]),
        63: Activity(raw: 63, name: "HIIT", symbol: "figure.highintensity.intervaltraining", met: 8.0, shares: [.arms: 0.1, .back: 0.05, .chest: 0.1, .core: 0.25, .legs: 0.4, .shoulders: 0.1]),
        64: Activity(raw: 64, name: "Jump rope", symbol: "figure.jumprope", met: 11.0, shares: [.core: 0.2, .legs: 0.7, .shoulders: 0.1]),
        65: Activity(raw: 65, name: "Kickboxing", symbol: "figure.kickboxing", met: 8.0, shares: [.arms: 0.2, .core: 0.25, .legs: 0.35, .shoulders: 0.2]),
        66: Activity(raw: 66, name: "Pilates", symbol: "figure.pilates", met: 3.5, shares: [.back: 0.15, .core: 0.5, .legs: 0.25, .shoulders: 0.1]),
        67: Activity(raw: 67, name: "Snowboard", symbol: "figure.snowboarding", met: 5.0, shares: [.back: 0.1, .core: 0.25, .legs: 0.65]),
        68: Activity(raw: 68, name: "Stairs", symbol: "figure.stair.stepper", met: nil, shares: [.core: 0.2, .legs: 0.8]),
        69: Activity(raw: 69, name: "Step training", symbol: "figure.stair.stepper", met: nil, shares: [.core: 0.2, .legs: 0.7, .shoulders: 0.1]),
        70: Activity(raw: 70, name: "Wheelchair walk", symbol: "figure.roll", met: nil, shares: [.arms: 0.3, .back: 0.25, .core: 0.1, .shoulders: 0.35]),
        71: Activity(raw: 71, name: "Wheelchair run", symbol: "figure.roll", met: nil, shares: [.arms: 0.3, .back: 0.25, .core: 0.1, .shoulders: 0.35]),
        72: Activity(raw: 72, name: "Tai chi", symbol: "figure.taichi", met: 3.0, shares: [.back: 0.1, .core: 0.3, .legs: 0.4, .shoulders: 0.2]),
        73: Activity(raw: 73, name: "Cardio", symbol: "figure.highintensity.intervaltraining", met: nil, shares: [.arms: 0.1, .core: 0.2, .legs: 0.55, .shoulders: 0.15]),
        74: Activity(raw: 74, name: "Hand cycling", symbol: "figure.hand.cycling", met: nil, shares: [.arms: 0.35, .back: 0.25, .core: 0.1, .shoulders: 0.3]),
        75: Activity(raw: 75, name: "Disc sports", symbol: "figure.disc.sports", met: nil, shares: [.arms: 0.1, .core: 0.2, .legs: 0.45, .shoulders: 0.25]),
        76: Activity(raw: 76, name: "Fitness gaming", symbol: "gamecontroller.fill", met: nil, shares: [.arms: 0.25, .core: 0.2, .legs: 0.4, .shoulders: 0.15]),
        77: Activity(raw: 77, name: "Cardio dance", symbol: "figure.dance", met: nil, shares: [.core: 0.25, .legs: 0.55, .shoulders: 0.2]),
        78: Activity(raw: 78, name: "Social dance", symbol: "figure.dance", met: nil, shares: [.core: 0.25, .legs: 0.55, .shoulders: 0.2]),
        79: Activity(raw: 79, name: "Pickleball", symbol: "figure.pickleball", met: nil, shares: [.arms: 0.2, .core: 0.15, .legs: 0.4, .shoulders: 0.25]),
        80: Activity(raw: 80, name: "Cooldown", symbol: "figure.cooldown", met: nil, shares: [.back: 0.3, .core: 0.2, .legs: 0.35, .shoulders: 0.15]),
        82: Activity(raw: 82, name: "Swim / bike / run", symbol: "figure.run", met: nil, shares: [.back: 0.2, .core: 0.1, .legs: 0.55, .shoulders: 0.15]),
        83: Activity(raw: 83, name: "Transition", symbol: "arrow.triangle.2.circlepath", met: nil, shares: [:]),
        84: Activity(raw: 84, name: "Diving", symbol: "figure.pool.swim", met: nil, shares: [.back: 0.2, .core: 0.3, .legs: 0.35, .shoulders: 0.15]),
        3000: Activity(raw: 3000, name: "Workout", symbol: "bolt.heart.fill", met: nil, shares: [:]),
    ]
}
