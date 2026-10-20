//
//  ExploreRanking.swift
//  Prism
//
//  Orders Explore by what the person seems to want to read: readings that
//  moved lately, the pages they open most, the pieces they read and save.
//  Pure arithmetic over values already on the device, so it is tested
//  without a Health store, and the same inputs always give the same page.
//

import Foundation

/// One thing about the person that points at a topic, with the few words
/// that say so on a card.
struct ExploreSignal: Equatable, Sendable {
    enum Source: Int, Equatable, Sendable {
        /// A reading that moved away from the person's usual.
        case reading
        /// Pieces they saved.
        case saved
        /// Pages they open often.
        case visits
        /// Pieces they have been reading.
        case reads
    }

    var source: Source
    var topic: ArticleTopic
    /// Words that make a piece a close match when its title or one line
    /// holds them, matched at the start of a word ("sleep" finds
    /// "sleeping"), lowercased.
    var keywords: [String] = []
    /// How strongly it counts, 0 to 1.
    var weight: Double
    /// "Because your sleep was short this week".
    var reason: String
}

enum ExploreSignals {
    /// Every signal, strongest first.
    static func make(readings: [InsightMetric: Insight], log: ExploreInterestLog, now: Date) -> [ExploreSignal] {
        (fromReadings(readings) + fromHabits(log, now: now)).sorted(by: stronger)
    }

    // MARK: Readings

    /// The readings that sit outside the person's usual lately, each as the
    /// topic it points at. A reading older than a week says nothing about
    /// this week, and one inside its usual band says nothing at all.
    static func fromReadings(_ readings: [InsightMetric: Insight]) -> [ExploreSignal] {
        InsightMetric.allCases.compactMap { metric in
            guard let insight = readings[metric], insight.current != nil,
                  let position = insight.position, position != .within,
                  (insight.currentAge ?? 0) <= InsightEngine.recentDays,
                  let words = words(for: metric, position == .above) else { return nil }
            return ExploreSignal(source: .reading, topic: words.topic, keywords: words.keywords,
                                 weight: 0.6 + 0.4 * min(max(insight.severity, 0), 1), reason: words.reason)
        }
    }

    private struct Words {
        var topic: ArticleTopic
        var keywords: [String]
        var reason: String
    }

    /// The topic, the matching words and the reason for a reading above or
    /// below its usual. Wellness words: what moved, never what it might mean.
    private static func words(for metric: InsightMetric, _ up: Bool) -> Words? {
        switch metric {
        case .sleepDuration:
            Words(topic: .sleep, keywords: ["sleep", "nap", "bedtime", "night"],
                  reason: up ? "Because you slept longer this week" : "Because your sleep was short this week")
        case .restingHeartRate:
            Words(topic: .heart, keywords: ["heart", "pulse", "cardio"],
                  reason: up ? "Because your resting heart rate is up" : "Because your resting heart rate is down")
        case .heartRateVariability:
            Words(topic: .recovery, keywords: ["hrv", "stress", "relax", "calm", "meditat", "heart rate variability"],
                  reason: up ? "Because your HRV rose this week" : "Because your HRV dipped this week")
        case .steps:
            Words(topic: .movement, keywords: ["walk", "step", "physical activity", "exercise", "active", "sitting"],
                  reason: up ? "Because you walked more this week" : "Because you walked less this week")
        case .walkingSpeed:
            up ? nil : Words(topic: .movement, keywords: ["walk", "balance", "mobility"],
                             reason: "Because you walked slower this week")
        case .respiratoryRate:
            up ? Words(topic: .recovery, keywords: ["breath", "lung", "respirat"],
                       reason: "Because your breathing rate is up") : nil
        case .bloodOxygen:
            up ? nil : Words(topic: .recovery, keywords: ["lung", "breath", "oxygen"],
                             reason: "Because your blood oxygen dipped")
        case .wristTemperature:
            up ? Words(topic: .recovery, keywords: ["immune", "cold", "temperature"],
                       reason: "Because your wrist temperature is up") : nil
        case .vo2Max:
            Words(topic: .longevity, keywords: ["fitness", "exercise", "aerobic", "cardio"],
                  reason: up ? "Because your cardio fitness rose" : "Because your cardio fitness dipped")
        case .heartRateRecovery:
            up ? nil : Words(topic: .heart, keywords: ["fitness", "exercise", "heart"],
                             reason: "Because your heart rate recovery dipped")
        case .weight:
            Words(topic: .nutrition, keywords: ["weight", "diet", "eating", "food"],
                  reason: "Because your weight moved this week")
        case .bloodPressure:
            up ? Words(topic: .heart, keywords: ["blood pressure", "salt", "sodium"],
                       reason: "Because your blood pressure is up") : nil
        case .bloodGlucose:
            up ? Words(topic: .nutrition, keywords: ["sugar", "glucose", "carbohydrate"],
                       reason: "Because your blood sugar is up") : nil
        case .bodyFat, .leanMass, .bodyMassIndex:
            nil
        }
    }

