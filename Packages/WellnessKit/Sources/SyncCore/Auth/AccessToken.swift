import Foundation

/// A bearer token for one user, supplied by the host app.
public struct AccessToken: Sendable, Hashable {
    public let userID: UserID
    public let value: String
    public let expiresAt: Date

    public init(userID: UserID, value: String, expiresAt: Date) {
        self.userID = userID
        self.value = value
        self.expiresAt = expiresAt
    }
}

public enum AuthError: Error, Sendable, Hashable {
    /// Nobody is signed in.
    case signedOut
    /// The server refused the refresh token. The user must sign in again.
    case refreshRejected
    /// A refresh could not be attempted, for example offline. Try later.
    case unavailable
}

/// The host app's session. The kits never sign anyone in or out.
public protocol AccessTokenProvider: Sendable {
    func currentToken() async throws(AuthError) -> AccessToken
    func refreshedToken(replacing rejected: AccessToken) async throws(AuthError) -> AccessToken
}
