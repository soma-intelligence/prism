//
//  AskAnswering.swift
//  Prism
//

import Foundation

/// One message of a conversation, as a model reads it.
struct AskMessage: Equatable, Sendable {
    enum Role: String, Sendable {
        case user
        case assistant
    }

    var role: Role
    var text: String
}

/// Why an answer did not come.
enum AskAnsweringError: Error, Equatable {
    /// No session or no network: the page answers from the phone instead.
    case offline
}

/// Whatever writes Soma's side of a turn, a piece at a time.
///
/// The page reads the stream, grows the reply as pieces land, and stops it by
/// cancelling the task that reads it. A stream that fails with
/// ``AskAnsweringError/offline`` before its first piece hands the turn to the
/// answers ``Ask`` builds from today's numbers on the phone; any other failure
/// is shown under the question with a way to try again.
///
/// The model client plugs in here: an adapter whose `stream` calls the
/// client's `stream(messages:context:)` and maps its no session and no network
/// errors to ``AskAnsweringError/offline``, then passed as `AskPage`'s
/// `answering`.
protocol AskAnswering: Sendable {
    func stream(messages: [AskMessage], facts: AskFacts) -> AsyncThrowingStream<String, Error>
    /// The same, naming the conversation and the turn, so whatever stores
    /// the answer files it where the page's history files it.
    func stream(messages: [AskMessage], facts: AskFacts, thread: AskThread) -> AsyncThrowingStream<String, Error>
}

/// Which conversation a question belongs to, and which turn it is.
struct AskThread: Equatable, Sendable {
    var conversation: UUID
    var turn: UUID
}

extension AskAnswering {
    /// An answerer that stores nothing has no use for the ids.
    func stream(messages: [AskMessage], facts: AskFacts, thread: AskThread) -> AsyncThrowingStream<String, Error> {
        stream(messages: messages, facts: facts)
    }
}

/// A provider that cannot answer yet (a key or an address missing): fails at
/// once with what to fix.
struct FailingAskAnswering: AskAnswering {
    let failure: AskFailure

    func stream(messages: [AskMessage], facts: AskFacts) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { $0.finish(throwing: failure) }
    }
}

/// The default until the model is connected: it reports offline at once, so
/// every question gets the answer the phone can give, with its move and its
/// follow ups.
struct CannedAskAnswering: AskAnswering {
    func stream(messages: [AskMessage], facts: AskFacts) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { $0.finish(throwing: AskAnsweringError.offline) }
    }
}

extension AskAnswer {
    /// A reply the model wrote: plain text, with today's questions left to ask.
    static func streamed(_ text: String, followUps: [AskSuggestion]) -> AskAnswer {
        AskAnswer(lead: text, rest: nil, signals: 0, sources: [], move: nil, followUps: followUps, isModelMissing: false)
    }

    /// The text a model reads back as Soma's earlier turn.
    var plainText: String {
        [lead, rest].compactMap { $0 }.joined(separator: " ")
    }
}
