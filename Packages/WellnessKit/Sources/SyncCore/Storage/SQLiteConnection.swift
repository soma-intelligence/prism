import Foundation
import SQLite3

/// An error reported by SQLite.
public struct SQLiteError: Error, Sendable, Hashable, CustomStringConvertible {
    /// Primary result code, for example `SQLITE_CONSTRAINT`.
    public let code: Int32
    /// Extended result code, for example `SQLITE_CONSTRAINT_PRIMARYKEY`.
    public let extendedCode: Int32
    public let message: String
    public let sql: String?

    public init(code: Int32, extendedCode: Int32, message: String, sql: String?) {
        self.code = code
        self.extendedCode = extendedCode
        self.message = message
        self.sql = sql
    }

    public var isCorruption: Bool { code == SQLITE_CORRUPT || code == SQLITE_NOTADB }
    public var isConstraintViolation: Bool { code == SQLITE_CONSTRAINT }

    public var description: String {
        "SQLite error \(extendedCode): \(message)" + (sql.map { " in \($0)" } ?? "")
    }

    public static func closed(_ sql: String?) -> SQLiteError {
        SQLiteError(code: SQLITE_MISUSE, extendedCode: SQLITE_MISUSE, message: "connection is closed", sql: sql)
    }
}

/// Anything that can run a read query.
public protocol SQLQuerying {
    func query(_ sql: String, _ bindings: [SQLiteValue]) throws(SQLiteError) -> [Row]
}

/// One SQLite connection. Not thread-safe by itself: every instance is confined
/// to exactly one actor (the store's writer) or one `Mutex` (a reader slot), which
/// is what makes the unchecked conformance sound.
final class SQLiteConnection: @unchecked Sendable {
    let path: String
    private var handle: OpaquePointer?
    private var statements: [String: OpaquePointer] = [:]

    init(path: String) throws(SQLiteError) {
        self.path = path
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX
        let code = sqlite3_open_v2(path, &db, flags, nil)
        guard code == SQLITE_OK, let db else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "cannot open database"
            if let db { sqlite3_close_v2(db) }
            throw SQLiteError(code: code & 0xFF, extendedCode: code, message: message, sql: nil)
        }
        sqlite3_extended_result_codes(db, 1)
        handle = db
    }

    deinit { close() }

    var isOpen: Bool { handle != nil }

    func close() {
        for statement in statements.values { sqlite3_finalize(statement) }
        statements.removeAll()
        if let handle { sqlite3_close_v2(handle) }
        handle = nil
    }

    /// Runs one or more statements without bindings.
    func execute(_ sql: String) throws(SQLiteError) {
        let db = try requireHandle(sql)
        var errorMessage: UnsafeMutablePointer<CChar>?
        let code = sqlite3_exec(db, sql, nil, nil, &errorMessage)
        guard code == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(db))
            sqlite3_free(errorMessage)
            throw SQLiteError(code: code & 0xFF, extendedCode: sqlite3_extended_errcode(db), message: message, sql: sql)
        }
    }

    /// Runs statements whose failure the caller handles by result code, such as
    /// `ROLLBACK` after an error. Returns the SQLite result code.
    func executeReturningCode(_ sql: String) -> Int32 {
        guard let handle else { return SQLITE_MISUSE }
        return sqlite3_exec(handle, sql, nil, nil, nil)
    }

    /// Runs one statement and returns the number of rows it changed.
    @discardableResult
    func run(_ sql: String, _ bindings: [SQLiteValue] = []) throws(SQLiteError) -> Int {
        let statement = try prepare(sql, bindings)
        defer {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
        }
        var code = sqlite3_step(statement)
        while code == SQLITE_ROW { code = sqlite3_step(statement) }
        guard code == SQLITE_DONE else { throw error(code, sql) }
        return Int(sqlite3_changes(handle))
    }

    func query(_ sql: String, _ bindings: [SQLiteValue] = []) throws(SQLiteError) -> [Row] {
        let statement = try prepare(sql, bindings)
        defer {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
        }
        let count = sqlite3_column_count(statement)
        let columns = (0..<count).map { String(cString: sqlite3_column_name(statement, $0)) }
        var rows: [Row] = []
        while true {
            let code = sqlite3_step(statement)
            if code == SQLITE_DONE { break }
            guard code == SQLITE_ROW else { throw error(code, sql) }
            rows.append(Row(columns: columns, values: (0..<count).map { value(statement, $0) }))
        }
        return rows
    }

    private func prepare(_ sql: String, _ bindings: [SQLiteValue]) throws(SQLiteError) -> OpaquePointer {
        let db = try requireHandle(sql)
        let statement: OpaquePointer
        if let cached = statements[sql] {
            statement = cached
        } else {
            var prepared: OpaquePointer?
            let code = sqlite3_prepare_v3(db, sql, -1, UInt32(SQLITE_PREPARE_PERSISTENT), &prepared, nil)
            guard code == SQLITE_OK, let prepared else { throw error(code, sql) }
            statements[sql] = prepared
            statement = prepared
        }
        for (index, value) in bindings.enumerated() {
            let position = Int32(index + 1)
            let code: Int32
            switch value {
            case .null:
                code = sqlite3_bind_null(statement, position)
            case .integer(let number):
                code = sqlite3_bind_int64(statement, position, number)
            case .real(let number):
                code = sqlite3_bind_double(statement, position, number)
            case .text(let text):
                code = sqlite3_bind_text(statement, position, text, -1, Self.transient)
            case .blob(let data):
                if data.isEmpty {
                    code = sqlite3_bind_zeroblob(statement, position, 0)
                } else {
                    code = data.withUnsafeBytes { buffer in
                        sqlite3_bind_blob(statement, position, buffer.baseAddress, Int32(buffer.count), Self.transient)
                    }
                }
            }
            guard code == SQLITE_OK else {
                sqlite3_reset(statement)
                throw error(code, sql)
            }
        }
        return statement
    }

    private func value(_ statement: OpaquePointer, _ index: Int32) -> SQLiteValue {
        switch sqlite3_column_type(statement, index) {
        case SQLITE_INTEGER:
            return .integer(sqlite3_column_int64(statement, index))
        case SQLITE_FLOAT:
            return .real(sqlite3_column_double(statement, index))
        case SQLITE_TEXT:
            guard let text = sqlite3_column_text(statement, index) else { return .text("") }
            let length = Int(sqlite3_column_bytes(statement, index))
            return .text(String(decoding: UnsafeBufferPointer(start: text, count: length), as: UTF8.self))
        case SQLITE_BLOB:
            guard let bytes = sqlite3_column_blob(statement, index) else { return .blob(Data()) }
            return .blob(Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, index))))
        default:
            return .null
        }
    }

    private func requireHandle(_ sql: String?) throws(SQLiteError) -> OpaquePointer {
        guard let handle else { throw SQLiteError.closed(sql) }
        return handle
    }

    private func error(_ code: Int32, _ sql: String?) -> SQLiteError {
        guard let handle else { return SQLiteError.closed(sql) }
        return SQLiteError(
            code: code & 0xFF,
            extendedCode: sqlite3_extended_errcode(handle),
            message: String(cString: sqlite3_errmsg(handle)),
            sql: sql
        )
    }

    private static var transient: sqlite3_destructor_type {
        unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    }
}

extension SQLiteConnection: SQLQuerying {}
