//
//  ThemeUniformityTests.swift
//  PrismTests
//

import Foundation
import SwiftUI
import Testing
import SomaUI
@testable import Prism

/// Holds the promise behind `SomaTheme`: change a font or a colour in one
/// place and every screen follows.
///
/// Two halves. The static half reads the sources of the app (`Prism/`) and of
/// the design system (`SomaUI/Sources/SomaUI`, minus `Tokens/` and `Theme/`,
/// where literals belong) and fails on every value a view writes for itself
/// instead of reading it off the theme: a colour, a font, a size, a curve. Each
/// kind has its own test, so a run says which promise is broken and where.
/// Preview blocks are skipped, comments and string literals are blanked first.
///
/// The runtime half renders real components under two themes and compares the
/// pixels: a theme change that does not move a pixel did not propagate.
///
/// Counts on 2026-10-24, when this suite was written: colours 174, fonts 102,
/// sizes 839, motion 10, duplicated components 33, system chrome sites 221.
/// The audit and the plan to bring each count to zero are in
/// `docs/uniformity-audit-2026-10-24.md`.
@Suite("Theme uniformity")
struct ThemeUniformityTests {

    // MARK: - Static: every bypass, by kind

    @Test("Colours come from theme.colors")
    func colours() {
        let hits = ThemeScan.hits(kind: .colour)
        #expect(hits.isEmpty, "\(ThemeScan.report(hits))")
    }

    @Test("Type comes from theme.typography through somaFont")
    func fonts() {
        let hits = ThemeScan.hits(kind: .font)
        #expect(hits.isEmpty, "\(ThemeScan.report(hits))")
    }

    @Test("Sizes come from theme.metrics")
    func sizes() {
        let hits = ThemeScan.hits(kind: .size)
        #expect(hits.isEmpty, "\(ThemeScan.report(hits))")
    }

    @Test("Curves and durations come from theme.motion")
    func motion() {
        let hits = ThemeScan.hits(kind: .motion)
        #expect(hits.isEmpty, "\(ThemeScan.report(hits))")
    }

    /// A feature folder that draws its own button, eyebrow, hairline, row
    /// card, chip or press style has made a second copy of something the
    /// package owns, and the copies drift: four primary buttons stand at four
    /// heights today. The fix is one component in SomaUI.
    @Test("No feature folder redraws a component the package should own")
    func duplicatedComponents() throws {
        let pattern = try NSRegularExpression(pattern: ThemeScan.duplicatePattern)
        var hits: [String] = []
        for source in ThemeScan.sources where source.isApp {
            for (index, line) in source.lines.enumerated() {
                let range = NSRange(line.startIndex..., in: line)
                for match in pattern.matches(in: line, range: range) {
                    let name = (line as NSString).substring(with: match.range(at: 1))
                    hits.append("\(source.relative):\(index + 1) \(name)")
                }
            }
        }
        #expect(hits.isEmpty, "\(hits.count) duplicated components:\n\(hits.sorted().joined(separator: "\n"))")
    }

    /// Text the system draws for us (a navigation title, an alert, a picker,
    /// a menu, a tab title, a text field's placeholder) is set in the system's
    /// font at the system's sizes: no `somaFont` reaches it, and no appearance
    /// proxy themes it. These sites cannot all go, so this is a ratchet: the
    /// count may fall, never rise. Lower `baseline` when it falls.
    @Test("System drawn text does not grow")
    func systemChrome() throws {
        let baseline = 221
        var hits: [String] = []
        for source in ThemeScan.sources {
            for (index, line) in source.lines.enumerated() {
                for (name, regex) in ThemeScan.systemText {
                    let range = NSRange(line.startIndex..., in: line)
                    if regex.firstMatch(in: line, range: range) != nil {
                        hits.append("\(source.relative):\(index + 1) \(name)")
                    }
                }
            }
        }
        #expect(hits.count <= baseline, "\(hits.count) system text sites, baseline \(baseline):\n\(hits.joined(separator: "\n"))")
    }

    /// An exception that no longer matches anything is a hole someone can
    /// walk a new literal through. Each entry has to keep earning its place.
    @Test("Every exception still matches a line")
    func exceptionsAreLive() {
        let used = Set(ThemeScan.allowed.map(\.exception))
        let stale = ThemeScan.exceptions.indices.filter { !used.contains($0) }
            .map { "\(ThemeScan.exceptions[$0].file) \(ThemeScan.exceptions[$0].contains)" }
        #expect(stale.isEmpty, "stale exceptions: \(stale)")
    }

