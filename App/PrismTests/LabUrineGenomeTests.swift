//
//  LabUrineGenomeTests.swift
//  PrismTests
//

import Foundation
import Testing
import CoreGraphics
import Compression
@testable import Prism

/// The urine and genome halves of the Body lab: the urine catalog and its
/// ranges, the report reader on sample text, the dipstick colour match on
/// synthetic strips, the DNA file reader on small files of both formats
/// (plain and zipped), the strand rules, the APOE table, and the stores.
@Suite("Lab: urine and genome")
@MainActor
struct LabUrineGenomeTests {
    // MARK: Urine catalog

    @Test("Every pad's chart runs low to high, and its first step is the usual one")
    func padCharts() {
        #expect(UrineCatalog.pads.count == 10)
        for marker in UrineCatalog.pads {
            let values = marker.steps.map(\.value)
            #expect(values == values.sorted(), "\(marker.id) steps out of order")
            #expect(Set(values).count == values.count, "\(marker.id) repeats a step")
            guard let first = marker.steps.first else { continue }
            if marker.id == "ph" || marker.id == "specificGravity" { continue }
            #expect(marker.status(forStorage: first.value) == .normal, "\(marker.id) first step should be usual")
            #expect(marker.status(forStorage: marker.steps.last!.value) == .high, "\(marker.id) last step should be flagged")
        }
    }

    @Test("Urine ranges and units match their sources")
    func urineRanges() throws {
        let sg = try #require(UrineCatalog.marker(id: "specificGravity"))
        #expect(sg.status(forStorage: 1.015) == .normal)
        #expect(sg.status(forStorage: 1.000) == .low)
        #expect(sg.status(forStorage: 1.035) == .high)
        let ph = try #require(UrineCatalog.marker(id: "ph"))
        #expect(ph.status(forStorage: 6) == .normal)
        #expect(ph.status(forStorage: 8.5) == .high)
        let acr = try #require(UrineCatalog.marker(id: "acr"))
        #expect(acr.refHigh == 30)
        let fromMmol = try #require(acr.toStorage(3, from: "mg/mmol"))
        #expect(abs(fromMmol - 26.52) < 0.01)
        let glucose = try #require(UrineCatalog.marker(id: "glucose"))
        #expect(abs((glucose.toStorage(1, from: "mmol/L") ?? 0) - 18.016) < 0.001)
        let creatinine = try #require(UrineCatalog.marker(id: "creatinine"))
        #expect(creatinine.status(forStorage: 110) == .normal)
        #expect(abs((creatinine.toStorage(10, from: "mmol/L") ?? 0) - 113.1) < 0.01)
        #expect(UrineCatalog.marker(id: "albumin")?.refHigh == 30)
    }

    @Test("A pad value reads as its chart word")
    func padText() {
        #expect(UrineValue(key: "protein", value: 15, enteredUnit: "mg/dL", source: .camera).text == "Trace")
        #expect(UrineValue(key: "nitrite", value: 0, enteredUnit: "", source: .camera).text == "Negative")
        #expect(UrineValue(key: "glucose", value: 250, enteredUnit: "mg/dL", source: .camera).text == "250 mg/dL")
        #expect(UrineValue(key: "specificGravity", value: 1.018, enteredUnit: "", source: .extracted).text == "1.018")
        #expect(UrineValue(key: "protein", value: 15, enteredUnit: "mg/dL", source: .camera).isOutside)
    }

    // MARK: Urine report

