//
//  StoolReportReader.swift
//  Prism
//
//  Reads a stool test report on the device: a clinical lab's (calprotectin,
//  hidden blood, elastase, H. pylori) or a microbiome kit's (diversity, taxa,
//  the Firmicutes to Bacteroidetes ratio). The text comes from the blood
//  reader (a PDF's text layer or Vision's OCR), so nothing leaves the phone;
//  this file only finds the stool markers in it.
//
//  Conservative like the urine reader: a value is emitted only when it sits
//  on the same line as a label the catalog knows, and every value lands on
//  the confirm screen before anything is saved. A line whose value cannot be
//  read is left out, never guessed: a kit that prints "low" in words gives
//  no number, so it gives no value.
//

import Foundation

/// One stool marker found in a report, in the unit it was printed in.
nonisolated struct ExtractedStoolMarker: Sendable, Identifiable, Hashable {
    var id: String
    var value: Double
    var unit: String
}

nonisolated enum StoolReportReader {
    /// The FIT cut off when a report prints the haemoglobin as a number, in
    /// µg per gram (US Multi-Society Task Force 2017).
    static let fitPositiveFrom = 20.0

    /// (normalised label, catalog id), longest first.
    private static let labels: [(needle: String, id: String)] = {
        var pairs: [(String, String)] = []
        for marker in StoolCatalog.all {
            pairs.append((FunctionalReportReader.normalize(marker.name), marker.id))
            for alias in marker.aliases { pairs.append((FunctionalReportReader.normalize(alias), marker.id)) }
        }
        return pairs.filter { $0.0.count >= 2 }.sorted { $0.0.count > $1.0.count }
    }()

    static func detect(in text: String) -> [ExtractedStoolMarker] {
        var found: [String: ExtractedStoolMarker] = [:]
        var order: [String] = []
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = String(raw).trimmingCharacters(in: .whitespacesAndNewlines)
            let hay = FunctionalReportReader.normalize(line)
            let hits = labels.compactMap { label in FunctionalReportReader.range(of: label.needle, in: hay).map { (label, $0) } }
            guard let (hit, at) = hits.min(by: { a, b in
                      a.1.lowerBound != b.1.lowerBound ? a.1.lowerBound < b.1.lowerBound : a.0.needle.count > b.0.needle.count
                  }),
                  found[hit.id] == nil,
                  let marker = StoolCatalog.marker(id: hit.id) else { continue }
            let offset = hay.distance(from: hay.startIndex, to: at.upperBound)
            guard offset <= line.count else { continue }
            let tail = String(line.dropFirst(offset))
            guard let parsed = parse(tail, for: marker) else { continue }
            found[hit.id] = parsed
            order.append(hit.id)
        }
        return order.compactMap { found[$0] }
    }

    /// A positive or negative word for a qualitative marker (or, for the
    /// FIT, a haemoglobin number against its cut off), else the first number
    /// and the unit printed after it.
    static func parse(_ tail: String, for marker: StoolMarker) -> ExtractedStoolMarker? {
        if marker.isQualitative {
            let hay = " " + FunctionalReportReader.normalize(tail).replacingOccurrences(of: "(", with: " ")
                .replacingOccurrences(of: ")", with: " ") + " "
            let negative = [" negative ", " neg ", " negatif ", " not detected ", " non detecte ", " absent ", " none detected "]
            let positive = [" positive ", " pos ", " positif ", " detected ", " detecte ", " present "]
            if negative.contains(where: hay.contains) { return .init(id: marker.id, value: 0, unit: "") }
            if positive.contains(where: hay.contains) { return .init(id: marker.id, value: 1, unit: "") }
            if marker.id == "fit", let (value, _) = FunctionalReportReader.signedNumbers(in: tail).first {
                return .init(id: marker.id, value: value >= fitPositiveFrom ? 1 : 0, unit: "")
            }
            return nil
        }
        guard let (value, after) = FunctionalReportReader.signedNumbers(in: tail).first, value >= 0 else { return nil }
        let normalised = BloodMarkerCatalog.normalize(after)
        let unit = marker.acceptedUnits.keys.sorted { $0.count > $1.count }.first { normalised.contains($0) }
        return .init(id: marker.id, value: value, unit: unit ?? marker.unit)
    }
}
