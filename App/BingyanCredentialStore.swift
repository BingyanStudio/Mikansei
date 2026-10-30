import Foundation
import Security

enum BingyanCredentialStoreError: LocalizedError {
    case unavailable
    case invalidValue

    var errorDescription: String? {
        switch self {
        case .unavailable: return "无法安全保存冰岩 Key，请重试。"
        case .invalidValue: return "本机保存的冰岩 Key 无法读取，请重新输入。"
        }
    }
}

/// Stores only the user's read-only schedule API key in this device's Keychain.
/// The item is explicitly non-synchronizable and excluded from device migration.
enum BingyanCredentialStore {
    private static let service = "net.mikansei.bingyan.schedule"
    private static let account = "schedule:self:read"

    static var hasSavedKey: Bool {
        do { return try load() != nil }
        catch { return false }
    }

    static func load() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw BingyanCredentialStoreError.invalidValue
        }
        return value
    }

    static func save(_ value: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else {
            throw BingyanCredentialStoreError.invalidValue
        }
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecAttrSynchronizable as String: false
        ]
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else { throw BingyanCredentialStoreError.unavailable }
        var addQuery = baseQuery
        for (key, value) in attributes { addQuery[key] = value }
        guard SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess else {
            throw BingyanCredentialStoreError.unavailable
        }
    }

    static func remove() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw BingyanCredentialStoreError.unavailable
        }
    }

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false
        ]
    }
}