    @Test("A urinalysis report reads numbers, words and grades")
    func urineReport() throws {
        let text = """
        URINALYSIS, random sample
        Specific gravity     1.020     1.005 - 1.030
        pH                   6.5       4.5 - 8.0
        Protein              Negative
        Glucose              Trace
        Ketones              2+
        Blood                Negative
        Nitrite              Positive
        Leukocyte esterase   1+
        Albumin/Creatinine ratio   12 mg/g   < 30
        Creatinine           110 mg/dL
        """
        let found = Dictionary(uniqueKeysWithValues: UrineReportReader.detect(in: text).map { ($0.id, $0) })
        let sg = try #require(found["specificGravity"])
        #expect(abs(sg.value - 1.020) < 0.0001)
        #expect(sg.refLow == 1.005 && sg.refHigh == 1.03)
        #expect(found["ph"]?.value == 6.5)
        #expect(found["protein"]?.value == 0)
        #expect(found["glucose"]?.value == 100)
        #expect(found["ketones"]?.value == 40)
        #expect(found["blood"]?.value == 0)
        #expect(found["nitrite"]?.value == 1)
        #expect(found["leukocytes"]?.value == 70)
        #expect(found["acr"]?.value == 12)
        #expect(found["acr"]?.unit == "mg/g")
        #expect(found["acr"]?.refHigh == 30)
        #expect(found["creatinine"]?.value == 110)
        #expect(found["albumin"] == nil)
    }

    @Test("A French report reads too")
    func urineReportFrench() {
        let text = """
        Densité urinaire : 1,015
        Protéines : négatif
        Leucocytes : traces
        Nitrites : absence
        """
        let found = Dictionary(uniqueKeysWithValues: UrineReportReader.detect(in: text).map { ($0.id, $0.value) })
        #expect(found["specificGravity"].map { abs($0 - 1.015) < 0.0001 } == true)
        #expect(found["protein"] == 0)
        #expect(found["leukocytes"] == 15)
        #expect(found["nitrite"] == 0)
    }

    // MARK: Dipstick colour match

    @Test("White balance undoes a tinted light exactly")
    func whiteBalance() {
        let colour = UrineRGB(red: 0.6, green: 0.4, blue: 0.3)
        let tint = (1.0, 0.82, 0.6)
        let (r, g, b) = colour.linear
        let seen = UrineRGB(linear: r * tint.0, g * tint.1, b * tint.2)
        let white = UrineRGB(linear: tint.0, tint.1, tint.2)
        let back = UrineDipstickReader.whiteBalanced(seen, white: white)
        #expect(UrineDipstickReader.deltaE(back, colour) < 0.5)
        #expect(UrineDipstickReader.deltaE(colour, colour) == 0)
    }

    @Test("Every chart step matches itself, and a colour near a step matches it")
    func matchSteps() {
        for marker in UrineCatalog.pads {
            for (index, step) in marker.steps.enumerated() {
                #expect(UrineDipstickReader.match(step.rgb, steps: marker.steps)?.index == index)
                let near = UrineRGB(red: min(1, step.red / 255 + 0.015), green: max(0, step.green / 255 - 0.01), blue: step.blue / 255)
                #expect(UrineDipstickReader.match(near, steps: marker.steps)?.index == index, "\(marker.id) step \(index)")
            }
        }
    }

    @Test("A colour far from the chart is marked unsure")
    func unsure() throws {
        let protein = try #require(UrineCatalog.marker(id: "protein"))
        let hit = try #require(UrineDipstickReader.match(UrineRGB(red: 0.9, green: 0.1, blue: 0.9), steps: protein.steps))
        #expect(hit.deltaE > UrinePadReading.unsureDeltaE)
    }

    /// A strip drawn into a bitmap under a warm light, with glare on one pad,
    /// read back pad by pad.
    @Test("A synthetic strip under warm light reads back its steps")
    func syntheticStrip() throws {
        let tint = (1.0, 0.84, 0.62)
        let picks = UrineCatalog.pads.enumerated().map { index, marker in (index * 3 + 1) % marker.steps.count }
        let image = try #require(Self.strip(picks: picks, tint: tint, glareOnPad: 4))
        let readings = try #require(UrineDipstickReader.read(image: image))
        #expect(readings.count == 10)
        for (index, reading) in readings.enumerated() {
            #expect(reading.markerID == UrineCatalog.padOrder[index])
            #expect(reading.stepIndex == picks[index], "\(reading.markerID)")
            #expect(!reading.isUnsure)
        }
        // Read the other way, the steps land on the mirrored pads.
        let flipped = try #require(UrineDipstickReader.read(image: image, reversed: true))
        #expect(flipped.first { $0.markerID == "glucose" }?.color != readings.first { $0.markerID == "glucose" }?.color)
    }

