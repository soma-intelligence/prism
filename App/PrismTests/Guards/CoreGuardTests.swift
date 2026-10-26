//
//  CoreGuardTests.swift
//  PrismTests
//

import Foundation
import Testing

/// Holds the line between the two halves of the app: `Prism/Core` is the
/// logic, read and tested without a screen; `Prism/Features` and `Prism/App`
/// draw it. A view or a view modifier declared in Core is logic that can only
/// be reached through a screen, which is how it ends up untested.
@Suite("Core guard")
struct CoreGuardTests {
    static let banned = [": View {", ": ViewModifier {"]

    @Test("Core declares no view and no view modifier")
    func coreDrawsNothing() {
        let core = StyleGuardTests.root.appendingPathComponent("Prism/Core")
        var hits: [String] = []
        for file in TypographyGuardTests.swiftFiles(under: core) {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                for pattern in Self.banned where line.contains(pattern) {
                    hits.append("\(StyleGuardTests.relative(file)):\(index + 1)")
                }
            }
        }
        #expect(hits.isEmpty, "views declared in Core at: \(hits)")
    }
}
