//
//  ExploreRankingTests.swift
//  PrismTests
//

import Foundation
import Testing
@testable import Prism

@Suite("Explore ranking")
struct ExploreRankingTests {
    private let now = Date(timeIntervalSince1970: 1_792_000_000)

    private func article(_ id: String, _ topic: ArticleTopic, title: String = "A piece", subtitle: String = "",
                         daysOld: Double = 30, written: Bool = false, guide: Bool = true) -> Article {
        Article(id: id, slug: id, title: title, subtitle: subtitle, topic: topic, minutes: 3, coverImageURL: nil,
                body: "", publishedAt: now.addingTimeInterval(-daysOld * 86_400),
                sources: guide ? [ArticleCitation(title: "Original article", publisher: "NIH News in Health", url: nil)] : [],
                photo: written ? ArticlePhoto(asset: "Articles/\(id)", credit: "Someone", url: nil, library: "Unsplash") : nil)
    }

    private func insight(_ position: Insight.Position, severity: Double = 0.5, age: Int = 0) -> Insight {
        var insight = Insight.empty(.higher)
        insight.current = 1
        insight.currentAge = age
        insight.position = position
        insight.severity = severity
        return insight
    }

    private var library: [Article] {
        [
            article("sleep-short", .sleep, title: "When sleep runs short"),
            article("sleep-dreams", .sleep, title: "What dreams are for"),
            article("heart-rest", .heart, title: "Your resting heart rate"),
            article("heart-valves", .heart, title: "How valves work"),
            article("heart-pulse", .heart, title: "Your pulse after a climb"),
            article("gut-fibre", .nutrition, title: "Fibre and the gut"),
            article("move-walk", .movement, title: "Walking for health"),
            article("mind-calm", .mind, title: "Calm in a busy week"),
            article("night-shift", .recovery, title: "Night shifts and your body clock", subtitle: "Sleep at odd hours"),
        ]
    }

    // MARK: Signals

    @Test("A reading outside its usual becomes a signal with plain words; one within, or old, does not")
    func readingsBecomeSignals() {
        let signals = ExploreSignals.fromReadings([
            .sleepDuration: insight(.below),
            .restingHeartRate: insight(.above),
            .steps: insight(.within),
            .heartRateVariability: insight(.below, age: 12),
        ])
        #expect(signals.map(\.reason) == ["Because your resting heart rate is up", "Because your sleep was short this week"])
        #expect(signals.map(\.topic) == [.heart, .sleep])
        #expect(signals.allSatisfy { $0.source == .reading && (0.6...1).contains($0.weight) })
    }

    @Test("A reading's reason never names a condition")
    func readingWordsStayWellness() {
        let every = InsightMetric.allCases.flatMap { metric in
            ExploreSignals.fromReadings([metric: insight(.above)]) + ExploreSignals.fromReadings([metric: insight(.below)])
        }
        #expect(!every.isEmpty)
        for signal in every {
            #expect(signal.reason.hasPrefix("Because "))
            for word in ["disease", "diagnos", "risk", "fever", "diabetes", "hypertension", "sick"] {
                #expect(!signal.reason.lowercased().contains(word), "\(signal.reason)")
            }
        }
    }

