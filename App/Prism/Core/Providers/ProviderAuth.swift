//
//  ProviderAuth.swift
//  Prism
//

import CryptoKit
import Foundation
import Security

// MARK: - PKCE

/// RFC 7636: a random verifier kept on the device and its SHA-256 challenge
/// sent with the sign in.
nonisolated struct PKCE: Sendable, Equatable {
    let verifier: String
    let challenge: String

    static let unreserved = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    init(verifier: String) {
        self.verifier = verifier
        self.challenge = Self.challenge(for: verifier)
    }

    /// A fresh pair with a 64 character verifier.
    static func make(length: Int = 64) -> PKCE {
        PKCE(verifier: randomString(length: length))
    }

    static func challenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Characters from the unreserved set, from the system's secure random.
    static func randomString(length: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: length)
        if SecRandomCopyBytes(kSecRandomDefault, length, &bytes) != errSecSuccess {
            var generator = SystemRandomNumberGenerator()
            bytes = bytes.map { _ in UInt8.random(in: 0...255, using: &generator) }
        }
        return String(bytes.map { unreserved[Int($0) % unreserved.count] })
    }
}

// MARK: - The sign in

nonisolated enum ProviderAuthError: Error, Equatable, Sendable {
    case notConfigured
    case cancelled
    case stateMismatch
    case missingCode
    case vendor(String)
    case tokenExchange(String)
}

/// One sign in in flight: what goes out, and the check on what comes back.
nonisolated struct OAuthRequest: Sendable, Equatable {
    let providerID: String
    let config: OAuthConfig
    let clientID: String
    let state: String
    let pkce: PKCE?

    init(provider: DataProvider, clientID: String, state: String? = nil, pkce: PKCE? = nil) throws {
        guard let config = provider.oauth else { throw ProviderAuthError.notConfigured }
        self.providerID = provider.id
        self.config = config
        self.clientID = clientID
        self.state = state ?? PKCE.randomString(length: config.stateLength)
        self.pkce = config.usesPKCE ? (pkce ?? .make()) : nil
    }

    var redirectURI: String { ProviderConfig.redirectURI(for: providerID) }

    var authorizeURL: URL {
        var components = URLComponents(url: config.authorizeURL, resolvingAgainstBaseURL: false)
        var items = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: config.scopes.joined(separator: config.scopeSeparator)),
            URLQueryItem(name: "state", value: state),
        ]
        if let pkce {
            items.append(URLQueryItem(name: "code_challenge", value: pkce.challenge))
            items.append(URLQueryItem(name: "code_challenge_method", value: "S256"))
        }
        components?.queryItems = items
        return components?.url ?? config.authorizeURL
    }

    /// The code out of the callback, once its state matches.
    func code(from callback: URL) throws -> String {
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        if let error = value("error") { throw ProviderAuthError.vendor(error) }
        guard value("state") == state else { throw ProviderAuthError.stateMismatch }
        guard let code = value("code"), !code.isEmpty else { throw ProviderAuthError.missingCode }
        return code
    }

    /// The form the token endpoint takes for `code`.
    func tokenForm(code: String) -> [String: String] {
        var form = [
            "grant_type": "authorization_code",
            "code": code,
            "client_id": clientID,
            "redirect_uri": redirectURI,
        ]
        if let pkce { form["code_verifier"] = pkce.verifier }
        if config.tokenStyle == .withings { form["action"] = "requesttoken" }
        return form
    }
}

/// What the vendor hands back, as kept in the Keychain.
nonisolated struct ProviderToken: Codable, Equatable, Sendable {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date?
    var account: String?
    var connectedAt: Date
    var lastSync: Date?
}

/// Posts the code to the token endpoint, or to Soma's relay when one is set.
nonisolated protocol TokenExchanging: Sendable {
    func exchange(_ request: OAuthRequest, code: String) async throws -> ProviderToken
}

nonisolated struct URLSessionTokenExchanger: TokenExchanging {
    func exchange(_ request: OAuthRequest, code: String) async throws -> ProviderToken {
        let endpoint = ProviderConfig.tokenRelay?.appending(path: request.providerID) ?? request.config.tokenURL
        var post = URLRequest(url: endpoint)
        post.httpMethod = "POST"
        post.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = URLComponents()
        form.queryItems = request.tokenForm(code: code).sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        post.httpBody = Data((form.percentEncodedQuery ?? "").utf8)

        let (data, response) = try await URLSession.shared.data(for: post)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ProviderAuthError.tokenExchange(String(decoding: data, as: UTF8.self))
        }
        return try Self.token(from: data, style: request.config.tokenStyle)
    }

    static func token(from data: Data, style: OAuthConfig.TokenStyle, now: Date = .now) throws -> ProviderToken {
        guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderAuthError.tokenExchange("not JSON")
        }
        if style == .withings {
            guard (object["status"] as? Int) == 0, let body = object["body"] as? [String: Any] else {
                throw ProviderAuthError.tokenExchange("status \(object["status"] ?? "missing")")
            }
            object = body
        }
        guard let access = object["access_token"] as? String else { throw ProviderAuthError.tokenExchange("no access token") }
        let expires = (object["expires_in"] as? Double) ?? (object["expires_in"] as? Int).map(Double.init)
        let account = (object["userid"] as? String) ?? (object["userid"] as? Int).map(String.init)
        return ProviderToken(
            accessToken: access, refreshToken: object["refresh_token"] as? String,
            expiresAt: expires.map { now.addingTimeInterval($0) }, account: account, connectedAt: now
        )
    }
}

// MARK: - Keychain

nonisolated protocol ProviderTokenStore: Sendable {
    func load(_ providerID: String) -> ProviderToken?
    func save(_ token: ProviderToken, for providerID: String) throws
    func delete(_ providerID: String)
}

/// One generic password per provider, this device only.
nonisolated struct KeychainTokenStore: ProviderTokenStore {
    var service = "Soma.Prism.providers"

    private func query(_ providerID: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: providerID]
    }

    func load(_ providerID: String) -> ProviderToken? {
        var query = query(providerID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(ProviderToken.self, from: data)
    }

    func save(_ token: ProviderToken, for providerID: String) throws {
        let data = try JSONEncoder().encode(token)
        delete(providerID)
        var item = query(providerID)
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw ProviderAuthError.tokenExchange("keychain \(status)") }
    }

    func delete(_ providerID: String) {
        SecItemDelete(query(providerID) as CFDictionary)
    }
}
