//
//  OpenHealthSyncTests.swift
//  PrismTests
//

import Foundation
import Testing
@testable import Prism

private final class NoTokens: ProviderTokenStore, @unchecked Sendable {
    func load(_ providerID: String) -> ProviderToken? { nil }
    func save(_ token: ProviderToken, for providerID: String) throws {}
    func delete(_ providerID: String) {}
}

/// A function stand in: one canned answer per action, and the bodies it got.
private final class FakeFunction: @unchecked Sendable {
    var answers: [String: (Int, String)] = [:]
    var bodies: [[String: String]] = []

    var client: OHSClient {
        OHSClient { body in
            self.bodies.append(body)
            let (status, json) = self.answers[body["action"] ?? ""] ?? (404, "{}")
            return (status, Data(json.utf8))
        }
    }
}

@Suite("Open Health Sync")
struct OpenHealthSyncTests {
    @Test("Connections decode, fractional seconds or not, and an odd status reads as disconnected")
    func decoding() throws {
        let json = """
        {"connections":[
          {"provider":"oura","status":"active","last_sync_at":"2026-10-18T02:00:00.123Z"},
          {"provider":"whoop","status":"needs_reauth","last_sync_at":"2026-10-17T02:00:00Z"},
          {"provider":"garmin","status":"paused","last_sync_at":null}
        ]}
        """
        struct Answer: Decodable { var connections: [OHSConnection] }
        let list = try JSONDecoder().decode(Answer.self, from: Data(json.utf8)).connections
        #expect(list.map(\.status) == [.active, .needsReauth, .disconnected])
        #expect(list[0].lastSyncAt != nil && list[1].lastSyncAt != nil)
        #expect(list[2].lastSyncAt == nil)
    }

    @Test("Daily summaries keep a missing figure as nil")
    func daily() throws {
        let json = #"{"date":"2026-10-17","readiness_score":82,"step_count":null,"hrv_avg_ms":41.5,"sources":{"readiness_score":"oura"},"metadata":{}}"#
        let day = try JSONDecoder().decode(OHSDailySummary.self, from: Data(json.utf8))
        #expect(day.readinessScore == 82)
        #expect(day.stepCount == nil)
        #expect(day.hrvAvgMS == 41.5)
        #expect(day.sources?["readiness_score"] == "oura")
    }

    @Test("Only the app's own callback is read, and only connected counts")
    func callback() throws {
        let connectedURL = try #require(URL(string: "soma://oauth/ohs?status=connected&provider=oura"))
        let ok = try #require(OHSClient.outcome(of: connectedURL))
        #expect(ok.connected && ok.provider == "oura")
        let errorURL = try #require(URL(string: "soma://oauth/ohs?status=error"))
        let failed = try #require(OHSClient.outcome(of: errorURL))
        #expect(!failed.connected)
        #expect(OHSClient.outcome(of: try #require(URL(string: "soma://oauth/oura?code=c"))) == nil)
        #expect(OHSClient.outcome(of: try #require(URL(string: "https://oauth/ohs?status=connected"))) == nil)
    }

    @Test("The request posts JSON with the project key; failures map to what the screen says")
    func wire() throws {
        let request = try OHSClient.request(url: try #require(URL(string: "https://p.supabase.co/functions/v1/ohs")), key: "pk", body: ["action": "connections"])
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "apikey") == "pk")
        #expect(try JSONDecoder().decode([String: String].self, from: try #require(request.httpBody)) == ["action": "connections"])
        #expect(OHSClient.failure(status: 503, body: Data()) == .notSetUp)
        #expect(OHSClient.failure(status: 401, body: Data()) == .signedOut)
        #expect(OHSClient.failure(status: 409, body: Data(#"{"error":"connect again"}"#.utf8)) == .refused("connect again"))
        #expect(OHSClient.failure(status: 502, body: Data()) == .server(502))
    }

    @Test("Every slug is one the instance knows, and Apple's own never go through it")
    func slugs() {
        let known: Set = ["withings", "oura", "whoop", "ultrahuman", "garmin", "polar", "fitbit", "eight_sleep", "dexcom", "strava"]
        for provider in DataProvider.all {
            if let slug = provider.ohsSlug { #expect(known.contains(slug), "\(provider.id)") }
        }
        #expect(!DataProvider.appleHealth.connectsThroughOHS && !DataProvider.appleWatch.connectsThroughOHS && !DataProvider.iPhoneMotion.connectsThroughOHS)
    }

    @Test("Refresh sets each known provider from the instance")
    @MainActor
    func refresh() async {
        let function = FakeFunction()
        function.answers["connections"] = (200, #"{"connections":[{"provider":"oura","status":"active","last_sync_at":"2026-10-18T02:00:00Z"},{"provider":"whoop","status":"needs_reauth"}]}"#)
        let connections = ProviderConnections(tokens: NoTokens(), exchanger: URLSessionTokenExchanger(), ohs: function.client)
        await connections.refreshFromOHS()
        #expect(connections.ohsAvailable == true)
        #expect(connections.state(.oura) == .connected(account: nil, lastSync: OHSClient.date("2026-10-18T02:00:00Z")))
        #expect(connections.state(.whoop) == .failed(String(localized: "Needs reconnecting")))
        #expect(connections.state(.withings) == .notConnected)

        function.answers["connections"] = (503, #"{"error":"Open Health Sync is not set up"}"#)
        let bare = ProviderConnections(tokens: NoTokens(), exchanger: URLSessionTokenExchanger(), ohs: function.client)
        await bare.refreshFromOHS()
        #expect(bare.ohsAvailable == false)
    }

    @Test("Connect opens the page, reads the callback, then refreshes; Disconnect asks the instance")
    @MainActor
    func connectFlow() async throws {
        let function = FakeFunction()
        function.answers["connect"] = (200, #"{"url":"https://ohs.example.org/connect/oura?session=abc","expires_at":"2026-10-18T03:30:00Z"}"#)
        function.answers["connections"] = (200, #"{"connections":[{"provider":"oura","status":"active","last_sync_at":null}]}"#)
        function.answers["disconnect"] = (200, #"{"disconnected":true}"#)
        let connections = ProviderConnections(tokens: NoTokens(), exchanger: URLSessionTokenExchanger(), ohs: function.client)

        var opened: URL?
        await connections.connectThroughOHS(.oura) { url, scheme in
            opened = url
            #expect(scheme == "soma")
            return try #require(URL(string: "soma://oauth/ohs?status=connected&provider=oura"))
        }
        #expect(opened?.absoluteString == "https://ohs.example.org/connect/oura?session=abc")
        #expect(function.bodies.first == ["action": "connect", "provider": "oura"])
        #expect(connections.state(.oura) == .connected(account: nil, lastSync: nil))

        await connections.disconnectThroughOHS(.oura)
        #expect(function.bodies.last == ["action": "disconnect", "provider": "oura"])
        #expect(connections.state(.oura) == .notConnected)

        await connections.connectThroughOHS(.whoop) { _, _ in
            try #require(URL(string: "soma://oauth/ohs?status=error&provider=whoop"))
        }
        #expect(connections.state(.whoop) == .failed(ProviderConnections.message(.vendor("refused"))))

        await connections.connectThroughOHS(.appleHealth) { url, _ in url }
        #expect(connections.state(.appleHealth) == .notConnected)
    }
}
