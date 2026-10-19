import Foundation
import SyncCore

public struct SupabaseConfiguration: Sendable, Hashable {
    public let projectURL: URL
    public let publishableKey: String
    public let storageBucket: String

    public init(projectURL: URL, publishableKey: String, storageBucket: String) {
        self.projectURL = projectURL
        self.publishableKey = publishableKey
        self.storageBucket = storageBucket
    }
}

/// `RemoteRecordStore` over the `sync_push` and `sync_pull` Postgres functions
/// shipped in `supabase/migrations`.
public struct SupabaseRecordStore: RemoteRecordStore {
    public let configuration: SupabaseConfiguration
    private let http: any HTTPClient
    private let clock: any SyncClock

    public init(configuration: SupabaseConfiguration, http: any HTTPClient = URLSessionHTTPClient(), clock: any SyncClock = SystemClock()) {
        self.configuration = configuration
        self.http = http
        self.clock = clock
    }

    public func push(_ changes: [OutgoingChange], type: RecordType, token: AccessToken) async throws(RemoteError) -> [PushOutcome] {
        var encodedChanges: [[String: Any]] = []
        for change in changes {
            let payload: [String: Any]
            do {
                payload = try change.payload.jsonObject()
            } catch {
                throw .rejected(status: 0, reason: "payload of \(change.id) is not a JSON object")
            }
            encodedChanges.append([
                "id": change.id.rawValue,
                "base_revision": change.baseRevision.map { NSNumber(value: $0.rawValue) } ?? NSNull(),
                "deleted": change.deleted,
                "payload": payload,
            ])
        }
        let body = try Self.encode(["record_type": type.rawValue, "changes": encodedChanges])
        let response = try await http.send(rpcRequest("sync_push", body: body, token: token))
        if let error = HTTPStatus.error(for: response, now: clock.now().date) { throw error }
        return try Self.decodePushOutcomes(response.body)
    }

    public func pull(_ type: RecordType, after revision: Revision?, limit: Int, resyncing: Bool, token: AccessToken) async throws(RemoteError) -> PullPage {
        let body = try Self.encode([
            "record_type": type.rawValue,
            "after": revision.map { NSNumber(value: $0.rawValue) } ?? NSNull(),
            "page_limit": limit,
            "resyncing": resyncing,
        ])
        let response = try await http.send(rpcRequest("sync_pull", body: body, token: token))
        if let error = HTTPStatus.error(for: response, now: clock.now().date) { throw error }
        guard
            let object = Self.parse(response.body) as? [String: Any],
            let expired = object["cursor_expired"] as? Bool,
            let records = object["records"] as? [[String: Any]],
            let hasMore = object["has_more"] as? Bool
        else {
            throw .malformedResponse("pull response is missing fields")
        }
        if expired { throw .cursorExpired }
        var parsed: [RemoteRecord] = []
        for record in records {
            parsed.append(try Self.remoteRecord(record))
        }
        return PullPage(records: parsed, hasMore: hasMore)
    }

    private func rpcRequest(_ function: String, body: Data, token: AccessToken) -> HTTPRequest {
        HTTPRequest(
            method: "POST",
            url: configuration.projectURL.appending(path: "rest/v1/rpc/\(function)"),
            headers: [
                "apikey": configuration.publishableKey,
                "Authorization": "Bearer \(token.value)",
                "Content-Type": "application/json",
                "Accept": "application/json",
            ],
            body: .data(body),
            timeout: .seconds(30)
        )
    }

    static func encode(_ object: [String: Any]) throws(RemoteError) -> Data {
        do {
            return try JSONSerialization.data(withJSONObject: object)
        } catch {
            throw .rejected(status: 0, reason: "cannot encode request: \(error)")
        }
    }

    /// `nil` when `data` is not JSON; callers turn that into `malformedResponse`.
    static func parse(_ data: Data) -> Any? {
        do {
            return try JSONSerialization.jsonObject(with: data)
        } catch {
            return nil
        }
    }

    static func int64(_ value: Any?) -> Int64? {
        (value as? NSNumber)?.int64Value
    }

    static func decodePushOutcomes(_ data: Data) throws(RemoteError) -> [PushOutcome] {
        guard let items = parse(data) as? [[String: Any]] else {
            throw .malformedResponse("push response is not an array of objects")
        }
        var outcomes: [PushOutcome] = []
        for item in items {
            guard let id = item["id"] as? String, let outcome = item["outcome"] as? String else {
                throw .malformedResponse("push outcome without id or outcome")
            }
            switch outcome {
            case "applied":
                guard let revision = int64(item["revision"]) else {
                    throw .malformedResponse("applied outcome without revision")
                }
                outcomes.append(.applied(RecordID(id), Revision(revision)))
            case "conflict":
                guard let record = item["record"] as? [String: Any] else {
                    throw .malformedResponse("conflict outcome without record")
                }
                outcomes.append(.conflict(RecordID(id), try remoteRecord(record)))
            case "rejected":
                outcomes.append(.rejected(RecordID(id), reason: item["reason"] as? String ?? "rejected by server"))
            default:
                throw .malformedResponse("unknown outcome \(outcome)")
            }
        }
        return outcomes
    }

    static func remoteRecord(_ object: [String: Any]) throws(RemoteError) -> RemoteRecord {
        guard let id = object["id"] as? String, let revision = int64(object["revision"]), let deleted = object["deleted"] as? Bool else {
            throw .malformedResponse("record without id, revision or deleted flag")
        }
        var payload: RecordPayload?
        if let raw = object["payload"], !(raw is NSNull) {
            do {
                payload = try RecordPayload(jsonObject: raw)
            } catch {
                throw .malformedResponse("record \(id) has a payload that is not an object")
            }
        }
        return RemoteRecord(id: RecordID(id), revision: Revision(revision), deleted: deleted, payload: payload)
    }
}

/// `RemoteObjectStore` over Supabase Storage. Uploads are upserts.
public struct SupabaseObjectStore: RemoteObjectStore {
    public let configuration: SupabaseConfiguration
    private let http: any HTTPClient
    private let clock: any SyncClock

    public init(configuration: SupabaseConfiguration, http: any HTTPClient = URLSessionHTTPClient(), clock: any SyncClock = SystemClock()) {
        self.configuration = configuration
        self.http = http
        self.clock = clock
    }

    public func put(key: String, file: URL, sha256: String, contentType: String, token: AccessToken) async throws(RemoteError) {
        let request = HTTPRequest(
            method: "POST",
            url: configuration.projectURL.appending(path: "storage/v1/object/\(configuration.storageBucket)/\(key)"),
            headers: [
                "apikey": configuration.publishableKey,
                "Authorization": "Bearer \(token.value)",
                "Content-Type": contentType,
                "x-upsert": "true",
                "Cache-Control": "no-cache",
            ],
            body: .file(file),
            timeout: .seconds(300)
        )
        let response = try await http.send(request)
        if let error = HTTPStatus.error(for: response, now: clock.now().date) { throw error }
    }
}
