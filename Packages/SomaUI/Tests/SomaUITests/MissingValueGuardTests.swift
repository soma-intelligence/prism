//
//  MissingValueGuardTests.swift
//  SomaUITests
//

import Foundation
import Testing

/// Holds two of the system's own rules in the package's components.
///
/// A value that was not measured is ``SomaMissingValue`` (through
/// ``SomaNumber`` or ``SomaDurationText``), never a hyphen typed into a
/// string: a hyphen sets thin and low, beside figures or a unit it reads as a
/// typo, and one screen ended up drawing one absence three ways. And an
/// eyebrow is never set in capitals: the eyebrow role carries the hierarchy.
@Suite("Missing value guard")
struct MissingValueGuardTests {
    /// A hyphen printed where a value would be.
    static let hyphens = [
        #"?? "-""#,
        #"Text("-")"#,
        #"Text(verbatim: "-")"#,
        #"return "-""#,
        #"else { "-" }"#,
    ]

    /// Lines allowed to keep a hyphen, by file and fragment, each with its
    /// reason.
    static let allowed: [(file: String, contains: String, reason: String)] = [
        ("SomaScoreDialParts.swift", #"Text(figure ?? "-")"#,
         "Today's Zones dial rolls in from a dash; the owner keeps Zones as they are (2026-10-27)."),
    ]

    @Test("No component prints a hyphen for a missing value")
    func noHyphens() {
        let hits = Self.scan(Self.hyphens)
        #expect(hits.isEmpty, "a hyphen stands for a missing value at: \(hits)")
    }

    @Test("No component sets text in capitals")
    func noUppercase() {
        let hits = Self.scan([".textCase(.uppercase)"])
        #expect(hits.isEmpty, "capitals set at: \(hits)")
    }

    static func scan(_ patterns: [String]) -> [String] {
        let components = StyleGuardTests.root.appendingPathComponent("Sources/SomaUI/Components")
        var hits: [String] = []
        for file in TypographyGuardTests.swiftFiles(under: components) {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                for pattern in patterns where line.contains(pattern) {
                    let excused = allowed.contains { file.lastPathComponent == $0.file && line.contains($0.contains) }
                    if !excused { hits.append("\(file.lastPathComponent):\(index + 1)") }
                }
            }
        }
        return hits
    }
}
