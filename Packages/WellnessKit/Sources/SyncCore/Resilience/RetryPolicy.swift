import Foundation

/// What to do after a remote failure.
public enum FailureDisposition: Sendable, Hashable {
    case retryLater(Duration)
    case waitForNetwork
    case reauthenticate
    case freeze(reason: String)
    case restartFromScratch
    case stop
}

public struct RetryPolicy: Sendable, Hashable {
    public var baseDelay: Duration
    public var multiplier: Int
    public var maximumDelay: Duration
    public var malformedResponseAttempts: Int
    public var breakerThreshold: Int

    public init(
        baseDelay: Duration = .seconds(2),
        multiplier: Int = 2,
        maximumDelay: Duration = .seconds(1_800),
        malformedResponseAttempts: Int = 3,
        breakerThreshold: Int = 5
    ) {
        self.baseDelay = baseDelay
        self.multiplier = multiplier
        self.maximumDelay = maximumDelay
        self.malformedResponseAttempts = malformedResponseAttempts
        self.breakerThreshold = breakerThreshold
    }

    public static let standard = RetryPolicy()

    /// Full jitter: uniform between zero and `min(maximumDelay, baseDelay * multiplier^(attempt-1))`,
    /// replaced by `retryAfter` when the server asked for longer.
    public func delay(forAttempt attempt: Int, retryAfter: Duration?, random: any RandomSource) -> Duration {
        var ceiling = baseDelay
        var step = 1
        while step < attempt, ceiling < maximumDelay {
            ceiling = ceiling * multiplier
            step += 1
        }
        if ceiling > maximumDelay { ceiling = maximumDelay }
        let jittered = Duration.milliseconds(Int64(Double(ceiling.wholeMilliseconds) * random.unitInterval()))
        if let retryAfter, retryAfter > jittered { return retryAfter }
        return jittered
    }

    public func disposition(for error: RemoteError, attempt: Int, random: any RandomSource) -> FailureDisposition {
        switch error {
        case .offline:
            return .waitForNetwork
        case .timeout:
            return .retryLater(delay(forAttempt: attempt, retryAfter: nil, random: random))
        case .transient(_, let retryAfter):
            return .retryLater(delay(forAttempt: attempt, retryAfter: retryAfter, random: random))
        case .unauthorized:
            return .reauthenticate
        case .forbidden:
            return .freeze(reason: "forbidden")
        case .rejected(let status, let reason):
            return .freeze(reason: "\(status): \(reason)")
        case .cursorExpired:
            return .restartFromScratch
        case .malformedResponse(let detail):
            if attempt >= malformedResponseAttempts {
                return .freeze(reason: "malformed response: \(detail)")
            }
            return .retryLater(delay(forAttempt: attempt, retryAfter: nil, random: random))
        case .cancelled:
            return .stop
        }
    }
}

extension RemoteError {
    /// Failures that suggest the remote itself is unwell.
    public var countsTowardBreaker: Bool {
        switch self {
        case .timeout, .transient, .malformedResponse: return true
        case .offline, .unauthorized, .forbidden, .rejected, .cursorExpired, .cancelled: return false
        }
    }
}

/// Stops hammering a remote after consecutive transient failures.
public struct CircuitBreaker: Sendable, Hashable {
    public let threshold: Int
    public private(set) var consecutiveFailures = 0
    public private(set) var openUntil: Instant?

    public init(threshold: Int) {
        self.threshold = threshold
    }

    public mutating func recordSuccess() {
        consecutiveFailures = 0
        openUntil = nil
    }

    public mutating func recordTransientFailure(now: Instant, pause: Duration) {
        consecutiveFailures += 1
        if consecutiveFailures >= threshold {
            openUntil = now.adding(pause)
        }
    }

    public func isOpen(at now: Instant) -> Bool {
        guard let openUntil else { return false }
        return now < openUntil
    }
}
