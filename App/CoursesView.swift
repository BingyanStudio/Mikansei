import SwiftUI
import UniformTypeIdentifiers

private struct CourseBatch: Identifiable {
    let id = UUID()
    var courses: [Course]
}

struct CoursesView: View {
    @EnvironmentObject private var store: EntryStore
    @EnvironmentObject private var notifications: NotificationManager
    @State private var editing: Course?
    @State private var importing = false
    @State private var importingBingyan = false
    @State private var batch: CourseBatch?
    @State private var message: String?
    @State private var exportingTemplate = false
    private var sorted: [Course] {
        store.courses.sorted { lhs, rhs in
            if Calendar.current.startOfDay(for: lhs.firstDate) != Calendar.current.startOfDay(for: rhs.firstDate) { return lhs.firstDate < rhs.firstDate }
            return lhs.weekday == rhs.weekday ? lhs.startMinutes < rhs.startMinutes : lhs.weekday < rhs.weekday
        }
    }
    private var template: BackupDocument {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let start = formatter.string(from: Date())
        let end = formatter.string(from: Calendar.current.date(byAdding: .day, value: 112, to: Date())!)
        return BackupDocument(data: Data("\(CourseCSV.header)\n示例课程,1,08:00,09:40,教学楼,学习通,\(start),\(end)\n".utf8))
    }
    var body: some View {
        List {
            Section {
                Button("导入冰岩每日课表", systemImage: "link") { importingBingyan = true }.disabled(store.readOnly)
                Button("导入 ICS / CSV 课表", systemImage: "calendar.badge.plus") { importing = true }.disabled(store.readOnly)
                Button("导出 CSV 模板", systemImage: "square.and.arrow.up") { exportingTemplate = true }
                Button("手动添加一节课", systemImage: "plus") { editing = Course() }.disabled(store.readOnly)
            } footer: {
                Text("每次下课提醒登记作业。ICS 会展开为逐次课程，支持常见按日 / 按周及单双周循环；调课覆盖等复杂规则会提示处理。HUSToday 导出后请先预览核对。")
            }
            if sorted.isEmpty {
                Section { Text("先添加课程和下课时间。通知会问你：有什么作业？在哪提交？DDL 和耗时是多少？").foregroundStyle(.secondary) }
            } else {
                Section("课程 · \(sorted.count) 条") {
                    ForEach(sorted) { course in
                        Button { editing = course } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                HStack { Text(course.name).font(.headline).foregroundStyle(.primary); Spacer(); if course.reminderEnabled { Image(systemName: "bell").foregroundStyle(Theme.accent) } }
                                Text("\(course.weekdayTitle) \(course.timeLabel)").font(.subheadline).foregroundStyle(.secondary)
                                if Calendar.current.isDate(course.firstDate, inSameDayAs: course.lastDate) {
                                    Text(course.firstDate, format: .dateTime.year().month().day()).font(.caption).foregroundStyle(.secondary)
                                }
                                if !course.location.isEmpty { Text(course.location).font(.caption).foregroundStyle(.secondary) }
                            }.padding(.vertical, 4)
                        }.swipeActions { Button("删除", role: .destructive) { store.deleteCourse(course.id) } }
                    }
                }
            }
        }.disabled(store.readOnly).navigationTitle("课表与登记")
            .sheet(item: $editing) { course in CourseEditor(course: course) }
            .sheet(item: $batch) { batch in CourseImportPreview(courses: batch.courses) }
            .sheet(isPresented: $importingBingyan) { BingyanScheduleImportView() }
            .fileExporter(isPresented: $exportingTemplate, document: template, contentType: .commaSeparatedText, defaultFilename: "Mikansei课表模板") { result in
                if case .failure(let error) = result { message = error.localizedDescription }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.commaSeparatedText, UTType(filenameExtension: "ics") ?? .plainText, .plainText]) { result in
                do {
                    let url = try result.get()
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    let data = try Data(contentsOf: url)
                    guard data.count <= 5_000_000, let text = String(data: data, encoding: .utf8) else { throw CourseImportError.malformed("请使用小于 5 MB 的 UTF-8 课表文件。") }
                    let courses = try text.contains("BEGIN:VCALENDAR") ? CourseICS.parse(text) : CourseCSV.parse(text)
                    guard !courses.isEmpty else { throw CourseImportError.malformed("课表没有课程。") }
                    batch = CourseBatch(courses: courses)
                } catch { message = "导入失败，未修改课表：\(error.localizedDescription)" }
            }
            .alert("课表导入", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("知道了", role: .cancel) {}
            } message: { Text(message ?? "") }
    }
}

