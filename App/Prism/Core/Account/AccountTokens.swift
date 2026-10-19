//
//  AccountTokens.swift
//  Prism
//

import Foundation
import SyncCore
import SyncSupabase

/// The signed in session's bearer tokens, for everything that is not the
/// Supabase client itself: SyncCore's outbox and the Ask stream.
///
/// The Supabase client (supabase-swift) keeps the session in the Keychain
/// and refreshes it before it expires. This actor puts SyncCore's rules on
/// top: a 401 asks for one refresh, two callers holding the same rejected
/// token share it, a refresh the server refuses (revoked, account deleted)
/// signs the person out, and one that could not be attempted (offline) keeps
/// them signed in.
actor AccountTokens: AccessTokenProvider {
    private let backend: any AccountAuthBackend
    private var refreshing: Task<SupabaseAuthSession, any Error>?
    private var lastRejected: String?
    private var lastFresh: SupabaseAuthSession?

    init(backend: any AccountAuthBackend) {
        self.backend = backend
    }

    // MARK: AccessTokenProvider

    func currentToken() async throws(AuthError) -> AccessToken {
        do {
            return try await backend.validSession().token
        } catch {
            throw Self.authError(error)
        }
    }

    func refreshedToken(replacing rejected: AccessToken) async throws(AuthError) -> AccessToken {
        // Someone refreshed past this token already: hand over the new one.
        if lastRejected == rejected.value, let lastFresh, lastFresh.accessToken != rejected.value {
            return lastFresh.token
        }
        let task: Task<SupabaseAuthSession, any Error>
        if let refreshing {
            task = refreshing
        } else {
            let backend = self.backend
            task = Task { () async throws -> SupabaseAuthSession in
                try await backend.refreshSession()
            }
            refreshing = task
        }
        do {
            let fresh = try await task.value
            if refreshing == task { refreshing = nil }
            lastRejected = rejected.value
            lastFresh = fresh
            return fresh.token
        } catch {
            if refreshing == task { refreshing = nil }
            if let error = error as? SupabaseAuthError {
                if case .refused = error { await backend.signOut() }
                throw Self.authError(error)
            }
            throw .unavailable
        }
    }

    static func authError(_ error: SupabaseAuthError) -> AuthError {
        switch error {
        case .signedOut: .signedOut
        case .refused: .refreshRejected
        case .remote: .unavailable
        }
    }
}
