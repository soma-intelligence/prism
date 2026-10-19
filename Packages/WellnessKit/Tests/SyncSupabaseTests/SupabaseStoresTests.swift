import Foundation
import Testing
import SyncCore
@testable import SyncSupabase
import SyncTesting

@Suite struct SupabaseStoresTests {
    let configuration = SupabaseConfiguration(
        projectURL: URL(string: "https://project.example.supabase.co")!,
        publishableKey: "publishable",
        storageBucket: "health-raw"
    )
    let token = AccessToken(userID: UserID("user-a"), value: "jwt", expiresAt: .distantFuture)

    func object(_ data: Data) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func body(of request: HTTPRequest) throws -> Data {
        guard case .data(let data) = request.body else {
            throw RecordCodingError("expected a data body")
        }
        return data
    }

    @Test func pushCallsTheRPCWithTheChangesAndTheToken() async throws {
        let http = StubHTTPClient(responses: [StubHTTPClient.json(200, #"[{"id":"a","outcome":"applied","revision":7}]"#)])
        let store = SupabaseRecordStore(configuration: configuration, http: http, clock: ManualClock())
        let payload = try RecordPayload(encoding: TestNote(id: RecordID("a"), body: "x"))

        let outcomes = try await store.push(
            [OutgoingChange(id: RecordID("a"), baseRevision: nil, deleted: false, payload: payload)],
            type: TestNote.recordType,
            token: token
        )

        #expect(outcomes == [.applied(RecordID("a"), Revision(7))])
        let request = try #require(await http.requests.first)
        #expect(request.method == "POST")
        #expect(request.url.absoluteString == "https://project.example.supabase.co/rest/v1/rpc/sync_push")
        #expect(request.headers["Authorization"] == "Bearer jwt")
        #expect(request.headers["apikey"] == "publishable")
        let sent = try object(try body(of: request))
        #expect(sent["record_type"] as? String == "test_note")
        let change = try #require((sent["changes"] as? [[String: Any]])?.first)
        #expect(change["id"] as? String == "a")
        #expect(change["base_revision"] is NSNull)
        #expect(change["deleted"] as? Bool == false)
        #expect((change["payload"] as? [String: Any])?["body"] as? String == "x")
    }

    @Test func conflictAndRejectedOutcomesDecode() async throws {
        let response = #"""
        [
          {"id":"a","outcome":"conflict","record":{"id":"a","revision":9,"deleted":false,"payload":{"rating":0,"id":"a","body":"server"}}},
          {"id":"b","outcome":"conflict","record":{"id":"b","revision":0,"deleted":true,"payload":null}},
          {"id":"c","outcome":"rejected","reason":"check violation"}
        ]
        """#
        let http = StubHTTPClient(responses: [StubHTTPClient.json(200, response)])
        let store = SupabaseRecordStore(configuration: configuration, http: http, clock: ManualClock())

        let outcomes = try await store.push([], type: TestNote.recordType, token: token)

        #expect(outcomes == [
            .conflict(RecordID("a"), RemoteRecord(id: RecordID("a"), revision: Revision(9), deleted: false, payload: try RecordPayload(encoding: TestNote(id: RecordID("a"), body: "server")))),
            .conflict(RecordID("b"), RemoteRecord(id: RecordID("b"), revision: Revision(0), deleted: true, payload: nil)),
            .rejected(RecordID("c"), reason: "check violation"),
        ])
    }

    @Test func httpStatusesBecomeRemoteErrors() async throws {
        let now = Date(timeIntervalSince1970: 1_000)
        #expect(HTTPStatus.error(for: HTTPResponse(status: 204, headers: [:], body: Data()), now: now) == nil)
        #expect(HTTPStatus.error(for: HTTPResponse(status: 401, headers: [:], body: Data()), now: now) == .unauthorized)
        #expect(HTTPStatus.error(for: HTTPResponse(status: 403, headers: [:], body: Data()), now: now) == .forbidden)
        #expect(HTTPStatus.error(for: HTTPResponse(status: 429, headers: ["retry-after": "30"], body: Data()), now: now) == .transient(status: 429, retryAfter: .seconds(30)))
        #expect(HTTPStatus.error(for: HTTPResponse(status: 503, headers: [:], body: Data()), now: now) == .transient(status: 503, retryAfter: nil))
        #expect(HTTPStatus.error(for: HTTPResponse(status: 400, headers: [:], body: Data("bad".utf8)), now: now) == .rejected(status: 400, reason: "bad"))
        #expect(HTTPStatus.retryAfter("Thu, 01 Jan 1970 00:17:20 GMT", now: now) == .seconds(40))
        #expect(HTTPStatus.retryAfter("soon", now: now) == nil)

        let http = StubHTTPClient(responses: [StubHTTPClient.json(401, "{}")])
        let store = SupabaseRecordStore(configuration: configuration, http: http, clock: ManualClock())
        await #expect(throws: RemoteError.unauthorized) { try await store.push([], type: TestNote.recordType, token: token) }
    }

    @Test func malformedResponsesAreReported() async {
        let http = StubHTTPClient(responses: [StubHTTPClient.json(200, #"{"not":"an array"}"#), StubHTTPClient.json(200, #"[{"id":"a","outcome":"teleported"}]"#)])
        let store = SupabaseRecordStore(configuration: configuration, http: http, clock: ManualClock())
        await #expect(throws: RemoteError.malformedResponse("push response is not an array of objects")) {
            try await store.push([], type: TestNote.recordType, token: token)
        }
        await #expect(throws: RemoteError.malformedResponse("unknown outcome teleported")) {
            try await store.push([], type: TestNote.recordType, token: token)
        }
    }

    @Test func pullDecodesAPageAndReportsExpiredCursors() async throws {
        let page = #"{"cursor_expired":false,"has_more":true,"records":[{"id":"a","revision":3,"deleted":true,"payload":{"id":"a","body":"x","rating":0}}]}"#
        let expired = #"{"cursor_expired":true,"has_more":false,"records":[]}"#
        let http = StubHTTPClient(responses: [StubHTTPClient.json(200, page), StubHTTPClient.json(200, expired)])
        let store = SupabaseRecordStore(configuration: configuration, http: http, clock: ManualClock())

        let result = try await store.pull(TestNote.recordType, after: Revision(2), limit: 50, resyncing: false, token: token)

        #expect(result.hasMore)
        #expect(result.records.map(\.revision) == [Revision(3)])
        #expect(result.records.first?.deleted == true)
        let request = try #require(await http.requests.first)
        #expect(request.url.path == "/rest/v1/rpc/sync_pull")
        let sent = try object(try body(of: request))
        #expect(sent["after"] as? Int == 2)
        #expect(sent["page_limit"] as? Int == 50)
        await #expect(throws: RemoteError.cursorExpired) { try await store.pull(TestNote.recordType, after: Revision(1), limit: 50, resyncing: false, token: token) }
    }

    @Test func objectUploadIsAnUpsertOfTheFile() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let file = directory.url.appendingPathComponent("batch.ndjson.gz")
        try Data("x".utf8).write(to: file)
        let http = StubHTTPClient(responses: [StubHTTPClient.json(200, #"{"Key":"health-raw/raw/u/b.gz"}"#)])
        let store = SupabaseObjectStore(configuration: configuration, http: http, clock: ManualClock())

        try await store.put(key: "raw/user-a/steps/a_b_0123.ndjson.gz", file: file, sha256: "abc", contentType: "application/gzip", token: token)

        let request = try #require(await http.requests.first)
        #expect(request.url.absoluteString == "https://project.example.supabase.co/storage/v1/object/health-raw/raw/user-a/steps/a_b_0123.ndjson.gz")
        #expect(request.headers["x-upsert"] == "true")
        #expect(request.headers["Content-Type"] == "application/gzip")
        guard case .file(let sentFile) = request.body else {
            Issue.record("expected a file body")
            return
        }
        #expect(sentFile == file)
    }

    @Test func urlErrorsBecomeRemoteErrors() {
        #expect(URLSessionHTTPClient.map(URLError(.notConnectedToInternet)) == .offline)
        #expect(URLSessionHTTPClient.map(URLError(.networkConnectionLost)) == .offline)
        #expect(URLSessionHTTPClient.map(URLError(.timedOut)) == .timeout)
        #expect(URLSessionHTTPClient.map(URLError(.cancelled)) == .cancelled)
        #expect(URLSessionHTTPClient.map(URLError(.badServerResponse)) == .transient(status: nil, retryAfter: nil))
    }
}
