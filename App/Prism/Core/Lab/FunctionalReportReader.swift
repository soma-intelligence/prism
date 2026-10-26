//
//  FunctionalReportReader.swift
//  Prism
//
//  Reads an imaging or functional test report on the device. The text comes
//  from the blood reader (a PDF's text layer or Vision's OCR, a photographed
//  page through Vision), so nothing leaves the phone; this file only finds
//  the values of the six tests in it.
//
//  Conservative like the urine reader: a value is emitted only when it sits
//  on the same line as a label the test knows, and every value lands on the
//  form before anything is saved. Unlike a blood report, a T-score is often
//  negative, so the sign in front of a number is kept.
//

import Foundation

/// One value found in a report, in the unit it was printed in.
nonisolated struct ExtractedFunctionalValue: Sendable, Hashable, Identifiable {
    var fieldID: String
    var kind: FunctionalTestKind
    var value: Double
    /// The normalised unit token on the line ("kg", "g/cm2"), empty when none.
    var unit: String

    var id: String { fieldID }
}

nonisolated enum FunctionalReportReader {
    /// The test a page is about: the one whose labels it names most, in the
    /// catalog's order on a tie. Nil when it names none.
    static func guessKind(in text: String) -> FunctionalTestKind? {
        let lines = text.split(whereSeparator: \.isNewline).map { normalize(String($0)) }
        var best: (kind: FunctionalTestKind, hits: Int)?
        for kind in FunctionalTestKind.reported {
            let needles = labels(kind)
            let hits = lines.filter { line in needles.contains { range(of: $0.needle, in: line) != nil } }.count
            if hits > (best?.hits ?? 0) { best = (kind, hits) }
        }
        return best?.kind
    }

    /// Every value of `kind` the text prints, or of the test it names most
    /// when `kind` is nil. The first reading of a field wins.
    static func detect(in text: String, kind: FunctionalTestKind?) -> [ExtractedFunctionalValue] {
        guard let kind = kind ?? guessKind(in: text) else { return [] }
        let needles = labels(kind)
        var found: [String: ExtractedFunctionalValue] = [:]
        var order: [String] = []
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = String(raw).trimmingCharacters(in: .whitespacesAndNewlines)
            let hay = normalize(line)
            // The label that starts first wins, the longest among those that
            // start together: "Visceral fat mass" is about visceral fat.
            let hits = needles.compactMap { label in range(of: label.needle, in: hay).map { (label, $0) } }
            guard let (hit, at) = hits.min(by: { a, b in
                      a.1.lowerBound != b.1.lowerBound ? a.1.lowerBound < b.1.lowerBound : a.0.needle.count > b.0.needle.count
                  }),
                  found[hit.id] == nil,
                  let field = FunctionalCatalog.field(hit.id, in: kind) else { continue }
            let offset = hay.distance(from: hay.startIndex, to: at.upperBound)
            guard offset <= line.count else { continue }
            let tail = String(line.dropFirst(offset))
            guard let parsed = parse(tail, for: field, kind: kind) else { continue }
            found[hit.id] = parsed
            order.append(hit.id)
        }
        return order.compactMap { found[$0] }
    }

    /// A word for a yes or no field, else the first number and the unit
    /// printed right after it.
    static func parse(_ tail: String, for field: FunctionalField, kind: FunctionalTestKind) -> ExtractedFunctionalValue? {
        if field.quantity == .yesNo {
            let hay = " " + normalize(tail) + " "
            let none = [" none ", " no ", " absent ", " absence ", " not seen ", " not detected ", " negative ", " aucune "]
            let some = [" present ", " presence ", " yes ", " seen ", " detected ", " positive ", " visible "]
            if none.contains(where: hay.contains) { return .init(fieldID: field.id, kind: kind, value: 0, unit: "") }
            if some.contains(where: hay.contains) { return .init(fieldID: field.id, kind: kind, value: 1, unit: "") }
            return nil
        }
        guard let (value, after) = signedNumbers(in: tail).first else { return nil }
        return .init(fieldID: field.id, kind: kind, value: value, unit: unitToken(in: after, for: field) ?? "")
    }

    /// Numbers in order with the text after each up to the next number. A
    /// minus sign counts only when it touches the digits and does not follow
    /// a digit or a letter, so "-1.8" is negative and "0.8-1.2" is a range.
    /// A space before exactly three digits joins a thousands group: "51 200 g".
    static func signedNumbers(in s: String) -> [(value: Double, after: String)] {
        let chars = Array(s)
        func digit(_ c: Character) -> Bool { c.isASCII && c.isNumber }
        var out: [(Double, Int, Int)] = []
        var i = 0
        while i < chars.count {
            guard digit(chars[i]) else { i += 1; continue }
            let start = i
            var body = ""
            while i < chars.count, digit(chars[i]) || ((chars[i] == "." || chars[i] == ",") && i + 1 < chars.count && digit(chars[i + 1])) {
                body.append(chars[i]); i += 1
            }
            // "51 200": one space, then exactly three digits.
            while !body.contains(where: { $0 == "." || $0 == "," }), body.count <= 6,
                  i + 3 < chars.count, chars[i] == " ",
                  digit(chars[i + 1]), digit(chars[i + 2]), digit(chars[i + 3]),
                  i + 4 == chars.count || !digit(chars[i + 4]) {
                body += String(chars[(i + 1)...(i + 3)]); i += 4
            }
            guard var value = BloodReportReader.parseDecimal(body) else { continue }
            if start > 0, chars[start - 1] == "-" || chars[start - 1] == "\u{2212}" {
                let before: Character? = start > 1 ? chars[start - 2] : nil
                if before.map({ !digit($0) && !$0.isLetter }) ?? true { value = -value }
            }
            out.append((value, start, i))
        }
        return out.enumerated().map { index, item in
            let end = index + 1 < out.count ? out[index + 1].1 : chars.count
            return (item.0, String(chars[item.2..<end]))
        }
    }

    /// The field's accepted unit the text names first, longest first so "kg"
    /// wins over "g".
    private static func unitToken(in s: String, for field: FunctionalField) -> String? {
        let normalised = BloodMarkerCatalog.normalize(s)
        return field.acceptedUnits.keys.sorted { $0.count > $1.count }.first { normalised.contains($0) }
    }

    /// (normalised label, field id) of one test, longest first.
    private static func labels(_ kind: FunctionalTestKind) -> [(needle: String, id: String)] {
        var pairs: [(String, String)] = []
        for field in kind.fields {
            pairs.append((normalize(field.name), field.id))
            for alias in field.aliases { pairs.append((normalize(alias), field.id)) }
        }
        return pairs.filter { $0.0.count >= 2 }.sorted { $0.0.count > $1.0.count }
    }

    /// Where `needle` sits in `hay` on word boundaries, so "imt" never matches
    /// inside "limit".
    static func range(of needle: String, in hay: String) -> Range<String.Index>? {
        var search = hay.startIndex..<hay.endIndex
        while let range = hay.range(of: needle, range: search) {
            let before = range.lowerBound == hay.startIndex ? nil : hay[hay.index(before: range.lowerBound)]
            let after = range.upperBound == hay.endIndex ? nil : hay[range.upperBound]
            let edge: (Character?) -> Bool = { $0.map { !$0.isLetter && !$0.isNumber } ?? true }
            if edge(before) && edge(after) { return range }
            search = range.upperBound..<hay.endIndex
        }
        return nil
    }

    /// Lowercased, accents folded, and a slash, a hyphen, an underscore or a
    /// colon read as a space, one character for one so an offset in it is an
    /// offset in the line.
    static func normalize(_ s: String) -> String {
        String(s.lowercased().folding(options: .diacriticInsensitive, locale: nil).map { "/-_:".contains($0) ? " " : $0 })
    }
}
