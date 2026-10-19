//
//  StyleGuardTests.swift
//  PrismTests
//

import Foundation
import Testing

/// Enforces the writing rules in the agent guide.
///
/// A rule that lives only in a document is a rule that drifts. These walk the
/// repository so a dash cannot reach a commit, whoever or whatever wrote it.
@Suite("Style guard")
struct StyleGuardTests {

    @Test("No em dash or en dash anywhere in the repository")
    func noDashPunctuation() throws {
        // Written as escapes so this file does not trip its own rule.
        let emDash = "\u{2014}"
        let enDash = "\u{2013}"

        var hits: [String] = []
        for file in try Self.trackedFiles() {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
            where line.contains(emDash) || line.contains(enDash) {
                hits.append("\(Self.relative(file)):\(index + 1)")
            }
        }
        #expect(hits.isEmpty, "dash punctuation found at: \(hits)")
    }

    @Test("No hyphen standing in for a dash, in prose")
    func noHyphenAsPunctuation() throws {
        // A hyphen between two spaces, with a word on each side.
        //
        // Prose only, which means comments and Markdown. Code is exempt because
        // subtracting one offset from another is arithmetic, not a sentence,
        // and a rule that cannot tell the two apart would ban the minus sign.
        // Hyphens inside a word are untouched everywhere: they are kebab-case,
        // flags and identifiers, which the rule allows.
        let pattern = try NSRegularExpression(pattern: "[a-zA-Z,\\)] - [a-z]")

        var hits: [String] = []
        for file in try Self.trackedFiles() {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            let isMarkdown = file.pathExtension == "md"
            var insideFence = false

            for (index, rawLine) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let line = String(rawLine)
                if line.hasPrefix("```") { insideFence.toggle(); continue }
                guard !insideFence else { continue }

                guard let prose = Self.prose(of: line, isMarkdown: isMarkdown) else { continue }
                let range = NSRange(prose.startIndex..., in: prose)
                if pattern.firstMatch(in: prose, range: range) != nil {
                    hits.append("\(Self.relative(file)):\(index + 1)")
                }
            }
        }
        #expect(hits.isEmpty, "hyphen used as punctuation at: \(hits)")
    }

    /// The part of a line a person reads as a sentence, or nil when there is
    /// none. In Markdown that is the whole line; in source it is what follows a
    /// comment marker.
    static func prose(of line: String, isMarkdown: Bool) -> String? {
        if isMarkdown { return line }
        guard let marker = line.range(of: "//") else { return nil }
        return String(line[marker.upperBound...])
    }

    @Test("The agent guide exists and states the rule")
    func ruleIsWrittenDown() throws {
        let guide = try #require(Self.rulesFile, "no agent guide beside the project or one folder up")
        let text = try String(contentsOf: guide, encoding: .utf8)
        #expect(text.contains("Writing rules"))
        #expect(text.contains("StyleGuardTests"))
    }

    /// The file names the agent guide may have, in the order they are tried.
    /// The public export rewrites this line to `AGENTS.md` alone.
    static let guideNames = ["AGENTS.md"]

    /// Where the rules are written: beside the Xcode project here, one folder
    /// up in the public repository, where the project sits in `App/`. Never
    /// further, so a stray file above the repository cannot stand in for it.
    static var rulesFile: URL? {
        [root, root.deletingLastPathComponent()]
            .flatMap { folder in guideNames.map { folder.appendingPathComponent($0) } }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    // MARK: - Walking the repository

    /// The repository root, found by walking up from this file to the directory
    /// holding the Xcode project.
    static let root: URL = {
        var url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while url.path != "/" {
            let project = url.appendingPathComponent("Prism.xcodeproj")
            if FileManager.default.fileExists(atPath: project.path) { return url }
            url = url.deletingLastPathComponent()
        }
        return URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    }()

    static func relative(_ file: URL) -> String {
        file.path.replacingOccurrences(of: root.path + "/", with: "")
    }

    /// Every file the rule applies to: what a person reads or writes.
    static func trackedFiles() throws -> [URL] {
        let extensions: Set<String> = ["swift", "md", "entitlements", "json", "yml", "yaml"]
        let skipped: Set<String> = [".build", "DerivedData", ".git", "Prism.xcodeproj"]

        guard let walker = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var files: [URL] = []
        for case let url as URL in walker {
            if skipped.contains(url.lastPathComponent) {
                walker.skipDescendants()
                continue
            }
            if extensions.contains(url.pathExtension) { files.append(url) }
        }
        return files
    }
}
