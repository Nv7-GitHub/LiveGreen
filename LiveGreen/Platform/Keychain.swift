import Foundation
import Security

/// Minimal generic-password Keychain wrapper.
nonisolated enum Keychain {
    static let defaultService = "com.nv7.LiveGreen"

    enum KeychainError: Error {
        case status(OSStatus)
    }

    static func read(account: String, service: String = defaultService) -> String? {
        var query = baseQuery(account: account, service: service)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func write(_ value: String, account: String, service: String = defaultService) throws {
        let data = Data(value.utf8)
        let query = baseQuery(account: account, service: service)
        let update = [kSecValueData as String: data]
        var status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            status = SecItemAdd(insert as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeychainError.status(status) }
    }

    static func delete(account: String, service: String = defaultService) {
        SecItemDelete(baseQuery(account: account, service: service) as CFDictionary)
    }

    private static func baseQuery(account: String, service: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }
}
