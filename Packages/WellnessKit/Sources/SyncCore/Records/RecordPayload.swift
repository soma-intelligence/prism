import Foundation

/// A record payload could not be encoded, decoded or validated.
public struct RecordCodingError: Error, Sendable, Hashable, CustomStringConvertible {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var description: String { message }
}

/// The canonical JSON object of one record: UTF-8, keys sorted, dates in
/// milliseconds. Two payloads with the same content have the same bytes.
public struct RecordPayload: Sendable, Hashable, CustomStringConvertible {
    public let json: Data

    public var text: String { String(decoding: json, as: UTF8.self) }
    public var description: String { text }

    /// Trusts that `json` is already canonical. Use only with bytes produced by this type.
    public init(canonicalJSON json: Data) {
        self.json = json
    }

    public init<Value: Encodable>(encoding value: Value) throws(RecordCodingError) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data: Data
        do {
            data = try encoder.encode(value)
        } catch {
            throw RecordCodingError("cannot encode \(Value.self): \(error)")
        }
        try self.init(validating: data)
    }

    /// Parses `data`, requires a top-level object, and re-serializes it canonically.
    public init(validating data: Data) throws(RecordCodingError) {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            throw RecordCodingError("payload is not valid JSON: \(error)")
        }
        try self.init(jsonObject: object)
    }

    /// Serializes a JSON object (as produced by `JSONSerialization`) canonically.
    public init(jsonObject object: Any) throws(RecordCodingError) {
        guard object is [String: Any] else {
            throw RecordCodingError("payload must be a JSON object")
        }
        do {
            json = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
        } catch {
            throw RecordCodingError("payload cannot be serialized: \(error)")
        }
    }

    public func decode<Value: Decodable>(_ type: Value.Type) throws(RecordCodingError) -> Value {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        do {
            return try decoder.decode(Value.self, from: json)
        } catch {
            throw RecordCodingError("cannot decode \(Value.self): \(error)")
        }
    }

    /// The payload as a `JSONSerialization` object, for embedding in a request body.
    public func jsonObject() throws(RecordCodingError) -> [String: Any] {
        do {
            guard let object = try JSONSerialization.jsonObject(with: json) as? [String: Any] else {
                throw RecordCodingError("payload is not an object")
            }
            return object
        } catch let error as RecordCodingError {
            throw error
        } catch {
            throw RecordCodingError("payload is not valid JSON: \(error)")
        }
    }
}
