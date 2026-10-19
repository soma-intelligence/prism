//
//  MindEntries.swift
//  Prism
//
//  What a person tells Mind: how they feel, a check-in, the words of a day,
//  and the choices of the consent screen. Plain values, so the pages'
//  arithmetic is tested without a store.
//

import Foundation

/// A feeling a person can name. The id is Apple Health's own label name, so
/// an entry written to Health and read back keeps its words.
nonisolated struct MindFeeling: Equatable, Hashable, Sendable, Identifiable {
    var id: String
    var title: String
    var isPleasant: Bool

    static let all: [MindFeeling] = [
        .init(id: "calm", title: "Calm", isPleasant: true),
        .init(id: "content", title: "Content", isPleasant: true),
        .init(id: "grateful", title: "Grateful", isPleasant: true),
        .init(id: "relieved", title: "Relieved", isPleasant: true),
        .init(id: "happy", title: "Happy", isPleasant: true),
        .init(id: "hopeful", title: "Hopeful", isPleasant: true),
        .init(id: "peaceful", title: "Peaceful", isPleasant: true),
        .init(id: "confident", title: "Confident", isPleasant: true),
        .init(id: "excited", title: "Excited", isPleasant: true),
        .init(id: "proud", title: "Proud", isPleasant: true),
        .init(id: "drained", title: "Tired", isPleasant: false),
        .init(id: "stressed", title: "Stretched", isPleasant: false),
        .init(id: "anxious", title: "Anxious", isPleasant: false),
        .init(id: "worried", title: "Worried", isPleasant: false),
        .init(id: "frustrated", title: "Frustrated", isPleasant: false),
        .init(id: "irritated", title: "Irritated", isPleasant: false),
        .init(id: "sad", title: "Sad", isPleasant: false),
        .init(id: "overwhelmed", title: "Overwhelmed", isPleasant: false),
        .init(id: "lonely", title: "Lonely", isPleasant: false),
        .init(id: "hopeless", title: "Hopeless", isPleasant: false),
    ]

    static func named(_ id: String) -> MindFeeling? { all.first { $0.id == id } }

    /// The first words offered: pleasant ones for a pleasant feeling, the
    /// others for an unpleasant one, and a mix in between.
    static func offered(for valence: Double) -> [MindFeeling] {
        if valence > 0.2 { return Array(all.filter(\.isPleasant).prefix(4)) + [all[10]] }
        if valence < -0.2 { return Array(all.filter { !$0.isPleasant }.prefix(5)) }
        return [all[0], all[1], all[10], all[11], all[12]]
    }
}

/// What had a hand in a feeling. The id is Apple Health's association name
/// where one exists.
nonisolated struct MindAssociation: Equatable, Hashable, Sendable, Identifiable {
    var id: String
    var title: String

    static let all: [MindAssociation] = [
        .init(id: "work", title: "Work"),
        .init(id: "health", title: "Health"),
        .init(id: "selfCare", title: "Sleep"),
        .init(id: "family", title: "Family"),
        .init(id: "friends", title: "Friends"),
        .init(id: "partner", title: "Partner"),
        .init(id: "fitness", title: "Fitness"),
        .init(id: "money", title: "Money"),
        .init(id: "tasks", title: "Tasks"),
        .init(id: "weather", title: "Weather"),
        .init(id: "travel", title: "Travel"),
        .init(id: "hobbies", title: "Hobbies"),
    ]

    static func named(_ id: String) -> MindAssociation? { all.first { $0.id == id } }
}

/// How a person feels, right now or over the day.
nonisolated struct MindMoodEntry: Codable, Equatable, Sendable, Identifiable {
    enum Kind: String, Codable, Sendable {
        /// An emotion, right now.
        case momentary
        /// A mood, over the day.
        case daily
    }

    var id = UUID()
    var date: Date
    var kind: Kind
    /// Apple's scale: very unpleasant -1 to very pleasant 1.
    var valence: Double
    /// ``MindFeeling`` ids.
    var labels: [String] = []
    /// ``MindAssociation`` ids.
    var associations: [String] = []
    /// Whether Apple Health holds it too, so a read back does not count it twice.
    var isInHealth = false

    /// The seven stops of the slider, from very unpleasant to very pleasant.
    static let stops = 7

    static func valence(stop: Int) -> Double {
        let clamped = min(max(stop, 0), stops - 1)
        return Double(clamped) / Double(stops - 1) * 2 - 1
    }

    static func stop(valence: Double) -> Int {
        Int(((min(max(valence, -1), 1) + 1) / 2 * Double(stops - 1)).rounded())
    }

    static func title(stop: Int) -> String {
        ["Very unpleasant", "Unpleasant", "Slightly unpleasant", "Neutral", "Slightly pleasant", "Pleasant", "Very pleasant"][min(max(stop, 0), stops - 1)]
    }

    /// Mood on the 0 to 100 scale every Mind dimension uses: -0.5 is 25.
    var mood: Double { (min(max(valence, -1), 1) + 1) / 2 * 100 }
}

/// A quick check-in: energy, mood and focus on five steps each, and an
/// answer to the question the body asked, when it asked one.
nonisolated struct MindCheckIn: Codable, Equatable, Sendable, Identifiable {
    enum Answer: String, Codable, Sendable, CaseIterable {
        case yes, no, notSure

        var title: String {
            switch self {
            case .yes: "Yes"
            case .no: "No"
            case .notSure: "Not sure"
            }
        }
    }

    var id = UUID()
    var date: Date
    /// 0 to 4, nil when skipped.
    var energy: Int?
    var mood: Int?
    var focus: Int?
    var question: String?
    var answer: Answer?

    static let steps = 5

    static func word(energy step: Int?) -> String {
        guard let step else { return "Not set" }
        return ["Very low", "Low", "Steady", "High", "Very high"][min(max(step, 0), 4)]
    }

    static func word(mood step: Int?) -> String {
        guard let step else { return "Not set" }
        return ["Low", "Flat", "Okay", "Good", "Great"][min(max(step, 0), 4)]
    }

    static func word(focus step: Int?) -> String {
        guard let step else { return "Not set" }
        return ["Foggy", "Scattered", "Present", "Clear", "Sharp"][min(max(step, 0), 4)]
    }
}

/// Which way a moment pulled.
nonisolated enum MindPull: String, Codable, Sendable {
    case lifted, weighed, none

    var title: String {
        switch self {
        case .lifted: "lifted"
        case .weighed: "weighed"
        case .none: "no pull"
        }
    }
}

/// A moment of a day, picked out of its words or added by hand.
nonisolated struct MindMoment: Codable, Equatable, Sendable, Identifiable {
    var id = UUID()
    var title: String
    var category: MindEventCategory
    var pull: MindPull
}

/// A day told in words, and what Soma picked out of them.
nonisolated struct MindDayNote: Codable, Equatable, Sendable, Identifiable {
    var id = UUID()
    var day: Date
    var text: String
    var people: [String] = []
    var places: [String] = []
    var moments: [MindMoment] = []
}

/// What the consent screen allowed. Stored on the phone only.
nonisolated struct MindConsent: Codable, Equatable, Sendable {
    /// When Mind was turned on. Nil until the person says yes.
    var givenAt: Date?
    var stateOfMind = true
    var calendar = true
    var voice = false

    var isGiven: Bool { givenAt != nil }
}
