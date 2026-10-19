//
//  SomaDeepLink.swift
//  Prism
//

import Foundation
import Observation

/// Which of the two daily check-ins a link opens.
nonisolated enum CheckInMoment: String, Codable, Sendable, CaseIterable {
    case morning, evening
}

/// Somewhere in the app a notification, an inbox row or a URL can send a
/// person.
///
/// One enum and one handler (``SomaDeepLinkHandling``) so every way in lands
/// the same way. A link travels inside a notification as its ``url`` string
/// under ``userInfoKey``, which survives a cold start and needs no registered
/// scheme to work.
nonisolated enum SomaDeepLink: Hashable, Codable, Sendable {
    /// The check-in: ``CheckInPresenter`` when it has questions, the quick
    /// check-in sheet otherwise.
    case checkIn(CheckInMoment)
    /// The Sleep readings.
    case sleep
    /// One Health type in the Vault, by HealthKit identifier.
    case vaultMetric(String)
    /// Pulse, on Trends: where the week reads.
    case trends
    /// Pulse, on Today.
    case today
    /// The notification center itself.
    case inbox
    /// One score page, by kind: sleep, recovery, strain or stress. Opened by
    /// the widgets.
    case score(String)
    /// Pulse, on Today, from the vitals widget.
    case vitals
    /// The nutrition page.
    case fuel
    /// Track, on Journal.
    case journal
    /// The mood entry.
    case trackMood
    /// The meal entry.
    case trackMeal
    /// The capture start. Only a debug build with capture compiled in
    /// acts on it.
    case captureStart

    /// The score kinds a link may carry.
    static let scoreKinds: Set<String> = ["sleep", "recovery", "strain", "stress"]

    static let userInfoKey = "soma.link"
    static let scheme = "soma"

    var url: URL {
        let path: String = switch self {
        case .checkIn(let moment): "checkin/\(moment.rawValue)"
        case .sleep: "sleep"
        case .vaultMetric(let identifier): "vault/\(identifier)"
        case .trends: "trends"
        case .today: "today"
        case .inbox: "inbox"
        case .score(let kind): "score/\(kind)"
        case .vitals: "vitals"
        case .fuel: "fuel"
        case .journal: "journal"
        case .trackMood: "track/mood"
        case .trackMeal: "track/meal"
        case .captureStart: "capture/start"
        }
        return URL(string: "\(Self.scheme)://\(path)") ?? URL(filePath: "/")
    }

    init?(url: URL) {
        guard url.scheme == Self.scheme, let host = url.host() else { return nil }
        let rest = url.pathComponents.filter { $0 != "/" }
        switch host {
        case "checkin":
            guard let moment = rest.first.flatMap(CheckInMoment.init(rawValue:)) else { return nil }
            self = .checkIn(moment)
        case "sleep": self = .sleep
        case "vault":
            guard let identifier = rest.first, !identifier.isEmpty else { return nil }
            self = .vaultMetric(identifier)
        case "trends": self = .trends
        case "today": self = .today
        case "inbox": self = .inbox
        case "score":
            guard let kind = rest.first, Self.scoreKinds.contains(kind) else { return nil }
            self = .score(kind)
        case "vitals": self = .vitals
        case "fuel": self = .fuel
        case "journal": self = .journal
        case "track":
            switch rest.first {
            case "mood": self = .trackMood
            case "meal": self = .trackMeal
            default: return nil
            }
        case "capture":
            guard rest.first == "start" else { return nil }
            self = .captureStart
        default: return nil
        }
    }

    init?(string: String?) {
        guard let string, let url = URL(string: string) else { return nil }
        self.init(url: url)
    }

    /// The link a notification carries, read back from its user info.
    init?(userInfo: [AnyHashable: Any]) {
        self.init(string: userInfo[Self.userInfoKey] as? String)
    }
}

/// The one queue every deep link goes through. Whoever opens a link sets
/// ``pending``; the shell's handler takes it and clears it.
@MainActor
@Observable
final class SomaDeepLinkRouter {
    static let shared = SomaDeepLinkRouter()

    var pending: SomaDeepLink?

    func open(_ link: SomaDeepLink) {
        pending = link
    }
}
