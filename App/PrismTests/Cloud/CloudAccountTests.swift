//
//  CloudAccountTests.swift
//  PrismTests
//

import Foundation
import Testing
import SyncCore
import SyncSupabase
@testable import Prism

// MARK: - Doubles

/// Supabase Auth as a script: counts refreshes and answers what it is told.
private actor ScriptedAuth: AccountAuthBackend {
    var refreshCalls = 0
    var signOutCalls = 0
    var lastNonce: String?
    private var session: SupabaseAuthSession?
    private var refreshAnswer: Result<SupabaseAuthSession, SupabaseAuthError>
    private var gate: CheckedContinuation<Void, Never>?
    private var holdsRefresh = false
    private let stored: SupabaseAuthSession?

    init(session: SupabaseAuthSession? = nil, refreshAnswer: Result<SupabaseAuthSession, SupabaseAuthError>) {
        self.session = session
        self.stored = session
        self.refreshAnswer = refreshAnswer
    }

    func setHold(_ hold: Bool) { holdsRefresh = hold }
    func release() { gate?.resume(); gate = nil }

    nonisolated func storedSession() -> SupabaseAuthSession? { stored }

    func signInWithApple(idToken: String, nonce: String) async throws(SupabaseAuthError) -> SupabaseAuthSession {
        lastNonce = nonce
        guard idToken == "good" else { throw .refused(reason: "bad token") }
        let fresh = CloudAccountTests.session("access-1", refresh: "refresh-1")
        session = fresh
        return fresh
    }

    func validSession() async throws(SupabaseAuthError) -> SupabaseAuthSession {
        guard let session else { throw .signedOut }
        return session
    }

    func refreshSession() async throws(SupabaseAuthError) -> SupabaseAuthSession {
        refreshCalls += 1
        if holdsRefresh { await withCheckedContinuation { gate = $0 } }
        let fresh = try refreshAnswer.get()
        session = fresh
        return fresh
    }

    func signOut() async {
        signOutCalls += 1
        session = nil
    }

    nonisolated func sessionChanges() -> AsyncStream<SupabaseAuthSession?> { AsyncStream { $0.finish() } }
}

// MARK: - Account

@Suite("Account: nonce and session")
struct CloudAccountTests {
    static let userID = "0f8fad5b-d9cb-469f-a165-70867728950e"

    static func session(_ access: String, refresh: String, expires: Date = .distantFuture) -> SupabaseAuthSession {
        SupabaseAuthSession(accessToken: access, refreshToken: refresh, expiresAt: expires, userID: userID, email: "a@privaterelay.appleid.com")
    }

    static let settings = SupabaseSettings(projectURL: URL(string: "https://qnysyehawitnlcnccyop.supabase.co")!, publishableKey: "k")

    @Test("The nonce is random, long enough, and its hash is lowercase hex SHA-256")
    func nonce() {
        let first = AppleNonce.make()
        let second = AppleNonce.make()
        #expect(first.count == 32)
        #expect(first != second)
        #expect(AppleNonce.alphabet.count == 64)
        // SHA-256("abc"), the standard's own example.
        #expect(AppleNonce.sha256("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    @MainActor
    @Test("Sign in hands the raw nonce to Supabase and signs the account in")
    func signIn() async throws {
        let auth = ScriptedAuth(refreshAnswer: .failure(.refused(reason: "unused")))
        let account = AccountSession(settings: Self.settings, services: .inMemory(configuration: Self.settings.configuration), backend: auth)
        #expect(account.state == .signedOut)

        try await account.signInWithApple(idToken: "good", nonce: "raw-nonce")

        #expect(await auth.lastNonce == "raw-nonce")
        #expect(account.state.user?.id == Self.userID)
        #expect(account.lastError == nil)
        #expect(try await account.tokens?.currentToken().value == "access-1")
        await CloudSync.shared.stop()
    }

    @MainActor
    @Test("A refused Apple token leaves nobody signed in and says so")
    func refusedSignIn() async {
        let auth = ScriptedAuth(refreshAnswer: .failure(.refused(reason: "x")))
        let account = AccountSession(settings: Self.settings, services: .inMemory(configuration: Self.settings.configuration), backend: auth)
        await #expect(throws: SupabaseAuthError.refused(reason: "bad token")) {
            try await account.signInWithApple(idToken: "bad", nonce: "n")
        }
        #expect(account.state == .signedOut)
        #expect(account.lastError != nil)
    }

    @Test("Two callers holding the same rejected token share one refresh")
    func singleFlightRefresh() async throws {
        let auth = ScriptedAuth(session: Self.session("old", refresh: "r-old"), refreshAnswer: .success(Self.session("new", refresh: "r-new")))
        await auth.setHold(true)
        let tokens = AccountTokens(backend: auth)
        let stale = try await tokens.currentToken()

        async let first = tokens.refreshedToken(replacing: stale)
        async let second = tokens.refreshedToken(replacing: stale)
        try await Task.sleep(for: .milliseconds(100))
        await auth.release()
        let values = try await [first.value, second.value]

        #expect(values == ["new", "new"])
        #expect(await auth.refreshCalls == 1)
        // A third caller still holding the old token gets the new one at once.
        #expect(try await tokens.refreshedToken(replacing: stale).value == "new")
        #expect(await auth.refreshCalls == 1)
    }

