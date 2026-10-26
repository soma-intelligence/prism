//
//  GenomeFileReader.swift
//  Prism
//
//  Reads a consumer DNA raw data file on the device: 23andMe's text (comment
//  lines under "#", then rsid, chromosome, position, genotype) or
//  AncestryDNA's (a "#" preamble, a header line, then rsid, chromosome,
//  position, allele1, allele2), either as the .txt or inside the .zip the
//  provider hands out.
//
//  The file is streamed in chunks, so a 25 MB file never sits in memory, and
//  only the variants Soma reads are kept, with a count of every line read.
//  A zip is opened by hand (the central directory, then the entry's raw
//  DEFLATE through Apple's Compression), since Foundation has no zip reader;
//  ZIP64 archives, which no provider ships, are refused with a word to unzip
//  the file first. Nothing is uploaded, ever.
//

import Foundation
import Compression

nonisolated enum GenomeProvider: String, Codable, Sendable {
    case twentyThreeAndMe, ancestry, unknown

    var title: String {
        switch self {
        case .twentyThreeAndMe: "23andMe"
        case .ancestry: "AncestryDNA"
        case .unknown: "DNA file"
        }
    }
}

/// What a file held: who wrote it, how many genotypes it carried, and the
/// raw genotype of each wanted variant as the file wrote it.
nonisolated struct GenomeParse: Sendable, Equatable {
    var provider: GenomeProvider = .unknown
    var build: String?
    var snpsRead = 0
    var noCalls = 0
    var genotypes: [String: String] = [:]
}

nonisolated enum GenomeFileReader {
    enum Failure: Error, Equatable {
        case unreadable
        case notAGenomeFile
        /// A ZIP64 archive, or an entry compressed with something other
        /// than DEFLATE: unzip it first.
        case unsupportedZip
        case noTextInZip

        var message: String {
            switch self {
            case .unreadable: "Soma couldn't open that file."
            case .notAGenomeFile: "That file doesn't look like a 23andMe or AncestryDNA raw data file."
            case .unsupportedZip: "Soma can't open this zip. Unzip it in Files, then choose the .txt inside."
            case .noTextInZip: "The zip has no .txt file inside. Choose the raw data .txt instead."
            }
        }
    }

    static let chunkSize = 256 * 1024

    /// Reads `url` off the main actor.
    static func read(url: URL, wanted: Set<String> = GenomeCatalog.wanted) async throws -> GenomeParse {
        try await Task.detached(priority: .userInitiated) {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            return try readNow(url: url, wanted: wanted)
        }.value
    }

    static func readNow(url: URL, wanted: Set<String>) throws -> GenomeParse {
        guard let handle = try? FileHandle(forReadingFrom: url) else { throw Failure.unreadable }
        defer { try? handle.close() }
        let magic = (try? handle.read(upToCount: 4)) ?? Data()
        let scanner = GenomeLineScanner(wanted: wanted)
        if magic.starts(with: [0x50, 0x4B, 0x03, 0x04]) {
            try readZip(handle, into: scanner)
        } else {
            try handle.seek(toOffset: 0)
            while let chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty {
                scanner.feed(chunk)
            }
        }
        scanner.finish()
        guard scanner.result.snpsRead > 0 else { throw Failure.notAGenomeFile }
        return scanner.result
    }

    /// Parses text already in memory, for tests and small files.
    static func parse(text: String, wanted: Set<String> = GenomeCatalog.wanted) -> GenomeParse {
        let scanner = GenomeLineScanner(wanted: wanted)
        scanner.feed(Data(text.utf8))
        scanner.finish()
        return scanner.result
    }

    // MARK: Zip

    private static func readZip(_ handle: FileHandle, into scanner: GenomeLineScanner) throws {
        let size = try handle.seekToEnd()
        let tailLength = min(size, 66_000)
        try handle.seek(toOffset: size - tailLength)
        let tail = [UInt8]((try handle.read(upToCount: Int(tailLength))) ?? Data())
        // The end of central directory record, searched from the end.
        guard tail.count >= 22, let end = stride(from: tail.count - 22, through: 0, by: -1).first(where: {
            tail[$0] == 0x50 && tail[$0 + 1] == 0x4B && tail[$0 + 2] == 0x05 && tail[$0 + 3] == 0x06
        }) else { throw Failure.unsupportedZip }
        let entries = Int(le16(tail, end + 10))
        let directorySize = le32(tail, end + 12)
        let directoryOffset = le32(tail, end + 16)
        guard directoryOffset != 0xFFFF_FFFF, directorySize != 0xFFFF_FFFF, entries != 0xFFFF else { throw Failure.unsupportedZip }

        try handle.seek(toOffset: UInt64(directoryOffset))
        let directory = [UInt8]((try handle.read(upToCount: Int(directorySize))) ?? Data())
        var at = 0
        var chosen: (method: UInt16, compressed: UInt32, offset: UInt32)?
        for _ in 0..<entries {
            guard at + 46 <= directory.count, le32(directory, at) == 0x0201_4B50 else { break }
            let method = le16(directory, at + 10)
            let compressed = le32(directory, at + 20)
            let nameLength = Int(le16(directory, at + 28))
            let extraLength = Int(le16(directory, at + 30))
            let commentLength = Int(le16(directory, at + 32))
            let offset = le32(directory, at + 42)
            guard at + 46 + nameLength <= directory.count else { break }
            let name = String(decoding: directory[(at + 46)..<(at + 46 + nameLength)], as: UTF8.self)
            let lower = name.lowercased()
            if !lower.hasPrefix("__macosx"), !lower.hasSuffix("/"), lower.hasSuffix(".txt") || lower.hasSuffix(".csv") || lower.hasSuffix(".tsv") {
                chosen = (method, compressed, offset)
                break
            }
            at += 46 + nameLength + extraLength + commentLength
        }
        guard let chosen else { throw Failure.noTextInZip }
        guard chosen.compressed != 0xFFFF_FFFF, chosen.offset != 0xFFFF_FFFF, chosen.method == 0 || chosen.method == 8 else {
            throw Failure.unsupportedZip
        }

        try handle.seek(toOffset: UInt64(chosen.offset))
        let local = [UInt8]((try handle.read(upToCount: 30)) ?? Data())
        guard local.count == 30, le32(local, 0) == 0x0403_4B50 else { throw Failure.unsupportedZip }
        let dataStart = UInt64(chosen.offset) + 30 + UInt64(le16(local, 26)) + UInt64(le16(local, 28))
        try handle.seek(toOffset: dataStart)

        var remaining = Int(chosen.compressed)
        if chosen.method == 0 {
            while remaining > 0, let chunk = try handle.read(upToCount: min(chunkSize, remaining)), !chunk.isEmpty {
                scanner.feed(chunk)
                remaining -= chunk.count
            }
        } else {
            // Compression's ZLIB is raw DEFLATE (RFC 1951), which is what a zip holds.
            let filter = try OutputFilter(.decompress, using: .zlib) { data in
                if let data { scanner.feed(data) }
            }
            while remaining > 0, let chunk = try handle.read(upToCount: min(chunkSize, remaining)), !chunk.isEmpty {
                try filter.write(chunk)
                remaining -= chunk.count
            }
            try filter.finalize()
        }
    }

    private static func le16(_ bytes: [UInt8], _ at: Int) -> UInt16 {
        UInt16(bytes[at]) | UInt16(bytes[at + 1]) << 8
    }

    private static func le32(_ bytes: [UInt8], _ at: Int) -> UInt32 {
        UInt32(bytes[at]) | UInt32(bytes[at + 1]) << 8 | UInt32(bytes[at + 2]) << 16 | UInt32(bytes[at + 3]) << 24
    }
}

