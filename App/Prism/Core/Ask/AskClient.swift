//
//  AskClient.swift
//  Prism
//

import Foundation
import SyncCore
import SyncSupabase

/// One turn of an Ask conversation.
nonisolated struct AskWireTurn: Codable, Equatable, Sendable {
    enum Role: String, Codable, Sendable { case user, assistant }
    var role: Role
    var content: String
}

nonisolated enum AskClientError: Error, Equatable, Sendable {
    /// Nobody is signed in, or the build has no project.
    case signedOut
    /// Over the hourly allowance. The message is the function's, for the screen.
    case rateLimited(String)
    /// The request was refused (400) or the model could not answer (502).
    case refused(String)
    case offline
    case server(Int)
}

/// Ask Soma's client: sends the conversation and the person's numbers to the
/// `ask-soma` Edge Function and yields the answer as it is written.
///
/// ```swift
/// let context = AskContextBuilder.make(scores: health.scores, insights: insights, profile: profile.profile)
/// for try await piece in AskClient.shared.stream(messages: turns, context: context, conversationID: conversation, turnID: turn) {
///     answer += piece
/// }
/// ```
///
/// The model and its key live in the function, never in the app. The call
/// carries the signed in session's token, taken from the Supabase client
/// (refreshed first if it is about to expire). The function keeps both turns
/// in `ask_messages`, under the conversation and the turn the page names, the
/// same ids ``AskHistorySync`` uploads the turn with.
@MainActor
final class AskClient {
    static let shared = AskClient()

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func stream(messages: [AskWireTurn], context: AskContext, conversationID: UUID, turnID: UUID) -> AsyncThrowingStream<String, any Error> {
        let account = AccountSession.shared
        guard let services = account.services, let tokens = account.tokens, account.isSignedIn else {
            return AsyncThrowingStream { $0.finish(throwing: AskClientError.signedOut) }
        }
        let request: URLRequest
        do {
            request = try Self.request(url: services.functionURL("ask-soma"), key: services.configuration.publishableKey,
                                       messages: messages, context: context, conversationID: conversationID, turnID: turnID)
        } catch {
            return AsyncThrowingStream { $0.finish(throwing: error) }
        }
        let session = self.session
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var authorized = request
                    authorized.setValue("Bearer \(try await tokens.currentToken().value)", forHTTPHeaderField: "Authorization")
                    let (bytes, response) = try await session.bytes(for: authorized)
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    guard status == 200 else {
                        var body = Data()
                        for try await byte in bytes { body.append(byte) }
                        throw Self.failure(status: status, body: body)
                    }
                    for try await line in bytes.lines {
                        switch Self.event(line) {
                        case .delta(let text): continuation.yield(text)
                        case .done: continuation.finish(); return
                        case .error(let message): throw AskClientError.refused(message)
                        case .none: continue
                        }
                    }
                    continuation.finish()
                } catch let error as URLError {
                    continuation.finish(throwing: Self.map(error))
                } catch let error as AuthError {
                    continuation.finish(throwing: error == .unavailable ? AskClientError.offline : AskClientError.signedOut)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: Wire format

    nonisolated static func request(url: URL, key: String, messages: [AskWireTurn], context: AskContext, conversationID: UUID, turnID: UUID = UUID()) throws -> URLRequest {
        struct Body: Encodable {
            var messages: [AskWireTurn]
            var context: AskContext
            var conversation_id: String
            var turn_id: String
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue(key, forHTTPHeaderField: "apikey")
        request.httpBody = try JSONEncoder().encode(Body(messages: messages, context: context, conversation_id: conversationID.uuidString.lowercased(), turn_id: turnID.uuidString.lowercased()))
        return request
    }

    nonisolated enum Event: Equatable {
        case delta(String)
        case done
        case error(String)
    }

    /// One server-sent event line, or nil for anything else (blank lines, comments).
    nonisolated static func event(_ line: String) -> Event? {
        guard line.hasPrefix("data:") else { return nil }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        guard let data = payload.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let delta = object["delta"] as? String { return .delta(delta) }
        if object["done"] as? Bool == true { return .done }
        if let error = object["error"] as? String { return .error(error) }
        return nil
    }

    nonisolated static func failure(status: Int, body: Data) -> AskClientError {
        let message = (try? JSONSerialization.jsonObject(with: body) as? [String: Any])?["error"] as? String ?? ""
        switch status {
        case 401: return .signedOut
        case 429: return .rateLimited(message)
        case 400, 502: return .refused(message)
        default: return .server(status)
        }
    }

    nonisolated static func map(_ error: URLError) -> AskClientError {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed, .timedOut:
            return .offline
        default:
            return .server(0)
        }
    }
}