    @Test("A refused refresh signs out; an offline one keeps the session")
    func refreshOutcomes() async throws {
        let offlineAuth = ScriptedAuth(session: Self.session("old", refresh: "r"), refreshAnswer: .failure(.remote(.offline)))
        let offline = AccountTokens(backend: offlineAuth)
        let stale = try await offline.currentToken()
        await #expect(throws: AuthError.unavailable) { try await offline.refreshedToken(replacing: stale) }
        #expect(await offlineAuth.signOutCalls == 0)

        let refusedAuth = ScriptedAuth(session: Self.session("old", refresh: "r"), refreshAnswer: .failure(.refused(reason: "revoked")))
        let refused = AccountTokens(backend: refusedAuth)
        await #expect(throws: AuthError.refreshRejected) { try await refused.refreshedToken(replacing: stale) }
        #expect(await refusedAuth.signOutCalls == 1)
        await #expect(throws: AuthError.signedOut) { try await refused.currentToken() }
    }

    @MainActor
    @Test("Without a project the account is unavailable; with a stored session it starts signed in")
    func accountStates() {
        #expect(AccountSession(settings: nil).state == .unavailable)
        let auth = ScriptedAuth(session: Self.session("a", refresh: "r"), refreshAnswer: .failure(.refused(reason: "x")))
        let account = AccountSession(settings: Self.settings, services: .inMemory(configuration: Self.settings.configuration), backend: auth)
        #expect(account.state.user?.id == Self.userID)
    }

    @Test("Settings ignore unexpanded build settings and plain http")
    func settingsResolve() {
        #expect(SupabaseSettings.resolve(info: ["SomaSupabaseURL": "$(SOMA_SUPABASE_URL)", "SomaSupabasePublishableKey": "k"], environment: [:]) == nil)
        #expect(SupabaseSettings.resolve(info: ["SomaSupabaseURL": "http://x.supabase.co", "SomaSupabasePublishableKey": "k"], environment: [:]) == nil)
        let resolved = SupabaseSettings.resolve(info: [:], environment: ["SOMA_SUPABASE_URL": "https://qnysyehawitnlcnccyop.supabase.co", "SOMA_SUPABASE_PUBLISHABLE_KEY": "k"])
        #expect(resolved?.configuration.storageBucket == "health-uploads")
    }
}

// MARK: - Records and storage paths

@Suite("Cloud records")
struct CloudRecordTests {
    let user = "0f8fad5b-d9cb-469f-a165-70867728950e"

    @Test("Natural key ids are stable, distinct per user, and UUIDs")
    func stableIDs() {
        let a = CloudRecords.id(CloudRecords.journalDays, userID: user, key: "2026-10-03")
        #expect(a == CloudRecords.id(CloudRecords.journalDays, userID: user.uppercased(), key: "2026-10-03"))
        #expect(a != CloudRecords.id(CloudRecords.journalDays, userID: "someone-else", key: "2026-10-03"))
        #expect(a != CloudRecords.id(CloudRecords.scoresDaily, userID: user, key: "2026-10-03"))
        #expect(UUID(uuidString: a.rawValue) != nil)
        #expect(Array(a.rawValue)[14] == "5")
    }

    @MainActor
    @Test("A journal day becomes yes and no lists the server projects")
    func journalSnapshot() throws {
        let days = ["2026-10-03": JournalDay(tags: ["sauna", "alcohol"], declined: ["nap"], feeling: 5), "2026-10-02": JournalDay()]
        let records = CloudSnapshots.journal(days, userID: user)
        #expect(records.count == 1)
        let payload = try RecordPayload(encoding: records[0]).jsonObject()
        #expect(payload["day"] as? String == "2026-10-03")
        #expect(payload["tags_yes"] as? [String] == ["alcohol", "sauna"])
        #expect(payload["tags_no"] as? [String] == ["nap"])
        #expect(payload["feeling"] as? Int == 5)
    }