    // MARK: - Runtime: does a theme change reach the pixels

    /// The shipped theme with every role larger and heavier: what "change the
    /// font" can mean today, since `SomaFontFamily` has one case.
    static var heavierType: SomaTheme {
        var theme = SomaTheme.standard
        let roles: [WritableKeyPath<SomaTypography, SomaFontSpec>] = [
            \.display, \.title, \.body, \.metric, \.caption, \.rowValue, \.field, \.tabLabel, \.eyebrow,
            \.segment, \.headerTitle, \.orbLabel, \.headline, \.callout, \.cardTitle, \.metricCompact,
            \.captionValue,
        ]
        for role in roles {
            theme.typography[keyPath: role].size *= 1.4
            theme.typography[keyPath: role].weight = .heavy
        }
        return theme
    }

    /// The shipped theme with the ink, the card and the accent repainted.
    static var otherColours: SomaTheme {
        var theme = SomaTheme.standard.withAccent(SomaColorValue(0xD7263D))
        theme.colors.inkPrimary = SomaColorValue(0x1B4DD8)
        theme.colors.inkSecondary = SomaColorValue(0x2E9E5B)
        theme.colors.surface = SomaColorValue(0xFFF1C9)
        return theme
    }

    @MainActor
    static func pixels<V: View>(_ view: V, theme: SomaTheme) -> Data? {
        let renderer = ImageRenderer(
            content: view
                .somaTheme(theme)
                .environment(\.colorScheme, .light)
                .frame(width: 390)
        )
        renderer.scale = 2
        guard let image = renderer.cgImage, let data = image.dataProvider?.data else { return nil }
        return (data as Data) + Data("\(image.width)x\(image.height)".utf8)
    }

    @MainActor
    static var samples: [(String, AnyView)] {
        [
            ("SomaCard", AnyView(CardSample())),
            ("SomaScoreRow", AnyView(SomaScoreRow([
                SomaScore(aspect: .sleep, value: "84", trend: .up),
                SomaScore(aspect: .heart, value: "61", trend: .down),
                SomaScore(aspect: .mind, value: "77"),
            ]))),
            ("ToolsEntryTile", AnyView(ToolsEntryTile())),
        ]
    }

    @Test("A typography change reaches the components")
    @MainActor
    func typographyPropagates() {
        for (name, view) in Self.samples {
            let before = Self.pixels(view, theme: .standard)
            let after = Self.pixels(view, theme: Self.heavierType)
            #expect(before != nil, "\(name) did not render")
            #expect(before != after, "\(name) drew the same pixels under a different typography")
        }
    }

    @Test("A colour change reaches the components")
    @MainActor
    func coloursPropagate() {
        for (name, view) in Self.samples {
            let before = Self.pixels(view, theme: .standard)
            let after = Self.pixels(view, theme: Self.otherColours)
            #expect(before != nil, "\(name) did not render")
            #expect(before != after, "\(name) drew the same pixels under a different palette")
        }
    }

    /// The leak this audit found most often: a glyph sized with
    /// `.font(.system(size: metrics.x))` takes its size from the metrics and
    /// its face and weight from the call site, so no typography change ever
    /// reaches it. `SomaIconLabel` is the package's own icon, and the 78
    /// `system font` hits in the static test are the same shape. This fails
    /// until glyphs get a role of their own.
    @Test("A typography change reaches the glyphs")
    @MainActor
    func glyphsFollowTypography() {
        let glyph = SomaIconLabel(symbol: "bell", style: .plain)
        let before = Self.pixels(glyph, theme: .standard)
        let after = Self.pixels(glyph, theme: Self.heavierType)
        #expect(before != nil)
        #expect(before != after, "SomaIconLabel ignores theme.typography: its glyph is Font.system at a metric size")
    }
}

/// A card the way a page writes one: its text set in roles read off the
/// environment's theme, so the card and its words answer the same theme.
private struct CardSample: View {
    @Environment(\.somaTheme) private var theme

    var body: some View {
        SomaCard {
            VStack(alignment: .leading, spacing: theme.metrics.cardHeaderSpacing) {
                Text(verbatim: "Recovery")
                    .somaFont(theme.typography.cardTitle)
                    .foregroundStyle(theme.colors.inkPrimary.color)
                Text(verbatim: "72")
                    .somaFont(theme.typography.metric)
                    .foregroundStyle(theme.colors.inkPrimary.color)
            }
        }
    }
}

