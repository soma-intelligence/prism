//
//  CloudRecordContractTests.swift
//  PrismTests
//

import Foundation
import Testing
import SyncCore
@testable import Prism

/// The app and the server agree on the names of a record's fields only through
/// `supabase/migrations/20261003120300_app_records.sql`: each table's trigger
/// reads keys out of the payload into typed columns, and a key it cannot find
/// becomes a null column without an error, by design. So a field renamed on one
/// side only would sync without complaint and leave a column empty forever.
/// These read the migration from the repository and hold every record to it.
@Suite("Cloud record contract")
struct CloudRecordContractTests {

    /// Columns the server reads that the app does not send yet. Each one is
    /// a known gap, not a typo: the column stays null until the app fills it.
    static let knownServerOnly: [String: Set<String>] = [:]

    /// The payload keys each table's trigger reads, by table.
    static func serverKeys() throws -> [String: Set<String>] {
        let url = StyleGuardTests.root.appendingPathComponent("supabase/migrations/20261003120300_app_records.sql")
        let sql = try String(contentsOf: url, encoding: .utf8)
        let function = try NSRegularExpression(
            pattern: #"create or replace function public\.(\w+)_project\(\)(.*?)\$\$;"#,
            options: [.dotMatchesLineSeparators]
        )
        let key = try NSRegularExpression(pattern: #"new\.payload(?:\s*->>?\s*|,\s*)'(\w+)'"#)

        var tables: [String: Set<String>] = [:]
        for match in function.matches(in: sql, range: NSRange(sql.startIndex..., in: sql)) {
            guard let name = Range(match.range(at: 1), in: sql), let body = Range(match.range(at: 2), in: sql) else { continue }
            let text = String(sql[body])
            let keys = key.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { found in
                Range(found.range(at: 1), in: text).map { String(text[$0]) }
            }
            tables[String(sql[name])] = Set(keys)
        }
        return tables
    }

    /// The keys a record sends, with every optional field filled so none is
    /// left out of the payload. The record id is the row's id, not a column the
    /// trigger reads.
    static func appKeys<Record: Encodable>(_ record: Record) throws -> Set<String> {
        Set(try RecordPayload(encoding: record).jsonObject().keys).subtracting(["id"])
    }

    /// One fully filled record of every type the app syncs, by table.
    static func everyRecord() throws -> [String: Set<String>] {
        let id = RecordID("0f8fad5b-d9cb-469f-a165-70867728950e")
        let now = Date(timeIntervalSince1970: 1_791_028_800)
        return [
            "journal_days": try appKeys(JournalDayRecord(id: id, day: "2026-10-03", tagsYes: ["sauna"], tagsNo: ["nap"], feeling: 4)),
            "check_in_answers": try appKeys(CheckInAnswerRecord(id: id, day: "2026-10-03", questionID: "sleep.rested",
                                                                answerKind: "scale", answerValue: 4, skipped: false,
                                                                questionText: "How rested do you feel?")),
            "mood_logs": try appKeys(MoodLogRecord(id: id, loggedAt: now, kind: "daily", valence: 0.3,
                                                   labels: ["calm"], associations: ["work"], origin: "mind")),
            "mind_check_ins": try appKeys(MindCheckInRecord(id: id, loggedAt: now, energy: 3, mood: 2, focus: 4,
                                                            question: "Slept badly?", answer: "no")),
            "track_logs": try appKeys(TrackLogRecord(id: id, kind: "fast", loggedAt: now, endedAt: now, value: 16,
                                                     unit: "h", label: "fast", detail: ["note": .text("ok")])),
            "lab_results": try appKeys(LabResultRecord(id: id, collectedOn: "2026-10-03", labName: "Cerba",
                                                       markers: [.init(marker: "ferritin", value: 80, unit: "ng/mL")])),
            "scores_daily": try appKeys(ScoreDayRecord(id: id, day: "2026-10-03", sleep: 80, recovery: 64, strain: 11,
                                                       stress: 32, energy: 70)),
            "notification_inbox": try appKeys(NotificationInboxRecord(id: id, deliveredAt: now, kind: "bedtime",
                                                                      title: "Wind down", body: "Bed in 45 min.",
                                                                      isRead: false, deepLink: "soma://sleep")),
            "provider_connections": try appKeys(ProviderConnectionRecord(id: id, provider: "oura", status: "connected",
                                                                         accountLabel: "ada", lastSyncAt: now, connectedAt: now)),
        ]
    }

    @Test("Every synced table has a trigger in the migration, and every trigger a record")
    func sameTables() throws {
        let server = try Self.serverKeys()
        let app = try Self.everyRecord()
        #expect(Set(server.keys) == Set(CloudRecords.all.map(\.rawValue)))
        #expect(Set(app.keys) == Set(server.keys))
    }

    @Test("Every field the app sends is a column the server fills")
    func appKeysReachColumns() throws {
        let server = try Self.serverKeys()
        for (table, keys) in try Self.everyRecord() {
            let unread = keys.subtracting(server[table] ?? [])
            #expect(unread.isEmpty, "\(table) sends \(unread.sorted()) and the server never reads them")
        }
    }

    @Test("Every column the server fills is a field the app sends, known gaps aside")
    func columnsHaveFields() throws {
        let app = try Self.everyRecord()
        for (table, keys) in try Self.serverKeys() {
            let missing = keys.subtracting(app[table] ?? []).subtracting(Self.knownServerOnly[table] ?? [])
            #expect(missing.isEmpty, "\(table) reads \(missing.sorted()) and the app never sends them")
        }
    }

    @Test("A known gap is still a gap: once the app sends it, it comes off the list")
    func knownGapsAreCurrent() throws {
        let app = try Self.everyRecord()
        for (table, keys) in Self.knownServerOnly {
            #expect(keys.isDisjoint(with: app[table] ?? []), "\(table) now sends \(keys.sorted())")
        }
    }

    @Test("A detail value keeps its kind through a payload: numbers stay numbers, flags stay flags")
    func detailValuesRoundTrip() throws {
        let values: [String: CloudValue] = [
            "zero": .number(0), "one": .number(1), "dose": .number(2.5),
            "on": .flag(true), "off": .flag(false), "word": .text("lunch"),
        ]
        let record = TrackLogRecord(id: RecordID("x"), kind: "meal", loggedAt: Date(timeIntervalSince1970: 0),
                                    endedAt: nil, value: nil, unit: nil, label: nil, detail: values)
        let decoded = try RecordPayload(encoding: record).decode(TrackLogRecord.self)
        #expect(decoded.detail == values)
    }
}
