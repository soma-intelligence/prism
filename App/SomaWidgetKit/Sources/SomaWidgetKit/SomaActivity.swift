import Foundation
#if canImport(ActivityKit) && os(iOS)
import ActivityKit
#endif

/// The moments Soma shows as a Live Activity, on the lock screen and in the
/// Dynamic Island.
public enum SomaActivityKind: String, Codable, CaseIterable, Hashable, Sendable {
    /// Counting down to lights out, started from the Sleep page.
    case windDown
    /// A nap, counting down to the wake up.
    case nap
    /// The cardio fitness test, counting up with distance and heart rate.
    case cardioTest
    /// A meeting that could run tense, counting down to its start.
    case meeting

    /// The glyph the activity wears everywhere it shows.
    public var symbol: String {
        switch self {
        case .windDown: "moon.stars.fill"
        case .nap: "powersleep"
        case .cardioTest: "figure.walk"
        case .meeting: "person.2.fill"
        }
    }
}

/// What an activity shows at a moment. Words are written by the app, in the
/// app's language, so the extension only lays them out.
public struct SomaActivityContent: Codable, Hashable, Sendable {
    /// The activity's name: "Lights out", "Nap", "6 minute walk".
    public var title: String
    /// One line under it: "Wake at 06:40", "Board review at 14:00".
    public var detail: String?
    /// When the clock started.
    public var start: Date
    /// What the clock counts down to; nil counts up from `start`.
    public var end: Date?
    /// A reading beside the clock: "420 m", "112 bpm".
    public var value: String?
    /// What the reading is: "Distance", "Heart rate".
    public var valueLabel: String?
    /// A second reading, set smaller.
    public var secondary: String?
    /// True when the moment asks for attention: the test's slow down call.
    public var alert: Bool
    /// Set once the moment is over: the clock stops on this many seconds.
    public var stoppedAt: TimeInterval?

    public init(title: String, detail: String? = nil, start: Date, end: Date? = nil, value: String? = nil,
                valueLabel: String? = nil, secondary: String? = nil, alert: Bool = false, stoppedAt: TimeInterval? = nil) {
        self.stoppedAt = stoppedAt
        self.title = title
        self.detail = detail
        self.start = start
        self.end = end
        self.value = value
        self.valueLabel = valueLabel
        self.secondary = secondary
        self.alert = alert
    }

    /// Whether the clock counts down.
    public var countsDown: Bool { end != nil }

    /// A stopped clock as it reads: "6:00", "1:02:05".
    public static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds).rounded())
        let hours = total / 3600, minutes = (total % 3600) / 60, rest = total % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, rest) : String(format: "%d:%02d", minutes, rest)
    }

    /// How far through a countdown `now` sits, 0 to 1; nil when counting up.
    public func progress(at now: Date) -> Double? {
        guard let end else { return nil }
        let span = end.timeIntervalSince(start)
        guard span > 0 else { return 1 }
        return min(1, max(0, now.timeIntervalSince(start) / span))
    }
}

#if canImport(ActivityKit) && os(iOS)
/// The one attributes type every Soma Live Activity uses: the kind is fixed
/// for the activity's life, the content moves.
public struct SomaActivityAttributes: ActivityAttributes {
    public typealias ContentState = SomaActivityContent

    public var kind: SomaActivityKind

    public init(kind: SomaActivityKind) {
        self.kind = kind
    }
}
#endif
