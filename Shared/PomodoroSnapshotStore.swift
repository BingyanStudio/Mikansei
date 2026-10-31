import Foundation
import Security

/// The widget only shares the small Pomodoro view model, never the underlying history.
enum PomodoroSnapshotStore {
    enum StorageError: LocalizedError {
        case missingGroup
        case keychain(OSStatus)
        case unsupportedVersion
        case unreadableData

        var errorDescription: String? {
            switch self {
            case .missingGroup:
                return "未配置 Pomodoro 小组件共享组。"
            case .keychain(let status):
                return "共享专注状态暂不可用（\(status)）。"
            case .unsupportedVersion:
                return "共享专注数据版本不兼容，请打开 App 更新。"
            case .unreadableData:
                return "共享专注数据无法读取，请打开 App 更新。"
            }
        }
    }

    private static func query() throws -> [String: Any] {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "MikanseiSharedKeychainGroup") as? String,
              !group.isEmpty, !group.contains("$(") else {
            throw StorageError.missingGroup
        }
        return [kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: "Mikansei.PomodoroSnapshot",
                kSecAttrAccount as String: "snapshot-v1",
                kSecAttrAccessGroup as String: group]
    }

    static func save(_ snapshot: PomodoroSnapshot) throws {
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

    static func load() throws -> PomodoroSnapshot? {
        var query = try query()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw StorageError.keychain(status) }
        guard let data = result as? Data else { throw StorageError.unreadableData }
        let snapshot = try JSONDecoder().decode(PomodoroSnapshot.self, from: data)
        guard snapshot.version == 1 else { throw StorageError.unsupportedVersion }
        return snapshot
    }
}
