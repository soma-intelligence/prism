import Foundation
import SyncCore

/// A host session whose answers a test scripts. Unscripted refreshes return
/// `token-2`, `token-3`, and so on.
public actor ScriptedTokenProvider: AccessTokenProvider {
    private var current: AccessToken
    private var currentErrors: [AuthError] = []
    private var refreshOutcomes: [Result<AccessToken, AuthError>] = []
    public private(set) var refreshCalls = 0

    public init(userID: UserID, value: String = "token-1", expiresAt: Date = .distantFuture) {
        current = AccessToken(userID: userID, value: value, expiresAt: expiresAt)
    }

    public func failNextCurrentToken(with error: AuthError) {
        currentErrors.append(error)
    }

    public func scriptRefresh(_ outcomes: [Result<AccessToken, AuthError>]) {
        refreshOutcomes.append(contentsOf: outcomes)
    }

    public func setCurrent(_ token: AccessToken) {
        current = token
    }

    public func currentToken() async throws(AuthError) -> AccessToken {
        if !currentErrors.isEmpty { throw currentErrors.removeFirst() }
        return current
    }

    public func refreshedToken(replacing rejected: AccessToken) async throws(AuthError) -> AccessToken {
        refreshCalls += 1
        if !refreshOutcomes.isEmpty {
            switch refreshOutcomes.removeFirst() {
            case .success(let token):
                current = token
                return token
            case .failure(let error):
                throw error
            }
        }
        let token = AccessToken(userID: current.userID, value: "token-\(refreshCalls + 1)", expiresAt: .distantFuture)
        current = token
        return token
    }
}
