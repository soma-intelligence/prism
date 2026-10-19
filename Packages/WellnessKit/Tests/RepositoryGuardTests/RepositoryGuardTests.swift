import Foundation
import Testing

/// Repository-wide rules, enforced on every `swift test`.
@Suite struct RepositoryGuardTests {
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    static let skippedDirectories: Set<String> = [".build", ".build-ios", ".git", ".swiftpm", "DerivedData"]

    static func files(under directory: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        ) else { return [] }
        var result: [URL] = []
        for case let url as URL in enumerator {
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDirectory {
                if skippedDirectories.contains(url.lastPathComponent) { enumerator.skipDescendants() }
                continue
            }
            result.append(url)
        }
        return result
    }

    static func relativePath(_ url: URL) -> String {
        String(url.standardizedFileURL.path.dropFirst(root.standardizedFileURL.path.count + 1))
    }

    static func text(of url: URL) -> String? {
        guard let data = FileManager.default.contents(atPath: url.path) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @Test func noLegacyBrandNameAnywhere() {
        // Built from fragments so this file does not contain the words it forbids.
        let forbidden = [["te", "mple"].joined(), ["ga", "ia"].joined()]
        var hits: [String] = []
        for file in Self.files(under: Self.root) {
            let path = Self.relativePath(file)
            if forbidden.contains(where: path.lowercased().contains) { hits.append(path) }
            guard let text = Self.text(of: file) else { continue }
            for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
            where forbidden.contains(where: line.lowercased().contains) {
                hits.append("\(path):\(index + 1)")
            }
        }
        #expect(hits.isEmpty, "legacy brand name found at: \(hits)")
    }

    @Test func noEmDashAnywhere() {
        let dash = "\u{2014}"
        var hits: [String] = []
        for file in Self.files(under: Self.root) {
            guard let text = Self.text(of: file) else { continue }
            for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
            where line.contains(dash) {
                hits.append("\(Self.relativePath(file)):\(index + 1)")
            }
        }
        #expect(hits.isEmpty, "em-dash found at: \(hits)")
    }

    @Test func noUnlistedTryOptionalInSources() {
        let allowlistURL = Self.root.appendingPathComponent("Tests/Allowlists/try-optional.txt")
        let allowed = Set(
            (Self.text(of: allowlistURL) ?? "")
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        )
        var hits: [String] = []
        for file in Self.files(under: Self.root.appendingPathComponent("Sources")) where file.pathExtension == "swift" {
            guard let text = Self.text(of: file) else { continue }
            for line in text.split(separator: "\n") where line.contains("try?") {
                let entry = "\(Self.relativePath(file)):\(line.trimmingCharacters(in: .whitespaces))"
                if !allowed.contains(entry) { hits.append(entry) }
            }
        }
        #expect(hits.isEmpty, "unlisted try? found: \(hits)")
    }
}
