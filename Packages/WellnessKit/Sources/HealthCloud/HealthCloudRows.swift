import Foundation
import HealthExportCore
import SyncCore

/// One row of `public.health_samples`: a Health sample with its provenance,
/// keyed on `(user_id, hk_uuid)` so an upload can be replayed.
public struct HealthSampleRow: Codable, Sendable, Hashable {
    public let userID: String
    public let hkUUID: String
    public let metric: String
    public let kind: String
    public let value: Double
    public let unit: String
    public let startAt: Date
    public let endAt: Date
    public let sourceName: String?
    public let sourceBundle: String?
    public let deviceName: String?
    public let deviceModel: String?
    public let wasUserEntered: Bool

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case hkUUID = "hk_uuid"
        case metric, kind, value, unit
        case startAt = "start_at"
        case endAt = "end_at"
        case sourceName = "source_name"
        case sourceBundle = "source_bundle"
        case deviceName = "device_name"
        case deviceModel = "device_model"
        case wasUserEntered = "was_user_entered"
    }

    public init(userID: UserID, record: HealthSampleRecord, kind: HealthMetricKind) {
        let reading = record.reading
        self.userID = userID.rawValue.lowercased()
        self.hkUUID = record.uuid.uuidString.lowercased()
        self.metric = reading.metric
        self.kind = kind.rawValue
        self.value = reading.value.isFinite ? reading.value : 0
        self.unit = reading.unit.rawValue
        self.startAt = reading.start
        self.endAt = max(reading.end, reading.start)
        self.sourceName = reading.source
        self.sourceBundle = reading.sourceBundle
        self.deviceName = reading.device
        self.deviceModel = reading.deviceModel
        self.wasUserEntered = reading.wasUserEntered
    }
}

/// One row of `public.health_daily`: a metric over one local day.
///
/// A cumulative quantity carries `sum` (Health's own total, which removes the
/// overlap between a watch and a phone); a discrete one carries `avg`, `min`,
/// `max` and `count`; a category or a workout carries `count` and, in `sum`,
/// the seconds its samples covered.
public struct HealthDailyRow: Codable, Sendable, Hashable {
    public let userID: String
    public let metric: String
    /// `yyyy-MM-dd` in `timeZone`.
    public let day: String
    public let timeZone: String
    public let unit: String
    public let sum: Double?
    public let avg: Double?
    public let min: Double?
    public let max: Double?
    public let count: Int?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case metric, day
        case timeZone = "time_zone"
        case unit, sum, avg, min, max, count
    }

    public init(userID: UserID, metric: String, day: String, timeZone: String, unit: String, sum: Double?, avg: Double?, min: Double?, max: Double?, count: Int?) {
        self.userID = userID.rawValue.lowercased()
        self.metric = metric
        self.day = day
        self.timeZone = timeZone
        self.unit = unit
        self.sum = sum
        self.avg = avg
        self.min = min
        self.max = max
        self.count = count
    }
}

/// One row of `public.health_sync_state`: how far this installation's upload
/// of one metric has gone.
public struct HealthSyncStateRow: Codable, Sendable, Hashable {
    public let userID: String
    public let installationID: String
    public let metric: String
    /// The Health anchor, base64. Lets a reinstall on the same phone resume
    /// instead of sending everything again.
    public let anchor: String?
    public let lastSyncedAt: Date
    public let samplesUploaded: Int
    public let lastSampleEnd: Date?
    public let lastError: String?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case installationID = "installation_id"
        case metric, anchor
        case lastSyncedAt = "last_synced_at"
        case samplesUploaded = "samples_uploaded"
        case lastSampleEnd = "last_sample_end"
        case lastError = "last_error"
    }

    public init(userID: UserID, installationID: String, metric: String, anchor: Data?, lastSyncedAt: Date, samplesUploaded: Int, lastSampleEnd: Date?, lastError: String?) {
        self.userID = userID.rawValue.lowercased()
        self.installationID = installationID
        self.metric = metric
        self.anchor = anchor?.base64EncodedString()
        self.lastSyncedAt = lastSyncedAt
        self.samplesUploaded = samplesUploaded
        self.lastSampleEnd = lastSampleEnd
        self.lastError = lastError
    }
}
