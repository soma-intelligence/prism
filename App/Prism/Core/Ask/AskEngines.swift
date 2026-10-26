//
//  AskEngines.swift
//  Prism
//

import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// The instructions every model gets: who Soma is, how it answers, and the
/// person's numbers. Kept short: the on-device model reads about four
/// thousand tokens in all, the conversation included.
nonisolated enum AskInstructions {
    static func make(_ context: AskContext) -> String {
        let numbers = (try? String(data: JSONEncoder().encode(context), encoding: .utf8)) ?? "{}"
        return """
        You are Soma, a calm health companion. Answer in two or three short sentences, \
        plain words, numbers from the data below when they help, one concrete thing to do \
        when it fits. Never diagnose; for anything that worries the person, suggest a \
        doctor. If the data does not say, say so. Answer in the language of the question.
        The person's data today, as JSON: \(numbers)
        """
    }
}

// MARK: - Apple Intelligence

/// Whether the on-device model can answer, and in words why not.
@MainActor
enum AppleIntelligence {
    enum Availability: Equatable {
        case available
        case deviceNotEligible
        case off
        case notReady
        case unknown

        /// What stands in the way, or nil when it is available.
        var reason: String? {
            switch self {
            case .available: nil
            case .deviceNotEligible: "This device can\u{2019}t run Apple Intelligence"
            case .off: "Turn on Apple Intelligence in Settings"
            case .notReady: "Apple Intelligence is still downloading"
            case .unknown: "Apple Intelligence isn\u{2019}t available right now"
            }
        }

        var failure: AskFailure {
            switch self {
            case .available, .unknown: .modelNotReady()
            case .deviceNotEligible: .deviceNotEligible()
            case .off: .intelligenceOff()
            case .notReady: .modelNotReady()
            }
        }
    }

    static var availability: Availability {
        #if canImport(FoundationModels)
        switch SystemLanguageModel.default.availability {
        case .available: return .available
        case .unavailable(.deviceNotEligible): return .deviceNotEligible
        case .unavailable(.appleIntelligenceNotEnabled): return .off
        case .unavailable(.modelNotReady): return .notReady
        default: return .unknown
        }
        #else
        return .deviceNotEligible
        #endif
    }
}

/// Answers on the phone with Apple's own model: no network, no account, no
/// cost, and the first words in well under a second on a recent iPhone. Each
/// question opens a session primed with the instructions and the earlier
/// turns; the stream yields only what is new in each snapshot, so the page
/// grows the reply the same way it does for a server.
struct AppleIntelligenceAnswering: AskAnswering {
    let context: @MainActor @Sendable () -> AskContext