    // MARK: Habits

    /// Pages opened at least twice in the last month, pieces read at least
    /// twice in the last two months, and anything saved.
    static func fromHabits(_ log: ExploreInterestLog, now: Date) -> [ExploreSignal] {
        let month = now.addingTimeInterval(-30 * 86_400)
        let twoMonths = now.addingTimeInterval(-60 * 86_400)
        var signals: [ExploreSignal] = []

        let visits = counts(log.visits.filter { $0.date >= month }.map(\.topic))
        let reads = counts(log.reads.filter { $0.date >= twoMonths }.map(\.topic))
        let saved = counts(log.saved.map(\.topic))

        for topic in ArticleTopic.allCases {
            if let count = saved[topic] {
                signals.append(ExploreSignal(source: .saved, topic: topic, weight: 0.3 + 0.1 * Double(min(count, 3)),
                                             reason: "Because you saved a piece on \(topic.title.lowercased())"))
            }
            if let count = visits[topic], count >= 2 {
                signals.append(ExploreSignal(source: .visits, topic: topic, weight: 0.25 + 0.05 * Double(min(count, 8)),
                                             reason: "Because you check \(topic.yours) often"))
            }
            if let count = reads[topic], count >= 2 {
                signals.append(ExploreSignal(source: .reads, topic: topic, weight: 0.2 + 0.05 * Double(min(count, 6)),
                                             reason: "Because you've been reading about \(topic.title.lowercased())"))
            }
        }
        return signals
    }

    private static func counts(_ topics: [ArticleTopic]) -> [ArticleTopic: Int] {
        topics.reduce(into: [:]) { $0[$1, default: 0] += 1 }
    }

    /// Heavier first; on a tie the source's order, then the topic's.
    static func stronger(_ a: ExploreSignal, _ b: ExploreSignal) -> Bool {
        if a.weight != b.weight { return a.weight > b.weight }
        if a.source != b.source { return a.source.rawValue < b.source.rawValue }
        return a.topic.order < b.topic.order
    }
}

/// A piece picked for the person, with why.
struct ExplorePick: Equatable, Identifiable, Sendable {
    var article: Article
    var reason: String
    var id: String { article.id }
}

/// A topic's best pieces for the person, in a sideways row.
struct ExploreShelf: Equatable, Identifiable, Sendable {
    var topic: ArticleTopic
    var articles: [Article]
    var id: ArticleTopic { topic }
}

/// The page Explore draws: "For you" at the top, what was saved, then a shelf
/// a topic in the order the person cares about them, and every piece ranked
/// for the grid a topic chip or a search opens.
struct ExplorePlan: Equatable, Sendable {
    var forYou: [ExplorePick]
    var saved: [Article]
    var shelves: [ExploreShelf]
    var ranked: [Article]

    static let empty = ExplorePlan(forYou: [], saved: [], shelves: [], ranked: [])
}

