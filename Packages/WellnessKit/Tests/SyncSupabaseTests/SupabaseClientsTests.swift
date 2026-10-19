import Foundation
import Testing
import Supabase
import SyncCore
@testable import SyncSupabase

@Suite struct SupabaseServicesTests {
    @Test func rowsEncodeWithMillisecondTimestamps() throws {
        struct Row: Encodable { let id: String; let at: Date }
        let data = try SupabaseServices.encoder().encode([Row(id: "a", at: Date(timeIntervalSince1970: 0))])
        #expect(String(decoding: data, as: UTF8.self) == #"[{"at":"1970-01-01T00:00:00.000Z","id":"a"}]"#)
    }

    @Test func postgresTimestampsDecode() {
        let date = SupabaseServices.date("2026-10-03T12:00:00.123456+00:00")
        #expect(abs((date?.timeIntervalSince1970 ?? 0) - 1_791_028_800.123) < 0.01)
        #expect(SupabaseServices.date("2026-10-03 12:00:00+00:00") != nil)
    }

    @Test func clientErrorsBecomeRemoteErrors() throws {
        let url = URL(string: "https://x.supabase.co")!
        func http(_ status: Int, retryAfter: String? = nil) -> HTTPError {
            HTTPError(data: Data("e".utf8), response: HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: retryAfter.map { ["Retry-After": $0] })!)
        }
        #expect(SupabaseServices.remoteError(URLError(.notConnectedToInternet)) == .offline)
        #expect(SupabaseServices.remoteError(http(503, retryAfter: "7")) == .transient(status: 503, retryAfter: .seconds(7)))
        #expect(SupabaseServices.remoteError(http(401)) == .unauthorized)
        #expect(SupabaseServices.remoteError(PostgrestError(code: "42501", message: "rls")) == .forbidden)
        #expect(SupabaseServices.remoteError(PostgrestError(code: "PGRST303", message: "jwt expired")) == .unauthorized)
        #expect(SupabaseServices.remoteError(StorageError(statusCode: "413", message: "too big")) == .rejected(status: 413, reason: "too big"))
        #expect(SupabaseServices.remoteError(CancellationError()) == .cancelled)
    }

    @Test func authRefusalsAndOutagesAreTold() {
        let url = URL(string: "https://x.supabase.co")!
        let refused = Auth.AuthError.api(message: "Invalid Refresh Token", errorCode: .refreshTokenNotFound, underlyingData: Data(),
                                         underlyingResponse: HTTPURLResponse(url: url, statusCode: 400, httpVersion: nil, headerFields: nil)!)
        #expect(SupabaseAccountAuth.classify(refused) == .refused(reason: "Invalid Refresh Token"))
        #expect(SupabaseAccountAuth.classify(Auth.AuthError.sessionMissing) == .signedOut)
        #expect(SupabaseAccountAuth.classify(URLError(.timedOut)) == .remote(.timeout))
    }
}

@Suite struct StoragePathTests {
    @Test func avatarPathIsTheUsersFolder() {
        #expect(StoragePath.avatar(userID: UserID("0F8FAD5B-D9CB")) == "0f8fad5b-d9cb/avatar.jpg")
    }

    @Test func uploadPathsCannotClimbOutOfTheFolder() {
        let path = StoragePath.healthUpload(userID: UserID("u1"), folder: "exports", name: "../../other/x.zip")
        #expect(path == "u1/exports/_.._other_x.zip")
        #expect(path.hasPrefix("u1/"))
        #expect(!path.contains("../"))
    }
}
