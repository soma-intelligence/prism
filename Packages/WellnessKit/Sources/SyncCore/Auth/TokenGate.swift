import Foundation

/// Why a sync stopped before finishing.
public enum SyncInterruption: Error, Sendable, Hashable {
    case offline
    case authRequired
    case authMismatch
    case circuitOpen(until: Instant)
    case cancelled
}

public enum AuthorizedCallError: Error, Sendable, Hashable {
    case interrupted(SyncInterruption)
    case remote(RemoteError)
}

/// The single place tokens are obtained, refreshed and checked.
public actor TokenGate {
    public nonisolated let userID: UserID
    private let provider: any AccessTokenProvider
    private let clock: any SyncClock
    private let refreshMargin: Duration

    public init(provider: any AccessTokenProvider, userID: UserID, clock: any SyncClock, refreshMargin: Duration = .seconds(60)) {
        self.provider = provider
        self.userID = userID
        self.clock = clock
        self.refreshMargin = refreshMargin
    }

    /// A token for `userID`, refreshed first when it expires within the margin.
    public func token() async throws(SyncInterruption) -> AccessToken {
        let current: AccessToken
        do {
            current = try await provider.currentToken()
        } catch {
            throw Self.interruption(for: error)
        }
        guard current.userID == userID else { throw .authMismatch }
        if Instant(current.expiresAt) <= clock.now().adding(refreshMargin) {
            return try await refresh(replacing: current)
        }
        return current
    }

    public func refresh(replacing rejected: AccessToken) async throws(SyncInterruption) -> AccessToken {
        let fresh: AccessToken
        do {
            fresh = try await provider.refreshedToken(replacing: rejected)
        } catch {
            throw Self.interruption(for: error)
        }
        guard fresh.userID == userID else { throw .authMismatch }
        return fresh
    }

    /// Runs `operation` with a valid token. On `unauthorized` it refreshes once
    /// and retries once; a second `unauthorized` means the user must sign in.
    public func perform<Value: Sendable>(
        _ operation: @Sendable (AccessToken) async throws(RemoteError) -> Value
    ) async throws(AuthorizedCallError) -> Value {
        let first: AccessToken
        do {
            first = try await token()
        } catch {
            throw .interrupted(error)
        }
        do {
            return try await operation(first)
        } catch .unauthorized {
            let second: AccessToken
            do {
                second = try await refresh(replacing: first)
            } catch {
                throw .interrupted(error)
            }
            do {
                return try await operation(second)
            } catch .unauthorized {
                throw .interrupted(.authRequired)
            } catch {
                throw .remote(error)
            }
        } catch {
            throw .remote(error)
        }
    }

    static func interruption(for error: AuthError) -> SyncInterruption {
        switch error {
        case .unavailable: return .offline
        case .signedOut, .refreshRejected: return .authRequired
        }
    }
}
