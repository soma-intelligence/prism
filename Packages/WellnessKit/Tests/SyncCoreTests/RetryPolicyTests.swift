import Foundation
import Testing
import SyncCore
import SyncTesting

@Suite struct RetryPolicyTests {
    let policy = RetryPolicy.standard
    let half = FixedRandom(0.5)

    @Test func delayIsFullJitterUnderAnExponentialCeiling() {
        #expect(policy.delay(forAttempt: 1, retryAfter: nil, random: half) == .milliseconds(1_000))
        #expect(policy.delay(forAttempt: 2, retryAfter: nil, random: half) == .milliseconds(2_000))
        #expect(policy.delay(forAttempt: 3, retryAfter: nil, random: half) == .milliseconds(4_000))
        #expect(policy.delay(forAttempt: 40, retryAfter: nil, random: half) == .milliseconds(900_000))
        #expect(policy.delay(forAttempt: 1, retryAfter: nil, random: FixedRandom(0)) == .zero)
    }

    @Test func retryAfterWinsOnlyWhenLonger() {
        #expect(policy.delay(forAttempt: 1, retryAfter: .seconds(60), random: half) == .seconds(60))
        #expect(policy.delay(forAttempt: 1, retryAfter: .milliseconds(100), random: half) == .milliseconds(1_000))
    }

    @Test func everyErrorHasOneDisposition() {
        #expect(policy.disposition(for: .offline, attempt: 1, random: half) == .waitForNetwork)
        #expect(policy.disposition(for: .timeout, attempt: 1, random: half) == .retryLater(.milliseconds(1_000)))
        #expect(policy.disposition(for: .transient(status: 503, retryAfter: nil), attempt: 2, random: half) == .retryLater(.milliseconds(2_000)))
        #expect(policy.disposition(for: .unauthorized, attempt: 1, random: half) == .reauthenticate)
        #expect(policy.disposition(for: .forbidden, attempt: 1, random: half) == .freeze(reason: "forbidden"))
        #expect(policy.disposition(for: .rejected(status: 422, reason: "bad"), attempt: 1, random: half) == .freeze(reason: "422: bad"))
        #expect(policy.disposition(for: .cursorExpired, attempt: 1, random: half) == .restartFromScratch)
        #expect(policy.disposition(for: .cancelled, attempt: 1, random: half) == .stop)
        #expect(policy.disposition(for: .malformedResponse("x"), attempt: 2, random: half) == .retryLater(.milliseconds(2_000)))
        #expect(policy.disposition(for: .malformedResponse("x"), attempt: 3, random: half) == .freeze(reason: "malformed response: x"))
    }

    @Test func onlyServerAndTransportFailuresCountTowardTheBreaker() {
        #expect(RemoteError.timeout.countsTowardBreaker)
        #expect(RemoteError.transient(status: 500, retryAfter: nil).countsTowardBreaker)
        #expect(RemoteError.malformedResponse("x").countsTowardBreaker)
        #expect(!RemoteError.offline.countsTowardBreaker)
        #expect(!RemoteError.unauthorized.countsTowardBreaker)
        #expect(!RemoteError.rejected(status: 400, reason: "").countsTowardBreaker)
    }

    @Test func breakerOpensAtThresholdAndClosesOnSuccess() {
        var breaker = CircuitBreaker(threshold: 3)
        let now = Instant(millisecondsSinceEpoch: 10_000)
        breaker.recordTransientFailure(now: now, pause: .seconds(30))
        breaker.recordTransientFailure(now: now, pause: .seconds(30))
        #expect(!breaker.isOpen(at: now))
        breaker.recordTransientFailure(now: now, pause: .seconds(30))
        #expect(breaker.isOpen(at: now.adding(.seconds(29))))
        #expect(!breaker.isOpen(at: now.adding(.seconds(30))))
        breaker.recordSuccess()
        #expect(breaker.consecutiveFailures == 0)
        #expect(breaker.openUntil == nil)
    }
}
