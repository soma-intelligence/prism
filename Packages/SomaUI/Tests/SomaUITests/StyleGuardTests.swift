//
//  StyleGuardTests.swift
//  SomaUITests
//

import Foundation
import Testing

/// The same writing rule the app enforces, applied to the design system.
///
/// SomaUI writes the strings and the comments that ship inside the app, so the
/// rule has to hold on this side of the package boundary too.
@Suite("Style guard")
struct StyleGuardTests {

    @Test("No em dash or en dash anywhere in the package")
    func noDashPunctuation() throws {
        let emDash = "\u{2014}"
        let enDash = "\u{2013}"

        var hits: [String] = []
        for file in files() {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
            where line.contains(emDash) || line.contains(enDash) {
                hits.append("\(file.lastPathComponent):\(index + 1)")
            }
        }
        #expect(hits.isEmpty, "dash punctuation found at: \(hits)")
    }

    static let root: URL = {
        var url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while url.path != "/" {
            if FileManager.default.fileExists(
                atPath: url.appendingPathComponent("Package.swift").path
            ) { return url }
            url = url.deletingLastPathComponent()
        }
        return url
    }()

    private func files() -> [URL] {
        let extensions: Set<String> = ["swift", "md"]
        guard let walker = FileManager.default.enumerator(
            at: Self.root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var found: [URL] = []
        for case let url as URL in walker {
            if url.lastPathComponent == ".build" {
                walker.skipDescendants()
                continue
            }
            if extensions.contains(url.pathExtension) { found.append(url) }
        }
        return found
    }
}
