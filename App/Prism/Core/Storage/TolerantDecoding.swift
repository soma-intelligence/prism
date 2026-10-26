//
//  TolerantDecoding.swift
//  Prism
//

import Foundation

nonisolated extension KeyedDecodingContainer {
    /// The value under `key`, or `fallback` when the key is missing or holds
    /// something this build no longer reads.
    ///
    /// The local stores read each field through this, so a file written
    /// before a field existed, or by a build that stored one differently,
    /// keeps everything else the person set.
    func value<Value: Decodable>(_ key: Key, or fallback: Value) -> Value {
        (try? decodeIfPresent(Value.self, forKey: key)) ?? fallback
    }
}