// MARK: - The scanner

/// Reads the sources once and classifies every line that bypasses the theme.
enum ThemeScan {
    enum Kind: String, CaseIterable {
        case colour, font, size, motion
    }

    struct Rule {
        let kind: Kind
        let name: String
        let regex: NSRegularExpression

        init(_ kind: Kind, _ name: String, _ pattern: String) {
            self.kind = kind
            self.name = name
            // A pattern that does not compile is a bug in this file: crash.
            self.regex = try! NSRegularExpression(pattern: pattern)
        }
    }

    /// A rule that looks inside one call's parentheses, which may span lines.
    struct CallRule {
        let kind: Kind
        let name: String
        let opener: NSRegularExpression
        let inner: NSRegularExpression

        init(_ kind: Kind, _ name: String, opener: String, inner: String) {
            self.kind = kind
            self.name = name
            self.opener = try! NSRegularExpression(pattern: opener)
            self.inner = try! NSRegularExpression(pattern: inner)
        }
    }

    struct Hit: Hashable {
        let kind: Kind
        let rule: String
        let file: String
        let line: Int
        let text: String
    }

    /// A line that writes a literal on purpose. Matched by file name and by a
    /// fragment of the line, so moving the line keeps it allowed and changing
    /// it does not.
    struct Exception {
        let file: String
        let contains: String
        let reason: String
    }

    static let exceptions: [Exception] = [
        Exception(file: "*", contains: "1 / displayScale",
                  reason: "One physical pixel: a hairline is a fact of the screen, not a design value."),
        Exception(file: "SomaAspectBackdrop.swift", contains: ".init(color: .black",
                  reason: "A mask stop: only its alpha is read, the hue never reaches the screen."),
        Exception(file: "SomaHeaderBlur.swift", contains: ".init(color: .black",
                  reason: "A mask stop: only its alpha is read."),
        Exception(file: "SomaHeaderBlur.swift", contains: ".ultraThinMaterial",
                  reason: "The progressive blur is the system material: a blur of what is behind, not a colour."),
        Exception(file: "SomaMarkUnfold.swift", contains: "with: .color(.black)",
                  reason: "Any opaque fill: the alpha threshold filter repaints it in the theme's ink."),
        Exception(file: "SomaLiquidFill.swift", contains: "with: .color(.black))",
                  reason: "A mask: only its alpha is read."),
        Exception(file: "SomaLiquidFill.swift", contains: ".fill(.ultraThinMaterial)",
                  reason: "The frosted water is the system material, not a colour."),
        Exception(file: "OnboardingSignIn.swift", contains: "signInWithAppleButtonStyle",
                  reason: "Apple's Sign in with Apple button comes only in black, white or outlined."),
        Exception(file: "SignaturePad.swift", contains: ".color(.black)",
                  reason: "Black ink on white paper: a signed consent reads the same in any theme."),
        Exception(file: "SignaturePad.swift", contains: "Color.white",
                  reason: "The paper under the signature, see above."),
        Exception(file: "CameraPreview.swift", contains: "backgroundColor = .black",
                  reason: "The letterbox behind the live camera feed."),
        Exception(file: "CaptureLivePreview.swift", contains: ".ultraThinMaterial",
                  reason: "A label over the live camera feed: a blur of the picture, not a colour."),
    ]

    private static let number = #"-?\d+(?:\.\d+)?"#
    private static let nonZero = #"-?(?:[1-9]\d*(?:\.\d+)?|0\.\d*[1-9])"#

