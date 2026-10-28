import SwiftUI
import UniformTypeIdentifiers

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .commaSeparatedText, .plainText] }
    var data: Data
    init(data: Data = Data()) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct SettingsView: View {
    @EnvironmentObject private var store: EntryStore
    @EnvironmentObject private var cloud: CloudAccountManager
    @EnvironmentObject private var notifications: NotificationManager
    @EnvironmentObject private var deadlineActivity: DeadlineActivityManager
    @AppStorage("appearance") private var appearance = 0
    @State private var backup = BackupDocument()
    @State private var exporting = false
    @State private var importing = false
    @State private var message: String?
    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    Image(systemName: "checklist").font(.system(size: 28)).foregroundStyle(Color(uiColor: .systemBackground))
                        .frame(width: 60, height: 60).background(Theme.accent, in: RoundedRectangle(cornerRadius: 16))
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Mikansei").font(.title2.weight(.semibold))
                        Text("把琐碎事项放在同一张清单里。") .font(.subheadline).foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 8)
                LabeledContent("待完成", value: "\(TaskBoard(entries: store.entries).open.count) 件")
                LabeledContent("已完成", value: "\(store.entries.filter { $0.isTask && $0.isCompleted }.count) 件")
                LabeledContent("笔记", value: "\(store.entries.filter { $0.kind == .note }.count) 条")
            }
            Section("作业登记") {
                NavigationLink { CoursesView() } label: { Label("课表与下课登记提醒", systemImage: "graduationcap") }
                Text("填写或导入课表，下课时提醒你记录作业、DDL 和提交平台。") .font(.caption).foregroundStyle(.secondary)
            }
            CloudAccountSettings(cloud: cloud)
            FolderSyncSettings(workspace: store)
            Section("日历") {
                NavigationLink { CalendarSyncView() } label: { Label("日历自动导入", systemImage: "calendar.badge.plus") }
                    .accessibilityIdentifier("calendar-sync-settings")
                Text("选择要自动同步的日历标签 / 来源，仅勾选的来源会导入。日程按开始时间和持续时间安排；常态支持重复规律或日历选日。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                LabeledContent("系统通知", value: notifications.statusTitle)
                LabeledContent("已安排弹窗", value: "\(notifications.scheduledCount) 个")
                LabeledContent("系统闹钟", value: notifications.alarmStatus)
                LabeledContent("已安排闹钟", value: "\(notifications.alarmCount) 个")
                if notifications.supportsAlarms {
                    Button("开启闹钟权限", systemImage: "alarm") { Task { _ = await notifications.requestAccess(for: .alarm); store.refreshNotifications() } }
                }
                if notifications.authorization == .notDetermined {
                    Button("开启提醒通知", systemImage: "bell.badge") {
                        Task { _ = await notifications.requestAccess(); store.refreshNotifications() }
                    }
                } else {
                    Button("打开系统通知设置", systemImage: "gear") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                }
                if let error = notifications.error { Text(error).font(.caption).foregroundStyle(.red) }
            } header: { Text("提醒") } footer: {
                Text("每件事项可选择弹窗或闹钟、铃声及稍后提醒间隔。弹窗遵循通知设置；系统闹钟需要 iOS 26 和独立授权。停止提醒不等于完成事项。")
            }
            Section("外观") {
                Picker("显示模式", selection: $appearance) {
                    Text("跟随系统").tag(0)
                    Text("浅色").tag(1)
                    Text("深色").tag(2)
                }.clearOptionText()
            }
            Section("主屏幕小组件") {
                Label("今日清单 · 快速添加 · 今日进度 · 正在做", systemImage: "rectangle.3.group")
                Text("长按主屏幕 → 编辑 → 添加小组件，搜索 Mikansei。添加后先打开 App 一次。")
                    .font(.subheadline).foregroundStyle(.secondary)
                if let error = store.widgetSyncError {
                    Text(error).font(.caption).foregroundStyle(.red)
                    Button("重试同步") { store.refreshNotifications() }
                }
            }
            Section {
                Toggle("自动显示今日 DDL", isOn: Binding(get: { deadlineActivity.enabled }, set: {
                    deadlineActivity.setEnabled($0, entries: store.entries)
                })).accessibilityIdentifier("deadline-live-activity-enabled")
                Text(deadlineActivity.status).font(.subheadline)
                    .accessibilityElement(children: .ignore).accessibilityLabel(deadlineActivity.status)
                    .accessibilityIdentifier("deadline-live-activity-status")
                if deadlineActivity.enabled {
                    Button("重新显示 / 更新", systemImage: "arrow.clockwise") {
                        deadlineActivity.setEnabled(true, entries: store.entries)
                    }.accessibilityIdentifier("deadline-live-activity-refresh")
                }
                if let error = deadlineActivity.error {
                    Text(error).font(.caption).foregroundStyle(.red)
                    Button("打开系统设置", systemImage: "gear") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                }
            } header: { Text("锁屏与灵动岛 · 实时活动") } footer: {
                Text("显示已超时、今日与无日期的未完成事项；按重要级和 DDL 排序。最重要的事项显示倒计时，日程显示距开始的时间，无日期则显示无时限。完成或改期时更新，今日清单为空时结束。倒计时归零后停在零；再次打开时刷新逾期状态。系统最多持续 8 小时，回到 App 可恢复。")
            }
            Section {
                Button("导出 JSON 备份", systemImage: "square.and.arrow.up") {
                    do { backup = BackupDocument(data: try EntryArchive(entries: store.entries, courses: store.courses, calendarSync: store.calendarSync).encoded()); exporting = true }
                    catch { message = "导出失败：\(error.localizedDescription)" }
                }.disabled(store.readOnly)
                Button("导入 JSON 备份", systemImage: "square.and.arrow.down") { importing = true }.disabled(store.readOnly)
                if store.entries.isEmpty && !store.readOnly {
                    Button("添加示例，了解用法", systemImage: "sparkles") { store.addExamples() }
                }
                if store.readOnly {
                    Text("数据读取失败，原文件未被覆盖。请保留 App 并联系开发者恢复数据。")
                        .font(.caption).foregroundStyle(.red)
                }
            } header: { Text("数据与备份") } footer: {
                Text("数据先保存在本机；选择 iCloud Drive 文件夹后与其他设备合并。卸载 App 会删除本地数据，请定期备份到“文件”。导入采用合并方式，相同编号保留最近修改的版本。")
            }
            Section("隐私与支持") {
                Link(destination: URL(string: "https://github.com/KikuchiHeinrich/Mikansei/blob/experimental/sync/Documentation/TestFlight/PRIVACY_POLICY.md")!) {
                    Label("隐私政策", systemImage: "hand.raised")
                }
                Link(destination: URL(string: "https://github.com/KikuchiHeinrich/Mikansei/blob/experimental/sync/Documentation/TestFlight/SUPPORT.md")!) {
                    Label("使用帮助与支持", systemImage: "questionmark.circle")
                }
                Link(destination: URL(string: "mailto:kikuchiheinr@qq.com")!) {
                    Label("邮件联系开发者", systemImage: "envelope")
                }
                Text("隐私政策说明 Mikansei 如何处理你的数据；遇到问题时可查看支持说明或联系开发者。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                LabeledContent("版本", value: "\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"))")
                    .accessibilityElement(children: .ignore).accessibilityLabel("版本")
                    .accessibilityValue("\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"))")
                    .accessibilityIdentifier("app-version")
                Text("待办、作业、Checklist 和随手笔记。") .font(.subheadline).foregroundStyle(.secondary)
                if NotificationPlan.pending(entries: store.entries, courses: store.courses, limit: 61).count > 60 {
                    Text("目前只安排最近 60 个提醒。打开 App 时会更新后续安排。")
                        .font(.caption).foregroundStyle(Theme.warm)
                }
            }
            Section {
                Text("课后与 routine 提醒提前安排未来 28 天，App 每次打开时补充，最多保留最近 60 条。很久不打开 App，后续提醒可能无法安排。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("我的")
        .task { await notifications.refresh() }
        .fileExporter(isPresented: $exporting, document: backup, contentType: .json, defaultFilename: "Mikansei备份-\(Date().formatted(.iso8601.year().month().day().dateSeparator(.dash)))") { result in
            if case .failure(let error) = result { message = "导出失败：\(error.localizedDescription)" }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get()
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let data = try Data(contentsOf: url)
                if store.importBackup(data) { message = "备份已合并，你的原有事项已保留。" }
            } catch { message = "导入失败：\(error.localizedDescription)" }
        }
        .alert("数据备份", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("知道了", role: .cancel) {}
        } message: { Text(message ?? "") }
    }
}
