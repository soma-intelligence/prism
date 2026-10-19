import Foundation
import Supabase
import SyncCore

/// The app's Supabase project through the official client (supabase-swift):
/// Auth, PostgREST, Storage and Functions share one session, persisted in
/// the Keychain and refreshed by the client before it expires.
///
/// Every call here reports failures as the foundation's `RemoteError`, so the
/// retry policy, the circuit breaker and the uploaders treat a Supabase
/// failure the way they treat any other.
///
/// Record sync (`SupabaseRecordStore`, the `sync_push` and `sync_pull`
/// functions) stays on the foundation's own HTTP client: its contract is
/// tested against `ScriptedRecordServer` and takes its token from the same
/// session through `AccessTokenProvider`.
public final class SupabaseServices: Sendable {
    public let configuration: SupabaseConfiguration
    public let client: SupabaseClient

    /// - Parameters:
    ///   - authStorage: where the session is kept. The Keychain on a device;
    ///     memory in tests.
    ///   - session: the URL session every sub-client uses. Tests pass one with
    ///     a stub protocol.
    public init(
        configuration: SupabaseConfiguration,
        authStorage: any AuthLocalStorage,
        session: URLSession = .shared
    ) {
        self.configuration = configuration
        self.client = SupabaseClient(
            supabaseURL: configuration.projectURL,
            supabaseKey: configuration.publishableKey,
            options: SupabaseClientOptions(
                db: .init(encoder: Self.encoder(), decoder: Self.decoder()),
                auth: .init(storage: authStorage, autoRefreshToken: true, emitLocalSessionAsInitialSession: true),
                global: .init(session: session)
            )
        )
    }

    // MARK: Rows

