//
//  BloodReportReader.swift
//  Prism
//
//  Reads a lab report on the device: the
//  text of a PDF (its text layer, or Vision's OCR when the PDF is a scan),
//  the text of a photographed page, and a conservative detector that emits a
//  marker only when a number sits next to a label the catalog knows. It never
//  invents a value, and nothing leaves the phone, and there is no cloud extractor.
//  Every value it finds goes through the confirm screen before it
//  is saved.
//

import Foundation
import CoreGraphics
#if canImport(PDFKit)
import PDFKit
#endif
#if canImport(Vision)
import Vision
#endif

/// One marker found in a report, in the unit it was printed in.
nonisolated struct ExtractedMarker: Sendable, Identifiable, Hashable {
    /// Catalog id.
    var id: String
    var name: String
    var value: Double
    var unit: String
    var refLow: Double?
    var refHigh: Double?
}

nonisolated enum BloodReportReader {
    /// Below this many useful characters a page, the text layer is too thin
    /// to trust and the page is read with OCR.
    static let minUsefulCharsPerPage = 40

    static func needsOCR(embeddedText: String, pageCount: Int) -> Bool {
        embeddedText.filter { !$0.isWhitespace }.count < max(1, pageCount) * minUsefulCharsPerPage
    }

    /// The text of a PDF: its text layer, or OCR over its rendered pages.
    static func text(fromPDF url: URL) async -> String {
        #if canImport(PDFKit) && canImport(Vision)
        return await Task.detached(priority: .userInitiated) { () -> String in
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            guard let document = PDFDocument(url: url) else { return "" }
            let embedded = (0..<document.pageCount).compactMap { document.page(at: $0)?.string }.joined(separator: "\n\n")
            guard needsOCR(embeddedText: embedded, pageCount: document.pageCount) else { return embedded }
            var chunks: [String] = []
            for index in 0..<document.pageCount {
                guard let page = document.page(at: index), let image = render(page) else { continue }
                chunks.append(ocr(image))
            }
            return [embedded, chunks.joined(separator: "\n")]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n\n")
        }.value
        #else
        return ""
        #endif
    }

    /// The text of a photographed page.
    static func text(fromImageData data: Data) async -> String {
        #if canImport(Vision)
        return await Task.detached(priority: .userInitiated) { () -> String in
            let request = recognizeRequest()
            let handler = VNImageRequestHandler(data: data, options: [:])
            try? handler.perform([request])
            return lines(request)
        }.value
        #else
        return ""
        #endif
    }

    #if canImport(PDFKit) && canImport(Vision)
    /// A page drawn at twice its size into a bitmap, for OCR.
    private static func render(_ page: PDFPage) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        let scale: CGFloat = 2
        let width = Int(bounds.width * scale), height = Int(bounds.height * scale)
        guard width > 0, height > 0,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        page.draw(with: .mediaBox, to: context)
        return context.makeImage()
    }

    private static func ocr(_ image: CGImage) -> String {
        let request = recognizeRequest()
        try? VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        return lines(request)
    }
    #endif

    #if canImport(Vision)
    private static func recognizeRequest() -> VNRecognizeTextRequest {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["en", "fr"]
        return request
    }

    private static func lines(_ request: VNRecognizeTextRequest) -> String {
        (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }
    #endif

    // MARK: - Detection

    /// (normalised label, catalog id), longest first so "t4 libre" wins over "t4".
    private static let labels: [(needle: String, id: String)] = {
        var pairs: [(String, String)] = []
        for marker in BloodMarkerCatalog.all {
            pairs.append((normalize(marker.name), marker.id))
            for alias in marker.aliases { pairs.append((normalize(alias), marker.id)) }
        }
        return pairs.filter { $0.0.count >= 2 }.sorted { $0.0.count > $1.0.count }
    }()

    /// Markers found line by line: the first value after a known label, its
    /// unit, and a printed range when the line carries one.
    static func detect(in text: String) -> [ExtractedMarker] {
        var found: [String: ExtractedMarker] = [:]
        var order: [String] = []
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = String(raw)
            let hay = normalize(line)
            guard let hit = labels.first(where: { containsWord(hay, $0.needle) }), found[hit.id] == nil,
                  let parsed = parse(after: hit.needle, in: line, hay: hay) else { continue }
            found[hit.id] = ExtractedMarker(
                id: hit.id, name: BloodMarkerCatalog.marker(id: hit.id)?.name ?? line,
                value: parsed.value, unit: parsed.unit ?? BloodMarkerCatalog.marker(id: hit.id)?.displayUnit ?? "",
                refLow: parsed.refLow, refHigh: parsed.refHigh)
            order.append(hit.id)
        }
        return order.compactMap { found[$0] }
    }

    /// True when `needle` sits in `hay` on word boundaries, so "ca" never
    /// matches inside "calcium" or "vs" inside a sentence.
    private static func containsWord(_ hay: String, _ needle: String) -> Bool {
        var search = hay.startIndex..<hay.endIndex
        while let range = hay.range(of: needle, range: search) {
            let before = range.lowerBound == hay.startIndex ? nil : hay[hay.index(before: range.lowerBound)]
            let after = range.upperBound == hay.endIndex ? nil : hay[range.upperBound]
            let edge: (Character?) -> Bool = { $0.map { !$0.isLetter } ?? true }
            if edge(before) && edge(after) { return true }
            search = range.upperBound..<hay.endIndex
        }
        return false
    }

    private struct Parsed { var value: Double; var unit: String?; var refLow: Double?; var refHigh: Double? }

    private static func parse(after needle: String, in line: String, hay: String) -> Parsed? {
        guard let range = hay.range(of: needle) else { return nil }
        let offset = hay.distance(from: hay.startIndex, to: range.upperBound)
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard offset <= trimmed.count else { return nil }
        let tail = String(trimmed.dropFirst(offset))
        guard let value = numbers(in: tail).first else { return nil }
        let unit = unitToken(in: tail)

        let scan: String
        let rangeNumbers: [Double]
        if let unit, let at = tail.range(of: unit, options: .caseInsensitive) {
            scan = String(tail[at.upperBound...])
            rangeNumbers = numbers(in: scan)
        } else {
            scan = tail
            rangeNumbers = Array(numbers(in: tail).dropFirst())
        }

        var low: Double?, high: Double?
        let lower = scan.lowercased()
        if scan.contains("-"), rangeNumbers.count >= 2 {
            if rangeNumbers[0] < rangeNumbers[1] { low = rangeNumbers[0]; high = rangeNumbers[1] }
        } else if lower.contains("<") || lower.contains("inf"), let bound = rangeNumbers.first {
            high = bound
        } else if lower.contains(">") || lower.contains("sup"), let bound = rangeNumbers.first {
            low = bound
        }
        return Parsed(value: value, unit: unit, refLow: low, refHigh: high)
    }

    /// Decimal numbers in order, a comma read as the decimal mark when it is one.
    static func numbers(in s: String) -> [Double] {
        var out: [Double] = []
        var current = ""
        func flush() {
            if let number = parseDecimal(current) { out.append(number) }
            current = ""
        }
        for ch in s {
            if ch.isNumber || ch == "." || ch == "," { current.append(ch) } else { flush() }
        }
        flush()
        return out
    }

    static func parseDecimal(_ raw: String) -> Double? {
        let body = raw.trimmingCharacters(in: .whitespaces).filter { "0123456789.,".contains($0) }
        guard body.contains(where: \.isNumber) else { return nil }
        let normalised: String
        switch (body.lastIndex(of: "."), body.lastIndex(of: ",")) {
        case let (dot?, comma?):
            normalised = comma > dot
                ? body.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
                : body.replacingOccurrences(of: ",", with: "")
        case (nil, _?):
            normalised = body.replacingOccurrences(of: ",", with: ".")
        default:
            normalised = body
        }
        return Double(normalised.trimmingCharacters(in: CharacterSet(charactersIn: ".")))
    }

    /// Known unit tokens, longest first so "ug/l" wins over "g/l".
    private static let knownUnits: [String] = [
        "mg/dl", "g/dl", "g/l", "mmol/l", "umol/l", "nmol/l", "pmol/l", "ug/l", "ng/ml", "pg/ml", "ng/l",
        "mu/l", "miu/l", "uiu/ml", "ui/ml", "iu/ml", "u/l", "iu/l", "%", "mm/h", "meq/l", "ug/dl", "ng/dl",
        "10^3/ul", "10^9/l", "mg/l", "fl",
    ].sorted { $0.count > $1.count }

    private static func unitToken(in s: String) -> String? {
        let normalised = BloodMarkerCatalog.normalize(s)
        return knownUnits.first { normalised.contains($0) }
    }

    private static func normalize(_ s: String) -> String {
        s.lowercased().folding(options: .diacriticInsensitive, locale: nil).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
