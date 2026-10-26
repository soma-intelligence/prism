//
//  DataExportTests.swift
//  PrismTests
//

import Foundation
import Testing
import HealthExportCore
@testable import Prism

/// A Health store that hands back its samples one per page, so the export has
/// to follow the anchor to the end to read them all. A metric named in
/// `failing` throws instead.
private struct PagedHealthSource: HealthAnchoredSampleSource {
    var records: [String: [HealthSampleRecord]] = [:]
    var failing: Set<String> = []
    var isAvailable = true

    func requestAuthorization(for metrics: [HealthMetric]) async throws {}
    func latest(_ metric: HealthMetric) async throws -> HealthReading? { nil }
    func total(_ metric: HealthMetric, from: Date, to: Date) async throws -> HealthReading? { nil }
    func average(_ metric: HealthMetric, from: Date, to: Date) async throws -> HealthReading? { nil }
    func samples(_ metric: HealthMetric, from: Date, to: Date, limit: Int) async throws -> [HealthReading] { [] }

    func changes(_ metric: HealthMetric, after anchor: Data?, limit: Int) async throws -> HealthSampleChanges {
        if failing.contains(metric.identifier) { throw CancellationError() }
        let all = records[metric.identifier] ?? []
        let index = anchor.flatMap { $0.first }.map(Int.init) ?? 0
        guard index < all.count else { return HealthSampleChanges(added: [], deleted: [], anchor: anchor, hasMore: false) }
        return HealthSampleChanges(added: [all[index]], deleted: [], anchor: Data([UInt8(index + 1)]), hasMore: index + 1 < all.count)
    }
}

/// Reads back an archive whose entries are stored, as `ZipWriter` writes them:
/// each local header, its name and its bytes, in order.
private func entries(of url: URL) throws -> [String: Data] {
    let data = try Data(contentsOf: url)
    func u16(_ at: Int) -> Int { Int(data[at]) | Int(data[at + 1]) << 8 }
    func u32(_ at: Int) -> Int { u16(at) | u16(at + 2) << 16 }

    var files: [String: Data] = [:]
    var offset = 0
    while offset + 30 <= data.count, u32(offset) == 0x0403_4b50 {
        let size = u32(offset + 18)
        let nameLength = u16(offset + 26)
        let extraLength = u16(offset + 28)
        let nameStart = offset + 30
        let name = String(decoding: data[nameStart..<nameStart + nameLength], as: UTF8.self)
        let bodyStart = nameStart + nameLength + extraLength
        files[name] = data[bodyStart..<bodyStart + size]
        offset = bodyStart + size
    }
    return files
}

@Suite("Data export", .serialized)
@MainActor
struct DataExportTests {
    let heartRate = "HKQuantityTypeIdentifierHeartRate"
    let steps = "HKQuantityTypeIdentifierStepCount"
    let now = Date(timeIntervalSince1970: 1_791_028_800)

    func record(_ value: Double, minutesAgo: Double) -> HealthSampleRecord {
        let start = now.addingTimeInterval(-minutesAgo * 60)
        return HealthSampleRecord(uuid: UUID(), reading: HealthReading(
            metric: heartRate, value: value, unit: .countPerMinute, start: start, end: start.addingTimeInterval(60),
            source: "Apple Watch", sourceBundle: "com.apple.health", device: "Apple Watch",
            deviceModel: "Watch Apple Inc.", wasUserEntered: false
        ))
    }

    /// Writes the archive from `source` into a folder of its own and reads it back.
    private func export(_ source: PagedHealthSource, scores: SomaScores? = nil) async throws -> [String: Data] {
        let folder = FileManager.default.temporaryDirectory.appending(path: "export-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let url = folder.appending(path: "soma.zip")
        let zip = try ZipWriter(url: url, modified: now)
        try await DataExport.write(into: zip, health: source, scores: scores, now: now)
        try zip.finish()
        return try entries(of: url)
    }

    @Test("The archive holds the README, the profile and one file per table")
    func everyTable() async throws {
        let files = try await export(PagedHealthSource())
        let expected: Set<String> = [
            "README.txt", "profile.json", "journal_days.json", "check_in_answers.json", "mood_logs.json",
            "mind_check_ins.json", "track_logs.json", "lab_results.json", "scores_daily.json", "notification_inbox.json",
            "provider_connections.json", "ask_conversations.json",
        ]
        #expect(expected.isSubset(of: Set(files.keys)))
        for (name, data) in files where name.hasSuffix(".json") {
            #expect((try? JSONSerialization.jsonObject(with: data)) != nil, "\(name) is not JSON")
        }
    }

    @Test("The scores go out as the days the account keeps, one record a day that has any")
    func scores() async throws {
        var scores = SomaScores.fixture
        scores.sleepSeries = [72, nil, 80]
        let files = try await export(PagedHealthSource(), scores: scores)
        let data = try #require(files["scores_daily.json"])
        let days = try #require(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        #expect(days.count == 2)

        let none = try await export(PagedHealthSource())
        let empty = try #require(none["scores_daily.json"])
        #expect((try JSONSerialization.jsonObject(with: empty) as? [Any])?.isEmpty == true)
    }

    @Test("The README names every file the archive holds at its top level")
    func readmeNamesEveryFile() async throws {
        let files = try await export(PagedHealthSource(records: [heartRate: [record(62, minutesAgo: 30)]]))
        let readme = String(decoding: try #require(files["README.txt"]), as: UTF8.self)
        for name in files.keys where !name.contains("/") && name != "README.txt" {
            #expect(readme.contains(name), "README.txt does not mention \(name)")
        }
        #expect(readme.contains("health/"))
    }

    @Test("Every Health sample is read across pages, one JSON line each, with its provenance")
    func healthSamples() async throws {
        let samples = [record(58, minutesAgo: 90), record(61, minutesAgo: 60), record(64, minutesAgo: 30)]
        let files = try await export(PagedHealthSource(records: [heartRate: samples]))

        let ndjson = try #require(files["health/\(heartRate).ndjson"])
        let lines = String(decoding: ndjson, as: UTF8.self).split(separator: "\n")
        #expect(lines.count == 3)

        let first = try #require(try JSONSerialization.jsonObject(with: Data(lines[0].utf8)) as? [String: Any])
        #expect(first["uuid"] as? String == samples[0].uuid.uuidString.lowercased())
        #expect(first["metric"] as? String == heartRate)
        #expect(first["value"] as? Double == 58)
        #expect(first["unit"] as? String == "countPerMinute")
        #expect(first["source_bundle"] as? String == "com.apple.health")
        #expect(first["device_model"] as? String == "Watch Apple Inc.")
        #expect(first["was_user_entered"] as? Bool == false)
        let start = try #require(first["start"] as? String)
        #expect(ISO8601DateFormatter().date(from: start) == samples[0].reading.start)
    }

    @Test("A metric that holds nothing gets no file, and one that fails to read does not stop the rest")
    func healthGaps() async throws {
        let source = PagedHealthSource(records: [heartRate: [record(60, minutesAgo: 10)]], failing: [steps])
        let files = try await export(source)
        #expect(files.keys.filter { $0.hasPrefix("health/") } == ["health/\(heartRate).ndjson"])
    }

    @Test("Without a Health store the archive carries no Health folder")
    func healthUnavailable() async throws {
        let source = PagedHealthSource(records: [heartRate: [record(60, minutesAgo: 10)]], isAvailable: false)
        let files = try await export(source)
        #expect(!files.keys.contains { $0.hasPrefix("health/") })
        #expect(files["README.txt"] != nil)
    }
}
