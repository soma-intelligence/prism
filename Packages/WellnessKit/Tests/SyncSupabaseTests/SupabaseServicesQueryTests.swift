import Foundation
import Testing
import SyncCore
@testable import SyncSupabase

/// What the row helpers put on the wire, read off a stub URL protocol.
@Suite(.serialized) struct SupabaseServicesQueryTests {
    struct Row: Codable, Equatable, Sendable { let id: Int }

    private func services() -> SupabaseServices {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RowStub.self]
        return SupabaseServices.inMemory(
            configuration: SupabaseConfiguration(projectURL: URL(string: "https://stub.supabase.co")!, publishableKey: "sb_publishable_x", storageBucket: "b"),
            session: URLSession(configuration: configuration)
        )
    }

    @Test func ignoringDuplicatesAsksPostgrestToKeepTheRowThere() async throws {
        RowStub.reset(rows: [])
        try await services().upsert([Row(id: 1)], into: "ask_messages", onConflict: "user_id,client_id", ignoreDuplicates: true)
        let request = try #require(RowStub.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.query?.removingPercentEncoding?.contains("on_conflict=user_id,client_id") == true)
        #expect(request.value(forHTTPHeaderField: "Prefer")?.contains("resolution=ignore-duplicates") == true)
    }

    @Test func selectAllReadsEveryPage() async throws {
        RowStub.reset(rows: (0..<5).map { Row(id: $0) })
        let rows = try await services().selectAll(Row.self, from: "ask_conversations", where: "user_id", equals: "u", orderBy: "id", pageSize: 2)
        #expect(rows.map(\.id) == [0, 1, 2, 3, 4])
        #expect(RowStub.requests.count == 3)
        #expect(RowStub.requests.allSatisfy { $0.url?.query?.contains("user_id=eq.u") == true })
    }

    @Test func selectInBatchesKeepsTheQueryShort() async throws {
        RowStub.reset(rows: [Row(id: 7)])
        let rows = try await services().select(Row.self, from: "ask_messages", where: "conversation_id", in: ["a", "b", "c"], orderBy: "created_at", batch: 2)
        #expect(rows.map(\.id) == [7, 7])
        #expect(RowStub.requests.count == 2)
        #expect(RowStub.requests.first?.url?.query?.removingPercentEncoding?.contains("conversation_id=in.(a,b)") == true)
    }
}

/// Answers PostgREST requests from `rows`, honouring offset and limit, and
/// keeps every request it saw.
final class RowStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requests: [URLRequest] = []
    nonisolated(unsafe) static var rows: [SupabaseServicesQueryTests.Row] = []
    private static let lock = NSLock()

    static func reset(rows: [SupabaseServicesQueryTests.Row]) {
        lock.withLock {
            requests = []
            self.rows = rows
        }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let offset = items.first { $0.name == "offset" }.flatMap { Int($0.value ?? "") } ?? 0
        let limit = items.first { $0.name == "limit" }.flatMap { Int($0.value ?? "") }
        let page = Self.lock.withLock { () -> [SupabaseServicesQueryTests.Row] in
            Self.requests.append(request)
            let rest = Array(Self.rows.dropFirst(offset))
            return limit.map { Array(rest.prefix($0)) } ?? rest
        }
        let body = request.httpMethod == "GET" ? (try? JSONEncoder().encode(page)) ?? Data("[]".utf8) : Data()
        let response = HTTPURLResponse(url: request.url!, statusCode: request.httpMethod == "GET" ? 200 : 201, httpVersion: nil,
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
