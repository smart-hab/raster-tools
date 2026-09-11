//
//  KeychainStore.swift
//  RasterTools
//
//  Created by Marek on 2026-09-02.
//

import Foundation
import Security

/// Stores API keys and passwords in the macOS Keychain, keyed by account name.
///
/// Only credentials belong here — everything else stays in `UserDefaults`. `AppSettings` is
/// the only intended caller; it mirrors each secret into a stored property so `@Observable`
/// can publish changes, and writes back through here on `didSet`.
struct KeychainStore {

    /// One service for every RasterTools secret; accounts distinguish them.
    private static let service = "com.rastertools.credentials"

    private static func query(for account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    static func string(for account: String) -> String? {
        var query = query(for: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    /// Writes `value`, or removes the item entirely when `value` is empty — a cleared text field
    /// should leave nothing behind rather than an empty secret.
    static func set(_ value: String, for account: String) {
        guard !value.isEmpty else {
            remove(account)
            return
        }

        let data = Data(value.utf8)
        let query = query(for: account)

        // Update in place when the item exists; SecItemAdd would fail with errSecDuplicateItem.
        let status = SecItemUpdate(
            query as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if status == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(insert as CFDictionary, nil)
        }
    }

    static func remove(_ account: String) {
        SecItemDelete(query(for: account) as CFDictionary)
    }
}
