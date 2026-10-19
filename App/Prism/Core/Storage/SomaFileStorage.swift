//
//  SomaFileStorage.swift
//  Prism
//

import Foundation

/// Atomic writes for the app's local JSON stores. File protection is kept
/// on iOS and visionOS; macOS rejects that writing option.
nonisolated enum SomaFileStorage {
    static var protectedAtomicOptions: Data.WritingOptions {
#if os(macOS)
        .atomic
#else
        [.atomic, .completeFileProtection]
#endif
    }
}