    static func strip(picks: [Int], tint: (Double, Double, Double), glareOnPad: Int?) -> CGImage? {
        let width = 1200, height = 100
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        func fill(_ colour: UrineRGB, _ rect: CGRect) {
            let (r, g, b) = colour.linear
            let lit = UrineRGB(linear: r * tint.0, g * tint.1, b * tint.2)
            context.setFillColor(CGColor(srgbRed: lit.red, green: lit.green, blue: lit.blue, alpha: 1))
            context.fill(rect)
        }
        let layout = UrineStripLayout.standard
        let w = Double(width), h = Double(height)
        // Paper, then the white strip.
        fill(UrineRGB(red: 0.97, green: 0.97, blue: 0.97), CGRect(x: 0, y: 0, width: w, height: h))
        fill(UrineRGB(red: 1, green: 1, blue: 1), CGRect(x: 0, y: h * 0.25, width: w, height: h * 0.5))
        for (index, marker) in UrineCatalog.pads.enumerated() {
            let centre = layout.centre(index) * w
            let side = layout.pitch * w * 0.8
            fill(marker.steps[picks[index]].rgb, CGRect(x: centre - side / 2, y: h * 0.25, width: side, height: h * 0.5))
            if index == glareOnPad {
                context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
                context.fill(CGRect(x: centre - 3, y: h * 0.45, width: 4, height: 6))
            }
        }
        return context.makeImage()
    }

    // MARK: Genome files

    static let twentyThree = """
    # This data file generated by 23andMe at: Mon Jan 01 00:00:00 2024
    # We are using reference human assembly build 37 (also known as Annotation Release 104).
    # rsid\tchromosome\tposition\tgenotype
    rs4477212\t1\t82154\tAA
    rs762551\t15\t75041917\tAC
    rs4988235\t2\t136608646\tAG
    rs1801133\t1\t11856378\tAA
    rs1815739\t11\t66328095\tCT
    rs9939609\t16\t53820527\tAT
    rs429358\t19\t45411941\tCT
    rs7412\t19\t45412079\tCC
    i5000001\t1\t100\t--
    rs12345\t1\t200\t--
    """

    static let ancestry = """
    #AncestryDNA raw data download
    #This file was generated by AncestryDNA at: 01/01/2024
    #Data was collected using AncestryDNA array version: V2.0
    #Genetic data is provided below as five TAB delimited columns.
    rsid\tchromosome\tposition\tallele1\tallele2\r
    rs3131972\t1\t752721\tA\tG\r
    rs762551\t15\t75041917\tA\tA\r
    rs4988235\t2\t136608646\tG\tG\r
    rs1801133\t1\t11856378\tC\tT\r
    rs429358\t19\t45411941\tT\tT\r
    rs7412\t19\t45412079\tC\tT\r
    rs99\t1\t1\t0\t0\r
    """

    @Test("A 23andMe file: provider, build, count, and only the wanted variants")
    func parse23andMe() {
        let parse = GenomeFileReader.parse(text: Self.twentyThree)
        #expect(parse.provider == .twentyThreeAndMe)
        #expect(parse.build == "GRCh37")
        #expect(parse.snpsRead == 10)
        #expect(parse.noCalls == 2)
        #expect(parse.genotypes.count == 7)
        #expect(parse.genotypes["rs4477212"] == nil)
        #expect(parse.genotypes["rs762551"] == "AC")
    }

    @Test("An AncestryDNA file: five columns, CRLF, zero for no call")
    func parseAncestry() {
        let parse = GenomeFileReader.parse(text: Self.ancestry)
        #expect(parse.provider == .ancestry)
        #expect(parse.snpsRead == 7)
        #expect(parse.noCalls == 1)
        #expect(parse.genotypes["rs762551"] == "AA")
        #expect(parse.genotypes["rs7412"] == "CT")
        let result = GenomeResult(importedAt: .now, parse: parse)
        // MTHFR written on the minus strand ("CT") is flipped to the plus strand.
        #expect(result.genotype(GenomeCatalog.byID["rs1801133"]!) == "AG")
        #expect(result.apoe?.type == .e2e3)
    }

