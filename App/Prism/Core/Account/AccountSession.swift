//
//  AccountSession.swift
//  Prism
//

import AuthenticationServices
import Foundation
import Observation
import SyncCore
import SyncSupabase

/// Who is signed in.
nonisolated struct AccountUser: Equatable, Sendable {
    /// The Supabase user id, lowercase.
    var id: String
    var email: String?
}

nonisolated enum AccountState: Equatable, Sendable {
    /// This build has no Supabase project (no URL or key), so there is no
    /// account to sign in to. Everything stays on the phone.
    case unavailable
    case signedOut
    case signingIn
    case signedIn(AccountUser)

    var user: AccountUser? {
        if case .signedIn(let user) = self { return user }
        return nil
    }
}

/// The person's Soma account: Sign in with Apple through Supabase Auth, the
/// session in the Keychain, and sign out.
///
/// The small surface the screens use:
///
/// ```swift
/// SignInWithAppleButton(.continue) { request in
///     AccountSession.shared.prepare(request)
/// } onCompletion: { result in
///     if case .success(let authorization) = result { AccountSession.shared.continueWithApple(authorization) }
/// }
/// await AccountSession.shared.signOut()
/// ```
///
/// The session itself is supabase-swift's: kept in the Keychain, refreshed
/// before it expires, and announced on its auth state stream, which this
/// type follows (a session revoked on the server signs the person out here).
///
/// Signing in starts the cloud sync (`CloudSync`); signing out stops it and
/// leaves what is on the phone where it is.
@MainActor
@Observable
final class AccountSession {
    static let shared = AccountSession()

    private(set) var state: AccountState
    /// Why the last sign in failed, in words for the screen. Nil after a success.
    private(set) var lastError: String?

    let settings: SupabaseSettings?
    /// The Supabase client: Auth, PostgREST, Storage, Functions. Nil when the
    /// build has no project.
    let services: SupabaseServices?
    /// The session's tokens, for the outbox and the Ask stream.
    let tokens: AccountTokens?
    private let backend: (any AccountAuthBackend)?

    /// The raw nonce of the Apple request in flight. Its hash went to Apple.
    private var pendingNonce: String?

    /// - Parameters:
    ///   - services: the Supabase client; the app's own (session in the
    ///     Keychain) when nil.
    ///   - backend: the auth calls; the client's Auth when nil. Tests pass a fake.
    init(settings: SupabaseSettings? = SupabaseSettings.current, services: SupabaseServices? = nil, backend: (any AccountAuthBackend)? = nil) {
        self.settings = settings
        guard let settings else {
            self.services = nil
            self.backend = nil
            self.tokens = nil
            state = .unavailable
            return
        }
        let services = services ?? SupabaseServices.onDevice(configuration: settings.configuration)
        let backend = backend ?? SupabaseAccountAuth(services: services)
        self.services = services
        self.backend = backend
        self.tokens = AccountTokens(backend: backend)
        if let stored = backend.storedSession() {
            state = .signedIn(AccountUser(id: stored.userID, email: stored.email))
        } else {
            state = .signedOut
        }
        // The account lives as long as the app; holding it here is no leak.
        let account = self
        let changes = backend.sessionChanges()
        Task { @MainActor in
            for await session in changes { account.sessionChanged(session) }
        }
    }

    var isSignedIn: Bool { state.user != nil }

    // MARK: Sign in with Apple

    /// Puts a fresh nonce's hash on the Apple request and keeps the raw nonce
    /// for the exchange. Call it from `SignInWithAppleButton`'s request closure.
    func prepare(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = AppleNonce.make()
        pendingNonce = nonce
        request.nonce = AppleNonce.sha256(nonce)
    }

    /// Exchanges Apple's answer for a Soma session, in the background of the
    /// screen: onboarding moves on at once, and a failure lands in
    /// ``lastError`` with the person still able to use the app on the phone.
    func continueWithApple(_ authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else { return }
        guard let token = credential.identityToken.flatMap({ String(data: $0, encoding: .utf8) }), let nonce = pendingNonce else {
            lastError = String(localized: "Apple did not send a sign in token. Try again.")
            return
        }
        pendingNonce = nil
        Task {
            do {
                try await signInWithApple(idToken: token, nonce: nonce)
            } catch {
                // lastError is already set.
            }
        }
    }

    /// Exchanges an Apple identity token with Supabase Auth
    /// (`signInWithIdToken`, provider apple). `nonce` is the raw nonce whose
    /// SHA-256 was on the Apple request.
    func signInWithApple(idToken: String, nonce: String) async throws {
        guard let backend else {
            lastError = String(localized: "Accounts aren’t set up in this build. Your data stays on this phone.")
            throw SupabaseAuthError.signedOut
        }
        let previous = state
        state = .signingIn
        do {
            let session = try await backend.signInWithApple(idToken: idToken, nonce: nonce)
            lastError = nil
            state = .signedIn(AccountUser(id: session.userID, email: session.email))
            CloudSync.shared.accountDidSignIn()
        } catch {
            state = previous == .signingIn ? .signedOut : previous
            switch error {
            case .refused, .signedOut:
                lastError = String(localized: "Sign in with Apple was refused. Try again.")
            case .remote:
                lastError = String(localized: "Couldn’t reach Soma. You’re using the app on this phone; sign in again later.")
            }
            throw error
        }
    }

    // MARK: Sign out

    /// Signs out here and on the server. What is on the phone stays.
    func signOut() async {
        await CloudSync.shared.stop()
        await backend?.signOut()
        state = settings == nil ? .unavailable : .signedOut
    }

    // MARK: Changes from the client

    private func sessionChanged(_ session: SupabaseAuthSession?) {
        if let session {
            let user = AccountUser(id: session.userID, email: session.email)
            if state.user != user { state = .signedIn(user) }
            CloudSync.shared.accountDidSignIn()
        } else if state.user != nil {
            state = .signedOut
            Task { await CloudSync.shared.stop() }
        }
    }
}