    @Test("Scores line up with their days, today last, and empty days are left out")
    func scoresSnapshot() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let today = Date(timeIntervalSince1970: 1_791_028_800)
        let scores = SomaScores.empty(sleep: [nil, 70, 80], recovery: [nil, nil, 60])
        let records = CloudSnapshots.scores(scores, today: today, userID: user, calendar: calendar)
        #expect(records.map(\.day) == ["2026-10-02", "2026-10-03"])
        #expect(records.last?.sleep == 80)
        #expect(records.last?.recovery == 60)
    }

    @Test("Dates keep whole milliseconds, so a record read back compares equal")
    func millisecondDates() throws {
        let record = MoodLogRecord(id: RecordID("x"), loggedAt: CloudSnapshots.ms(Date(timeIntervalSince1970: 1.0004567)),
                                   kind: "daily", valence: 0.25, labels: [], associations: [], origin: "mind")
        let decoded = try RecordPayload(encoding: record).decode(MoodLogRecord.self)
        #expect(decoded == record)
    }

    @Test("Provider connections never carry a token")
    func providersCarryNoToken() throws {
        let records = CloudSnapshots.providers(["oura": .connected(account: "ada", lastSync: nil), "whoop": .notConnected], userID: user)
        #expect(records.count == 1)
        let keys = Set(try RecordPayload(encoding: records[0]).jsonObject().keys)
        #expect(keys.isDisjoint(with: ["access_token", "refresh_token", "token", "id_token"]))
    }

    @Test("Storage paths sit in the person's own folder")
    func storagePaths() {
        #expect(StoragePath.avatar(userID: UserID(user)) == "\(user)/avatar.jpg")
        #expect(StoragePath.healthUpload(userID: UserID(user), folder: "exports", name: "soma 2026.zip") == "\(user)/exports/soma_2026.zip")
        #expect(CloudSync.contentType(for: "batch.ndjson") == "application/x-ndjson")
        #expect(CloudSync.contentType(for: "export.zip") == "application/zip")
    }

    @Test("A profile row sends cleared fields as null")
    func profileRowNulls() throws {
        var profile = SomaProfile()
        profile.name = "Ada"
        let row = ProfileRow.make(userID: user.uppercased(), profile: profile, avatarPath: nil)
        let json = try #require(try JSONSerialization.jsonObject(with: SupabaseServices.encoder().encode(row)) as? [String: Any])
        #expect(json["id"] as? String == user)
        #expect(json["first_name"] as? String == "Ada")
        #expect(json["avatar_path"] is NSNull)
        #expect(json["birth_date"] is NSNull)
    }
}

// MARK: - Outbox mirror

/// A server that applies every push, for the mirror's tests.
private actor AcceptingServer: RemoteRecordStore {
    var pushed: [String: Int] = [:]
    private var revision: Int64 = 0

    func push(_ changes: [OutgoingChange], type: RecordType, token: AccessToken) async throws(RemoteError) -> [PushOutcome] {
        pushed[type.rawValue, default: 0] += changes.count
        return changes.map { change in
            revision += 1
            return .applied(change.id, Revision(revision))
        }
    }

    func pull(_ type: RecordType, after revision: Revision?, limit: Int, resyncing: Bool, token: AccessToken) async throws(RemoteError) -> PullPage {
        PullPage(records: [], hasMore: false)
    }
}

private struct NoObjects: RemoteObjectStore {
    func put(key: String, file: URL, sha256: String, contentType: String, token: AccessToken) async throws(RemoteError) {}
}

private struct FixedTokens: AccessTokenProvider {
    let userID: UserID
    func currentToken() async throws(AuthError) -> AccessToken { AccessToken(userID: userID, value: "t", expiresAt: .distantFuture) }
    func refreshedToken(replacing rejected: AccessToken) async throws(AuthError) -> AccessToken { try await currentToken() }
}

private struct Offline: ConnectivityMonitor {
    func updates() -> AsyncStream<Bool> { AsyncStream { $0.finish() } }
}

@Suite("Cloud mirror", .serialized)
struct CloudMirrorTests {
    @Test("Only changes reach the outbox, a removal is deleted, and pulled records are never deleted")
    func mirrorDiffs() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "cloud-mirror-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let user = UserID("mirror-user")
        let server = AcceptingServer()
        let session = try await WellnessSession.open(
            WellnessEnvironment(userID: user, tokens: FixedTokens(userID: user), records: server, objects: NoObjects(),
                                connectivity: Offline(), rootDirectory: root, syncDebounce: .seconds(3600)),
            modules: [CloudRecords.module]
        )
        let mirror = CloudMirror(session: session)
        func day(_ key: String, feeling: Int) -> JournalDayRecord {
            JournalDayRecord(id: CloudRecords.id(CloudRecords.journalDays, userID: user.rawValue, key: key), day: key, tagsYes: [], tagsNo: [], feeling: feeling)
        }

        // A record that arrived from the server, which this phone never mirrored.
        try await session.repository(for: JournalDayRecord.self).save(day("2026-01-01", feeling: 1))

        #expect(try await mirror.mirror([day("2026-10-02", feeling: 3), day("2026-10-03", feeling: 4)]) == 2)
        #expect(try await mirror.mirror([day("2026-10-02", feeling: 3), day("2026-10-03", feeling: 4)]) == 0)
        #expect(try await mirror.mirror([day("2026-10-03", feeling: 5)]) == 2)

        let left = try await session.repository(for: JournalDayRecord.self).fetchAll().map(\.day).sorted()
        #expect(left == ["2026-01-01", "2026-10-03"])
        await session.syncNow()
        #expect(await server.pushed["journal_days"] ?? 0 >= 3)
        await session.close()
    }
}

private extension SomaScores {
    /// Scores with only the series a test sets.
    static func empty(sleep: [Double?], recovery: [Double?]) -> SomaScores {
        var scores = SomaScores.fixture
        scores.sleepSeries = sleep
        scores.recoverySeries = recovery
        return scores
    }
}
