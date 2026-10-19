import Foundation

/// The four scores a widget can open.
public enum ScoreKind: String, Codable, CaseIterable, Sendable {
    case sleep, recovery, strain, stress
}

/// Where a tap on a widget lands. The URL strings are the contract with the
/// app: Prism parses them in its own `SomaDeepLink`, and tests on both sides
/// pin the same strings.
public enum WidgetLink: Equatable, Sendable {
    case score(ScoreKind)
    case vitals
    case fuel
    case journal
    case mood
    case meal
    case captureStart

    public var url: URL {
        let path: String = switch self {
        case .score(let kind): "score/\(kind.rawValue)"
        case .vitals: "vitals"
        case .fuel: "fuel"
        case .journal: "journal"
        case .mood: "track/mood"
        case .meal: "track/meal"
        case .captureStart: "capture/start"
        }
        return URL(string: "soma://\(path)") ?? URL(filePath: "/")
    }
}
