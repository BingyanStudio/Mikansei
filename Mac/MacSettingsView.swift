import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

struct MacBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }; self.data = data }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
struct MacSettingsView: View {
    @EnvironmentObject private var store: MacWorkspaceStore
    @EnvironmentObject private var cloud: CloudAccountManager
    @EnvironmentObject private var sync: FolderSyncManager
    @State private var exporting = false
    @State private var backup = MacBackupDocument(data: Data())
    @State private var notice = ""
    @AppStorage("appearance") private var appearance = 0
    var body: some View {
        Form {
            CloudAccountSettings(cloud: cloud)
            FolderSyncSettings(workspace: store)
            Section("提醒") {
                Button("允许 Mac 提醒") { Task { do { let allowed = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]); notice = allowed ? "已允许通知" : "请在系统设置 → 通知 → Mikansei 允许提醒"; store.scheduleNotifications() } catch { notice = error.localizedDescription } } }
                Text("Mac 使用系统通知，iPhone 闹钟设置保留在共享事项中。").font(.caption).foregroundStyle(.secondary)
                if !notice.isEmpty { Text(notice) }
            }
            MacCalendarSettings()
            Section("外观") {
                Picker("显示模式", selection: $appearance) { Text("跟随系统").tag(0); Text("浅色").tag(1); Text("深色").tag(2) }
            }
            Section("数据") {
                Button("导出 JSON 备份") { do { backup = MacBackupDocument(data: try store.archive.encoded()); exporting = true } catch { store.error = error.localizedDescription } }
                if store.hasUnsavedChanges { Button("重试本机保存") { store.persist() } }
                LabeledContent("版本", value: "\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"))")
            }
        }.formStyle(.grouped)
        .tint(MacTheme.accent)
        .preferredColorScheme(appearance == 1 ? .light : appearance == 2 ? .dark : nil)
        .fileExporter(isPresented: $exporting, document: backup, contentType: .json, defaultFilename: "Mikansei备份") { result in if case .failure(let error) = result { notice = error.localizedDescription } }
    }
}
