import Foundation
import Supabase
import SyncCore

/// A Supabase Auth session as the app needs it.
public struct SupabaseAuthSession: Sendable, Hashable {
    public let accessToken: String
    public let refreshToken: String
    public let expiresAt: Date
    /// The Supabase user id, lowercase.
    public let userID: String
    public let email: String?

    public init(accessToken: String, refreshToken: String, expiresAt: Date, userID: String, email: String?) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.userID = userID.lowercased()
        self.email = email
    }

    init(_ session: Session) {
        self.init(
            accessToken: session.accessToken,
            refreshToken: session.refreshToken,
            expiresAt: Date(timeIntervalSince1970: session.expiresAt),
            userID: session.user.id.uuidString,
            email: session.user.email
        )
    }

    /// The bearer as the sync foundation takes it.
    public var token: AccessToken {
        AccessToken(userID: UserID(userID), value: accessToken, expiresAt: expiresAt)
    }
}

/// Why an auth call failed.
public enum SupabaseAuthError: Error, Sendable, Hashable {
    /// Nobody is signed in.
    case signedOut
    /// The identity token, the nonce or the refresh token was refused. The
    /// person has to sign in again.
    case refused(reason: String)
    /// Anything that could succeed later: offline, timeouts, 5xx.
    case remote(RemoteError)
}

/// The account's auth calls. A protocol so the session rules are tested
/// with a fake; ``SupabaseAccountAuth`` is the real one.
public protocol AccountAuthBackend: Sendable {
    /// The session kept on this device, possibly expired, without a network call.
    func storedSession() -> SupabaseAuthSession?
    /// Exchanges Apple's identity token (with the raw nonce whose hash went to
    /// Apple) for a session, and keeps it.
    func signInWithApple(idToken: String, nonce: String) async throws(SupabaseAuthError) -> SupabaseAuthSession
    /// A session valid now, refreshed first when it is about to expire.
    func validSession() async throws(SupabaseAuthError) -> SupabaseAuthSession
    /// A new session from the refresh token, whatever the expiry says.
    func refreshSession() async throws(SupabaseAuthError) -> SupabaseAuthSession
    /// Revokes this device's session and forgets it.
    func signOut() async
    /// Every change of session: a session after a sign in or refresh, nil
    /// after a sign out (including one the server forced).
    func sessionChanges() -> AsyncStream<SupabaseAuthSession?>
}

/// ``AccountAuthBackend`` over supabase-swift's Auth client, which persists
/// the session in the Keychain and refreshes it on its own.
public struct SupabaseAccountAuth: AccountAuthBackend {
    public let services: SupabaseServices

    public init(services: SupabaseServices) {
        self.services = services
    }

    private var auth: AuthClient { services.client.auth }

    public func storedSession() -> SupabaseAuthSession? {
        auth.currentSession.map(SupabaseAuthSession.init)
    }

    public func signInWithApple(idToken: String, nonce: String) async throws(SupabaseAuthError) -> SupabaseAuthSession {
        do {
            let session = try await auth.signInWithIdToken(credentials: OpenIDConnectCredentials(provider: .apple, idToken: idToken, nonce: nonce))
            return SupabaseAuthSession(session)
        } catch {
            throw Self.classify(error)
        }
    }

    public func validSession() async throws(SupabaseAuthError) -> SupabaseAuthSession {
        do {
            return SupabaseAuthSession(try await auth.session)
        } catch {
            throw Self.classify(error)
        }
    }

    public func refreshSession() async throws(SupabaseAuthError) -> SupabaseAuthSession {
        do {
            return SupabaseAuthSession(try await auth.refreshSession())
        } catch {
            throw Self.classify(error)
        }
    }

    public func signOut() async {
        do {
            try await auth.signOut(scope: .local)
        } catch {
            // The client forgets the session even when revocation fails;
            // the token expires within the hour.
        }
    }

    public func sessionChanges() -> AsyncStream<SupabaseAuthSession?> {
        let changes = auth.authStateChanges
        return AsyncStream { continuation in
            let task = Task {
                for await (event, session) in changes {
                    switch event {
                    case .signedOut, .userDeleted:
                        continuation.yield(nil)
                    case .signedIn, .tokenRefreshed, .userUpdated, .initialSession:
                        continuation.yield(session.map(SupabaseAuthSession.init))
                    default:
                        continue
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    static func classify(_ error: any Error) -> SupabaseAuthError {
        if let error = error as? Auth.AuthError {
            switch error {
            case .sessionMissing:
                return .signedOut
            case .api(let message, _, _, let response) where (400..<500).contains(response.statusCode) && response.statusCode != 408 && response.statusCode != 429:
                return .refused(reason: message)
            case .refreshDiscarded:
                return .remote(.transient(status: nil, retryAfter: nil))
            default:
                break
            }
        }
        let remote = SupabaseServices.remoteError(error)
        if case .rejected(_, let reason) = remote { return .refused(reason: reason) }
        return .remote(remote)
    }
}
