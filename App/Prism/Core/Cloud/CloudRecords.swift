//
//  CloudRecords.swift
//  Prism
//

import CryptoKit
import Foundation
import SyncCore

/// The app's synced record types, one per table in
/// `supabase/migrations/20261003120300_app_records.sql`.
///
/// Each is a `SyncRecord`: SyncCore keeps it in the person's local database,
/// enqueues every change in its outbox in the same transaction, and pushes it
/// through `sync_push`. Keys are snake case and equal the server's typed
/// column names, which a trigger fills from the payload. Dates travel as
/// milliseconds since 1970, days as `yyyy-MM-dd` in the person's calendar.
nonisolated enum CloudRecords {
    static let moduleName = "PrismCloud"

    static let journalDays = RecordType("journal_days")
    static let checkInAnswers = RecordType("check_in_answers")
    static let moodLogs = RecordType("mood_logs")
    static let mindCheckIns = RecordType("mind_check_ins")
    static let trackLogs = RecordType("track_logs")
    static let labResults = RecordType("lab_results")
    static let scoresDaily = RecordType("scores_daily")
    static let notificationInbox = RecordType("notification_inbox")
    static let providerConnections = RecordType("provider_connections")

    static let all: [RecordType] = [
        journalDays, checkInAnswers, moodLogs, mindCheckIns, trackLogs,
        labResults, scoresDaily, notificationInbox, providerConnections,
    ]

    /// The local tables, created once in the session's database.
    static var module: SchemaModule {
        SchemaModule(
            name: moduleName,
            migrations: [
                Migration(module: moduleName, version: 1, sql: all.map(SyncTable.createStatement(for:)).joined(separator: "\n")),
            ],
            recordTypes: all
        )
    }

    /// A stable record id for a natural key: the same person, table and key
    /// give the same UUID on every phone, so a day logged on two phones is one
    /// row, not two. Name based (version 5 layout over SHA-256).
    static func id(_ type: RecordType, userID: String, key: String) -> RecordID {
        let digest = SHA256.hash(data: Data("\(userID.lowercased())|\(type.rawValue)|\(key)".utf8))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        let uuid = UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                               bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
        return RecordID(uuid.uuidString.lowercased())
    }

    /// A local entry's own UUID as a record id.
    static func id(_ uuid: UUID) -> RecordID {
        RecordID(uuid.uuidString.lowercased())
    }
}

/// A loose value for `detail` objects: a number, a word, or a yes or no.
nonisolated enum CloudValue: Codable, Equatable, Sendable {
    case number(Double)
    case text(String)
    case flag(Bool)

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let flag = try? container.decode(Bool.self) {
            self = .flag(flag)
        } else if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else {
            self = .text(try container.decode(String.self))
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .number(let value): try container.encode(value)
        case .text(let value): try container.encode(value)
        case .flag(let value): try container.encode(value)
        }
    }
}

nonisolated struct JournalDayRecord: SyncRecord {
    static let recordType = CloudRecords.journalDays
    var id: RecordID
    var day: String
    var tagsYes: [String]
    var tagsNo: [String]
    var feeling: Int?

    enum CodingKeys: String, CodingKey {
        case id, day, feeling
        case tagsYes = "tags_yes"
        case tagsNo = "tags_no"
    }
}

nonisolated struct CheckInAnswerRecord: SyncRecord {
    static let recordType = CloudRecords.checkInAnswers
    var id: RecordID
    var day: String
    var questionID: String
    /// yes, no, scale or number; nil when skipped.
    var answerKind: String?
    var answerValue: Int?
    var skipped: Bool
    var questionText: String?

    enum CodingKeys: String, CodingKey {
        case id, day, skipped
        case questionID = "question_id"
        case answerKind = "answer_kind"
        case answerValue = "answer_value"
        case questionText = "question_text"
    }
}

nonisolated struct MoodLogRecord: SyncRecord {
    static let recordType = CloudRecords.moodLogs
    var id: RecordID
    var loggedAt: Date
    /// momentary or daily.
    var kind: String
    /// Apple's scale, -1 to 1.
    var valence: Double
    var labels: [String]
    var associations: [String]
    /// The surface that logged it: mind or track.
    var origin: String

    enum CodingKeys: String, CodingKey {
        case id, kind, valence, labels, associations, origin
        case loggedAt = "logged_at"
    }
}

nonisolated struct MindCheckInRecord: SyncRecord {
    static let recordType = CloudRecords.mindCheckIns
    var id: RecordID
    var loggedAt: Date
    var energy: Int?
    var mood: Int?
    var focus: Int?
    var question: String?
    var answer: String?

    enum CodingKeys: String, CodingKey {
        case id, energy, mood, focus, question, answer
        case loggedAt = "logged_at"
    }
}

nonisolated struct TrackLogRecord: SyncRecord {
    static let recordType = CloudRecords.trackLogs
    var id: RecordID
    /// drink, meal, dose, supplement, practice, fast, measure, wake_rating.
    var kind: String
    var loggedAt: Date
    var endedAt: Date?
    var value: Double?
    var unit: String?
    var label: String?
    var detail: [String: CloudValue]

    enum CodingKeys: String, CodingKey {
        case id, kind, value, unit, label, detail
        case loggedAt = "logged_at"
        case endedAt = "ended_at"
    }
}

nonisolated struct LabResultRecord: SyncRecord {
    static let recordType = CloudRecords.labResults

    struct Marker: Codable, Equatable, Sendable {
        var marker: String
        var value: Double
        var unit: String
    }

    var id: RecordID
    var collectedOn: String
    var labName: String?
    var markers: [Marker]

    enum CodingKeys: String, CodingKey {
        case id, markers
        case collectedOn = "collected_on"
        case labName = "lab_name"
    }
}

nonisolated struct ScoreDayRecord: SyncRecord {
    static let recordType = CloudRecords.scoresDaily
    var id: RecordID
    var day: String
    var sleep: Int?
    var recovery: Int?
    var strain: Int?
    var stress: Int?
    var energy: Int?
}

nonisolated struct NotificationInboxRecord: SyncRecord {
    static let recordType = CloudRecords.notificationInbox
    var id: RecordID
    var deliveredAt: Date
    var kind: String
    var title: String
    var body: String
    var isRead: Bool
    var deepLink: String?

    enum CodingKeys: String, CodingKey {
        case id, kind, title, body
        case deliveredAt = "delivered_at"
        case isRead = "is_read"
        case deepLink = "deep_link"
    }
}

/// A linked outside service. Never a token: those stay in the Keychain, and
/// the server refuses a payload that names one.
nonisolated struct ProviderConnectionRecord: SyncRecord {
    static let recordType = CloudRecords.providerConnections
    var id: RecordID
    var provider: String
    var status: String
    var accountLabel: String?
    var lastSyncAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, provider, status
        case accountLabel = "account_label"
        case lastSyncAt = "last_sync_at"
    }
}
