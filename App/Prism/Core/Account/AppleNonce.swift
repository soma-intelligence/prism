//
//  AppleNonce.swift
//  Prism
//

import CryptoKit
import Foundation
import Security

/// The nonce that ties one Sign in with Apple answer to one sign in.
///
/// Apple gets the SHA-256 of a random string and writes it into the identity
/// token it signs. Supabase gets the raw string, hashes it, and refuses the
/// token unless the two match, so a token lifted from somewhere else cannot be
/// replayed into this app's sign in.
nonisolated enum AppleNonce {
    static let alphabet = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-.")

    /// `length` characters from the system's secure random source.
    static func make(length: Int = 32) -> String {
        precondition(length > 0)
        var bytes = [UInt8](repeating: 0, count: length)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status != errSecSuccess {
            // The secure source never fails in practice; the system generator
            // is the fallback rather than a crash at sign in.
            var generator = SystemRandomNumberGenerator()
            bytes = (0..<length).map { _ in UInt8.random(in: 0...255, using: &generator) }
        }
        // 64 characters: a byte modulo 64 keeps the draw uniform.
        return String(bytes.map { alphabet[Int($0) % alphabet.count] })
    }

    /// Lowercase hex SHA-256, the form Apple and Supabase both expect.
    static func sha256(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
