import Foundation
import Security

enum WidgetSnapshotStore {
    enum StorageError: LocalizedError {
        case missingGroup, keychain(OSStatus), unsupportedVersion
        var errorDescription: String? {
            switch self {
            case .missingGroup: return "未配置小组件共享签名。"
            case .keychain(let status): return "共享数据暂时不可用（\(status)）。"
            case .unsupportedVersion: return "小组件数据版本不兼容，请重新打开 App。"
            }
        }
    }
    private static func query() throws -> [String: Any] {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "MikanseiSharedKeychainGroup") as? String,
              !group.isEmpty, !group.contains("$(") else { throw StorageError.missingGroup }
        return [kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: "Mikansei.WidgetSnapshot",
                kSecAttrAccount as String: "summary-v1",
                kSecAttrAccessGroup as String: group]
    }
    static func save(_ snapshot: WidgetSnapshot) throws {
        let data = try JSONEncoder().encode(snapshot)
        let query = try query()
        let changes: [String: Any] = [kSecValueData as String: data,
                                    kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        var status = SecItemUpdate(query as CFDictionary, changes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(changes) { _, value in value } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw StorageError.keychain(status) }
    }
    static func load() throws -> WidgetSnapshot? {
        var query = try query()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw StorageError.keychain(status) }
        guard let data = result as? Data else { return nil }
        let snapshot = try JSONDecoder().decode(WidgetSnapshot.self, from: data)
        guard snapshot.version == 1 else { throw StorageError.unsupportedVersion }
        return snapshot
    }
}
