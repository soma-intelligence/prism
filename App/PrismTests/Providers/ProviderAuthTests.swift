//
//  ProviderAuthTests.swift
//  PrismTests
//

import Foundation
import Testing
@testable import Prism

private final class MemoryTokens: ProviderTokenStore, @unchecked Sendable {
    var tokens: [String: ProviderToken] = [:]
    func load(_ providerID: String) -> ProviderToken? { tokens[providerID] }
    func save(_ token: ProviderToken, for providerID: String) throws { tokens[providerID] = token }
    func delete(_ providerID: String) { tokens[providerID] = nil }
}

private struct StubExchanger: TokenExchanging {
    var fails = false
    func exchange(_ request: OAuthRequest, code: String) async throws -> ProviderToken {
        if fails { throw ProviderAuthError.tokenExchange("no") }
        return ProviderToken(accessToken: "token-\(code)", refreshToken: "r", expiresAt: nil, account: "42", connectedAt: .now)
    }
}

@Suite("Provider sign in")
struct ProviderAuthTests {
    @Test("PKCE matches RFC 7636's own example")
    func pkceVector() {
        let pkce = PKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        #expect(pkce.challenge == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    @Test("A fresh verifier is long enough and unreserved only")
    func pkceFresh() {
        let pkce = PKCE.make()
        #expect((43...128).contains(pkce.verifier.count))
        #expect(pkce.verifier.allSatisfy { PKCE.unreserved.contains($0) })
        #expect(PKCE.make().verifier != pkce.verifier)
        #expect(!pkce.challenge.contains("=") && !pkce.challenge.contains("+") && !pkce.challenge.contains("/"))
    }

    @Test("The authorize URL carries the client, scopes, state and challenge")
    func authorizeURL() throws {
        let pkce = PKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        let request = try OAuthRequest(provider: .oura, clientID: "abc", state: "s1", pkce: pkce)
        let items = try #require(URLComponents(url: request.authorizeURL, resolvingAgainstBaseURL: false)?.queryItems)
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        #expect(request.authorizeURL.host() == "cloud.ouraring.com")
        #expect(value("client_id") == "abc")
        #expect(value("state") == "s1")
        #expect(value("code_challenge") == pkce.challenge)
        #expect(value("code_challenge_method") == "S256")
        #expect(value("redirect_uri") == "soma://oauth/oura")
        #expect(request.tokenForm(code: "c")["code_verifier"] == pkce.verifier)
    }

    @Test("Whoop gets eight characters of state, Withings its action and commas")
    func vendorQuirks() throws {
        let whoop = try OAuthRequest(provider: .whoop, clientID: "w")
        #expect(whoop.state.count == 8)
        #expect(whoop.pkce == nil)
        let withings = try OAuthRequest(provider: .withings, clientID: "w")
        #expect(withings.tokenForm(code: "c")["action"] == "requesttoken")
        let scope = URLComponents(url: withings.authorizeURL, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "scope" }?.value
        #expect(scope == "user.info,user.metrics,user.activity")
    }

    @Test("The callback is checked against the state")
    func callback() throws {
        let request = try OAuthRequest(provider: .oura, clientID: "abc", state: "good")
        #expect(try request.code(from: #require(URL(string: "soma://oauth/oura?code=xyz&state=good"))) == "xyz")
        #expect(throws: ProviderAuthError.stateMismatch) {
            try request.code(from: #require(URL(string: "soma://oauth/oura?code=xyz&state=bad")))
        }
        #expect(throws: ProviderAuthError.vendor("access_denied")) {
            try request.code(from: #require(URL(string: "soma://oauth/oura?error=access_denied&state=good")))
        }
    }

    @Test("Token bodies: standard and Withings' wrapper")
    func tokenParsing() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let standard = try URLSessionTokenExchanger.token(
            from: Data(#"{"access_token":"a","refresh_token":"r","expires_in":3600}"#.utf8), style: .standard, now: now)
        #expect(standard.accessToken == "a" && standard.expiresAt == now.addingTimeInterval(3600))
        let withings = try URLSessionTokenExchanger.token(
            from: Data(#"{"status":0,"body":{"userid":7,"access_token":"w","expires_in":10800}}"#.utf8), style: .withings, now: now)
        #expect(withings.accessToken == "w" && withings.account == "7")
        #expect(throws: ProviderAuthError.self) {
            try URLSessionTokenExchanger.token(from: Data(#"{"status":503}"#.utf8), style: .withings)
        }
    }

    @Test("Connection states move only the allowed ways")
    func stateMachine() {
        let rest = ProviderConnectionState.notConnected
        #expect(rest.applying(.start) == .connecting)
        #expect(rest.applying(.authorized(account: "x")) == rest)
        #expect(rest.applying(.synced(.now)) == rest)
        #expect(ProviderConnectionState.connecting.applying(.authorized(account: "x")) == .connected(account: "x", lastSync: nil))
        #expect(ProviderConnectionState.connecting.applying(.cancelled) == .notConnected)
        #expect(ProviderConnectionState.connecting.applying(.failed("e")) == .failed("e"))
        #expect(ProviderConnectionState.connecting.applying(.start) == .connecting)
        #expect(ProviderConnectionState.failed("e").applying(.start) == .connecting)
        let date = Date()
        #expect(ProviderConnectionState.connected(account: "x", lastSync: nil).applying(.synced(date)) == .connected(account: "x", lastSync: date))
        #expect(ProviderConnectionState.connected(account: "x", lastSync: nil).applying(.start) == .connected(account: "x", lastSync: nil))
        #expect(ProviderConnectionState.connected(account: "x", lastSync: nil).applying(.disconnect) == .notConnected)
    }

    @Test("Without a client id the providers stay on Soon")
    func notConfigured() {
        for provider in [DataProvider.oura, .whoop, .withings] {
            #expect(provider.oauth != nil)
            #expect(provider.canConnect == (ProviderConfig.clientIDs[provider.id] != nil))
        }
        #expect(!DataProvider.appleWatch.canConnect)
        #expect(Set(DataProvider.all.map(\.id)).count == DataProvider.all.count)
    }

    @Test("Connect stores the token, Disconnect forgets it")
    @MainActor
    func connectFlow() async throws {
        let tokens = MemoryTokens()
        let connections = ProviderConnections(tokens: tokens, exchanger: StubExchanger())
        let provider = DataProvider.oura
        if provider.clientID == nil {
            // No client id in this build: Connect does nothing.
            await connections.connect(provider) { url, _ in url }
            #expect(connections.state(provider) == .notConnected)
        }
        await connections.connect(provider, clientID: "test") { url, _ in
            let state = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "state" }?.value ?? ""
            return try #require(URL(string: "soma://oauth/oura?code=c&state=\(state)"))
        }
        #expect(connections.state(provider) == .connected(account: "42", lastSync: nil))
        #expect(tokens.load("oura")?.accessToken == "token-c")
        #expect(connections.connectionDates()["oura"] == tokens.load("oura")?.connectedAt)
        connections.disconnect(provider)
        #expect(connections.state(provider) == .notConnected)
        #expect(tokens.load("oura") == nil)
        #expect(connections.connectionDates()["oura"] == nil)

        await connections.connect(provider, clientID: "test") { _, _ in throw ProviderAuthError.cancelled }
        #expect(connections.state(provider) == .notConnected)
        await connections.connect(provider, clientID: "test") { _, _ in
            try #require(URL(string: "soma://oauth/oura?code=c&state=forged"))
        }
        #expect(connections.state(provider) == .failed(ProviderConnections.message(.stateMismatch)))
    }
}
