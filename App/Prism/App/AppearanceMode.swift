//
//  AppearanceMode.swift
//  Prism
//

import SwiftUI

/// Whether the app follows the phone between light and dark, or holds one.
///
/// Stored by name rather than as a colour scheme: the name is an identifier
/// that must never change once something has been written with it, and the
/// title is copy that may.
enum AppearanceMode: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    /// Where the choice lives in user defaults.
    static let storageKey = "appearance.mode"

    /// What a fresh install draws, and what a name that no longer reads falls
    /// back to.
    static let fallback: AppearanceMode = .system

    var id: String { rawValue }

    /// The scheme to force, or nil to follow the system.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    /// What a person picking one reads.
    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// Resolves a name read back out of storage, or nil when it names nothing.
    ///
    /// Nil rather than a default, so the caller decides what an unreadable
    /// setting means.
    init?(storedName: String) {
        self.init(rawValue: storedName)
    }
}
