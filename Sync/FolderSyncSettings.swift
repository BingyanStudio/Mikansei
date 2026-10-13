import SwiftUI
import UniformTypeIdentifiers

struct FolderSyncSettings: View {
    @EnvironmentObject private var sync: FolderSyncManager
    let workspace: any SyncWorkspace
    @State private var picking = false
    var body: some View {
        Section {
            Text(sync.status)
            if let folder = sync.folder { LabeledContent("文件夹", value: folder.lastPathComponent) }
            if let date = sync.lastSync { LabeledContent("本次同步", value: date.formatted(date: .abbreviated, time: .shortened)) }
            Button(sync.folder == nil ? "选择 iCloud Drive 同步文件夹" : "更换同步文件夹", systemImage: "folder.badge.gearshape") { picking = true }
            if sync.folder != nil {
                Button("立即同步", systemImage: "arrow.triangle.2.circlepath") { sync.request(workspace) }.disabled(sync.isSyncing || !workspace.syncReady)
                Button("停止本机同步", role: .destructive) { sync.disconnect() }
            }
            if let error = sync.error { Text(error).font(.caption).foregroundStyle(.red) }
        } header: { Text("iCloud Drive · 跨设备同步") } footer: {
            Text("在同一 Apple ID 的 iCloud Drive 中创建一个文件夹，然后在 iPhone 和 Mac 各选择一次同一个文件夹。自动合并待办、笔记、Checklist、计时和课表；删除也会同步。日历来源、权限与外观按设备设置。打开 App、保存修改和前台每 30 秒刷新；iCloud 的上传与下载由系统完成，离线时保留修改。")
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.folder]) { result in
            do { sync.connect(try result.get(), workspace: workspace) }
            catch { /* Cancelling the system picker keeps the existing connection. */ }
        }
    }
}
