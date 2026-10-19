//
//  SupabaseSettings.swift
//  Prism
//

import Foundation
import SyncSupabase

/// Where the app's own Supabase project is, read at runtime. Never written in
/// source.
///
/// The app's project is `qnysyehawitnlcnccyop`, not the website's. The values
/// come from the Info.plist keys `SomaSupabaseURL` and
/// `SomaSupabasePublishableKey`, which `Prism-Info.plist` fills from the build
/// settings `SOMA_SUPABASE_URL` and `SOMA_SUPABASE_PUBLISHABLE_KEY`, set in
/// `Config/Supabase.xcconfig` (git ignored; copy `Supabase.example.xcconfig`).
/// A development run can pass the same two names as scheme environment
/// variables instead. The Explore library reads the same pair
/// (`ArticleBackend`), so one setting serves both.
///
/// Without both values there is no account: sign in says so, and everything
/// stays on the phone as before.
nonisolated struct SupabaseSettings: Equatable, Sendable {
    var projectURL: URL
    var publishableKey: String

    static let infoURLKey = "SomaSupabaseURL"
    static let infoKeyKey = "SomaSupabasePublishableKey"
    static let environmentURLKey = "SOMA_SUPABASE_URL"
    static let environmentKeyKey = "SOMA_SUPABASE_PUBLISHABLE_KEY"

    /// This build's project, or nil when it was built without one.
    static var current: SupabaseSettings? {
        resolve(info: Bundle.main.infoDictionary ?? [:], environment: ProcessInfo.processInfo.environment)
    }

    /// Info.plist first, then the environment. A value still holding an
    /// unexpanded build setting counts as absent, and so does an address that
    /// is not https.
    static func resolve(info: [String: Any], environment: [String: String]) -> SupabaseSettings? {
        func clean(_ value: Any?) -> String? {
            guard let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty, !text.contains("$(") else { return nil }
            return text
        }
        guard let address = clean(info[infoURLKey]) ?? clean(environment[environmentURLKey]),
              let key = clean(info[infoKeyKey]) ?? clean(environment[environmentKeyKey]),
              let url = URL(string: address), url.scheme == "https", url.host() != nil
        else { return nil }
        return SupabaseSettings(projectURL: url, publishableKey: key)
    }

    /// The adapter's configuration. The bucket is the upload journal's: data
    /// exports and bulk files.
    var configuration: SupabaseConfiguration {
        SupabaseConfiguration(projectURL: projectURL, publishableKey: publishableKey, storageBucket: StoragePath.healthUploadsBucket)
    }
}
