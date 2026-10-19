import Foundation
import Synchronization
import Testing
import SyncCore
import SyncTesting

final class TokenLog: Sendable {
    let values = Mutex<[String]>([])
    func append(_ value: String) { values.withLock { $0.append(value) } }
    var all: [String] { values.withLock { $0 } }
}

@Suite struct TokenGateTests {
    let user = UserID("user-a")

    @Test func returnsTheCurrentTokenWhenFarFromExpiry() async throws {
        let clock = ManualClock()
        let provider = ScriptedTokenProvider(userID: user)
        let gate = TokenGate(provider: provider, userID: user, clock: clock)
        #expect(try await gate.token().value == "token-1")
        #expect(await provider.refreshCalls == 0)
    }

    @Test func refreshesProactivelyWithinSixtySecondsOfExpiry() async throws {
        let clock = ManualClock()
        let provider = ScriptedTokenProvider(userID: user, expiresAt: clock.now().adding(.seconds(30)).date)
        let gate = TokenGate(provider: provider, userID: user, clock: clock)
        #expect(try await gate.token().value == "token-2")
        #expect(await provider.refreshCalls == 1)
    }

    @Test func unauthorizedTriggersOneRefreshAndOneRetry() async throws {
        let provider = ScriptedTokenProvider(userID: user)
        let gate = TokenGate(provider: provider, userID: user, clock: ManualClock())
        let log = TokenLog()
        let result = try await gate.perform { token throws(RemoteError) -> String in
            log.append(token.value)
            if token.value == "token-1" { throw .unauthorized }
            return "done"
        }
        #expect(result == "done")
        #expect(log.all == ["token-1", "token-2"])
        #expect(await provider.refreshCalls == 1)
    }

    @Test func secondUnauthorizedRequiresAuthentication() async {
        let provider = ScriptedTokenProvider(userID: user)
        let gate = TokenGate(provider: provider, userID: user, clock: ManualClock())
        await #expect(throws: AuthorizedCallError.interrupted(.authRequired)) {
            try await gate.perform { _ throws(RemoteError) -> Void in throw .unauthorized }
        }
    }

    @Test func refreshUnavailableIsTreatedAsOffline() async {
        let provider = ScriptedTokenProvider(userID: user)
        await provider.failNextCurrentToken(with: .unavailable)
        let gate = TokenGate(provider: provider, userID: user, clock: ManualClock())
        await #expect(throws: SyncInterruption.offline) { try await gate.token() }
    }

    @Test func rejectedRefreshRequiresAuthentication() async {
        let clock = ManualClock()
        let provider = ScriptedTokenProvider(userID: user, expiresAt: clock.now().date)
        await provider.scriptRefresh([.failure(.refreshRejected)])
        let gate = TokenGate(provider: provider, userID: user, clock: clock)
        await #expect(throws: SyncInterruption.authRequired) { try await gate.token() }
    }

    @Test func tokenOfAnotherUserIsAMismatch() async {
        let provider = ScriptedTokenProvider(userID: UserID("someone-else"))
        let gate = TokenGate(provider: provider, userID: user, clock: ManualClock())
        await #expect(throws: SyncInterruption.authMismatch) { try await gate.token() }
    }

    @Test func otherRemoteErrorsPassThrough() async {
        let gate = TokenGate(provider: ScriptedTokenProvider(userID: user), userID: user, clock: ManualClock())
        await #expect(throws: AuthorizedCallError.remote(.transient(status: 503, retryAfter: nil))) {
            try await gate.perform { _ throws(RemoteError) -> Void in throw .transient(status: 503, retryAfter: nil) }
        }
    }
}
