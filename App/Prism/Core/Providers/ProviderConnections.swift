//
//  ProviderConnections.swift
//  Prism
//

import Foundation
import Observation

/// Where one direct provider stands.
nonisolated enum ProviderConnectionState: Equatable, Sendable {
    case notConnected
    case connecting
    case connected(account: String?, lastSync: Date?)
    case failed(String)

    nonisolated enum Event: Equatable, Sendable {
        case start
        case authorized(account: String?)
        case cancelled
        case failed(String)
        case synced(Date)
        case disconnect
    }

    /// The only moves allowed: a sign in starts from rest or a failure, ends
    /// connected, failed or back at rest, and a sync only touches a connection.
    func applying(_ event: Event) -> ProviderConnectionState {
        switch (self, event) {
        case (.notConnected, .start), (.failed, .start): .connecting
        case (.connecting, .authorized(let account)): .connected(account: account, lastSync: nil)
        case (.connecting, .cancelled): .notConnected
        case (.connecting, .failed(let message)): .failed(message)
        case (.connected(let account, _), .synced(let date)): .connected(account: account, lastSync: date)
        case (_, .disconnect): .notConnected
        default: self
        }
    }

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
}

/// The direct providers' connections: sign in, the token in the Keychain,
/// and Disconnect. No data is fetched yet; this is the seam the vendor
/// integrations plug into.
@MainActor
@Observable
final class ProviderConnections {
    static let shared = ProviderConnections()

    private(set) var states: [String: ProviderConnectionState] = [:]

    @ObservationIgnored let tokens: any ProviderTokenStore
    @ObservationIgnored let exchanger: any TokenExchanging

    init(tokens: any ProviderTokenStore = KeychainTokenStore(), exchanger: any TokenExchanging = URLSessionTokenExchanger()) {
        self.tokens = tokens
        self.exchanger = exchanger
        for provider in DataProvider.all where provider.oauth != nil {
            if let token = tokens.load(provider.id) {
                states[provider.id] = .connected(account: token.account, lastSync: token.lastSync)
            }
        }
    }

    func state(_ provider: DataProvider) -> ProviderConnectionState {
        states[provider.id] ?? .notConnected
    }

    private func send(_ event: ProviderConnectionState.Event, to provider: DataProvider) {
        states[provider.id] = state(provider).applying(event)
    }

    /// Runs the sign in. `authenticate` opens the vendor's page and returns
    /// the callback URL: the system's web authentication session in the app,
    /// a stub in the tests.
    func connect(
        _ provider: DataProvider,
        clientID override: String? = nil,
        authenticate: (URL, String) async throws -> URL
    ) async {
        guard let clientID = override ?? provider.clientID, provider.oauth != nil else { return }
        send(.start, to: provider)
        guard state(provider) == .connecting else { return }
        do {
            let request = try OAuthRequest(provider: provider, clientID: clientID)
            let callback = try await authenticate(request.authorizeURL, ProviderConfig.callbackScheme)
            let code = try request.code(from: callback)
            let token = try await exchanger.exchange(request, code: code)
            try tokens.save(token, for: provider.id)
            send(.authorized(account: token.account), to: provider)
        } catch ProviderAuthError.cancelled {
            send(.cancelled, to: provider)
        } catch let error as ProviderAuthError {
            send(.failed(Self.message(error)), to: provider)
        } catch {
            if (error as NSError).code == 1, (error as NSError).domain.contains("AuthenticationServices") {
                send(.cancelled, to: provider)
            } else {
                send(.failed(error.localizedDescription), to: provider)
            }
        }
    }

    func disconnect(_ provider: DataProvider) {
        tokens.delete(provider.id)
        send(.disconnect, to: provider)
    }

    static func message(_ error: ProviderAuthError) -> String {
        switch error {
        case .notConfigured: String(localized: "Not available yet")
        case .cancelled: String(localized: "Cancelled")
        case .stateMismatch: String(localized: "The sign in did not match. Try again.")
        case .missingCode, .vendor: String(localized: "The sign in was refused")
        case .tokenExchange: String(localized: "Could not finish signing in")
        }
    }
}
