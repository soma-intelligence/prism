//
//  GlassGuardTests.swift
//  PrismTests
//

import Foundation
import Testing

/// Holds the one way the app draws glass.
///
/// The target builds for visionOS too, and visionOS has no Liquid Glass:
/// `glassEffect` and its container are unavailable there, so a view that calls
/// them directly breaks the headset build while every iPhone build stays green.
/// Glass goes through SomaUI's `somaGlass(_:in:)` and its siblings, which fall
/// back to a material on visionOS.
@Suite("Glass guard")
struct GlassGuardTests {
    static let banned = [
        "glassEffect(",
        "glassEffectID(",
        "glassEffectUnion(",
        "glassEffectTransition(",
        "GlassEffectContainer(",
        ".buttonStyle(.glass)",
        ".buttonStyle(.glassProminent)",
    ]

    @Test("Glass goes through somaGlass, which falls back on visionOS")
    func glassGoesThroughSomaGlass() {
        let sources = StyleGuardTests.root.appendingPathComponent("Prism")
        var hits: [String] = []
        for file in TypographyGuardTests.swiftFiles(under: sources) {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                for pattern in Self.banned where line.contains(pattern) {
                    hits.append("\(StyleGuardTests.relative(file)):\(index + 1) \(pattern)")
                }
            }
        }
        #expect(hits.isEmpty, "glass drawn without somaGlass at: \(hits)")
    }
}