enum ExploreRanking {
    /// Pieces in "For you".
    static let picks = 4
    /// Picks that may share one reason, so one signal does not fill the
    /// section.
    static let perReason = 2
    /// Pieces on a shelf.
    static let shelfSize = 10
    /// What a piece already read keeps of its score: it sinks, it does not
    /// vanish.
    static let readKeeps = 0.25
    /// A match on the title or the one line counts this much more than a
    /// match on the topic alone.
    static let keywordWeight = 1.5
    /// What every signal but the strongest adds for a piece: a piece that
    /// touches many signals a little does not beat one that answers one
    /// signal well.
    static let otherSignals = 0.25
    /// Words that name a condition, matched at the start of a word. A
    /// reading never offers a piece whose title or one line holds one: "your
    /// resting heart rate is up" beside "heart attack" reads as a warning,
    /// and Prism makes none. Such a piece stays on its shelf and in search.
    /// A reading's own keywords never hold one either.
    static let conditionWords = [
        "attack", "stroke", "disease", "cancer", "tumor", "covid", "diabetes", "failure", "death", "dying",
        "dementia", "alzheimer", "disorder", "infection", "syndrome", "sclerosis", "injury", "opioid",
        "overdose", "hiv", "illness", "risk", "hypertension", "insomnia", "fever", "influenza", "falls",
    ]
    /// Condition words too short to match as the start of a word ("flu"
    /// begins "fluid"), so matched whole.
    static let conditionWholeWords = ["flu"]
    /// The newest pieces lead a little: the most a piece gains for being new,
    /// lost evenly over two years.
    static let freshness = 0.25
    static let freshnessDays = 730.0
    /// Pieces written for a reader to act on lead over research news: the
    /// library's own the most, NIH News in Health a little.
    static let writtenBonus = 0.6
    static let guideBonus = 0.3
    /// The reason a piece is offered when nothing about the person points
    /// anywhere yet.
    static let startReason = "A good place to start"

    struct Scored: Equatable {
        var score: Double
        /// The signal that counted most for this piece, if any did.
        var reason: ExploreSignal?
        /// Whether that signal's words are in the title or the one line:
        /// a reading only offers a piece in "For you" that names it, so a
        /// short night brings pieces about sleep rather than anything filed
        /// under the topic.
        var close: Bool
        /// What the signals alone gave it.
        var personal: Double
    }

    /// One piece's score for the person.
    static func score(_ article: Article, signals: [ExploreSignal], read: Bool, now: Date) -> Scored {
        score(article, words: words(of: article), signals: signals, read: read, now: now)
    }

    private static func score(_ article: Article, words: String, signals: [ExploreSignal], read: Bool, now: Date) -> Scored {
        var sum = 0.0
        var best: (value: Double, signal: ExploreSignal, close: Bool)?
        for signal in signals {
            var value = article.topic == signal.topic ? signal.weight : 0
            let close = signal.keywords.contains { words.contains(" " + $0) }
            if close { value += signal.weight * keywordWeight }
            guard value > 0 else { continue }
            sum += value
            if value > (best?.value ?? 0) { best = (value, signal, close) }
        }
        let top = best?.value ?? 0
        let personal = top + otherSignals * (sum - top)
        let age = max(0, now.timeIntervalSince(article.publishedAt) / 86_400)
        let kind = article.isWritten ? writtenBonus : article.isGuide ? guideBonus : 0
        var total = personal + freshness * max(0, 1 - age / freshnessDays) + kind
        if read { total *= readKeeps }
        return Scored(score: total, reason: best?.signal, close: best?.close ?? false, personal: personal)
    }

    /// The title and one line, lowercased, every run of anything but letters
    /// and digits made one space, with a space at each end: a keyword
    /// matches at the start of a word by looking for a space before it.
    static func words(of article: Article) -> String {
        let text = "\(article.title) \(article.subtitle)".lowercased()
        var out = " "
        var lastWasSpace = true
        for character in text {
            if character.isLetter || character.isNumber {
                out.append(character)
                lastWasSpace = false
            } else if !lastWasSpace {
                out.append(" ")
                lastWasSpace = true
            }
        }
        if !lastWasSpace { out.append(" ") }
        return out
    }

