import Foundation

/// The account a session belongs to. Opaque to the kits.
public struct UserID: RawRepresentable, Hashable, Sendable, Codable, CustomStringConvertible {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public var description: String { rawValue }
}

/// Identifier of one synced record. UUIDv7 in production, so ids sort by creation time.
public struct RecordID: RawRepresentable, Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public var description: String { rawValue }
    public static func < (lhs: RecordID, rhs: RecordID) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Name of a record type. It is also the local table name, so it is restricted
/// to lowercase letters, digits and underscores, starting with a letter.
public struct RecordType: RawRepresentable, Hashable, Sendable, Codable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        precondition(Self.isValid(rawValue), "invalid record type name: \(rawValue)")
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) { self.init(rawValue: rawValue) }

    public var description: String { rawValue }

    public static func isValid(_ name: String) -> Bool {
        guard let first = name.unicodeScalars.first, ("a"..."z").contains(first) else { return false }
        return name.unicodeScalars.allSatisfy { ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "_" }
    }
}

/// A server-assigned revision. Revisions only grow, across every record type.
public struct Revision: RawRepresentable, Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    public let rawValue: Int64
    public init(rawValue: Int64) { self.rawValue = rawValue }
    public init(_ rawValue: Int64) { self.rawValue = rawValue }
    public var description: String { String(rawValue) }
    public static func < (lhs: Revision, rhs: Revision) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// A point in time with millisecond precision, as stored in the database.
public struct Instant: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    public let millisecondsSinceEpoch: Int64

    public init(millisecondsSinceEpoch: Int64) { self.millisecondsSinceEpoch = millisecondsSinceEpoch }

    public init(_ date: Date) {
        self.millisecondsSinceEpoch = Int64((date.timeIntervalSince1970 * 1000).rounded())
    }

    public var date: Date { Date(timeIntervalSince1970: Double(millisecondsSinceEpoch) / 1000) }

    public func adding(_ duration: Duration) -> Instant {
        Instant(millisecondsSinceEpoch: millisecondsSinceEpoch + duration.wholeMilliseconds)
    }

    public var description: String { String(millisecondsSinceEpoch) }

    public static func < (lhs: Instant, rhs: Instant) -> Bool {
        lhs.millisecondsSinceEpoch < rhs.millisecondsSinceEpoch
    }

    public static func - (lhs: Instant, rhs: Instant) -> Duration {
        .milliseconds(lhs.millisecondsSinceEpoch - rhs.millisecondsSinceEpoch)
    }
}

extension Duration {
    /// The duration in whole milliseconds, truncated toward zero.
    public var wholeMilliseconds: Int64 {
        let parts = components
        return parts.seconds * 1000 + parts.attoseconds / 1_000_000_000_000_000
    }

    /// The duration in seconds as a floating point number.
    public var timeInterval: TimeInterval {
        let parts = components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
    }
}
