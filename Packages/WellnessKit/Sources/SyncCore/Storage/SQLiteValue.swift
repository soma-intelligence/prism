import Foundation

/// One SQLite value.
public enum SQLiteValue: Sendable, Hashable {
    case null
    case integer(Int64)
    case real(Double)
    case text(String)
    case blob(Data)

    public var int64Value: Int64? {
        if case .integer(let value) = self { return value }
        return nil
    }

    public var stringValue: String? {
        if case .text(let value) = self { return value }
        return nil
    }
}

/// A column could not be read as the requested type.
public struct RowError: Error, Sendable, Hashable, CustomStringConvertible {
    public let column: String
    public let expected: String
    public let found: SQLiteValue

    public var description: String { "column \(column): expected \(expected), found \(found)" }
}

/// One result row. Values are copied out of SQLite, so a row is a plain value.
public struct Row: Sendable, Hashable {
    public let columns: [String]
    public let values: [SQLiteValue]

    public init(columns: [String], values: [SQLiteValue]) {
        self.columns = columns
        self.values = values
    }

    public subscript(_ name: String) -> SQLiteValue {
        guard let index = columns.firstIndex(of: name) else { return .null }
        return values[index]
    }

    public func int64(_ name: String) throws(RowError) -> Int64 {
        guard case .integer(let value) = self[name] else {
            throw RowError(column: name, expected: "integer", found: self[name])
        }
        return value
    }

    public func optionalInt64(_ name: String) throws(RowError) -> Int64? {
        switch self[name] {
        case .null: return nil
        case .integer(let value): return value
        case let other: throw RowError(column: name, expected: "integer or null", found: other)
        }
    }

    public func string(_ name: String) throws(RowError) -> String {
        guard case .text(let value) = self[name] else {
            throw RowError(column: name, expected: "text", found: self[name])
        }
        return value
    }

    public func optionalString(_ name: String) throws(RowError) -> String? {
        switch self[name] {
        case .null: return nil
        case .text(let value): return value
        case let other: throw RowError(column: name, expected: "text or null", found: other)
        }
    }

    public func bool(_ name: String) throws(RowError) -> Bool {
        try int64(name) != 0
    }

    public func optionalData(_ name: String) throws(RowError) -> Data? {
        switch self[name] {
        case .null: return nil
        case .blob(let value): return value
        case .text(let value): return Data(value.utf8)
        case let other: throw RowError(column: name, expected: "blob, text or null", found: other)
        }
    }

    /// The row as a JSON object. Blobs are base64 encoded. Used to keep a
    /// faithful copy of a row that cannot be decoded.
    public func jsonString() -> String {
        var object: [String: Any] = [:]
        for (name, value) in zip(columns, values) {
            switch value {
            case .null: object[name] = NSNull()
            case .integer(let number): object[name] = NSNumber(value: number)
            case .real(let number): object[name] = number.isFinite ? NSNumber(value: number) : String(number)
            case .text(let text): object[name] = text
            case .blob(let data): object[name] = data.base64EncodedString()
            }
        }
        do {
            let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            return String(decoding: data, as: UTF8.self)
        } catch {
            return "{\"unserializable_row\":\"\(error)\"}"
        }
    }
}
