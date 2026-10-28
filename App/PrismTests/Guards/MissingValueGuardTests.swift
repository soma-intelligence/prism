//
//  MissingValueGuardTests.swift
//  PrismTests
//

import Foundation
import Testing

/// Holds two design system rules in the app's feature folders, as ratchets.
///
/// A value that was not measured is SomaUI's drawn mark (`SomaNumber`,
/// `SomaMissingValue`, `SomaDurationText`), never a hyphen typed into a
/// string: a hyphen sets thin and low, and beside figures or a unit ("- mg")
/// it reads as a typo. And no eyebrow is set in capitals: the eyebrow role
/// carries the hierarchy, in sentence case.
///
/// Both were everywhere when the design pass of 2026-10-27 began, so a count
/// may fall, never rise. Lower a baseline when a batch lands; zero is the
/// goal. The package holds both at zero in its own guard.
@Suite("Missing value guard")
struct MissingValueGuardTests {
    /// Lines in `Prism/Features` that print a hyphen literal, 2026-10-27.
    static let hyphenBaseline = 13
    /// `.textCase(.uppercase)` in `Prism`, 2026-10-27.
    static let uppercaseBaseline = 2

    /// A hyphen literal that is not a missing value: a sign being read, a
    /// field's placeholder, a comparison with a stored value.
    static let notAValue = [#"hasPrefix("-")"#, #"== "-""#, #"placeholder: "-""#]

    @Test("Hyphens standing for a missing value do not grow")
    func hyphens() {
        let hits = Self.lines(under: "Prism/Features") { line in
            line.contains(#""-""#) && !Self.notAValue.contains { line.contains($0) }
        }
        #expect(hits.count <= Self.hyphenBaseline,
                "\(hits.count) hyphens for missing values, baseline \(Self.hyphenBaseline):\n\(hits.joined(separator: "\n"))")
    }

    @Test("Text set in capitals does not grow")
    func uppercase() {
        let hits = Self.lines(under: "Prism") { $0.contains(".textCase(.uppercase)") }
        #expect(hits.count <= Self.uppercaseBaseline,
                "\(hits.count) uppercase sites, baseline \(Self.uppercaseBaseline):\n\(hits.joined(separator: "\n"))")
    }

    static func lines(under folder: String, where matches: (Substring) -> Bool) -> [String] {
        let root = StyleGuardTests.root.appendingPathComponent(folder)
        var hits: [String] = []
        for file in TypographyGuardTests.swiftFiles(under: root).sorted(by: { $0.path < $1.path }) {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() where matches(line) {
                hits.append("\(StyleGuardTests.relative(file)):\(index + 1)")
            }
        }
        return hits
    }
}
