//
//  TypographyGuardTests.swift
//  SomaUITests
//

import Foundation
import Testing

/// Holds the type rules in the package's own sources.
///
/// A role is a font and its tracking, so a role reaches the screen through
/// `somaFont(_:)`: a call site that sets the font alone drops the tracking,
/// which is how every page title lost its own, and one that sets the tracking
/// by hand is a second place for the two to drift apart. And no call site names
/// a font design: SF Pro is the only family, and a design written at a call
/// site is a second family that never went through `SomaFontFamily`.
@Suite("Type guard")
struct TypographyGuardTests {
    static let banned = [
        ".font(theme.typography.",
        ".kerning(theme.typography.",
        ".tracking(theme.typography.",
        "design: .rounded",
        "design: .monospaced",
        "design: .serif",
    ]

    @Test("Roles go through somaFont, and no call site picks a design")
    func rolesAndDesigns() {
        let sources = StyleGuardTests.root.appendingPathComponent("Sources")
        var hits: [String] = []
        for file in Self.swiftFiles(under: sources) {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                for pattern in Self.banned where line.contains(pattern) {
                    hits.append("\(file.lastPathComponent):\(index + 1) \(pattern)")
                }
            }
        }
        #expect(hits.isEmpty, "type rule broken at: \(hits)")
    }

    static func swiftFiles(under root: URL) -> [URL] {
        guard let walker = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var found: [URL] = []
        for case let url as URL in walker where url.pathExtension == "swift" {
            found.append(url)
        }
        return found
    }
}
