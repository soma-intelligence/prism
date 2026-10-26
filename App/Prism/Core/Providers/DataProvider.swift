//
//  DataProvider.swift
//  Prism
//

import Foundation
import SomaUI

/// The one switch for every direct provider: a client id per vendor, set
/// once Soma is registered with them. Nil keeps the provider's button on
/// "Soon", disabled.
///
/// The token exchange of Whoop and Withings needs the client secret, which
/// never ships in the app: ``tokenRelay`` names the Soma endpoint that holds
/// it and forwards the exchange. Oura takes the code with PKCE alone.
nonisolated enum ProviderConfig {
    static let clientIDs: [String: String] = [:]
    static let tokenRelay: URL? = nil
    /// Where each vendor sends the person back: `soma://oauth/<provider>`.
    static let callbackScheme = "soma"

    static func redirectURI(for providerID: String) -> String {
        "\(callbackScheme)://oauth/\(providerID)"
    }
}

/// How a direct provider signs in: OAuth 2 authorization code, PKCE where the
/// vendor supports it. Endpoints checked against each vendor's own developer
/// documentation on 2026-10-03.
nonisolated struct OAuthConfig: Sendable, Equatable {
    nonisolated enum TokenStyle: Sendable, Equatable {
        /// RFC 6749: a form post, a JSON body back.
        case standard
        /// Withings: `action=requesttoken` in the form, the token inside
        /// `body` of the response.
        case withings
    }

    var authorizeURL: URL
    var tokenURL: URL
    var scopes: [String]
    var scopeSeparator = " "
    var usesPKCE = true
    /// Whoop wants exactly eight characters of state.
    var stateLength = 32
    var tokenStyle: TokenStyle = .standard
}

/// A source of data Soma reads, and how it reaches Soma.
nonisolated struct DataProvider: Identifiable, Sendable, Equatable {
    nonisolated enum Access: Sendable, Equatable {
        /// Apple Health itself.
        case appleHealth
        /// The iPhone's own step counter, through Core Motion.
        case phoneMotion
        /// Syncs into Apple Health, so Soma reads it there.
        case throughHealth
        /// Its own sign in, then its own API.
        case direct(OAuthConfig)
        /// Nothing yet.
        case soon
    }

    var id: String
    var name: String
    var symbol: String
    var access: Access
    /// The provider's slug on Open Health Sync, when the instance can sign in
    /// to it for Soma. With an account, the provider connects there instead of
    /// through ``access``: no client secret in Soma, and the instance pulls the
    /// data on its own schedule.
    var ohsSlug: String? = nil

    var oauth: OAuthConfig? {
        if case .direct(let config) = access { return config }
        return nil
    }

    var clientID: String? { ProviderConfig.clientIDs[id] }

    /// Whether the Connect button can do anything in this build.
    var canConnect: Bool { oauth != nil && clientID != nil }

    /// Whether Open Health Sync can connect it.
    var connectsThroughOHS: Bool { ohsSlug != nil }
}

extension DataProvider {
    private static func url(_ string: String) -> URL { URL(string: string) ?? URL(filePath: "/") }

    static let appleHealth = DataProvider(id: "apple-health", name: "Apple Health", symbol: "heart", access: .appleHealth)
    static let iPhoneMotion = DataProvider(id: "iphone-motion", name: "iPhone motion", symbol: "figure.walk", access: .phoneMotion)
    static let appleWatch = DataProvider(id: "apple-watch", name: "Apple Watch", symbol: "applewatch", access: .throughHealth)

    static let withings = DataProvider(
        id: "withings", name: "Withings", symbol: "scalemass",
        access: .direct(OAuthConfig(
            authorizeURL: url("https://account.withings.com/oauth2_user/authorize2"),
            tokenURL: url("https://wbsapi.withings.net/v2/oauth2"),
            scopes: ["user.info", "user.metrics", "user.activity"],
            scopeSeparator: ",", usesPKCE: false, tokenStyle: .withings
        )),
        ohsSlug: "withings"
    )
    static let oura = DataProvider(
        id: "oura", name: "Oura", symbol: "circle.circle",
        access: .direct(OAuthConfig(
            authorizeURL: url("https://cloud.ouraring.com/oauth/authorize"),
            tokenURL: url("https://api.ouraring.com/oauth/token"),
            scopes: ["personal", "daily", "heartrate", "workout", "session", "spo2"]
        )),
        ohsSlug: "oura"
    )
    static let whoop = DataProvider(
        id: "whoop", name: "Whoop", symbol: "bolt.heart",
        access: .direct(OAuthConfig(
            authorizeURL: url("https://api.prod.whoop.com/oauth/oauth2/auth"),
            tokenURL: url("https://api.prod.whoop.com/oauth/oauth2/token"),
            scopes: ["offline", "read:recovery", "read:cycles", "read:sleep", "read:workout", "read:profile", "read:body_measurement"],
            usesPKCE: false, stateLength: 8
        )),
        ohsSlug: "whoop"
    )

    /// Every provider the Health access page lists, in its order: Apple's
    /// three, the three direct ones, then the rest.
    static let all: [DataProvider] = [
        appleHealth, iPhoneMotion, appleWatch,
        withings, oura, whoop,
        DataProvider(id: "ultrahuman", name: "Ultrahuman", symbol: "circle.dashed", access: .throughHealth, ohsSlug: "ultrahuman"),
        DataProvider(id: "garmin", name: "Garmin", symbol: "location.north.circle", access: .throughHealth, ohsSlug: "garmin"),
        DataProvider(id: "polar", name: "Polar", symbol: "heart.circle", access: .throughHealth, ohsSlug: "polar"),
        DataProvider(id: "fitbit", name: "Fitbit", symbol: "square.grid.3x3", access: .soon, ohsSlug: "fitbit"),
        DataProvider(id: "eight-sleep", name: "Eight Sleep", symbol: "bed.double", access: .throughHealth, ohsSlug: "eight_sleep"),
        DataProvider(id: "dexcom", name: "Dexcom", symbol: "drop", access: .throughHealth, ohsSlug: "dexcom"),
        DataProvider(id: "levels", name: "Levels", symbol: "chart.line.uptrend.xyaxis", access: .soon),
        DataProvider(id: "strava", name: "Strava", symbol: "figure.run", access: .throughHealth, ohsSlug: "strava"),
        DataProvider(id: "myfitnesspal", name: "MyFitnessPal", symbol: "fork.knife", access: .throughHealth),
    ]
}
