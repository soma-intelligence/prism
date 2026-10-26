//
//  OpenHealthSync.swift
//  Prism
//

import Foundation
import SyncCore
import SyncSupabase

/// One provider's connection as Open Health Sync reports it.
nonisolated struct OHSConnection: Decodable, Equatable, Sendable {
    nonisolated enum Status: String, Decodable, Sendable {
        case active
        case needsReauth = "needs_reauth"
        case disconnected
    }

    var provider: String
    var status: Status
    var lastSyncAt: Date?

    private enum CodingKeys: String, CodingKey {
        case provider, status
        case lastSyncAt = "last_sync_at"
    }

    init(provider: String, status: Status, lastSyncAt: Date?) {
        self.provider = provider
        self.status = status
        self.lastSyncAt = lastSyncAt
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        provider = try container.decode(String.self, forKey: .provider)
        status = (try? container.decode(Status.self, forKey: .status)) ?? .disconnected
        lastSyncAt = try container.decodeIfPresent(String.self, forKey: .lastSyncAt).flatMap(OHSClient.date)
    }
}

/// One local day as Open Health Sync merges it across the connected sources.
/// A figure no source had is nil, and renders as a dash.
nonisolated struct OHSDailySummary: Decodable, Equatable, Sendable {
    /// The person's local calendar day, `YYYY-MM-DD`.
    var date: String
    var readinessScore: Double?
    var sleepScore: Double?
    var activityScore: Double?
    var recoveryScore: Double?
    var strainScore: Double?
    var stepCount: Int?
    var activeKcal: Double?
    var distanceM: Double?
    var restingHR: Double?
    var hrvAvgMS: Double?
    /// Which source each figure came from, keyed by the figure's name.
    var sources: [String: String]?

    private enum CodingKeys: String, CodingKey {
        case date, sources
        case readinessScore = "readiness_score"
        case sleepScore = "sleep_score"
        case activityScore = "activity_score"
        case recoveryScore = "recovery_score"
        case strainScore = "strain_score"
        case stepCount = "step_count"
        case activeKcal = "active_kcal"
        case distanceM = "distance_m"
        case restingHR = "resting_hr"
        case hrvAvgMS = "hrv_avg_ms"
    }
}

nonisolated enum OHSError: Error, Equatable, Sendable {
    /// Nobody is signed in, or the build has no project.
    case signedOut
    /// The function has no Open Health Sync instance to talk to yet.
    case notSetUp
    case rateLimited
    /// Refused, with the function's words for the screen.
    case refused(String)
    case offline
    case server(Int)
}

/// The app's client for Open Health Sync, the server that signs in to the
/// wearable clouds (Oura, Whoop, Withings, Garmin, Polar and the rest), pulls
/// their data and keeps it with where each value came from.
///
/// Everything goes through the `ohs` Edge Function with the person's own
/// session: the instance's key reads every person on it, so it stays in the
/// function, and the function only ever touches the signed in person's user.
///
/// ```swift
/// let link = try await OHSClient.live.connectURL(provider: "oura")
/// let connections = try await OHSClient.live.connections()
/// let days = try await OHSClient.live.daily(from: "2026-10-01", to: "2026-10-18")
/// ```
nonisolated struct OHSClient: Sendable {
    static let functionName = "ohs"
    /// Where the connect page sends the browser back to: the function's return
    /// route redirects here, which closes the web authentication session.
    static let callbackHost = "oauth"
    static let callbackPath = "/ohs"

    /// Posts one body to the function and hands back the status and the bytes.
    var send: @Sendable (_ body: [String: String]) async throws -> (status: Int, data: Data)

    func connections() async throws -> [OHSConnection] {
        struct Answer: Decodable { var connections: [OHSConnection] }
        return try await call(["action": "connections"], as: Answer.self).connections
    }

    /// A hosted connect page for one provider, valid a quarter of an hour.
    func connectURL(provider: String) async throws -> URL {
        struct Answer: Decodable { var url: String }
        let answer = try await call(["action": "connect", "provider": provider], as: Answer.self)
        guard let url = URL(string: answer.url), url.scheme == "https" else { throw OHSError.server(502) }
        return url
    }

    /// Stops pulling. What was already pulled stays.
    func disconnect(provider: String) async throws {
        struct Answer: Decodable {}
        _ = try await call(["action": "disconnect", "provider": provider], as: Answer.self)
    }

    /// Asks the instance to pull now rather than on its schedule.
    func sync(provider: String) async throws {
        struct Answer: Decodable {}
        _ = try await call(["action": "sync", "provider": provider], as: Answer.self)
    }

    /// Daily summaries, `start <= day < end`, both `YYYY-MM-DD`.
    func daily(from start: String, to end: String) async throws -> [OHSDailySummary] {
        struct Answer: Decodable { var data: [OHSDailySummary] }
        return try await call(["action": "daily", "start": start, "end": end], as: Answer.self).data
    }

    private func call<Answer: Decodable>(_ body: [String: String], as type: Answer.Type) async throws -> Answer {
        let (status, data) = try await send(body)
        guard (200..<300).contains(status) else { throw Self.failure(status: status, body: data) }
        return try JSONDecoder().decode(Answer.self, from: data)
    }

    // MARK: Wire format

    static func request(url: URL, key: String, body: [String: String]) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "apikey")
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    static func failure(status: Int, body: Data) -> OHSError {
        let message = (try? JSONSerialization.jsonObject(with: body) as? [String: Any])?["error"] as? String ?? ""
        switch status {
        case 401: return .signedOut
        case 503: return .notSetUp
        case 429: return .rateLimited
        case 400, 404, 409: return .refused(message)
        default: return .server(status)
        }
    }

    /// What the connect page said, from the URL it sent the browser back to.
    /// Nil when the URL is not the app's Open Health Sync callback.
    static func outcome(of callback: URL) -> (connected: Bool, provider: String?)? {
        guard callback.scheme == ProviderConfig.callbackScheme, callback.host() == callbackHost, callback.path() == callbackPath else { return nil }
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        return (value("status") == "connected", value("provider"))
    }

    /// RFC 3339, with or without fractional seconds.
    static func date(_ text: String) -> Date? {
        if let date = try? Date(text, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) { return date }
        return try? Date(text, strategy: Date.ISO8601FormatStyle())
    }

    // MARK: Live

    /// The signed in session's client: the function's address and the
    /// session's token from ``AccountSession``, refreshed once on a 401.
    static let live = OHSClient { body in
        let (url, key, tokens) = try await MainActor.run { () throws -> (URL, String, AccountTokens) in
            let account = AccountSession.shared
            guard let services = account.services, let tokens = account.tokens, account.isSignedIn else { throw OHSError.signedOut }
            return (try services.functionURL(OHSClient.functionName), services.configuration.publishableKey, tokens)
        }
        let prepared = try OHSClient.request(url: url, key: key, body: body)
        do {
            var token = try await tokens.currentToken()
            for attempt in 0..<2 {
                var authorized = prepared
                authorized.setValue("Bearer \(token.value)", forHTTPHeaderField: "Authorization")
                let (data, response) = try await URLSession.shared.data(for: authorized)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                if status == 401, attempt == 0 {
                    token = try await tokens.refreshedToken(replacing: token)
                    continue
                }
                return (status, data)
            }
            throw OHSError.signedOut
        } catch let error as AuthError {
            throw error == .unavailable ? OHSError.offline : OHSError.signedOut
        } catch is URLError {
            throw OHSError.offline
        }
    }
}
