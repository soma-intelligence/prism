//
//  HorizontalScrollGuardTests.swift
//  PrismTests
//

import Foundation
import Testing

/// Holds the owner's rule: a page never moves sideways.
///
/// Two ways it used to: a row that scrolls sideways (shelves, chip rows,
/// rails), and a vertical page whose column ran a fraction of a point wider
/// than the screen, which a finger could then drag across. Rows wrap or sit
/// in a grid instead (`SomaFlowLayout`, `LazyVGrid`), and every page scrolls
/// through SomaUI's `SomaPageScroll`, which holds its column to the screen's
/// width.
@Suite("Horizontal scroll guard")
struct HorizontalScrollGuardTests {
    /// A scroll view given the horizontal axis, alone or with the vertical.
    static let horizontal = try! NSRegularExpression(
        pattern: #"ScrollView\s*\(\s*(axes:\s*)?(\.horizontal|\[[^\]]*\.horizontal)"#
    )
    /// A plain vertical `ScrollView`, which lets an over wide column pan.
    static let bare = try! NSRegularExpression(
        pattern: #"(^|[^A-Za-z.])ScrollView\s*(\{|\(\s*(\.vertical|showsIndicators))"#
    )

    /// Files allowed a horizontal scroll view, and why. Empty: nothing on a
    /// page needs one. The developer capture surface under `Features/Dev` is
    /// not a page a person sees and is left out below.
    static let allowed: [String: String] = [
        // A chart's periods: one whole week, month or year a page, swiped like
        // the pages of a book. The page itself never moves sideways.
        "SomaPeriodPager.swift": "a chart pages whole periods",
    ]

    private static var sources: [URL] {
        let root = StyleGuardTests.root
        let features = root.appendingPathComponent("Prism/Features")
        // SomaUI sits beside the app here, and under Packages in the public
        // repository.
        let somaUI = ["SomaUI", "Packages/SomaUI"]
            .map { root.deletingLastPathComponent().appendingPathComponent("\($0)/Sources/SomaUI") }
            .flatMap(TypographyGuardTests.swiftFiles(under:))
        return (TypographyGuardTests.swiftFiles(under: features) + somaUI)
            .filter { !$0.path.contains("/Features/Dev/") }
    }

    /// The lines a guard reads: the whole file in the app, and in SomaUI only
    /// what sits above the first `#Preview` (a preview may scroll as it likes).
    private static func lines(of file: URL) -> [Substring] {
        guard var text = try? String(contentsOf: file, encoding: .utf8) else { return [] }
        if file.path.contains("/SomaUI/Sources/"), let preview = text.range(of: "#Preview") {
            text = String(text[..<preview.lowerBound])
        }
        return text.split(separator: "\n", omittingEmptySubsequences: false)
    }

    private static func hits(_ pattern: NSRegularExpression, in files: [URL]) -> [String] {
        var hits: [String] = []
        for file in files {
            for (index, line) in lines(of: file).enumerated() {
                let line = String(line)
                if line.trimmingCharacters(in: .whitespaces).hasPrefix("//") { continue }
                if pattern.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil {
                    hits.append("\(file.lastPathComponent):\(index + 1)")
                }
            }
        }
        return hits
    }

    @Test("No row on a page scrolls sideways: it wraps or sits in a grid")
    func noHorizontalScrollViews() {
        #expect(Self.sources.count > 100, "the guard found the sources")
        let files = Self.sources.filter { Self.allowed[$0.lastPathComponent] == nil }
        let hits = Self.hits(Self.horizontal, in: files)
        #expect(hits.isEmpty, "a sideways scroll view at: \(hits)")
    }

    @Test("Pages scroll through SomaPageScroll, which holds the column to the screen")
    func pagesUseSomaPageScroll() {
        // SomaPageScroll is the one scroll view a page may hold.
        let hits = Self.hits(Self.bare, in: Self.sources.filter { $0.lastPathComponent != "SomaPageScroll.swift" })
        #expect(hits.isEmpty, "a bare ScrollView (use SomaPageScroll) at: \(hits)")
    }
}
