//
//  UrineReportReader.swift
//  Prism
//
//  Reads a urinalysis report on the device. The text comes from the blood
//  reader (a PDF's text layer or Vision's OCR, a photographed page through
//  Vision), so nothing leaves the phone; this file only finds the urine
//  markers in it.
//
//  Like the blood detector it is conservative: a value is emitted only when
//  it sits on the same line as a label the urine catalog knows. A urine
//  report prints half its results in words ("Negative", "Trace", "2+"), so
//  those are read too and mapped onto the marker's chart steps. Every value
//  lands on the confirm screen before anything is saved.
//

import Foundation

/// One urine marker found in a report, in the unit it was printed in.
nonisolated struct ExtractedUrineMarker: Sendable, Identifiable, Hashable {
    var id: String
    var value: Double
    var unit: String
    var refLow: Double?
    var refHigh: Double?
}

nonisolated enum UrineReportReader {
    /// (normalised label, catalog id), longest first so "albumin creatinine
    /// ratio" wins over "albumin" and over "creatinine".
    private static let labels: [(needle: String, id: String)] = {
        var pairs: [(String, String)] = []
        for marker in UrineCatalog.all {
            pairs.append((normalize(marker.name), marker.id))
            for alias in marker.aliases { pairs.append((normalize(alias), marker.id)) }
        }
        return pairs.filter { $0.0.count >= 2 }.sorted { $0.0.count > $1.0.count }
    }()

    static func detect(in text: String) -> [ExtractedUrineMarker] {
        var found: [String: ExtractedUrineMarker] = [:]
        var order: [String] = []
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = String(raw).trimmingCharacters(in: .whitespacesAndNewlines)
            let hay = normalize(line)
            // The label that starts first wins, the longest among those that
            // start together: "Protein/creatinine" is about protein.
            let hits = labels.compactMap { label in range(of: label.needle, in: hay).map { (label, $0) } }
            guard let (hit, at) = hits.min(by: { a, b in
                      a.1.lowerBound != b.1.lowerBound ? a.1.lowerBound < b.1.lowerBound : a.0.needle.count > b.0.needle.count
                  }),
                  found[hit.id] == nil,
                  let marker = UrineCatalog.marker(id: hit.id) else { continue }
            let offset = hay.distance(from: hay.startIndex, to: at.upperBound)
            guard offset <= line.count else { continue }
            let tail = String(line.dropFirst(offset))
            guard let parsed = parse(tail, for: marker) else { continue }
            found[hit.id] = parsed
            order.append(hit.id)
        }
        return order.compactMap { found[$0] }
    }

    /// A word or grade first ("Negative", "Trace", "2+"), else the first number
    /// with its unit and the printed range.
    static func parse(_ tail: String, for marker: UrineMarker) -> ExtractedUrineMarker? {
        if let word = qualitative(tail, for: marker) {
            return ExtractedUrineMarker(id: marker.id, value: word, unit: marker.unit)
        }
        let numbers = BloodReportReader.numbers(in: tail)
        guard let value = numbers.first else { return nil }
        let unit = unitToken(in: tail)
        let rest = Array(numbers.dropFirst())
        var low: Double?, high: Double?
        let lower = tail.lowercased()
        if (tail.contains("-") || lower.contains(" to ") || lower.contains(" a ")), rest.count >= 2, rest[0] < rest[1] {
            low = rest[0]; high = rest[1]
        } else if lower.contains("<"), let bound = rest.first {
            high = bound
        } else if lower.contains(">"), let bound = rest.first {
            low = bound
        }
        return ExtractedUrineMarker(id: marker.id, value: value, unit: unit ?? marker.unit, refLow: low, refHigh: high)
    }

    /// A result printed in words, as the marker's stored value: negative is
    /// the chart's first step, trace its second, a grade "n+" the step n up
    /// from trace. Nil when the line carries no such word.
    static func qualitative(_ tail: String, for marker: UrineMarker) -> Double? {
        let hay = " " + normalize(tail).replacingOccurrences(of: "(", with: " ").replacingOccurrences(of: ")", with: " ") + " "
        let steps = marker.steps
        let negative = [" negative ", " neg ", " negatif ", " absent ", " absence ", " nil ", " none ", " not detected "]
        if negative.contains(where: hay.contains) { return steps.first?.value ?? 0 }
        if marker.id == "urobilinogen", hay.contains(" normal ") { return steps.first?.value }
        if marker.id == "nitrite", hay.contains(" positive ") || hay.contains(" positif ") || hay.contains(" present ") {
            return 1
        }
        guard steps.count >= 3 else { return nil }
        // "1+", "2 +", "+++": the grade counts up from trace.
        if let grade = plusGrade(hay) {
            let hasTrace = steps[1].label.lowercased().hasPrefix("trace")
            let index = min((hasTrace ? 1 : 0) + grade, steps.count - 1)
            return steps[index].value
        }
        if hay.contains(" trace ") || hay.contains(" traces ") {
            return steps[1].value
        }
        for (word, grade) in [(" small ", 1), (" moderate ", 2), (" large ", 3)] where hay.contains(word) {
            let hasTrace = steps[1].label.lowercased().hasPrefix("trace")
            return steps[min((hasTrace ? 1 : 0) + grade, steps.count - 1)].value
        }
        return nil
    }

    private static func plusGrade(_ hay: String) -> Int? {
        if let match = hay.firstMatch(of: /\s([1-4])\s?\+/), let n = Int(match.1) { return n }
        if let match = hay.firstMatch(of: /\s(\+{1,4})\s/) { return match.1.count }
        return nil
    }

    private static let knownUnits: [String] = [
        "mg/dl", "mg/l", "g/l", "mmol/l", "umol/l", "mg/g", "mg/mmol", "ug/mg", "ery/ul", "leu/ul", "/ul", "eu/dl",
    ].sorted { $0.count > $1.count }

    private static func unitToken(in s: String) -> String? {
        let normalised = BloodMarkerCatalog.normalize(s)
        return knownUnits.first { normalised.contains($0) }
    }

    /// Where `needle` sits in `hay` on word boundaries, so "ph" never matches
    /// inside "phosphate".
    private static func range(of needle: String, in hay: String) -> Range<String.Index>? {
        var search = hay.startIndex..<hay.endIndex
        while let range = hay.range(of: needle, range: search) {
            let before = range.lowerBound == hay.startIndex ? nil : hay[hay.index(before: range.lowerBound)]
            let after = range.upperBound == hay.endIndex ? nil : hay[range.upperBound]
            let edge: (Character?) -> Bool = { $0.map { !$0.isLetter } ?? true }
            if edge(before) && edge(after) { return range }
            search = range.upperBound..<hay.endIndex
        }
        return nil
    }

    /// Lowercased, accents folded, and a slash or a hyphen read as a space,
    /// one character for one so an offset in it is an offset in the line.
    private static func normalize(_ s: String) -> String {
        String(s.lowercased().folding(options: .diacriticInsensitive, locale: nil).map { "/-_:".contains($0) ? " " : $0 })
    }
}