    func stream(messages: [AskMessage], facts: AskFacts) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { @MainActor in
                #if canImport(FoundationModels)
                let availability = AppleIntelligence.availability
                guard availability == .available else {
                    continuation.finish(throwing: availability.failure)
                    return
                }
                let earlier = messages.dropLast().map { "\($0.role == .user ? "Person" : "Soma"): \($0.text)" }
                    .suffix(6).joined(separator: "\n")
                let instructions = AskInstructions.make(context())
                    + (earlier.isEmpty ? "" : "\nThe conversation so far:\n\(earlier)")
                let session = LanguageModelSession(instructions: instructions)
                let question = messages.last?.text ?? ""
                do {
                    var sent = ""
                    for try await snapshot in session.streamResponse(to: question) {
                        let text = snapshot.content
                        if text.hasPrefix(sent) {
                            let piece = String(text.dropFirst(sent.count))
                            if !piece.isEmpty { continuation.yield(piece) }
                        } else {
                            continuation.yield(text)
                        }
                        sent = text
                    }
                    continuation.finish()
                } catch let error as LanguageModelSession.GenerationError {
                    switch error {
                    case .exceededContextWindowSize: continuation.finish(throwing: AskFailure.tooLong())
                    case .guardrailViolation, .refusal: continuation.finish(throwing: AskFailure.refused(nil))
                    case .assetsUnavailable: continuation.finish(throwing: AskFailure.modelNotReady())
                    case .rateLimited: continuation.finish(throwing: AskFailure.limitReached(used: nil, of: nil, retry: "in a moment"))
                    default: continuation.finish(throwing: AskFailure.server(.appleIntelligence, status: 0))
                    }
                } catch {
                    continuation.finish(throwing: Task.isCancelled ? CancellationError() : AskFailure.server(.appleIntelligence, status: 0))
                }
                #else
                continuation.finish(throwing: AskFailure.deviceNotEligible())
                #endif
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

// MARK: - The person's own accounts

/// Answers with the person's own key, streamed over server-sent events:
/// the OpenAI chat completions protocol for OpenAI, OpenRouter, Azure and any
/// compatible server, and Anthropic's messages protocol for Claude.
struct RemoteAskAnswering: AskAnswering {
    let provider: AskProvider
    let key: String
    let model: String
    let endpoint: String
    let context: @MainActor @Sendable () -> AskContext
    var session: URLSession = .shared

    func stream(messages: [AskMessage], facts: AskFacts) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { @MainActor in
                let request: URLRequest
                do {
                    request = try makeRequest(messages: messages, instructions: AskInstructions.make(context()))
                } catch {
                    continuation.finish(throwing: error)
                    return
                }
                do {
                    let (bytes, response) = try await session.bytes(for: request)
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    guard (200..<300).contains(status) else {
                        var body = Data()
                        for try await byte in bytes { body.append(byte); if body.count > 4_096 { break } }
                        continuation.finish(throwing: Self.failure(provider, model: model, status: status, body: body,
                                                                   retry: (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Retry-After")))
                        return
                    }
                    for try await line in bytes.lines {
                        if let piece = Self.piece(line, anthropic: provider == .anthropic) { continuation.yield(piece) }
                    }
                    continuation.finish()
                } catch let error as URLError {
                    continuation.finish(throwing: error.code == .cancelled ? CancellationError() : AskFailure.offline())
                } catch {
                    continuation.finish(throwing: Task.isCancelled ? CancellationError() : AskFailure.server(provider, status: 0))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func makeRequest(messages: [AskMessage], instructions: String) throws -> URLRequest {
        let turns = messages.map { ["role": $0.role == .user ? "user" : "assistant", "content": $0.text] }
        let url: URL?
        var request: URLRequest
        var body: [String: Any]
        switch provider {
        case .anthropic:
            url = URL(string: "https://api.anthropic.com/v1/messages")
            body = ["model": model, "max_tokens": 700, "stream": true, "system": instructions, "messages": turns]
        case .azure:
            let base = endpoint.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
            url = URL(string: "\(base)/openai/deployments/\(model)/chat/completions?api-version=2025-04-01-preview")
            body = ["stream": true, "messages": [["role": "system", "content": instructions]] + turns]
        default:
            let base = switch provider {
            case .openAI: "https://api.openai.com/v1"
            case .openRouter: "https://openrouter.ai/api/v1"
            default: endpoint.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
            }
            url = URL(string: "\(base)/chat/completions")
            body = ["model": model, "stream": true, "messages": [["role": "system", "content": instructions]] + turns]
        }
        guard let url, url.scheme == "https" || url.host == "localhost" else {
            throw AskFailure(kind: .badModel, title: "The server address isn\u{2019}t valid",
                             detail: "Check it in Ask\u{2019}s settings. It must start with https://", opensSettings: true)
        }
        request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        switch provider {
        case .anthropic:
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        case .azure:
            request.setValue(key, forHTTPHeaderField: "api-key")
        default:
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            if provider == .openRouter {
                request.setValue("https://www.somalabs.me", forHTTPHeaderField: "HTTP-Referer")
                request.setValue("Soma", forHTTPHeaderField: "X-Title")
            }
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// The text in one server-sent event line, or nil.
    nonisolated static func piece(_ line: String, anthropic: Bool) -> String? {
        guard line.hasPrefix("data:") else { return nil }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        guard payload != "[DONE]", let data = payload.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if anthropic {
            guard object["type"] as? String == "content_block_delta",
                  let delta = object["delta"] as? [String: Any] else { return nil }
            return delta["text"] as? String
        }
        guard let choices = object["choices"] as? [[String: Any]], let delta = choices.first?["delta"] as? [String: Any] else { return nil }
        return delta["content"] as? String
    }

    /// The person's words for an HTTP error from a provider.
    nonisolated static func failure(_ provider: AskProvider, model: String, status: Int, body: Data, retry: String?) -> AskFailure {
        let raw = String(data: body, encoding: .utf8)?.lowercased() ?? ""
        switch status {
        case 401, 403: return .badKey(provider)
        case 404: return .badModel(provider, model)
        case 400 where raw.contains("model"): return .badModel(provider, model)
        case 400 where raw.contains("context") || raw.contains("too long") || raw.contains("maximum"): return .tooLong()
        case 402: return .badKey(provider)
        case 429: return .limitReached(used: nil, of: nil, retry: AskRetry.phrase(retry))
        default: return .server(provider, status: status)
        }
    }
}

/// "in 10 minutes" from a Retry-After header in seconds.
nonisolated enum AskRetry {
    static func phrase(_ header: String?) -> String? {
        guard let header, let seconds = Double(header.trimmingCharacters(in: .whitespaces)), seconds.isFinite, seconds > 0 else { return nil }
        let minutes = Int((seconds / 60).rounded(.up))
        return minutes <= 1 ? "in a minute" : "in \(minutes) minutes"
    }
}
