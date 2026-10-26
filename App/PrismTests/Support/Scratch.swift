//
//  Scratch.swift
//  PrismTests
//

import Foundation
import Testing

/// A folder of its own under the temporary directory, removed when `body`
/// returns, so a store under test never reads or writes the app's files.
func withTemporaryFolder<T>(_ body: (URL) throws -> T) throws -> T {
    let folder = FileManager.default.temporaryDirectory.appending(path: "PrismTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    return try body(folder)
}

/// A defaults domain of its own, so a test never reads or writes the app's.
/// Remove it when done with `defaults.removePersistentDomain(forName: name)`.
func scratchDefaults() throws -> (defaults: UserDefaults, name: String) {
    let name = "PrismTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    return (defaults, name)
}
