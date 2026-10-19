import Foundation
import SyncCore
import SyncSupabase

/// Where Health rows go. A protocol so the uploader is tested without a server.
///
/// Every method is idempotent: an upsert on the table's natural key, or a
/// delete by identifier. A call that failed halfway is simply made again.
/// Failures are `AuthorizedCallError`, the foundation's own classification.
public protocol HealthCloudWriter: Sendable {
    func upsertSamples(_ rows: [HealthSampleRow]) async throws(AuthorizedCallError)
    func deleteSamples(_ uuids: [UUID]) async throws(AuthorizedCallError)
    func upsertDaily(_ rows: [HealthDailyRow]) async throws(AuthorizedCallError)
    func upsertSyncState(_ rows: [HealthSyncStateRow]) async throws(AuthorizedCallError)
}

/// The writer over PostgREST, through the Supabase client's session.
public struct SupabaseHealthWriter: HealthCloudWriter {
    public static let samplesTable = "health_samples"
    public static let dailyTable = "health_daily"
    public static let syncStateTable = "health_sync_state"

    private let services: SupabaseServices

    public init(services: SupabaseServices) {
        self.services = services
    }

    public func upsertSamples(_ rows: [HealthSampleRow]) async throws(AuthorizedCallError) {
        do {
            try await services.upsert(rows, into: Self.samplesTable, onConflict: "user_id,hk_uuid")
        } catch {
            throw .remote(error)
        }
    }

    public func deleteSamples(_ uuids: [UUID]) async throws(AuthorizedCallError) {
        // A URL has a length cap; 200 identifiers stay well under it.
        let values = uuids.map { $0.uuidString.lowercased() }
        for start in stride(from: 0, to: values.count, by: 200) {
            let chunk = Array(values[start..<min(start + 200, values.count)])
            do {
                try await services.delete(from: Self.samplesTable, where: "hk_uuid", in: chunk)
            } catch {
                throw .remote(error)
            }
        }
    }

    public func upsertDaily(_ rows: [HealthDailyRow]) async throws(AuthorizedCallError) {
        do {
            try await services.upsert(rows, into: Self.dailyTable, onConflict: "user_id,metric,day")
        } catch {
            throw .remote(error)
        }
    }

    public func upsertSyncState(_ rows: [HealthSyncStateRow]) async throws(AuthorizedCallError) {
        do {
            try await services.upsert(rows, into: Self.syncStateTable, onConflict: "user_id,installation_id,metric")
        } catch {
            throw .remote(error)
        }
    }
}
