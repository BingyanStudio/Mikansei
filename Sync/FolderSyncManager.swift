import Foundation
import Combine

@MainActor
protocol SyncWorkspace: AnyObject {
    var replica: WorkspaceReplica { get }
    var syncReady: Bool { get }
    func applySync(_ document: WorkspaceSyncDocument)
}

@MainActor
final class FolderSyncManager: ObservableObject {
    @Published private(set) var folder: URL?
    @Published private(set) var status = "尚未选择同步文件夹"
    @Published private(set) var error: String?
    @Published private(set) var lastSync: Date?
    @Published private(set) var isSyncing = false
    private var worker: Task<Void, Never>?
    private var repeatRequested = false
    private var generation = 0
    private let bookmarkKey = "Mikansei.syncFolderBookmark.v1"
    private let testing = ProcessInfo.processInfo.arguments.contains("--ui-testing")

    init() {
        guard !testing, let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return }
        do {
            var stale = false
            #if os(macOS)
            let options: URL.BookmarkResolutionOptions = [.withSecurityScope, .withoutUI]
            #else
            let options: URL.BookmarkResolutionOptions = [.withoutUI]
            #endif
            folder = try URL(resolvingBookmarkData: data, options: options, bookmarkDataIsStale: &stale)
            status = stale ? "文件夹授权已变化，请重新选择" : "已连接 · 等待同步"
            if stale { folder = nil }
        } catch { self.error = "请重新选择同步文件夹：\(error.localizedDescription)" }
    }
    func connect(_ url: URL, workspace: any SyncWorkspace) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            #if os(macOS)
            let options: URL.BookmarkCreationOptions = [.withSecurityScope]
            #else
            let options: URL.BookmarkCreationOptions = [.minimalBookmark]
            #endif
            let data = try url.bookmarkData(options: options, includingResourceValuesForKeys: nil, relativeTo: nil)
            generation += 1
            UserDefaults.standard.set(data, forKey: bookmarkKey)
            folder = url
            status = "已连接 · 等待同步"
            error = nil
            request(workspace)
        } catch { self.error = "无法保存文件夹授权：\(error.localizedDescription)" }
    }
    func disconnect() {
        generation += 1; folder = nil; lastSync = nil
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
        status = "已停止同步，本机数据保留"; error = nil
    }
    func request(_ workspace: any SyncWorkspace) {
        guard !testing, folder != nil else { return }
        repeatRequested = true
        guard worker == nil else { return }
        worker = Task { [weak self, weak workspace] in
            guard let self, let workspace else { return }
            isSyncing = true
            defer { isSyncing = false; worker = nil }
            while repeatRequested {
                repeatRequested = false
                guard workspace.syncReady, let url = folder else { return }
                let token = generation
                let snapshot = workspace.replica
                do {
                    let remote = try await Task.detached(priority: .utility) {
                        try FolderSyncTransport.exchange(snapshot: snapshot, folder: url)
                    }.value
                    guard token == generation else { continue }
                    workspace.applySync(remote)
                    lastSync = Date(); error = nil
                    status = "已同步到所选文件夹"
                } catch {
                    guard token == generation else { continue }
                    status = "暂未同步，本机修改已保留"
                    self.error = error.localizedDescription
                }
            }
        }
    }
}
