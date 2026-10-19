//
//  ZipWriter.swift
//  Prism
//

import Foundation

/// A ZIP archive written straight to disk, entries stored without
/// compression: Foundation has no ZIP writer, and an export is opened once by
/// a person or a script, so the format matters more than the size. Every
/// unzip tool reads it. Files over 4 GB are out of scope (no ZIP64).
nonisolated final class ZipWriter {
    nonisolated enum Failure: Error, Equatable {
        case tooLarge(String)
        case cannotOpen(URL)
    }

    private struct Entry {
        var name: Data
        var crc: UInt32
        var size: UInt32
        var offset: UInt32
        var time: UInt16
        var date: UInt16
    }

    private let handle: FileHandle
    private var entries: [Entry] = []
    private var offset: UInt64 = 0
    private let modified: Date

    init(url: URL, modified: Date = Date()) throws {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        guard let handle = FileHandle(forWritingAtPath: url.path) else { throw Failure.cannotOpen(url) }
        self.handle = handle
        self.modified = modified
    }

    /// Adds one file. `name` is its path inside the archive, `/` separated.
    func add(_ name: String, data: Data) throws {
        guard data.count < Int(UInt32.max), offset < UInt64(UInt32.max) else { throw Failure.tooLarge(name) }
        let nameData = Data(name.utf8)
        let (time, date) = Self.dosTime(modified)
        let entry = Entry(name: nameData, crc: Self.crc32(data), size: UInt32(data.count), offset: UInt32(offset), time: time, date: date)
        var header = Data()
        header.append(le32: 0x0403_4b50)
        header.append(le16: 20)            // version needed
        header.append(le16: 0x0800)        // UTF-8 names
        header.append(le16: 0)             // stored
        header.append(le16: entry.time)
        header.append(le16: entry.date)
        header.append(le32: entry.crc)
        header.append(le32: entry.size)
        header.append(le32: entry.size)
        header.append(le16: UInt16(nameData.count))
        header.append(le16: 0)
        header.append(nameData)
        try handle.write(contentsOf: header)
        try handle.write(contentsOf: data)
        offset += UInt64(header.count + data.count)
        entries.append(entry)
    }

    /// Writes the central directory and closes the file.
    func finish() throws {
        let start = offset
        var directory = Data()
        for entry in entries {
            directory.append(le32: 0x0201_4b50)
            directory.append(le16: 20)     // made by
            directory.append(le16: 20)     // needed
            directory.append(le16: 0x0800)
            directory.append(le16: 0)
            directory.append(le16: entry.time)
            directory.append(le16: entry.date)
            directory.append(le32: entry.crc)
            directory.append(le32: entry.size)
            directory.append(le32: entry.size)
            directory.append(le16: UInt16(entry.name.count))
            directory.append(le16: 0)      // extra
            directory.append(le16: 0)      // comment
            directory.append(le16: 0)      // disk
            directory.append(le16: 0)      // internal attributes
            directory.append(le32: 0)      // external attributes
            directory.append(le32: entry.offset)
            directory.append(entry.name)
        }
        var end = Data()
        end.append(le32: 0x0605_4b50)
        end.append(le16: 0)
        end.append(le16: 0)
        end.append(le16: UInt16(entries.count))
        end.append(le16: UInt16(entries.count))
        end.append(le32: UInt32(directory.count))
        end.append(le32: UInt32(start))
        end.append(le16: 0)
        try handle.write(contentsOf: directory)
        try handle.write(contentsOf: end)
        try handle.close()
    }

    static func dosTime(_ date: Date) -> (UInt16, UInt16) {
        let parts = Calendar(identifier: .gregorian).dateComponents(in: .current, from: date)
        let time = UInt16((parts.hour ?? 0) << 11 | (parts.minute ?? 0) << 5 | (parts.second ?? 0) / 2)
        let day = UInt16(max(0, (parts.year ?? 1980) - 1980) << 9 | (parts.month ?? 1) << 5 | (parts.day ?? 1))
        return (time, day)
    }

    private static let table: [UInt32] = (0..<256).map { index in
        var value = UInt32(index)
        for _ in 0..<8 { value = value & 1 == 1 ? 0xEDB8_8320 ^ (value >> 1) : value >> 1 }
        return value
    }

    /// CRC-32 as ZIP uses it (IEEE 802.3).
    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }
}

private extension Data {
    mutating func append(le16 value: UInt16) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }

    mutating func append(le32 value: UInt32) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}