    @Test("Habits count: pages opened twice in a month, pieces read twice, anything saved")
    func habitsBecomeSignals() {
        var log = ExploreInterestLog()
        log.visit(.sleep, at: now.addingTimeInterval(-3 * 86_400))
        log.visit(.sleep, at: now.addingTimeInterval(-1 * 86_400))
        log.visit(.heart, at: now.addingTimeInterval(-1 * 86_400))
        log.visit(.mind, at: now.addingTimeInterval(-50 * 86_400))
        log.visit(.mind, at: now.addingTimeInterval(-45 * 86_400))
        log.read(id: "a", topic: .movement, at: now.addingTimeInterval(-2 * 86_400))
        log.read(id: "b", topic: .movement, at: now.addingTimeInterval(-1 * 86_400))
        log.toggleSaved(id: "c", topic: .nutrition, at: now)

        let signals = ExploreSignals.fromHabits(log, now: now)
        #expect(Set(signals.map(\.reason)) == [
            "Because you check your sleep often",
            "Because you've been reading about movement",
            "Because you saved a piece on nutrition",
        ])
    }

    @Test("Opening the same page again within the hour is one visit")
    func visitsAreThrottled() {
        var log = ExploreInterestLog()
        log.visit(.sleep, at: now)
        log.visit(.sleep, at: now.addingTimeInterval(600))
        log.visit(.heart, at: now.addingTimeInterval(700))
        log.visit(.sleep, at: now.addingTimeInterval(3_700))
        #expect(log.visits.map(\.topic) == [.sleep, .heart, .sleep])
    }

    // MARK: The plan

    @Test("Short sleep leads For you with the sleep pieces, the one that names sleep first, with its reason")
    func shortSleepLeads() {
        let signals = ExploreSignals.make(readings: [.sleepDuration: insight(.below, severity: 0.8)],
                                          log: ExploreInterestLog(), now: now)
        let plan = ExploreRanking.plan(articles: library, signals: signals, log: ExploreInterestLog(), now: now)

        #expect(plan.forYou.first?.article.id == "sleep-short")
        #expect(plan.forYou.first?.reason == "Because your sleep was short this week")
        // One reason fills two picks at most.
        #expect(plan.forYou.filter { $0.reason == "Because your sleep was short this week" }.count == 2)
        // A piece on another topic that names sleep still counts as close.
        #expect(plan.forYou.map(\.article.id).contains("night-shift"))
        // The sleep shelf comes first.
        #expect(plan.shelves.first?.topic == .sleep)
    }

    @Test("A reading offers only pieces that name it; one merely filed under the topic waits on its shelf")
    func readingsNeedWords() {
        let signals = ExploreSignals.make(readings: [.sleepDuration: insight(.below)], log: ExploreInterestLog(), now: now)
        let plan = ExploreRanking.plan(articles: library, signals: signals, log: ExploreInterestLog(), now: now)
        #expect(!plan.forYou.map(\.id).contains("sleep-dreams"))
        #expect(plan.shelves.first { $0.topic == .sleep }?.articles.map(\.id) == ["sleep-dreams"])
    }

    @Test("The library's own piece leads; a study report never answers a reading")
    func writtenLeads() {
        let articles = [article("study", .recovery, title: "HRV in a large study", daysOld: 2, guide: false),
                        article("practical", .recovery, title: "Stress and your HRV", daysOld: 2),
                        article("written", .recovery, title: "What your HRV is telling you", daysOld: 200, written: true, guide: false)]
        let signals = ExploreSignals.make(readings: [.heartRateVariability: insight(.below)], log: ExploreInterestLog(), now: now)
        let plan = ExploreRanking.plan(articles: articles, signals: signals, log: ExploreInterestLog(), now: now)
        #expect(plan.forYou.map(\.id) == ["written", "practical"])
        #expect(plan.forYou.first?.reason == "Because your HRV dipped this week")
    }

    @Test("A reading never pairs with a piece that names a condition")
    func noConditionsForReadings() {
        let articles = [article("attack", .heart, title: "Heart attack signs"),
                        article("calm", .heart, title: "Your heart at rest")]
        let signals = ExploreSignals.make(readings: [.restingHeartRate: insight(.above)], log: ExploreInterestLog(), now: now)
        let plan = ExploreRanking.plan(articles: articles, signals: signals, log: ExploreInterestLog(), now: now)
        #expect(plan.forYou.map(\.id) == ["calm"])
        #expect(plan.shelves.first?.articles.map(\.id) == ["attack"])
    }

    @Test("A condition never reaches For you from a reading, through its keywords or its title")
    func conditionWordsStayOut() {
        // No reading's keywords name a condition.
        let every = InsightMetric.allCases.flatMap { metric in
            ExploreSignals.fromReadings([metric: insight(.above)]) + ExploreSignals.fromReadings([metric: insight(.below)])
        }
        for signal in every {
            for keyword in signal.keywords {
                let probe = article("probe", signal.topic, title: keyword)
                #expect(!ExploreRanking.namesCondition(probe), "\(keyword)")
            }
        }

        let articles = [article("managing", .heart, title: "Managing hypertension", subtitle: "Salt and your blood pressure"),
                        article("salt", .heart, title: "Less salt, steadier blood pressure"),
                        article("falls", .movement, title: "Preventing falls", subtitle: "Balance as you walk"),
                        article("fever", .recovery, title: "When a fever comes", subtitle: "Your temperature at night"),
                        article("flu", .recovery, title: "Flu season", subtitle: "Cold weather and your immune system"),
                        article("fluids", .recovery, title: "Fluids when it's warm", subtitle: "Your temperature and water")]
        let signals = ExploreSignals.make(readings: [.bloodPressure: insight(.above), .walkingSpeed: insight(.below),
                                                     .wristTemperature: insight(.above)],
                                          log: ExploreInterestLog(), now: now)
        let plan = ExploreRanking.plan(articles: articles, signals: signals, log: ExploreInterestLog(), now: now)
        let picked = plan.forYou.map(\.id)
        #expect(!picked.contains("managing"))
        #expect(!picked.contains("falls"))
        #expect(!picked.contains("fever"))
        #expect(!picked.contains("flu"))
        #expect(picked.contains("salt"))
        // "Flu" is matched whole: a piece on fluids still answers.
        #expect(picked.contains("fluids"))
        // The held pieces stay on their shelf.
        #expect(plan.shelves.flatMap(\.articles).map(\.id).contains("managing"))
    }

    @Test("A piece that answers one signal well beats one that touches several a little")
    func oneSignalWell() {
        let articles = [article("both", .heart, title: "Breath and calm"),
                        article("exact", .sleep, title: "Sleep when nights run short")]
        let signals = ExploreSignals.make(readings: [.sleepDuration: insight(.below), .heartRateVariability: insight(.below),
                                                     .restingHeartRate: insight(.above)],
                                          log: ExploreInterestLog(), now: now)
        let plan = ExploreRanking.plan(articles: articles, signals: signals, log: ExploreInterestLog(), now: now)
        #expect(plan.ranked.first?.id == "exact")
    }

    @Test("Two signals share For you, and a shelf leaves out what For you shows")
    func signalsShare() {
        let signals = ExploreSignals.make(readings: [.sleepDuration: insight(.below), .restingHeartRate: insight(.above)],
                                          log: ExploreInterestLog(), now: now)
        let plan = ExploreRanking.plan(articles: library, signals: signals, log: ExploreInterestLog(), now: now)

        #expect(plan.forYou.count == ExploreRanking.picks)
        #expect(Set(plan.forYou.map(\.reason)) == ["Because your sleep was short this week", "Because your resting heart rate is up"])
        let picked = Set(plan.forYou.map(\.id))
        #expect(plan.shelves.allSatisfy { shelf in shelf.articles.allSatisfy { !picked.contains($0.id) } })
    }

    @Test("Read pieces leave For you and sink on their shelf; saved ones get their own row")
    func readAndSaved() throws {
        var log = ExploreInterestLog()
        log.read(id: "sleep-short", topic: .sleep, at: now)
        log.toggleSaved(id: "heart-valves", topic: .heart, at: now)
        let signals = ExploreSignals.make(readings: [.sleepDuration: insight(.below)], log: log, now: now)
        let plan = ExploreRanking.plan(articles: library, signals: signals, log: log, now: now)

        #expect(!plan.forYou.map(\.id).contains("sleep-short"))
        #expect(!plan.forYou.map(\.id).contains("heart-valves"))
        #expect(plan.saved.map(\.id) == ["heart-valves"])
        // Read, the closest match sinks below a sleep piece that only shares its topic.
        let order = plan.ranked.map(\.id)
        #expect(try #require(order.firstIndex(of: "sleep-dreams")) < (try #require(order.firstIndex(of: "sleep-short"))))
    }

    @Test("With nothing to go on, For you offers the library's own pieces, newest first")
    func startHere() {
        let articles = library + [article("written-old", .mind, daysOld: 90, written: true),
                                  article("written-new", .sleep, daysOld: 5, written: true)]
        let plan = ExploreRanking.plan(articles: articles, signals: [], log: ExploreInterestLog(), now: now)
        #expect(plan.forYou.map(\.id) == ["written-new", "written-old"])
        #expect(plan.forYou.allSatisfy { $0.reason == ExploreRanking.startReason })
        #expect(plan.shelves.map(\.topic) == ArticleTopic.allCases.filter { topic in articles.contains { $0.topic == topic } })
    }

    @Test("The same inputs give the same page, whatever order the library comes in")
    func deterministic() {
        let signals = ExploreSignals.make(readings: [.steps: insight(.below)], log: ExploreInterestLog(), now: now)
        let one = ExploreRanking.plan(articles: library, signals: signals, log: ExploreInterestLog(), now: now)
        let two = ExploreRanking.plan(articles: library.reversed(), signals: signals, log: ExploreInterestLog(), now: now)
        #expect(one == two)
        #expect(one.forYou.first?.article.id == "move-walk")
        #expect(one.forYou.first?.reason == "Because you walked less this week")
    }

    @Test("Keywords match at the start of a word only")
    func keywordsMatchWords() {
        let words = ExploreRanking.words(of: article("x", .mind, title: "Restoring sleep-wake rhythm", subtitle: "Interest, rest"))
        #expect(words == " restoring sleep wake rhythm interest rest ")
        #expect(words.contains(" sleep"))
        #expect(!words.contains(" store"))
    }

    // MARK: The store

    @Test("The interest log survives a relaunch, and a save toggles")
    @MainActor
    func storeRoundTrip() throws {
        let suite = "explore.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let piece = article("heart-rest", .heart)
        let first = ExploreInterest(defaults: defaults)
        first.noteVisit(.sleep, at: now)
        first.noteRead(piece, at: now)
        first.toggleSaved(piece, at: now)
        #expect(first.isSaved(piece))

        let again = ExploreInterest(defaults: defaults)
        #expect(again.log == first.log)
        again.toggleSaved(piece, at: now)
        #expect(!again.isSaved(piece))
    }
}