/// Lines out of chunks: holds the partial line between two chunks, reads
/// each whole one, and keeps only what is wanted. Used from one task at a
/// time.
nonisolated final class GenomeLineScanner: @unchecked Sendable {
    private let wanted: Set<String>
    private var pending = Data()
    private(set) var result = GenomeParse()

    init(wanted: Set<String>) { self.wanted = wanted }

    func feed(_ chunk: Data) {
        pending.append(chunk)
        var start = pending.startIndex
        while let newline = pending[start...].firstIndex(of: 0x0A) {
            line(pending[start..<newline])
            start = pending.index(after: newline)
        }
        pending = Data(pending[start...])
    }

    func finish() {
        if !pending.isEmpty { line(pending[...]) }
        pending = Data()
    }

    private func line(_ bytes: Data) {
        guard let first = bytes.first else { return }
        // "#" lines are the preamble: who wrote the file and on which build.
        if first == 0x23 {
            let text = String(decoding: bytes, as: UTF8.self).lowercased()
            if text.contains("23andme") { result.provider = .twentyThreeAndMe }
            if text.contains("ancestrydna") { result.provider = .ancestry }
            if result.build == nil {
                if text.contains("build 37") || text.contains("grch37") { result.build = "GRCh37" }
                else if text.contains("build 38") || text.contains("grch38") { result.build = "GRCh38" }
                else if text.contains("build 36") { result.build = "NCBI36" }
            }
            return
        }
        // Only lines that start with an rsid or a provider's internal id count.
        guard first == 0x72 || first == 0x69 else { return }   // "r", "i"
        var text = String(decoding: bytes, as: UTF8.self)
        if text.hasSuffix("\r") { text.removeLast() }
        let fields = text.split(whereSeparator: { $0 == "\t" || $0 == "," || $0 == " " })
        guard fields.count >= 4 else { return }
        let id = String(fields[0])
        if id == "rsid" { return }   // AncestryDNA's column header
        let genotype: String
        if fields.count >= 5 {
            genotype = String(fields[3]) + String(fields[4])
            if result.provider == .unknown { result.provider = .ancestry }
        } else {
            genotype = String(fields[3])
        }
        result.snpsRead += 1
        let called = genotype.filter { "ACGTDI".contains($0) }
        if called.isEmpty || genotype.contains("-") || genotype.contains("0") { result.noCalls += 1 }
        if wanted.contains(id) { result.genotypes[id] = called.isEmpty ? "--" : called }
    }
}
