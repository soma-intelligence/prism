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

    /// For a file the app reads while the phone is locked: a sleep visit
    /// wakes the app in the background, often at night, and a file under
    /// complete protection reads as nothing then. Still encrypted until the
    /// first unlock after a restart.
    static var backgroundReadableAtomicOptions: Data.WritingOptions {
#if os(macOS)
        .atomic
#else
        [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
#endif
    }

    /// Moves a file written under complete protection to the class of
    /// ``backgroundReadableAtomicOptions``, so the next locked wake reads it
    /// without waiting for a save.
    static func allowBackgroundReads(at url: URL?) {
#if !os(macOS)
        guard let url else { return }
        try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                                               ofItemAtPath: url.path())
#endif
    }

    /// What reading a store's file gave.
    enum Read<Value> {
        /// No file: a first launch, or erased.
        case missing
        /// The file is there but could not be read, most often because the
        /// phone is locked. Saving over it would lose what it holds.
        case unreadable
        case loaded(Value)
    }

    /// Reads and decodes `url`. A file that is present but fails to read is
    /// ``Read/unreadable``; one that reads but fails to decode is treated as
    /// missing, since nothing in it could ever be used.
    static func read<Value: Decodable>(_ type: Value.Type, at url: URL?) -> Read<Value> {
        guard let url else { return .missing }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            return FileManager.default.fileExists(atPath: url.path()) ? .unreadable : .missing
        }
        guard let value = try? JSONDecoder().decode(type, from: data) else { return .missing }
        return .loaded(value)
    }
}