private struct CourseImportPreview: View {
    @EnvironmentObject private var store: EntryStore
    @EnvironmentObject private var notifications: NotificationManager
    @Environment(\.dismiss) private var dismiss
    let courses: [Course]
    @State private var enabled = true
    @State private var createSchedules = false
    @State private var scheduleRemindersEnabled = false
    @State private var saving = false
    @State private var warning: String?
    private var generatedSchedules: [Entry]? {
        try? CourseScheduleConversion.schedules(for: courses)
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("识别到 \(courses.count) 条课程").font(.headline)
                    Toggle("下课时提醒登记作业", isOn: $enabled).disabled(store.readOnly)
                    Toggle("同时转为逐次日程", isOn: $createSchedules).disabled(store.readOnly)
                    if createSchedules {
                        Toggle("日程开始时提醒", isOn: $scheduleRemindersEnabled).disabled(store.readOnly)
                        if let generatedSchedules {
                            Text("将创建 \(generatedSchedules.count) 个具体日期日程；重复导入会跳过已存在的条目。")
                                .font(.caption).foregroundStyle(.secondary)
                            ForEach(Array(generatedSchedules.prefix(5)), id: \.source) { entry in
                                if let start = entry.plannedStart, let end = entry.plannedEnd {
                                    Text("\(start.formatted(.dateTime.year().month().day().weekday(.wide)))  \(start.formatted(date: .omitted, time: .shortened))–\(end.formatted(date: .omitted, time: .shortened)) · \(entry.title)")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            if generatedSchedules.count > 5 {
                                Text("其余 \(generatedSchedules.count - 5) 次课程也会按日期加入。")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        } else {
                            Text("展开后超过 2,048 次日程，请先缩短课表日期范围。")
                                .font(.caption).foregroundStyle(.red)
                        }
                    }
                    Text("按手机当前时区显示。请核对课程名、日期和下课时刻；相同课程与日期会去重。") .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(courses) { course in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(course.name).font(.headline)
                        Text("\(course.weekdayTitle) \(course.timeLabel)").foregroundStyle(.secondary)
                        Text("\(course.firstDate.formatted(.dateTime.year().month().day())) — \(course.lastDate.formatted(.dateTime.year().month().day()))")
                            .font(.caption).foregroundStyle(.secondary)
                        if !course.location.isEmpty { Text(course.location).font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }.navigationTitle("核对课表").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(saving) }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("确认导入") { Task { await save() } }
                            .disabled(saving || store.readOnly || (createSchedules && generatedSchedules == nil))
                    }
                }
                .interactiveDismissDisabled(saving)
                .alert("课表登记", isPresented: Binding(get: { warning != nil }, set: { if !$0 { warning = nil } })) {
                    Button("知道了") { if store.error == nil { dismiss() } }
                } message: { Text(warning ?? "") }
        }
    }
    private func save() async {
        guard !store.readOnly else { warning = "当前为只读模式，不能导入课程。"; return }
        saving = true
        let authorized = (enabled || (createSchedules && scheduleRemindersEnabled))
            ? await notifications.requestAccess() : true
        let prepared = courses.map { course in var c = course; c.reminderEnabled = enabled; return c }
        let schedules = (generatedSchedules ?? []).map { entry in
            var copy = entry
            copy.reminder = scheduleRemindersEnabled && createSchedules ? .atTime : nil
            return copy
        }
        if store.importCourseSchedules(prepared, schedules: createSchedules ? schedules : []) {
            if !authorized { warning = "课表已导入。系统通知未开启，请在设置中开启后接收下课登记提醒。" }
            else { dismiss() }
        } else { warning = store.error ?? "保存失败。" }
        saving = false
    }
}

