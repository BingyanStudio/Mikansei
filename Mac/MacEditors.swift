import SwiftUI

struct MacEntryEditor: View {
    @EnvironmentObject private var store: MacWorkspaceStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Entry
    @State private var stepTitle = ""
    @State private var conflict = false
    @State private var repeatDate = Date()
    private let original: Entry
    init(entry: Entry) { original = entry; _draft = State(initialValue: entry) }
    var body: some View {
        VStack(spacing: 0) {
            HStack { Text(original.title.isEmpty ? "新建事项" : "编辑事项").font(.title2); Spacer(); Button("取消") { dismiss() }.keyboardShortcut(.cancelAction); Button("保存") { save() }.keyboardShortcut("s").disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.readOnly) }.padding(20)
            Divider()
            Form {
                TextField("事项", text: $draft.title).autocorrectionDisabled().accessibilityIdentifier("entry-title")
                Picker("类型", selection: $draft.kind) { ForEach(EntryKind.allCases) { Text($0.title).tag($0) } }
                    .onChange(of: draft.kind) { _, kind in
                        if kind == .schedule {
                            draft.plannedStart = draft.plannedStart ?? Date().addingTimeInterval(3600)
                            draft.plannedEnd = draft.plannedEnd ?? draft.plannedStart!.addingTimeInterval(1800)
                            draft.dueDate = nil; draft.reminderAnchor = .execution
                        } else {
                            draft.plannedStart = nil; draft.plannedEnd = nil; draft.plannedAllDay = false; draft.reminderAnchor = .deadline
                            if kind == .note { draft.reminder = nil; draft.repeatRule = .never }
                        }
                    }
                if draft.kind != .note {
                    Picker("重要级", selection: $draft.priority) { ForEach(EntryPriority.allCases) { Text($0.title).tag($0) } }
                    if draft.kind == .schedule {
                        DatePicker("开始", selection: optionalDate(\.plannedStart))
                        DatePicker("结束", selection: optionalDate(\.plannedEnd), in: (draft.plannedStart ?? .distantPast)...)
                        Toggle("全天", isOn: $draft.plannedAllDay)
                    } else {
                        Toggle("设置 DDL", isOn: Binding(get: { draft.dueDate != nil }, set: { draft.dueDate = $0 ? Date().addingTimeInterval(3600) : nil; if !$0 { draft.reminder = nil } }))
                        if draft.dueDate != nil { DatePicker("DDL", selection: optionalDate(\.dueDate)) }
                    }
                    TextField("科目 / 分类", text: $draft.category)
                    TextField("处理平台", text: $draft.platform)
                    TextField("地点", text: $draft.location)
                    TextField("预计分钟", value: $draft.estimatedMinutes, format: .number)
                    Picker("常态", selection: $draft.repeatRule) { ForEach(RepeatRule.allCases) { Text($0.title).tag($0) } }
                    if draft.repeatRule == .custom { Stepper("每 \(draft.repeatIntervalDays) 天", value: $draft.repeatIntervalDays, in: 1...365) }
                    if draft.repeatRule == .monthly { Stepper("每 \(draft.repeatIntervalMonths) 月", value: $draft.repeatIntervalMonths, in: 1...12) }
                    if draft.repeatRule == .weekly {
                        HStack { ForEach(1...7, id: \.self) { day in Toggle(["一", "二", "三", "四", "五", "六", "日"][day - 1], isOn: Binding(get: { draft.repeatWeekdays.contains(day) }, set: { on in draft.repeatWeekdays.removeAll { $0 == day }; if on { draft.repeatWeekdays.append(day) } })).toggleStyle(.button) } }
                    }
                    if draft.repeatRule == .dates {
                        HStack { DatePicker("选日", selection: $repeatDate, displayedComponents: .date); Button("加入") { draft.repeatDates.append(repeatDate) } }
                        ForEach(Array(draft.repeatDates.enumerated()), id: \.offset) { index, date in HStack { Text(date, style: .date); Spacer(); Button("移除") { draft.repeatDates.remove(at: index) } } }
                    }
                    if draft.attentionDate != nil {
                        Toggle("提醒", isOn: Binding(get: { draft.reminder != nil }, set: { draft.reminder = $0 ? .atTime : nil }))
                        if draft.reminder != nil { Picker("提前", selection: Binding(get: { draft.reminder ?? .atTime }, set: { draft.reminder = $0 })) { ForEach(ReminderLead.allCases) { Text($0.title).tag($0) } } }
                    }
                }
                Section("备注") { TextEditor(text: $draft.body).frame(minHeight: 110) }
                Section("Checklist") {
                    ForEach($draft.checklist) { $step in HStack { Toggle("", isOn: $step.isDone).labelsHidden(); TextField("步骤", text: $step.title); Button("删除") { draft.checklist.removeAll { $0.id == step.id } } } }
                    HStack { TextField("添加一步", text: $stepTitle).onSubmit(addStep); Button("加入", action: addStep).disabled(stepTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                }
            }.formStyle(.grouped)
        }.frame(width: 650, height: 720)
        .alert("事项已在其他地方更新", isPresented: $conflict) {
            Button("保存为新事项") { draft.id = UUID(); finish() }
            Button("使用当前草稿") { finish() }
            Button("继续编辑", role: .cancel) {}
        } message: { Text("你的草稿仍在。可以保留为另一件事项，或用当前草稿更新这件事项。") }
    }
    private func optionalDate(_ key: WritableKeyPath<Entry, Date?>) -> Binding<Date> { Binding(get: { draft[keyPath: key] ?? Date() }, set: { draft[keyPath: key] = $0 }) }
    private func addStep() { let title = stepTitle.trimmingCharacters(in: .whitespacesAndNewlines); if !title.isEmpty { draft.checklist.append(ChecklistItem(title: title)); stepTitle = "" } }
    private func save() {
        let latest = store.entries.first(where: { $0.id == original.id })
        if !original.title.isEmpty && latest != original { conflict = true } else { finish() }
    }
    private func finish() {
        draft = draft.normalized()
        do { _ = try EntryArchive.decode(EntryArchive(entries: [draft]).encoded()); store.save(draft); dismiss() }
        catch { store.error = error.localizedDescription }
    }
}

struct MacCourseEditor: View {
    @EnvironmentObject private var store: MacWorkspaceStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Course
    init(course: Course) { _draft = State(initialValue: course) }
    var body: some View {
        VStack {
            Form {
                TextField("课程名称", text: $draft.name)
                Picker("星期", selection: $draft.weekday) { ForEach(1...7, id: \.self) { Text(["周一", "周二", "周三", "周四", "周五", "周六", "周日"][$0 - 1]).tag($0) } }
                DatePicker("上课", selection: clock(\.startMinutes), displayedComponents: .hourAndMinute)
                DatePicker("下课", selection: clock(\.endMinutes), displayedComponents: .hourAndMinute)
                DatePicker("开始日期", selection: $draft.firstDate, displayedComponents: .date)
                DatePicker("结束日期", selection: $draft.lastDate, in: draft.firstDate..., displayedComponents: .date)
                TextField("地点", text: $draft.location); TextField("提交平台", text: $draft.platform)
                Toggle("下课提醒登记作业", isOn: $draft.reminderEnabled)
                Text("Mac 使用系统通知，请在设置中允许提醒。").font(.caption).foregroundStyle(.secondary)
            }.formStyle(.grouped)
            HStack { Spacer(); Button("取消") { dismiss() }.keyboardShortcut(.cancelAction); Button("保存") { store.saveCourse(draft); dismiss() }.disabled(!draft.isValid || store.readOnly).keyboardShortcut("s") }.padding()
        }.frame(width: 520, height: 470)
    }
    private func clock(_ key: WritableKeyPath<Course, Int>) -> Binding<Date> { Binding(get: { Calendar.current.date(bySettingHour: draft[keyPath: key] / 60, minute: draft[keyPath: key] % 60, second: 0, of: Date())! }, set: { draft[keyPath: key] = Calendar.current.component(.hour, from: $0) * 60 + Calendar.current.component(.minute, from: $0) }) }
}
