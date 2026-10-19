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

    static func current() -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "id",
            kSecUseDataProtectionKeychain as String: true,
        ]
        var request = query
        request[kSecReturnData as String] = true
        var result: CFTypeRef?
        if SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess,
           let data = result as? Data, let text = String(data: data, encoding: .utf8), !text.isEmpty {
            return text
        }
        let made = UUID().uuidString.lowercased()
        var item = query
        item[kSecValueData as String] = Data(made.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
        return made
    }
}