private struct CourseEditor: View {
    @EnvironmentObject private var store: EntryStore
    @EnvironmentObject private var notifications: NotificationManager
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Course
    @State private var saving = false
    @State private var warning: String?
    @State private var saved = false
    @State private var createSchedules = false
    @State private var scheduleRemindersEnabled = false
    init(course: Course) { _draft = State(initialValue: course) }
    var body: some View {
        NavigationStack {
            Form {
                Section("课程") {
                    TextField("课程名称", text: $draft.name)
                    Picker("星期", selection: $draft.weekday) { ForEach(1...7, id: \.self) { Text(["周一", "周二", "周三", "周四", "周五", "周六", "周日"][$0 - 1]).tag($0) } }.clearOptionText()
                    DatePicker("上课", selection: clockBinding(\.startMinutes), displayedComponents: .hourAndMinute)
                    DatePicker("下课", selection: clockBinding(\.endMinutes), displayedComponents: .hourAndMinute)
                    TextField("教室 / 地点", text: $draft.location)
                    TextField("常用作业提交平台", text: $draft.platform)
                }
                Section("有效日期范围") {
                    DatePicker("开始日期", selection: $draft.firstDate, displayedComponents: .date)
                    DatePicker("结束日期", selection: $draft.lastDate, in: draft.firstDate..., displayedComponents: .date)
                }
                Section {
                    Toggle("下课时提醒登记作业", isOn: $draft.reminderEnabled)
                    if draft.reminderEnabled { ReminderOptionsView(delivery: $draft.reminderDelivery, sound: $draft.reminderSound, snoozeMinutes: $draft.snoozeMinutes) }
                } footer: { Text("提醒点击后会预填课程与提交平台，你只需要记下这次作业。") }
                if isNewCourse {
                    Section("同时创建日程") {
                        Toggle("把有效日期内的每次上课加入日程", isOn: $createSchedules).disabled(store.readOnly)
                        if createSchedules {
                            Toggle("日程开始时提醒", isOn: $scheduleRemindersEnabled).disabled(store.readOnly)
                            if let generatedSchedules {
                                Text("将创建 \(generatedSchedules.count) 个逐次日程。再次保存会跳过已存在的日程，不会自动改写旧记录。")
                                    .font(.caption).foregroundStyle(.secondary)
                                ForEach(Array(generatedSchedules.prefix(5)), id: \.source) { entry in
                                    if let start = entry.plannedStart, let end = entry.plannedEnd {
                                        Text("\(start.formatted(.dateTime.year().month().day().weekday(.wide)))  \(start.formatted(date: .omitted, time: .shortened))–\(end.formatted(date: .omitted, time: .shortened))")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                if generatedSchedules.count > 5 {
                                    Text("其余 \(generatedSchedules.count - 5) 次课程也会按日期加入。")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            } else {
                                Text("有效日期范围展开后超过 2,048 次日程。")
                                    .font(.caption).foregroundStyle(.red)
                            }
                        }
                    }
                }
                if !draft.isValid { Text("请填写名称，并确保下课时间晚于上课时间。") .font(.caption).foregroundStyle(.red) }
            }.navigationTitle("课程设置").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(saving) }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") { Task { await save() } }
                            .disabled(!draft.isValid || saving || store.readOnly || (createSchedules && generatedSchedules == nil))
                    }
                }
                .interactiveDismissDisabled(saving)
                .alert("课程提醒", isPresented: Binding(get: { warning != nil }, set: { if !$0 { warning = nil } })) {
                    Button("知道了") { if saved { dismiss() } }
                } message: { Text(warning ?? "") }
        }
    }
    private func clockBinding(_ keyPath: WritableKeyPath<Course, Int>) -> Binding<Date> {
        Binding(get: { Calendar.current.date(bySettingHour: draft[keyPath: keyPath] / 60, minute: draft[keyPath: keyPath] % 60, second: 0, of: Date())! },
                set: { draft[keyPath: keyPath] = Calendar.current.component(.hour, from: $0) * 60 + Calendar.current.component(.minute, from: $0) })
    }
    private var isNewCourse: Bool { !store.courses.contains { $0.id == draft.id } }
    private var generatedSchedules: [Entry]? {
        try? CourseScheduleConversion.schedules(for: [draft])
    }
    private func save() async {
        guard !store.readOnly else { warning = "当前为只读模式，不能保存课程。"; return }
        saving = true
        let schedules = (generatedSchedules ?? []).map { entry in
            var copy = entry
            copy.reminder = scheduleRemindersEnabled && createSchedules ? .atTime : nil
            return copy
        }
        let needsNotifications = draft.reminderEnabled || (createSchedules && scheduleRemindersEnabled)
        let authorized = needsNotifications ? await notifications.requestAccess(for: draft.reminderEnabled ? draft.reminderDelivery : .popup) : true
        saved = createSchedules
            ? store.importCourseSchedules([draft], schedules: schedules)
            : store.saveCourse(draft)
        if saved && authorized { dismiss() }
        else {
            let needsAlarm = draft.reminderEnabled && draft.reminderDelivery == .alarm
            warning = saved
                ? needsAlarm ? "课程已保存。闹钟需要 iOS 26 并允许闹钟权限。" : "课程已保存。请在系统设置开启通知后接收提醒。"
                : store.error ?? "保存失败。"
        }
        saving = false
    }
}
