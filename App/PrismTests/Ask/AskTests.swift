//
//  AskTests.swift
//  PrismTests
//

import Foundation
import Testing
import SomaUI
@testable import Prism

/// Ask answers its own suggestions from today's numbers and nothing else.
@Suite("Ask")
struct AskTests {
    let full = AskFacts(
        variability: "44", variabilityTrend: .down,
        sleep: "6:10", sleepTrend: .down,
        resting: "58",
        move: AskMove(aspect: .mind, title: "Breathe for 10 minutes", reason: "Brings your HRV back toward usual.")
    )

    @Test("Suggestions are built from today's readings")
    func suggestionsFromToday() {
        let questions = Ask.suggestions(full).map(\.question)
        #expect(questions == ["Why is my HRV 44 ms today?", "Can tonight bring my HRV back?", "Can I train hard tomorrow?"])

        let empty = Ask.suggestions(AskFacts()).map(\.question)
        #expect(empty == ["What is my HRV saying today?", "How did last night\u{2019}s sleep do?", "Can I train hard tomorrow?"])
    }

    @Test("Each suggestion maps to its own topic, however it is typed")
    func suggestionMapsToTopic() {
        let offered = Ask.suggestions(full)
        #expect(Ask.topic(of: "Why is my HRV 44 ms today?", in: offered) == .mind)
        #expect(Ask.topic(of: "  can tonight bring my hrv back ", in: offered) == .sleep)
        #expect(Ask.topic(of: "Can I train hard tomorrow", in: offered) == .training)
        #expect(Ask.topic(of: "How did last night's sleep do?", in: Ask.suggestions(AskFacts())) == .sleep)
        #expect(Ask.topic(of: "What should I eat?", in: offered) == nil)
    }

    @Test("A matching question is answered from the numbers, with the others offered next")
    func answersFromNumbers() {
        let mind = Ask.answer(to: "Why is my HRV 44 ms today?", facts: full)
        #expect(!mind.isModelMissing)
        #expect(mind.lead == "Your HRV is 44 ms, below your usual.")
        #expect(mind.rest?.contains("Resting heart rate reads 58 bpm.") == true)
        #expect(mind.signals == 2)
        #expect(mind.sourceLine == "From Apple Health: HRV and resting heart rate.")
        #expect(mind.move?.title == "Breathe for 10 minutes")
        #expect(mind.followUps.map(\.topic) == [.sleep, .training])

        let training = Ask.answer(to: "Can I train hard tomorrow?", facts: full)
        #expect(training.lead == "I\u{2019}d keep tomorrow easy.")
        #expect(training.rest?.contains("your HRV is below your usual and last night was short") == true)
    }

    @Test("Nothing measured says what would fill it, never a number")
    func emptyStoreAnswersHonestly() {
        let answer = Ask.answer(to: "Can I train hard tomorrow?", facts: AskFacts())
        #expect(answer.lead == "I can\u{2019}t tell yet.")
        #expect(answer.signals == 0)
        #expect(answer.sourceLine == nil)
    }

    @Test("Anything else says the model is not connected")
    func otherQuestionsWaitForTheModel() {
        let answer = Ask.answer(to: "What should I eat tonight?", facts: full)
        #expect(answer.isModelMissing)
        #expect(answer.lead == "The conversation model isn\u{2019}t connected yet.")
        #expect(answer.followUps.count == 3)
    }
}