    /// The encoder rows go through: keys are each row's own `CodingKeys`,
    /// dates ISO 8601 with milliseconds.
    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(timestamp(date))
        }
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            if let date = date(text) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "not a timestamp: \(text)")
        }
        return decoder
    }

    public static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    public static func date(_ text: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: text) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let date = plain.date(from: text) { return date }
        // Postgres prints microseconds and may drop the T.
        let postgres = DateFormatter()
        postgres.locale = Locale(identifier: "en_US_POSIX")
        for format in ["yyyy-MM-dd HH:mm:ss.SSSSSSXXXXX", "yyyy-MM-dd'T'HH:mm:ss.SSSSSSXXXXX", "yyyy-MM-dd HH:mm:ssXXXXX"] {
            postgres.dateFormat = format
            if let date = postgres.date(from: text) { return date }
        }
        return nil
    }

    /// `INSERT ... ON CONFLICT (onConflict) DO UPDATE`, returning nothing.
    /// Replaying the same rows is harmless, which is what makes a retry safe.
    public func upsert<Row: Encodable & Sendable>(_ rows: [Row], into table: String, onConflict: String) async throws(RemoteError) {
        guard !rows.isEmpty else { return }
        try await Self.run {
            _ = try await self.client.from(table).upsert(rows, onConflict: onConflict, returning: .minimal).execute()
            return ()
        }
    }

    /// `INSERT ... ON CONFLICT (onConflict) DO NOTHING` when `ignoreDuplicates`
    /// is true: a row already there is kept as it is, so a second writer of
    /// the same row (a retry, or another client that wrote it first) changes
    /// nothing. With false it is ``upsert(_:into:onConflict:)``.
    public func upsert<Row: Encodable & Sendable>(_ rows: [Row], into table: String, onConflict: String, ignoreDuplicates: Bool) async throws(RemoteError) {
        guard !rows.isEmpty else { return }
        try await Self.run {
            _ = try await self.client.from(table)
                .upsert(rows, onConflict: onConflict, returning: .minimal, ignoreDuplicates: ignoreDuplicates)
                .execute()
            return ()
        }
    }

    /// Every row of `table` where `column` equals `value`, read a page at a
    /// time in `orderBy` order, so a table longer than the server's row cap
    /// still comes back whole.
    public func selectAll<Row: Decodable & Sendable>(
        _ type: Row.Type,
        from table: String,
        columns: String = "*",
        where column: String,
        equals value: String,
        orderBy: String,
        pageSize: Int = 500
    ) async throws(RemoteError) -> [Row] {
        let size = max(1, pageSize)
        var rows: [Row] = []
        while true {
            let start = rows.count
            let page: [Row] = try await Self.run {
                try await self.client.from(table).select(columns).eq(column, value: value)
                    .order(orderBy).range(from: start, to: start + size - 1).execute().value
            }
            rows += page
            if page.count < size { return rows }
        }
    }

    /// Rows of `table` whose `column` is one of `values`, asked in batches
    /// so the query string stays short, each batch read a page at a time.
    public func select<Row: Decodable & Sendable>(
        _ type: Row.Type,
        from table: String,
        columns: String = "*",
        where column: String,
        in values: [String],
        orderBy: String,
        batch: Int = 50,
        pageSize: Int = 500
    ) async throws(RemoteError) -> [Row] {
        var rows: [Row] = []
        var index = 0
        let size = max(1, batch)
        let page = max(1, pageSize)
        while index < values.count {
            let chunk = Array(values[index..<min(index + size, values.count)])
            index += size
            var offset = 0
            while true {
                let start = offset
                let found: [Row] = try await Self.run {
                    try await self.client.from(table).select(columns).in(column, values: chunk)
                        .order(orderBy).range(from: start, to: start + page - 1).execute().value
                }
                rows += found
                offset += found.count
                if found.count < page { break }
            }
        }
        return rows
    }

    /// Deletes the caller's rows whose `column` is one of `values`.
    public func delete(from table: String, where column: String, in values: [String]) async throws(RemoteError) {
        guard !values.isEmpty else { return }
        try await Self.run {
            _ = try await self.client.from(table).delete(returning: .minimal).in(column, values: values).execute()
            return ()
        }
    }

    /// Rows of `table` where `column` equals `value`.
    public func select<Row: Decodable & Sendable>(_ type: Row.Type, from table: String, columns: String = "*", where column: String, equals value: String) async throws(RemoteError) -> [Row] {
        try await Self.run {
            try await self.client.from(table).select(columns).eq(column, value: value).execute().value
        }
    }

    /// Calls a Postgres function, ignoring its answer.
    public func rpc<Arguments: Encodable & Sendable>(_ function: String, arguments: Arguments) async throws(RemoteError) {
        try await Self.run {
            _ = try await self.client.rpc(function, params: arguments).execute()
            return ()
        }
    }

    // MARK: Storage

    public func upload(_ data: Data, bucket: String, path: String, contentType: String) async throws(RemoteError) {
        try await Self.run {
            try await self.client.storage.from(bucket).upload(path, data: data, options: FileOptions(cacheControl: "0", contentType: contentType, upsert: true))
        }
    }

    public func upload(file: URL, bucket: String, path: String, contentType: String) async throws(RemoteError) {
        try await Self.run {
            try await self.client.storage.from(bucket).upload(path, fileURL: file, options: FileOptions(cacheControl: "0", contentType: contentType, upsert: true))
        }
    }

    /// The object's bytes, or nil when there is none at `path`.
    public func download(bucket: String, path: String) async throws(RemoteError) -> Data? {
        do {
            return try await self.client.storage.from(bucket).download(path: path)
        } catch let error as StorageError where error.statusCode == "404" || error.statusCode == "400" && error.message.lowercased().contains("not found") {
            return nil
        } catch {
            throw Self.remoteError(error)
        }
    }

    public func remove(bucket: String, paths: [String]) async throws(RemoteError) {
        guard !paths.isEmpty else { return }
        try await Self.run {
            _ = try await self.client.storage.from(bucket).remove(paths: paths)
        }
    }

    /// Every file under `folder`, folders walked, as full paths.
    public func listFiles(bucket: String, folder: String) async throws(RemoteError) -> [String] {
        var pending = [folder]
        var files: [String] = []
        while let current = pending.popLast() {
            let objects = try await Self.run {
                try await self.client.storage.from(bucket).list(path: current)
            }
            for object in objects {
                // A folder comes back without an id.
                if object.id == nil { pending.append("\(current)/\(object.name)") } else { files.append("\(current)/\(object.name)") }
            }
        }
        return files
    }

    /// A link that opens a private object for `seconds`.
    public func signedURL(bucket: String, path: String, seconds: Int) async throws(RemoteError) -> URL {
        try await Self.run {
            try await self.client.storage.from(bucket).createSignedURL(path: path, expiresIn: seconds)
        }
    }

    // MARK: Functions

    /// Calls an Edge Function with the session's token and an optional JSON
    /// body, ignoring its answer.
    public func invoke<Body: Encodable & Sendable>(_ function: String, body: Body) async throws(RemoteError) {
        try await Self.run {
            try await self.client.functions.invoke(function, options: FunctionInvokeOptions(body: body))
        }
    }

    public func invoke(_ function: String) async throws(RemoteError) {
        try await Self.run {
            try await self.client.functions.invoke(function)
        }
    }

    /// Where an Edge Function answers, for a call the client cannot make
    /// itself (a streamed answer read line by line).
    public func functionURL(_ function: String) -> URL {
        configuration.projectURL.appending(path: "functions/v1/\(function)")
    }

    // MARK: Errors

    static func run<Value: Sendable>(_ body: @Sendable () async throws -> Value) async throws(RemoteError) -> Value {
        do {
            return try await body()
        } catch {
            throw remoteError(error)
        }
    }

    /// The client's many error types, classified once.
    public static func remoteError(_ error: any Error) -> RemoteError {
        switch error {
        case let error as RemoteError:
            return error
        case let error as URLError:
            return URLSessionHTTPClient.map(error)
        case is CancellationError:
            return .cancelled
        case let error as HTTPError:
            return status(error.response.statusCode, body: error.data, retryAfter: error.response.value(forHTTPHeaderField: "Retry-After"))
        case let error as StorageError:
            return status(Int(error.statusCode ?? "") ?? 0, body: Data(error.message.utf8), retryAfter: nil)
        case let error as PostgrestError:
            // PostgREST names a Postgres error, not a status: a policy refusal
            // (42501) is forbidden, a JWT problem (PGRST301, PGRST303) is
            // unauthorized, anything else is this request's fault.
            switch error.code {
            case "42501": return .forbidden
            case "PGRST301", "PGRST302", "PGRST303": return .unauthorized
            default: return .rejected(status: 400, reason: "\(error.code ?? "") \(error.message)")
            }
        case let error as Auth.AuthError:
            switch error {
            case .sessionMissing: return .unauthorized
            case .api(_, _, _, let response): return status(response.statusCode, body: Data(error.localizedDescription.utf8), retryAfter: nil)
            default: return .rejected(status: 0, reason: error.localizedDescription)
            }
        case is DecodingError:
            return .malformedResponse(String(describing: error))
        default:
            return .transient(status: nil, retryAfter: nil)
        }
    }

    static func status(_ code: Int, body: Data, retryAfter: String?) -> RemoteError {
        let response = HTTPResponse(status: code, headers: retryAfter.map { ["Retry-After": $0] } ?? [:], body: body)
        return HTTPStatus.error(for: response, now: Date()) ?? .malformedResponse("status \(code) reported as an error")
    }
}

extension SupabaseServices {
    /// The client for the app: the session in the Keychain under `service`,
    /// readable after the first unlock and never synced to another device.
    public static func onDevice(configuration: SupabaseConfiguration, keychainService: String = "Soma.Prism.account") -> SupabaseServices {
        SupabaseServices(configuration: configuration, authStorage: KeychainLocalStorage(service: keychainService))
    }

    /// A client whose session lives in memory only, for tests and previews.
    public static func inMemory(configuration: SupabaseConfiguration, session: URLSession = .shared) -> SupabaseServices {
        SupabaseServices(configuration: configuration, authStorage: MemoryAuthStorage(), session: session)
    }
}

/// Session storage in memory.
final class MemoryAuthStorage: AuthLocalStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String: Data] = [:]

    func store(key: String, value: Data) throws { lock.withLock { items[key] = value } }
    func retrieve(key: String) throws -> Data? { lock.withLock { items[key] } }
    func remove(key: String) throws { _ = lock.withLock { items.removeValue(forKey: key) } }
}