    @Test("A stream split anywhere reads the same")
    func chunked() {
        let data = Data(Self.twentyThree.utf8)
        let scanner = GenomeLineScanner(wanted: GenomeCatalog.wanted)
        var at = 0
        while at < data.count {
            let end = min(at + 7, data.count)
            scanner.feed(data[at..<end])
            at = end
        }
        scanner.finish()
        #expect(scanner.result == GenomeFileReader.parse(text: Self.twentyThree))
    }

    @Test("A zipped file reads, deflated or stored")
    func zipped() throws {
        let text = Data(Self.twentyThree.utf8)
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        for deflate in [true, false] {
            let url = folder.appending(path: deflate ? "deflated.zip" : "stored.zip")
            try Self.zip(name: "genome_Jane_v5_Full.txt", data: text, deflate: deflate).write(to: url)
            let parse = try GenomeFileReader.readNow(url: url, wanted: GenomeCatalog.wanted)
            #expect(parse == GenomeFileReader.parse(text: Self.twentyThree))
        }
        let plain = folder.appending(path: "plain.txt")
        try text.write(to: plain)
        #expect(try GenomeFileReader.readNow(url: plain, wanted: GenomeCatalog.wanted).snpsRead == 10)
        let junk = folder.appending(path: "junk.txt")
        try Data("hello\nworld\n".utf8).write(to: junk)
        #expect(throws: GenomeFileReader.Failure.notAGenomeFile) { try GenomeFileReader.readNow(url: junk, wanted: GenomeCatalog.wanted) }
    }

