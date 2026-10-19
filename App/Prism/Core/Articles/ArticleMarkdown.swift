//
//  ArticleMarkdown.swift
//  Prism
//

import Foundation

/// An article body cut into the blocks the reader lays out. `AttributedString`
/// reads inline Markdown well (emphasis, links) but flattens headings and
/// lists into one run, so the blocks are found here and only their text goes
/// through it.
enum ArticleBlock: Equatable, Sendable {
    /// `## A heading` (any level from one to four hashes).
    case heading(String)
    /// Lines run together until a blank line.
    case paragraph(String)
    /// Consecutive `- ` or `* ` lines.
    case bullets([String])
    /// `> ` lines, set apart from the body.
    case quote(String)
}

enum ArticleMarkdown {
    static func blocks(_ body: String) -> [ArticleBlock] {
        var blocks: [ArticleBlock] = []
        var paragraph: [String] = []
        var bullets: [String] = []
        var quote: [String] = []

        func flush() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: " "))) }
            if !bullets.isEmpty { blocks.append(.bullets(bullets)) }
            if !quote.isEmpty { blocks.append(.quote(quote.joined(separator: " "))) }
            paragraph = []
            bullets = []
            quote = []
        }

        for raw in body.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                flush()
            } else if let heading = headingText(line) {
                flush()
                blocks.append(.heading(heading))
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                if !paragraph.isEmpty || !quote.isEmpty { flush() }
                bullets.append(String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces))
            } else if line.hasPrefix(">") {
                if !paragraph.isEmpty || !bullets.isEmpty { flush() }
                quote.append(String(line.dropFirst()).trimmingCharacters(in: .whitespaces))
            } else if !bullets.isEmpty, raw.hasPrefix("  ") {
                // A wrapped list item continues the last one.
                bullets[bullets.count - 1] += " " + line
            } else {
                if !bullets.isEmpty || !quote.isEmpty { flush() }
                paragraph.append(line)
            }
        }
        flush()
        return blocks
    }

    private static func headingText(_ line: String) -> String? {
        let hashes = line.prefix { $0 == "#" }.count
        guard (1...4).contains(hashes) else { return nil }
        let rest = line.dropFirst(hashes)
        guard rest.first == " " else { return nil }
        return rest.trimmingCharacters(in: .whitespaces)
    }

    /// One block's text with its inline Markdown applied; the plain text
    /// when it does not parse.
    static func inline(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}