    static let rules: [Rule] = [
        // Colours
        Rule(.colour, "rgb/hue/white init",
             #"\b(?:Color|UIColor|NSColor)\s*\(\s*(?:red|hue|white|\.sRGB|\.displayP3|srgbRed|displayP3Red|cgColor)\b"#),
        Rule(.colour, "hex literal", ##"0x[0-9A-Fa-f]{6}\b|Color\s*\(\s*hex:|#colorLiteral"##),
        Rule(.colour, "named system colour",
             #"(?<!==\s)(?<![\w\)\]])\.(?:white|black|red|green|blue|orange|yellow|gray|grey|pink|purple|mint|teal|cyan|indigo|brown)\b(?!\s*[:(=])"#),
        Rule(.colour, "named system colour",
             #"\b(?:Color|UIColor|NSColor)\.(?:white|black|red|green|blue|orange|yellow|gray|grey|pink|purple|mint|teal|cyan|indigo|brown|label|secondaryLabel|systemBackground|secondarySystemBackground|systemGray\d?|systemFill|separator|tertiaryLabel)\b"#),
        Rule(.colour, "hierarchical style",
             #"\bColor\.(?:primary|secondary|accentColor)\b|\.(?:foregroundStyle|foregroundColor|tint|fill|stroke)\(\s*\.(?:primary|secondary|tertiary|quaternary|quinary)\b|(?<![\w\)])\.(?:tertiary|quaternary|quinary)\b(?!\s*[:(=])|HierarchicalShapeStyle"#),
        Rule(.colour, "material/system bg",
             #"(?<![\w\)])\.(?:ultraThinMaterial|thinMaterial|regularMaterial|thickMaterial|ultraThickMaterial|bar)\b(?!\s*[:(=])|\.background\(\s*\.(?:background|secondary)\b"#),
        Rule(.colour, "opacity literal", #"\.opacity\((?:[^()]|\([^()]*\))*?(?<![\w.])0?\.\d*[1-9]"#),
        Rule(.colour, "static theme read",
             #"\bSomaTheme\.standard\b|\bSoma(?:Colors|Typography|Metrics|Motion|Aspects)\.(?:standard|touch|pointer)\b"#),
        // Fonts
        Rule(.font, "system font", ##"\bFont\.system\b|\.system\(\s*size:|\bUIFont\b|\bNSFont\b|Font\.custom|\.custom\(\s*""##),
        Rule(.font, "text style",
             #"\.font\(\s*\.(?:largeTitle|title|title2|title3|headline|subheadline|body|callout|footnote|caption|caption2)\b"#),
        Rule(.font, ".font( outside somaFont",
             #"\.font\((?!\s*\.(?:largeTitle|title|title2|title3|headline|subheadline|body|callout|footnote|caption|caption2|system)\b)"#),
        Rule(.font, "weight/design/width ad hoc", #"\.(?:fontWeight|fontDesign|fontWidth)\(|\.bold\(\)|\.italic\(\)|\.monospaced\(\)"#),
        Rule(.font, "monospacedDigit ad hoc", #"\.monospacedDigit\(\)"#),
        Rule(.font, "tracking/kerning", #"\.(?:tracking|kerning)\("#),
        // Sizes
        Rule(.size, "spacing literal", #"\bspacing:\s*"# + nonZero + #"\b"#),
        Rule(.size, "cornerRadius literal", #"\bcornerRadius:?\s*\(?\s*"# + nonZero + #"\b"#),
        Rule(.size, "lineWidth literal", #"\blineWidth:\s*"# + nonZero + #"\b"#),
        Rule(.size, "token arithmetic literal",
             #"\b(?:metrics|typography|motion)\.\w+(?:\.\w+)?\s*(?:[-+*]\s*\(?\s*\d+(?:\.\d+)?|/\s*(?!2\b)\d+(?:\.\d+)?)|(?<![\w.])\d+(?:\.\d+)?\s*\*\s*(?:theme\.)?metrics\."#),
        // Motion
        Rule(.motion, "curve literal",
             #"(?<![\w])\.(?:easeInOut|easeIn|easeOut|linear|spring|interactiveSpring|bouncy|snappy|smooth|interpolatingSpring)\b(?!\s*[:=])|\bAnimation\.(?:easeInOut|easeIn|easeOut|linear|spring|default|bouncy|snappy|smooth)\b|\.animation\(\s*\.default\b"#),
        Rule(.motion, "UI delay literal", #"Task\.sleep\(for:\s*\.milliseconds\(\s*\d+"#),
        Rule(.motion, "duration/delay literal",
             #"\b(?:duration|response|dampingFraction|bounce|blendDuration):\s*"# + number + #"\b|\.delay\(\s*"# + number + #"\s*\)|\.speed\(\s*"# + number + #"\s*\)"#),
    ]

    static let callRules: [CallRule] = [
        CallRule(.size, "padding literal", opener: #"\.padding\("#,
                 inner: #"(?:^\(|,|\b(?:top|leading|bottom|trailing):)\s*(?:\.[a-zA-Z]+\s*,\s*)?"# + nonZero + #"\s*(?=[,)])"#),
        CallRule(.size, "frame literal", opener: #"\.frame\("#,
                 inner: #"\b(?:width|height|minWidth|maxWidth|minHeight|maxHeight|idealWidth|idealHeight):\s*"# + nonZero + #"\b"#),
    ]

    static let duplicatePattern =
        #"struct (\w*(?:PrimaryButton|SecondaryButton|QuietButton|OutlineButton|WideButton|Eyebrow|Hairline|RowsCard|RowGroup|PressStyle|Chip))\b"#

    static let systemText: [(String, NSRegularExpression)] = [
        ("navigationTitle", #"\.navigationTitle\("#),
        ("toolbarTitleDisplayMode", #"\.toolbarTitleDisplayMode\("#),
        ("navigationBarTitleDisplayMode", #"\.navigationBarTitleDisplayMode\("#),
        ("alert", #"\.alert\("#),
        ("confirmationDialog", #"\.confirmationDialog\("#),
        ("Picker", #"\bPicker\s*\("#),
        ("DatePicker", #"\bDatePicker\s*\("#),
        ("Menu", #"\bMenu\s*[({]"#),
        ("searchable", #"\.searchable\("#),
        ("contextMenu", #"\.contextMenu\b"#),
        ("TextField/SecureField", #"\b(?:TextField|SecureField|TextEditor)\s*\("#),
        ("Toggle", #"\bToggle\s*\("#),
        ("Stepper", #"\bStepper\s*\("#),
        ("Tab(title)", ##"\bTab\s*\(\s*""##),
        ("Label(", #"\bLabel\s*\("#),
        ("ShareLink", #"\bShareLink\s*\("#),
        ("swipeActions", #"\.swipeActions\b"#),
        ("appearance proxy", #"\.appearance\(\)|largeTitleTextAttributes|titleTextAttributes"#),
    ].map { ($0.0, try! NSRegularExpression(pattern: $0.1)) }

    // MARK: Sources

    struct Source {
        let relative: String
        let isApp: Bool
        /// The cleaned lines: comments and string contents blanked, preview
        /// blocks emptied. Line numbers match the file.
        let lines: [String]
        let raw: [String]
    }

    /// The folder holding both repositories.
    static let soma = StyleGuardTests.root.deletingLastPathComponent()

    static let sources: [Source] = {
        let app = StyleGuardTests.root.appendingPathComponent("Prism")
        let package = soma.appendingPathComponent("SomaUI/Sources/SomaUI")
        var found: [Source] = []
        for (base, isApp) in [(app, true), (package, false)] {
            for file in TypographyGuardTests.swiftFiles(under: base).sorted(by: { $0.path < $1.path }) {
                let inside = file.path.replacingOccurrences(of: base.path + "/", with: "")
                if !isApp, inside.hasPrefix("Tokens/") || inside.hasPrefix("Theme/") { continue }
                guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
                let relative = file.path.replacingOccurrences(of: soma.path + "/", with: "")
                let cleaned = stripPreviews(clean(text).components(separatedBy: "\n"))
                found.append(Source(relative: relative, isApp: isApp, lines: cleaned,
                                    raw: text.components(separatedBy: "\n")))
            }
        }
        return found
    }()

    /// Every hit before the exceptions, each paired with the exception that
    /// allows it, if one does.
    private static let classified: [(hit: Hit, exception: Int?)] = {
        var result: [(Hit, Int?)] = []
        for source in sources {
            func add(_ rule: String, _ kind: Kind, _ line: Int) {
                let text = source.raw[line].trimmingCharacters(in: .whitespaces)
                let hit = Hit(kind: kind, rule: rule, file: source.relative, line: line + 1, text: text)
                let exception = exceptions.firstIndex {
                    ($0.file == "*" || source.relative.hasSuffix("/" + $0.file)) && text.contains($0.contains)
                }
                result.append((hit, exception))
            }

            for (index, line) in source.lines.enumerated() {
                let range = NSRange(line.startIndex..., in: line)
                for rule in rules {
                    for _ in rule.regex.matches(in: line, range: range) { add(rule.name, rule.kind, index) }
                }
            }

            let joined = source.lines.joined(separator: "\n") as NSString
            var lineStarts: [Int] = [0]
            for line in source.lines { lineStarts.append(lineStarts.last! + (line as NSString).length + 1) }
            for rule in callRules {
                for open in rule.opener.matches(in: joined as String, range: NSRange(location: 0, length: joined.length)) {
                    let start = open.range.location + open.range.length - 1
                    let body = balanced(joined, from: start)
                    for inner in rule.inner.matches(in: body as String, range: NSRange(location: 0, length: body.length)) {
                        let offset = start + inner.range.location
                        let line = (lineStarts.lastIndex { $0 <= offset } ?? 0)
                        add(rule.name, rule.kind, line)
                    }
                }
            }
        }
        return result
    }()

    static let allowed: [(hit: Hit, exception: Int)] = classified.compactMap { entry in
        entry.exception.map { (entry.hit, $0) }
    }

    static func hits(kind: Kind) -> [Hit] {
        classified.filter { $0.exception == nil && $0.hit.kind == kind }.map(\.hit)
    }

    /// The count, the count per rule, then each file with its lines.
    static func report(_ hits: [Hit]) -> String {
        let byRule = Dictionary(grouping: hits, by: \.rule).map { "\($0.key): \($0.value.count)" }.sorted()
        let byFile = Dictionary(grouping: hits, by: \.file).sorted { $0.value.count > $1.value.count }
        var lines = ["\(hits.count) bypasses in \(byFile.count) files (\(byRule.joined(separator: ", ")))"]
        for (file, fileHits) in byFile {
            lines.append("\(file) [\(fileHits.count)]")
            for hit in fileHits.sorted(by: { $0.line < $1.line }) {
                lines.append("  \(hit.line) \(hit.rule): \(hit.text.prefix(120))")
            }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: Text handling

    /// The parenthesised run starting at `start`, an opening parenthesis.
    static func balanced(_ text: NSString, from start: Int) -> NSString {
        var depth = 0
        var index = start
        while index < text.length {
            let unit = text.character(at: index)
            if unit == 0x28 { depth += 1 }
            if unit == 0x29 {
                depth -= 1
                if depth == 0 { return text.substring(with: NSRange(location: start, length: index - start + 1)) as NSString }
            }
            index += 1
        }
        return text.substring(from: start) as NSString
    }

    /// Blanks comments and the inside of string literals, keeping every line
    /// break, so a word in a comment or in copy is never read as code.
    static func clean(_ text: String) -> String {
        let chars = Array(text.unicodeScalars)
        let count = chars.count
        var out = String.UnicodeScalarView()
        var index = 0

        func starts(_ literal: String, at position: Int) -> Bool {
            let scalars = Array(literal.unicodeScalars)
            guard position + scalars.count <= count else { return false }
            for offset in scalars.indices where chars[position + offset] != scalars[offset] { return false }
            return true
        }
        func find(_ literal: String, from position: Int) -> Int {
            var cursor = position
            while cursor < count {
                if starts(literal, at: cursor) { return cursor }
                cursor += 1
            }
            return count
        }

        while index < count {
            let char = chars[index]
            if starts("\"\"\"", at: index) {
                let end = find("\"\"\"", from: index + 3)
                out.append("\"")
                for scalar in chars[(index + 3)..<end] { out.append(scalar == "\n" ? "\n" : " ") }
                out.append("\"")
                index = end + 3
                continue
            }
            if char == "\"" {
                var cursor = index + 1
                while cursor < count, chars[cursor] != "\"", chars[cursor] != "\n" {
                    if chars[cursor] == "\\" { cursor += 1 }
                    cursor += 1
                }
                out.append("\"")
                out.append("\"")
                index = cursor < count && chars[cursor] == "\"" ? cursor + 1 : cursor
                continue
            }
            if starts("//", at: index) {
                index = find("\n", from: index)
                continue
            }
            if starts("/*", at: index) {
                let end = find("*/", from: index + 2)
                for scalar in chars[index..<end] where scalar == "\n" { out.append("\n") }
                index = end + 2
                continue
            }
            out.append(char)
            index += 1
        }
        return String(out)
    }

    /// Empties every `#Preview` block and `PreviewProvider`: a preview is a
    /// fixture, and its literals never ship.
    static func stripPreviews(_ lines: [String]) -> [String] {
        var result = lines
        let provider = try! NSRegularExpression(pattern: #"struct \w+_Previews\s*:"#)
        var index = 0
        while index < result.count {
            let line = result[index]
            let range = NSRange(line.startIndex..., in: line)
            let opens = line.trimmingCharacters(in: .whitespaces).hasPrefix("#Preview")
                || provider.firstMatch(in: line, range: range) != nil
            guard opens else { index += 1; continue }

            var depth = 0
            var started = false
            var cursor = index
            while cursor < result.count {
                for char in result[cursor] {
                    if char == "{" { depth += 1; started = true }
                    if char == "}" { depth -= 1 }
                }
                result[cursor] = ""
                if started && depth <= 0 { break }
                cursor += 1
            }
            index = cursor + 1
        }
        return result
    }
}
