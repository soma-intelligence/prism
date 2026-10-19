import Foundation

/// Time as the foundation sees it. Injected everywhere so tests control it.
public protocol SyncClock: Sendable {
    func now() -> Instant
    /// Suspends for `duration`. Throws `CancellationError` when the task is cancelled.
    func sleep(for duration: Duration) async throws
}

public struct SystemClock: SyncClock {
    public init() {}
    public func now() -> Instant { Instant(Date()) }
    public func sleep(for duration: Duration) async throws { try await Task.sleep(for: duration) }
}

/// Randomness used for retry jitter. Injected so tests are deterministic.
public protocol RandomSource: Sendable {
    /// A value in `0..<1`.
    func unitInterval() -> Double
}

public struct SystemRandomSource: RandomSource {
    public init() {}
    public func unitInterval() -> Double { Double.random(in: 0..<1) }
}

/// Produces record identifiers.
public protocol IDGenerator: Sendable {
    func next() -> RecordID
}

/// UUID version 7: 48 bits of Unix milliseconds, then random bits. Lowercase.
public struct UUIDv7Generator: IDGenerator {
    private let clock: any SyncClock

    public init(clock: any SyncClock = SystemClock()) {
        self.clock = clock
    }

    public func next() -> RecordID {
        var generator = SystemRandomNumberGenerator()
        let milliseconds = UInt64(clamping: clock.now().millisecondsSinceEpoch)
        return RecordID(Self.make(milliseconds: milliseconds, random: generator.next(), random2: generator.next()))
    }

    static func make(milliseconds: UInt64, random: UInt64, random2: UInt64) -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        let timestamp = milliseconds & 0xFFFF_FFFF_FFFF
        for index in 0..<6 {
            bytes[index] = UInt8((timestamp >> UInt64(40 - index * 8)) & 0xFF)
        }
        bytes[6] = 0x70 | UInt8((random >> 60) & 0x0F)
        bytes[7] = UInt8((random >> 52) & 0xFF)
        bytes[8] = 0x80 | UInt8((random2 >> 58) & 0x3F)
        for index in 9..<16 {
            bytes[index] = UInt8((random2 >> UInt64(48 - (index - 9) * 8)) & 0xFF)
        }
        let digits = Array("0123456789abcdef")
        var text = ""
        text.reserveCapacity(36)
        for (index, byte) in bytes.enumerated() {
            if index == 4 || index == 6 || index == 8 || index == 10 { text.append("-") }
            text.append(digits[Int(byte >> 4)])
            text.append(digits[Int(byte & 0x0F)])
        }
        return text
    }
}
