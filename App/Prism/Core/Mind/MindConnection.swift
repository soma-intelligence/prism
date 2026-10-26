//
//  MindConnection.swift
//  Prism
//
//  Connection: how lonely a person feels (the three item UCLA loneliness
//  scale), whether life feels like it has a direction (one item on
//  purpose), and the week's time with people, read from what the phone
//  already holds: the calendar's social events, the moods logged with
//  friends, family or a partner, and the Journal's social tags. Plain
//  values, tested without a store or a view.
//

import Foundation

/// The three item UCLA loneliness scale: Hughes, Waite, Hawkley and
/// Cacioppo, "A Short Scale for Measuring Loneliness in Large Surveys",
/// Research on Aging 2004. Each answer counts 1 to 3, so a total runs 3 to
/// 9; 6 and over is the usual cut for lonely (Steptoe, Shankar, Demakakos
/// and Wardle, PNAS 2013).
nonisolated enum LonelinessScore {
    /// The paper's introduction, with "tell me" turned to "choose" for a
    /// screen rather than an interviewer.
    static let stem = "The next questions are about how you feel about different aspects of your life. For each one, choose how often you feel that way."

    /// The three items, word for word.
    static let items = [
        "How often do you feel that you lack companionship?",
        "How often do you feel left out?",
        "How often do you feel isolated from others?",
    ]

    static let options = ["Hardly ever", "Some of the time", "Often"]

    /// Three answers at "Hardly ever".
    static let minimum = 3
    /// At or over this total the answers read as lonely.
    static let lonely = 6

    /// The total of three answers given as option indexes, 0 to 2. Nil
    /// unless all three are there and on the scale.
    static func score(answers: [Int]) -> Int? {
        MindInstrument.ucla3.score(answers)
    }

    static func isLonely(_ score: Int) -> Bool { score >= lonely }

    static func reading(_ score: Int) -> MindAssessmentReading {
        isLonely(score)
            ? MindAssessmentReading(
                value: "\(score)", unit: "of 9", word: "Often lonely",
                detail: "Many people feel this way at times. Reaching out to one person this week can help, and if it weighs on you, a doctor or a therapist can too."
            )
            : MindAssessmentReading(
                value: "\(score)", unit: "of 9", word: "Rarely lonely",
                detail: "By these three questions you rarely feel left out or alone."
            )
    }
}

/// One item on purpose in life, from Ryff's Psychological Well-Being
/// scales (Ryff, J Pers Soc Psychol 1989), on the scales' six steps of
/// agreement. Read as a word, never added to anything.
nonisolated enum MindPurpose {
    static let stem = "How much do you agree with this statement?"
    static let item = "I have a sense of direction and purpose in life."
    static let options = [
        "Strongly disagree", "Moderately disagree", "Slightly disagree",
        "Slightly agree", "Moderately agree", "Strongly agree",
    ]

    /// - Parameter score: 1 to 6, the answer's step.
    static func reading(_ score: Int) -> MindAssessmentReading {
        let word = options[min(max(score - 1, 0), options.count - 1)]
        // A stronger sense of purpose goes with lower mortality (Alimujiang
        // and colleagues, JAMA Network Open 2019).
        let detail = score >= 4
            ? "A sense of purpose tends to go with better health over the years."
            : "Purpose can come back in small ways: a project, helping someone, time on what matters to you."
        return MindAssessmentReading(value: "\(score)", unit: "of 6", word: word, detail: detail)
    }
}

/// The Journal tags that mean time with people. The first three are offered
/// to tap; ``timeWithPeople`` is what the evening question writes.
nonisolated enum SocialTag {
    static let sawFriends = "saw-friends"
    static let calledFamily = "called-family"
    static let volunteered = "volunteered"
    /// Written by the evening question, "Time with people you care about today?".
    static let timeWithPeople = "time-with-people"

    static let all = [sawFriends, calledFamily, volunteered, timeWithPeople]
}

/// The last monthly connection check.
nonisolated enum MindConnectionCheck {
    /// Loneliness, then purpose: the check the monthly reminder asks for.
    static let instruments: [MindInstrument] = [.ucla3, .purpose]

    @MainActor
    static func lastDate(in store: MindStore) -> Date? {
        store.latest(.ucla3)?.date
    }
}

/// The last seven days with people, from what the phone already holds. A
/// count the phone cannot know is nil, shown as a dash: the calendar's
/// minutes without access to the calendar.
nonisolated struct ConnectionWeek: Equatable, Sendable {
    /// Minutes of calendar events read as social. Nil without the calendar.
    var socialMinutes: Double?
    /// Feelings logged with friends, family or a partner named.
    var moodsWithPeople: Int
    /// Days with at least one social tag in the Journal.
    var taggedDays: Int

    /// The ``MindAssociation`` ids that are people.
    static let peopleAssociations: Set<String> = ["friends", "family", "partner"]
    static let days = 7

    var hasPeople: Bool {
        (socialMinutes ?? 0) > 0 || moodsWithPeople > 0 || taggedDays > 0
    }

    /// - Parameters:
    ///   - journal: each day's start to the tags tapped on it.
    ///   - category: how an event reads, the person's corrections first
    ///     (``MindStore/category(of:)``).
    static func make(
        moods: [MindMoodEntry],
        events: [MindCalendarEvent],
        calendarAllowed: Bool,
        journal: [Date: Set<String>],
        now: Date,
        calendar: Calendar,
        category: (MindCalendarEvent) -> MindEventCategory
    ) -> ConnectionWeek {
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -(days - 1), to: today) ?? today
        let inWeek: (Date) -> Bool = { $0 >= start && $0 <= now }

        let minutes = events
            .filter { inWeek($0.start) && category($0) == .social }
            .reduce(0) { $0 + max($1.minutes, 0) }
        let moodCount = moods.filter { inWeek($0.date) && !peopleAssociations.isDisjoint(with: $0.associations) }.count
        let tags = Set(SocialTag.all)
        let tagged = journal.filter { inWeek($0.key) && !tags.isDisjoint(with: $0.value) }.count

        return ConnectionWeek(
            socialMinutes: calendarAllowed ? minutes : nil,
            moodsWithPeople: moodCount,
            taggedDays: tagged
        )
    }

    /// The one thing the page proposes for the week ahead.
    func suggestion(lonely: Bool) -> (title: String, detail: String) {
        if lonely || !hasPeople {
            return ("Reach out to one person",
                    "A call, a message or a coffee with someone you like. Short counts.")
        }
        return ("Plan the next one",
                "You spent time with people this week. Putting the next one in the calendar makes it happen.")
    }
}