    /// Whether a reading that moved may offer this piece in "For you".
    static func offersForReading(_ article: Article, close: Bool) -> Bool {
        guard close || article.isWritten, article.isWritten || article.isGuide else { return false }
        return !namesCondition(article)
    }

    /// Whether the title or the one line names a condition.
    static func namesCondition(_ article: Article) -> Bool {
        let words = words(of: article)
        return conditionWords.contains { words.contains(" " + $0) }
            || conditionWholeWords.contains { words.contains(" \($0) ") }
    }

    /// The whole page for the person.
    static func plan(articles: [Article], signals: [ExploreSignal], log: ExploreInterestLog, now: Date) -> ExplorePlan {
        let readIDs = log.readIDs
        let savedIDs = Set(log.saved.map(\.id))

        let scored = articles.map { article in
            (article: article, scored: score(article, words: words(of: article), signals: signals,
                                             read: readIDs.contains(article.id), now: now))
        }
        let order = scored.sorted { a, b in
            a.scored.score != b.scored.score ? a.scored.score > b.scored.score : a.article.id < b.article.id
        }

        // For you: the best unread, unsaved pieces some signal points at, no
        // more than two for one reason. A reading only offers a piece written
        // for readers (not a study report) that names it and names no
        // condition.
        var picks: [ExplorePick] = []
        var perReason: [String: Int] = [:]
        for entry in order where picks.count < Self.picks {
            guard let reason = entry.scored.reason, !readIDs.contains(entry.article.id),
                  !savedIDs.contains(entry.article.id),
                  reason.source != .reading || offersForReading(entry.article, close: entry.scored.close) else { continue }
            guard perReason[reason.reason, default: 0] < Self.perReason else { continue }
            perReason[reason.reason, default: 0] += 1
            picks.append(ExplorePick(article: entry.article, reason: reason.reason))
        }
        // Nothing to go on yet: the library's own pieces, newest first.
        if picks.isEmpty {
            picks = articles
                .filter { $0.isWritten && !readIDs.contains($0.id) && !savedIDs.contains($0.id) }
                .sorted { $0.publishedAt != $1.publishedAt ? $0.publishedAt > $1.publishedAt : $0.id < $1.id }
                .prefix(Self.picks)
                .map { ExplorePick(article: $0, reason: startReason) }
        }

        let byID = Dictionary(articles.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let saved = log.saved.compactMap { byID[$0.id] }

        // Shelves: topics the person leans toward first, then the rest in
        // their usual order; a shelf leaves out what "For you" shows.
        let picked = Set(picks.map(\.id))
        let lean = signals.reduce(into: [ArticleTopic: Double]()) { $0[$1.topic, default: 0] += $1.weight }
        let topics = ArticleTopic.allCases.sorted { a, b in
            let la = lean[a] ?? 0, lb = lean[b] ?? 0
            return la != lb ? la > lb : a.order < b.order
        }
        let shelves = topics.compactMap { topic -> ExploreShelf? in
            let pieces = order.lazy.map(\.article).filter { $0.topic == topic && !picked.contains($0.id) }.prefix(Self.shelfSize)
            return pieces.isEmpty ? nil : ExploreShelf(topic: topic, articles: Array(pieces))
        }

        return ExplorePlan(forYou: picks, saved: saved, shelves: shelves, ranked: order.map(\.article))
    }
}

extension Article {
    /// One of the library's own pieces, written for this app (they carry a
    /// cover photograph; the NIH pieces do not).
    var isWritten: Bool { photo != nil }

    /// A piece written for a reader to act on: NIH News in Health, as
    /// against NIH Research Matters, which reports single studies.
    var isGuide: Bool {
        sources.contains { $0.publisher == "NIH News in Health" }
    }
}

extension ArticleTopic {
    /// The topic's place in the enum, for ties.
    var order: Int { Self.allCases.firstIndex(of: self) ?? 0 }
}
