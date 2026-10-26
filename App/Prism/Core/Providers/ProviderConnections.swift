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
///
/// With an account, the providers Open Health Sync knows connect there
/// instead (``connectThroughOHS(_:authenticate:)``): the instance signs in,
/// keeps the grant and pulls the data, and ``refreshFromOHS()`` reads where
/// each connection stands. No token reaches the phone on that path.
@MainActor
@Observable
final class ProviderConnections {
    static let shared = ProviderConnections()

    private(set) var states: [String: ProviderConnectionState] = [:]

    /// Whether the account's Open Health Sync is reachable: nil until the first
    /// answer, false when the function has no instance set up yet.
    private(set) var ohsAvailable: Bool?

    @ObservationIgnored let tokens: any ProviderTokenStore
    @ObservationIgnored let exchanger: any TokenExchanging
    @ObservationIgnored let ohs: OHSClient

    init(tokens: any ProviderTokenStore = KeychainTokenStore(), exchanger: any TokenExchanging = URLSessionTokenExchanger(), ohs: OHSClient = .live) {
        self.tokens = tokens
        self.exchanger = exchanger
        self.ohs = ohs
        for provider in DataProvider.all where provider.oauth != nil {
            if let token = tokens.load(provider.id) {
                states[provider.id] = .connected(account: token.account, lastSync: token.lastSync)
            }
        }
    }

    /// When each direct connection was made, read from its token. A
    /// connection made through Open Health Sync keeps no date on the phone.
    func connectionDates() -> [String: Date] {
        var dates: [String: Date] = [:]
        for provider in DataProvider.all where provider.oauth != nil {
            if let token = tokens.load(provider.id) { dates[provider.id] = token.connectedAt }
        }
        return dates
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
            if Self.isCancellation(error) {
                send(.cancelled, to: provider)
            } else {
                send(.failed(error.localizedDescription), to: provider)
            }
        }
    }

    // MARK: Open Health Sync

    /// Reads every connection the account holds on Open Health Sync and sets
    /// the providers it knows to match: active is connected with its last
    /// pull, a grant the vendor stopped honouring asks to reconnect, anything
    /// else is at rest. A sign in in flight is left alone.
    func refreshFromOHS() async {
        let list: [OHSConnection]
        do {
            list = try await ohs.connections()
            ohsAvailable = true
        } catch OHSError.notSetUp {
            ohsAvailable = false
            return
        } catch {
            return
        }
        apply(list)
    }

    func apply(_ list: [OHSConnection]) {
        let bySlug = Dictionary(list.map { ($0.provider, $0) }, uniquingKeysWith: { first, _ in first })
        for provider in DataProvider.all {
            guard let slug = provider.ohsSlug, state(provider) != .connecting else { continue }
            switch bySlug[slug]?.status {
            case .active: states[provider.id] = .connected(account: nil, lastSync: bySlug[slug]?.lastSyncAt)
            case .needsReauth: states[provider.id] = .failed(String(localized: "Needs reconnecting"))
            case .disconnected, nil: states[provider.id] = provider.oauth != nil && tokens.load(provider.id) != nil ? states[provider.id] : nil
            }
        }
    }

    /// Opens the provider's row of the Open Health Sync connect page, where the
    /// person signs in on the vendor's own site, and reads the result back.
    /// `authenticate` is the system's web authentication session in the app,
    /// a stub in the tests, as for ``connect(_:clientID:authenticate:)``.
    func connectThroughOHS(_ provider: DataProvider, authenticate: (URL, String) async throws -> URL) async {
        guard let slug = provider.ohsSlug else { return }
        send(.start, to: provider)
        guard state(provider) == .connecting else { return }
        do {
            let page = try await ohs.connectURL(provider: slug)
            let callback = try await authenticate(page, ProviderConfig.callbackScheme)
            guard let outcome = OHSClient.outcome(of: callback), outcome.connected else {
                send(.failed(Self.message(.vendor("refused"))), to: provider)
                return
            }
            send(.authorized(account: nil), to: provider)
            await refreshFromOHS()
        } catch OHSError.notSetUp {
            ohsAvailable = false
            send(.failed(Self.message(.notConfigured)), to: provider)
        } catch let error as OHSError {
            send(.failed(Self.message(error)), to: provider)
        } catch {
            if Self.isCancellation(error) {
                send(.cancelled, to: provider)
            } else {
                send(.failed(error.localizedDescription), to: provider)
            }
        }
    }

    /// Ends the connection on Open Health Sync. The data already pulled stays
    /// there; deleting the account erases it.
    func disconnectThroughOHS(_ provider: DataProvider) async {
        guard let slug = provider.ohsSlug else { return }
        do {
            try await ohs.disconnect(provider: slug)
            send(.disconnect, to: provider)
        } catch {
            await refreshFromOHS()
        }
    }

    static func message(_ error: OHSError) -> String {
        switch error {
        case .signedOut: String(localized: "Sign in to connect")
        case .notSetUp: String(localized: "Not available yet")
        case .rateLimited: String(localized: "Too many tries. Wait a minute.")
        case .offline: String(localized: "You're offline")
        case .refused, .server: String(localized: "Could not finish signing in")
        }
    }

    /// The person closed the web authentication session.
    static func isCancellation(_ error: any Error) -> Bool {
        (error as NSError).code == 1 && (error as NSError).domain.contains("AuthenticationServices")
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
