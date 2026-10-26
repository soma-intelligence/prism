//
//  InstallationID.swift
//  Prism
//

import Foundation
import Security

/// A random identifier made once per installation and kept in the Keychain:
/// names this phone in `devices` and in `health_sync_state`, whose Health
/// anchors belong to this phone's store only.
nonisolated enum InstallationID {
    private static let service = "Soma.Prism.installation"

    private static let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: "id",
        kSecUseDataProtectionKeychain as String: true,
    ]

    /// The stored id, made and stored on the first call.
    ///
    /// Two first calls can race (cloud sync and the device row both ask at
    /// launch): each finds nothing and makes an id, and only one is stored.
    /// The one that loses reads back the stored id rather than handing on an
    /// id the Keychain never kept.
    static func current() -> String {
        if let stored = stored() { return stored }
        let made = UUID().uuidString.lowercased()
        var item = query
        item[kSecValueData as String] = Data(made.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        if SecItemAdd(item as CFDictionary, nil) == errSecDuplicateItem, let stored = stored() {
            return stored
        }
        return made
    }

    private static func stored() -> String? {
        var request = query
        request[kSecReturnData as String] = true
        var result: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data, let text = String(data: data, encoding: .utf8), !text.isEmpty
        else { return nil }
        return text
    }
}