    /// A one entry zip: local header, data, central directory, end record.
    /// The CRC is left at zero; the reader does not check it.
    static func zip(name: String, data: Data, deflate: Bool) throws -> Data {
        var body = data
        if deflate {
            var out = Data()
            let filter = try OutputFilter(.compress, using: .zlib) { chunk in if let chunk { out.append(chunk) } }
            try filter.write(data)
            try filter.finalize()
            body = out
        }
        func le16(_ v: Int) -> [UInt8] { [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF)] }
        func le32(_ v: Int) -> [UInt8] { [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 24) & 0xFF)] }
        let nameBytes = Array(name.utf8)
        let method = deflate ? 8 : 0
        var zip = Data()
        zip += le32(0x0403_4B50) + le16(20) + le16(0) + le16(method) + le16(0) + le16(0)
        zip += le32(0) + le32(body.count) + le32(data.count) + le16(nameBytes.count) + le16(0)
        zip += nameBytes
        zip += body
        let directoryOffset = zip.count
        var directory = Data()
        directory += le32(0x0201_4B50) + le16(20) + le16(20) + le16(0) + le16(method) + le16(0) + le16(0)
        directory += le32(0) + le32(body.count) + le32(data.count) + le16(nameBytes.count) + le16(0) + le16(0)
        directory += le16(0) + le16(0) + le32(0) + le32(0)
        directory += nameBytes
        zip += directory
        zip += le32(0x0605_4B50) + le16(0) + le16(0) + le16(1) + le16(1) + le32(directory.count) + le32(directoryOffset) + le16(0)
        return zip
    }

    // MARK: Strand and APOE

    @Test("Strand: the complement flips, a palindrome is read as written")
    func strand() throws {
        let mthfr = try #require(GenomeCatalog.byID["rs1801133"])
        #expect(mthfr.oriented("GA") == "AG")
        #expect(mthfr.oriented("CT") == "AG")
        #expect(mthfr.oriented("TT") == "AA")
        #expect(mthfr.oriented("--") == nil)
        let fto = try #require(GenomeCatalog.byID["rs9939609"])
        #expect(fto.isPalindromic)
        #expect(fto.oriented("TA") == "AT")
        #expect(fto.oriented("CG") == nil)
        let lct = try #require(GenomeCatalog.byID["rs4988235"])
        #expect(lct.meaning(of: "GG")?.headline.contains("fade") == true)
        for variant in GenomeCatalog.shown {
            #expect(variant.meanings.count == 3, "\(variant.id) needs a reading for each genotype")
            #expect(!variant.sources.isEmpty)
        }
    }

    @Test("APOE from rs429358 and rs7412, every pair")
    func apoeTable() {
        let table: [(String, String, APOEType, Bool)] = [
            ("TT", "TT", .e2e2, false), ("TT", "CT", .e2e3, false), ("TT", "CC", .e3e3, false),
            ("CT", "CT", .e2e4, true), ("CT", "CC", .e3e4, false), ("CC", "CC", .e4e4, false),
            ("CT", "TT", .e1e2, false), ("CC", "CT", .e1e4, false), ("CC", "TT", .e1e1, false),
        ]
        for (a, b, type, ambiguous) in table {
            let got = APOEType.from(rs429358: a, rs7412: b)
            #expect(got?.type == type, "\(a) \(b)")
            #expect(got?.isAmbiguous == ambiguous)
        }
        #expect(APOEType.e3e4.e4Copies == 1)
        #expect(APOEType.e4e4.e4Copies == 2)
        #expect(APOEType.from(rs429358: "T", rs7412: "CC") == nil)
    }

    // MARK: Stores

    @Test("The urine store keeps what is saved, and erases it")
    func urineStore() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "urine-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = UrinePanelStore(url: url)
        let old = UrinePanel(sampledAt: .now.addingTimeInterval(-86_400 * 40), createdAt: .now, kind: .labReport,
                             values: [UrineValue(key: "acr", value: 12, enteredUnit: "mg/g", source: .extracted)])
        let new = UrinePanel(sampledAt: .now, createdAt: .now, kind: .dipstick,
                             values: [UrineValue(key: "protein", value: 15, enteredUnit: "mg/dL", source: .camera),
                                      UrineValue(key: "acr", value: 18, enteredUnit: "mg/g", source: .manual)])
        store.save(old)
        store.save(new)
        let reopened = UrinePanelStore(url: url)
        #expect(reopened.panels.map(\.id) == [new.id, old.id])
        #expect(reopened.latest?.isApproximate == true)
        #expect(reopened.latest?.flagged.map(\.key) == ["protein"])
        #expect(reopened.previous(of: "acr")?.value.value == 12)
        reopened.eraseAll()
        #expect(reopened.panels.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(UrinePanelStore(url: url).panels.isEmpty)
    }

    @Test("The genome store keeps the variants, the choice and the file, and erases all three")
    func genomeStore() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "genome-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "genome.json")
        let source = folder.appending(path: "source.txt")
        try Data(Self.twentyThree.utf8).write(to: source)

        let store = GenomeStore(url: url, folder: folder)
        let kept = store.keep(copyOf: source)
        #expect(kept == "genome-raw.txt")
        store.save(GenomeResult(importedAt: .now, parse: GenomeFileReader.parse(text: Self.twentyThree), keptFileName: kept))
        store.setShowsAPOE(true)

        let reopened = GenomeStore(url: url, folder: folder)
        #expect(reopened.showsAPOE)
        #expect(reopened.result?.snpsRead == 10)
        #expect(reopened.result?.found.count == 5)
        #expect(reopened.result?.apoe?.type == .e3e4)
        // Only the catalog's variants are in the stored JSON.
        let json = try String(contentsOf: url, encoding: .utf8)
        #expect(!json.contains("rs4477212"))
        let keptURL = try #require(reopened.keptFileURL)
        #expect(FileManager.default.fileExists(atPath: keptURL.path))

        reopened.eraseAll()
        #expect(reopened.result == nil)
        #expect(!reopened.showsAPOE)
        #expect(!FileManager.default.fileExists(atPath: keptURL.path))
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }
}
