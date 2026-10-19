//
//  SomaPreviewSamples+Questions.swift
//  SomaUIPreviewSupport
//

import SwiftUI
import SomaUI

/// A morning's run of questions for the gallery and the previews: Sam
/// Rivera after a short night, one question of each kind.
public extension SomaPreviewSamples {
    enum QuestionKind: Sendable, Equatable {
        case yesNo
        case scale(low: String, high: String, tone: SomaScaleTone)
        case count(range: ClosedRange<Int>, start: Int, unit: String?)
    }

    struct Question: Identifiable, Sendable {
        public let id: String
        public let text: String
        public let kind: QuestionKind
        public let aspect: SomaAspect
    }

    static let questions: [Question] = [
        Question(id: "sleep", text: "Slept 50 min less than usual. Feeling it?", kind: .yesNo, aspect: .sleep),
        Question(id: "rested", text: "How rested do you feel?", kind: .scale(low: "Exhausted", high: "Fully rested", tone: .rising), aspect: .sleep),
        Question(id: "stress", text: "How stressed was today?", kind: .scale(low: "Calm", high: "Very", tone: .falling), aspect: .mind),
        Question(id: "drinks", text: "How many glasses of water so far?", kind: .count(range: 0...12, start: 4, unit: nil), aspect: .gut),
        Question(id: "alcohol", text: "Did you drink alcohol yesterday?", kind: .yesNo, aspect: .heart),
    ]

    static let questionYes = "Yes"
    static let questionNo = "No"
    static let questionSkip = "Skip"
    static let questionLater = "Later"
    static let questionDone = "Done for today"
    static let questionClose = "Close"
    static let questionNext = "Next"
    static let questionLess = "Less"
    static let questionMore = "More"

    static func questionProgress(_ index: Int, of count: Int) -> String {
        "\(min(index + 1, count)) of \(count)"
    }
}
