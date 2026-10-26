//
//  ModelAskAnswering.swift
//  Prism
//

import Foundation
import HealthScoring

/// Ask's answers from the model: the conversation goes to `AskClient`, which
/// streams `ask-soma`'s reply. No session or no network falls back to the
/// phone's own answer, so the page never stalls on an error it can't fix.
struct ModelAskAnswering: AskAnswering {
    /// The person's numbers at the moment the question is asked.
    let context: @MainActor @Sendable () -> AskContext

    func stream(messages: [AskMessage], facts: AskFacts) -> AsyncThrowingStream<String, Error> {
        stream(messages: messages, facts: facts, thread: AskThread(conversation: UUID(), turn: UUID()))
    }

    func stream(messages: [AskMessage], facts: AskFacts, thread: AskThread) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { @MainActor in
                let turns = messages.map {
                    AskWireTurn(role: $0.role == .user ? .user : .assistant, content: $0.text)
                }
                do {
                    for try await piece in AskClient.shared.stream(messages: turns, context: context(),
                                                                         conversationID: thread.conversation, turnID: thread.turn) {
                        continuation.yield(piece)
                    }
                    continuation.finish()
                } catch let error as AskClientError {
                    switch error {
                    case .signedOut, .offline: continuation.finish(throwing: AskAnsweringError.offline)
                    case .rateLimited(let message):
                        // "That's 60 questions this hour": used up, so 60 of 60.
                        let total = message.split(separator: " ").compactMap { Int($0) }.first
                        continuation.finish(throwing: AskFailure.limitReached(used: total, of: total, retry: "in a little while"))
                    case .refused(let message): continuation.finish(throwing: AskFailure.refused(message))
                    case .server(let status): continuation.finish(throwing: AskFailure.server(.soma, status: status))
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
