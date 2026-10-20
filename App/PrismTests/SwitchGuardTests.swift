//
//  SwitchGuardTests.swift
//  PrismTests
//

import Foundation
import Testing

/// Holds the switches to Soma's own: a plain `Toggle` takes the accent as its
/// tint, which is near white in dark mode, and drew white on white in Tools,
/// Track's customize list and the bedroom sheet (found 2026-10-20). Every
/// toggle on a page is drawn as `SomaSwitch`, through `.toggleStyle(.soma)`.
@Suite("Switch guard")
struct SwitchGuardTests {
    /// Files allowed a plain toggle, and why.
    static let allowed: [String: String] = [
        "CustomizationPage.swift": "a toggle inside a Menu is drawn by the menu as a checkmark row",
    ]

    @Test("Every toggle on a page is drawn as the Soma switch")
    func togglesUseTheSomaSwitch() {
        let features = StyleGuardTests.root.appendingPathComponent("Prism/Features")
        let files = TypographyGuardTests.swiftFiles(under: features)
            .filter { !$0.path.contains("/Features/Dev/") && Self.allowed[$0.lastPathComponent] == nil }
        #expect(files.count > 100, "the guard found the sources")
        var plain: [String] = []
        for file in files {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            for (index, line) in lines.enumerated() where line.contains("Toggle(") {
                if line.trimmingCharacters(in: .whitespaces).hasPrefix("//") { continue }
                let following = lines[index..<min(lines.count, index + 24)].joined(separator: "\n")
                if !following.contains(".toggleStyle(.soma)") {
                    plain.append("\(file.lastPathComponent):\(index + 1)")
                }
            }
        }
        #expect(plain.isEmpty, "a plain toggle at: \(plain)")
    }
}
