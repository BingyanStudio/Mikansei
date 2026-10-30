import SwiftUI
import UniformTypeIdentifiers

private struct BingyanSchedulePreviewPresentation: Identifiable {
    let id = UUID()
    let batch: BingyanScheduleImportBatch
}

struct BingyanScheduleImportView: View {
    @EnvironmentObject private var store: EntryStore
    @Environment(\.dismiss) private var dismiss
    @State private var apiKeyInput = ""
    @State private var keyIsSaved = false
    @State private var fromDate = Calendar.current.startOfDay(for: Date())
    @State private var toDate = Calendar.current.date(byAdding: .day, value: 6, to: Calendar.current.startOfDay(for: Date())) ?? Date()
    @State private var periodTable = "auto"
    @State private var reading = false
    @State private var choosingJSON = false
    @State private var preview: BingyanSchedulePreviewPresentation?
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("冰岩开放平台") {
                    SecureField("粘贴个人只读 API Key", text: $apiKeyInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .disabled(store.readOnly)
                    if keyIsSaved {
                        Label("这台设备已安全保存课表 Key", systemImage: "key.fill")
                            .font(.footnote).foregroundStyle(.secondary)
                        Button("移除这台设备上的 Key", role: .destructive) {
                            do {
                                try BingyanCredentialStore.remove()
                                apiKeyInput = ""
                                keyIsSaved = false
                            } catch { message = error.localizedDescription }
                        }.disabled(store.readOnly)
                    }
                    Link(destination: URL(string: "https://open.bingyan.net")!) {
                        Label("前往冰岩开放平台创建或管理 Key", systemImage: "arrow.up.right.square")
                    }
                    Text("创建 Key 时只选择课表只读权限。Key 仅在这台设备的安全存储中保存，不会进入账号同步或导出备份。命令行授权不会自动连接此 App。")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Section("读取日期") {
                    DatePicker("开始日期", selection: $fromDate, displayedComponents: .date)
                    DatePicker("结束日期", selection: $toDate, in: fromDate..., displayedComponents: .date)
                    Picker("作息时间", selection: $periodTable) {
                        Text("自动").tag("auto")
                        Text("冬令时").tag("winter")
                        Text("夏令时").tag("summer")
                        Text("网安作息").tag("cyber")
                    }
                    Text("最多读取 200 天。日期范围使用上海时区；接口只提供明确的课程起止时间，缺少时段的项目会留在跳过统计中。")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Section {
                    Button {
                        Task { await readFromAPI() }
                    } label: {
                        HStack {
                            if reading { ProgressView().controlSize(.small) }
                            Text(reading ? "正在读取课表…" : "读取并预览课表")
                        }
                    }
                    .disabled(reading || !isRangeValid || store.readOnly)

                    Button {
                        choosingJSON = true
                    } label: {
                        Label("从 JSON 文件导入", systemImage: "doc.badge.arrow.up")
                    }
                    .disabled(reading || store.readOnly)
                    Text("也可以选择冰岩 CLI 导出的每日课表 JSON，或使用 ICS / CSV 文件导入。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("冰岩课表")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { keyIsSaved = BingyanCredentialStore.hasSavedKey }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }.disabled(reading)
                }
            }
            .fileImporter(isPresented: $choosingJSON, allowedContentTypes: [.json]) { result in
                do {
                    let url = try result.get()
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    let data = try Data(contentsOf: url)
                    guard data.count <= 5_000_000 else {
                        throw BingyanScheduleImportError.invalidJSON
                    }
                    let decoder = JSONDecoder()
                    decoder.keyDecodingStrategy = .convertFromSnakeCase
                    let response = try decoder.decode(BingyanScheduleResponse.self, from: data)
                    let batch = BingyanScheduleImportBuilder.build(response)
                    preview = BingyanSchedulePreviewPresentation(batch: batch)
                } catch { message = "无法读取课表 JSON：\(error.localizedDescription)" }
            }
            .sheet(item: $preview) { presentation in
                BingyanSchedulePreviewView(batch: presentation.batch)
            }
            .alert("冰岩课表", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("知道了", role: .cancel) {}
            } message: { Text(message ?? "") }
        }
    }

    private var isRangeValid: Bool {
        guard let first = BingyanScheduleDate.parseDay(BingyanScheduleDate.string(from: fromDate, calendar: .current)),
              let last = BingyanScheduleDate.parseDay(BingyanScheduleDate.string(from: toDate, calendar: .current)),
              last >= first,
              let span = BingyanScheduleDate.calendar.dateComponents([.day], from: first, to: last).day else { return false }
        return span < 200
    }

    private func readFromAPI() async {
        guard !store.readOnly else { message = "当前为只读模式，不能读取并导入课表。"; return }
        guard isRangeValid else { message = "请选择不超过 200 天的日期范围。"; return }
        reading = true
        defer { reading = false }
        do {
            let suppliedKey = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = suppliedKey.isEmpty ? try BingyanCredentialStore.load() : suppliedKey
            guard let key, !key.isEmpty else {
                message = "请先粘贴个人 API Key，或从 JSON 文件导入课表。"
                return
            }
            let from = BingyanScheduleDate.string(from: fromDate, calendar: .current)
            let to = BingyanScheduleDate.string(from: toDate, calendar: .current)
            let selectedTable = periodTable == "auto" ? nil : periodTable
            let response = try await BingyanScheduleClient().fetch(from: from, to: to,
                                                                  periodTable: selectedTable, apiKey: key)
            if !suppliedKey.isEmpty {
                do {
                    try BingyanCredentialStore.save(key)
                    apiKeyInput = ""
                    keyIsSaved = true
                } catch {
                    message = "课表已经读取。Key 未能保存在这台设备上；关闭页面后需要重新输入。"
                }
            }
            let batch = BingyanScheduleImportBuilder.build(response)
            preview = BingyanSchedulePreviewPresentation(batch: batch)
        } catch let error as BingyanScheduleHTTPError {
            switch error.statusCode {
            case 401: message = "Key 无效、已撤销或已过期。请在冰岩开放平台核对后重新输入。"
            case 403: message = "这个 Key 没有课表只读权限。请创建一个包含课表只读权限的 Key。"
            case 404: message = "冰岩云端还没有可读取的课表，请先在 Hustoday App 中同步课表。"
            default: message = error.localizedDescription
            }
        } catch {
            message = error.localizedDescription
        }
    }
}

private struct BingyanSchedulePreviewView: View {
    @EnvironmentObject private var store: EntryStore
    @EnvironmentObject private var notifications: NotificationManager
    @Environment(\.dismiss) private var dismiss
    let batch: BingyanScheduleImportBatch
    @State private var courseRemindersEnabled = true
    @State private var scheduleRemindersEnabled = false
    @State private var saving = false
    @State private var imported = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("可导入 \(batch.schedules.count) 个日程").font(.headline)
                    Text("\(batch.courses.count) 次课程可保留现有下课登记提醒")
                        .font(.subheadline).foregroundStyle(.secondary)
                    if batch.skippedCount > 0 {
                        Label("跳过 \(batch.skippedCount) 项：没有有效的具体起止时间，或时间格式无效。", systemImage: "exclamationmark.circle")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Text("这是一次课表快照。重复导入会按课程内容去重，不会自动跟随之后的课表变化，也不会覆盖你已编辑的日程。")
                        .font(.footnote).foregroundStyle(.secondary)
                    Toggle("下课时提醒登记作业", isOn: $courseRemindersEnabled)
                    Toggle("日程开始时提醒", isOn: $scheduleRemindersEnabled)
                }
                if batch.items.isEmpty {
                    ContentUnavailableView("没有可导入的定时项目",
                                           systemImage: "calendar.badge.exclamationmark",
                                           description: Text("课表项目缺少可用的开始或结束时刻。"))
                } else {
                    Section("预览") {
                        ForEach(batch.items) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(item.title).font(.headline)
                                    Spacer()
                                    Text(item.isCourse ? "课程" : "日程")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Text("\(item.start.formatted(.dateTime.year().month().day().weekday(.wide)))  \(item.start.formatted(date: .omitted, time: .shortened))–\(item.end.formatted(date: .omitted, time: .shortened))")
                                    .font(.subheadline).foregroundStyle(.secondary)
                                if !item.location.isEmpty {
                                    Text(item.location).font(.caption).foregroundStyle(.secondary)
                                }
                                if !item.details.isEmpty {
                                    Text(item.details).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 3)
                        }
                    }
                }
            }
            .navigationTitle("核对冰岩课表")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("返回") { dismiss() }.disabled(saving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("确认导入") { Task { await save() } }
                        .disabled(saving || !batch.hasImportableItems || store.readOnly)
                }
            }
            .interactiveDismissDisabled(saving)
            .alert("课表导入", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("知道了") { if imported { dismiss() } }
            } message: { Text(message ?? "") }
        }
    }

    private func save() async {
        guard !store.readOnly else { message = "当前为只读模式，不能导入课表。"; return }
        saving = true
        defer { saving = false }
        let needsNotifications = courseRemindersEnabled || scheduleRemindersEnabled
        let authorized = needsNotifications ? await notifications.requestAccess() : true
        let courses = batch.courses.map { course in
            var copy = course
            copy.reminderEnabled = courseRemindersEnabled
            return copy
        }
        let schedules = batch.schedules.map { entry in
            var copy = entry
            copy.reminder = scheduleRemindersEnabled ? .atTime : nil
            copy.reminderDelivery = .popup
            return copy
        }
        guard store.importCourseSchedules(courses, schedules: schedules) else {
            message = store.error ?? "保存失败。"
            return
        }
        imported = true
        if needsNotifications && !authorized {
            message = "课表已导入。系统通知未开启，请在设置中开启后接收提醒。"
        } else {
            dismiss()
        }
    }
}
