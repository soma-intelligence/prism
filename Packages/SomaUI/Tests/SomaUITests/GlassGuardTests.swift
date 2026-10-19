//
//  GlassGuardTests.swift
//  SomaUITests
//

import Foundation
import Testing

/// Holds the one way the package draws glass.
///
/// visionOS has no Liquid Glass: `Glass`, its container and its modifiers are
/// unavailable there, so one component calling them directly stops the whole
/// package from building for the headset, and nothing on an iPhone build says
/// so. Glass goes through `somaGlass(_:in:)` and its siblings instead, and
/// `SomaGlass.swift` is the one file that names the system's own.
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

    /// The file that holds the platform split.
    static let home = "SomaGlass.swift"

    @Test("Glass goes through somaGlass, which falls back on visionOS")
    func glassGoesThroughSomaGlass() {
        let sources = StyleGuardTests.root.appendingPathComponent("Sources")
        var hits: [String] = []
        for file in TypographyGuardTests.swiftFiles(under: sources) where file.lastPathComponent != Self.home {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                for pattern in Self.banned where line.contains(pattern) {
                    hits.append("\(file.lastPathComponent):\(index + 1) \(pattern)")
                }
            }
        }
        #expect(hits.isEmpty, "glass drawn without somaGlass at: \(hits)")
    }
}
