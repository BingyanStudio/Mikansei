import SwiftUI
import EventKit
import EventKitUI

struct EntryEditor: View {
    @EnvironmentObject private var store: EntryStore
    @EnvironmentObject private var notifications: NotificationManager
    @EnvironmentObject private var calendarSync: CalendarSyncManager
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Entry
    @State private var hasDueDate: Bool
    @State private var date: Date
    @State private var hasReminder: Bool
    @State private var lead: ReminderLead
    @State private var durationMinutes: Int
    @State private var newStep = ""
    @State private var saving = false
    @State private var confirmDelete = false
    @State private var notificationWarning = false
    @State private var calendarPlan: CalendarPlanSession?
    @State private var calendarLinkWarning: String?
    @State private var validationError: String?
    @State private var expanded: Bool
    @State private var discardChanges = false
    @FocusState private var titleFocused: Bool
    private let original: Entry
    let isNew: Bool

    init(entry: Entry, isNew: Bool) {
        original = entry
        self.isNew = isNew
        _draft = State(initialValue: entry)
        _hasDueDate = State(initialValue: entry.dueDate != nil)
        let suggested = Date(timeIntervalSince1970: (Date().addingTimeInterval(3600).timeIntervalSince1970 / 60).rounded(.up) * 60)
        _date = State(initialValue: entry.dueDate ?? suggested)
        _hasReminder = State(initialValue: entry.reminder != nil)
        _lead = State(initialValue: entry.reminder ?? .atTime)
        _durationMinutes = State(initialValue: Self.duration(of: entry))
        _expanded = State(initialValue: !isNew || entry.kind == .schedule || entry.plannedStart != nil || (!entry.source.isEmpty && !entry.source.hasPrefix("课后登记：")))
    }
    private var canSave: Bool { !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !saving && !store.readOnly }
    private var dirty: Bool {
        draft != original || !newStep.isEmpty || hasDueDate != (original.dueDate != nil) ||
        (hasDueDate && date != original.dueDate) || hasReminder != (original.reminder != nil) ||
        (hasReminder && lead != original.reminder) || durationMinutes != Self.duration(of: original)
    }
    private var candidate: Entry {
        var entry = draft
        entry.dueDate = hasDueDate && entry.isTask && entry.kind != .schedule ? date : nil
        if entry.kind == .schedule, let start = entry.plannedStart {
            let minutes = min(525600, max(1, durationMinutes))
            entry.plannedEnd = entry.plannedAllDay
                ? Calendar.current.date(byAdding: .day, value: max(1, minutes / 1440), to: Calendar.current.startOfDay(for: start))
                : start.addingTimeInterval(Double(minutes) * 60)
        }
        if entry.repeatRule == .dates, (isNew || draft.repeatDates != original.repeatDates || draft.repeatRule != original.repeatRule),
           let first = entry.repeatDates.min(), let base = entry.recurrenceReferenceDate {
            let time = Calendar.current.dateComponents([.hour, .minute], from: base)
            if let firstDate = Calendar.current.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: 0, of: first) {
                entry = entry.occurrence(at: firstDate)
            }
        }
        entry.reminder = entry.attentionDate != nil && hasReminder && entry.isTask ? lead : nil
        if !newStep.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            entry.checklist.append(ChecklistItem(title: newStep))
        }
        if entry.isCompleted && entry.checklist.contains(where: { !$0.isDone }) {
            entry.isCompleted = false
            entry.completedAt = nil
        }
        return entry.normalized()
    }
    var body: some View {
        NavigationStack {
            editorForm
            .disabled(store.readOnly || saving)
            .navigationTitle(isNew ? "新建\(draft.kind.title)" : "编辑\(draft.kind.title)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { if dirty { discardChanges = true } else { dismiss() } }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { Task { await save() } }.fontWeight(.semibold).disabled(!canSave)
                        .accessibilityIdentifier("save-entry")
                }
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("收起键盘") { titleFocused = false; hideKeyboard() } }
            }
            .interactiveDismissDisabled(saving || dirty)
             .onChange(of: hasDueDate) { _, enabled in
                if enabled { hasReminder = true } else if draft.plannedStart == nil { hasReminder = false }
                if !enabled && draft.plannedStart == nil { draft.repeatRule = .never }
            }
            .onChange(of: draft.kind) { _, kind in
                if kind == .schedule {
                    let start = draft.plannedStart ?? date
                    draft.plannedStart = start
                    draft.plannedEnd = start.addingTimeInterval(Double(durationMinutes) * 60)
                    hasDueDate = false; hasReminder = true; lead = .atTime
                    draft.reminderDelivery = .alarm; draft.reminderAnchor = .execution
                    draft.reminderPattern = .single; expanded = true
                }
            }
            .onChange(of: date) { _, _ in draft.repeatAnchorDate = nil }
            .task { if isNew && draft.title.isEmpty { titleFocused = true } }
            .confirmationDialog("放弃未保存的修改？", isPresented: $discardChanges, titleVisibility: .visible) { Button("放弃修改", role: .destructive) { dismiss() } }
            .confirmationDialog("删除后无法撤销，建议先导出备份。", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("删除", role: .destructive) { if store.delete(draft.id) { dismiss() } else { validationError = store.error } }
            }
            .alert("无法保存", isPresented: Binding(get: { validationError != nil }, set: { if !$0 { validationError = nil } })) {
                Button("知道了", role: .cancel) {}
            } message: { Text(validationError ?? "") }
            .sheet(item: $calendarPlan) { session in
                CalendarPlanEditor(session: session) { action, event in
                    if action == .saved, let event, let record = CalendarSyncManager.record(event) {
                        if !store.linkCalendarEvent(record, entryID: session.entryID) { calendarLinkWarning = "日程已写入日历，但清单关联保存失败。请在设置中立即同步日历后核对。" }
                    } else if action == .deleted, let entry = store.entries.first(where: { $0.id == session.entryID }) {
                        var next = entry
                        next.calendarEvent?.missingFromSource = true
                        _ = store.save(next)
                    }
                    calendarPlan = nil
                    if calendarLinkWarning == nil { dismiss() }
                }.ignoresSafeArea()
            }
            .alert("日历已保存", isPresented: Binding(get: { calendarLinkWarning != nil }, set: { if !$0 { calendarLinkWarning = nil } })) { Button("知道了") { dismiss() } } message: { Text(calendarLinkWarning ?? "") }
            .alert(candidate.reminderDelivery == .alarm ? "闹钟提醒不可用" : "系统通知未开启", isPresented: $notificationWarning) {
                Button("先保存事项") { persist() }
                Button("前往设置") { persist(); openSettings() }
                Button("继续编辑", role: .cancel) {}
            } message: { Text(candidate.reminderDelivery == .alarm ? notifications.supportsAlarms ? "事项可以保存。请在系统设置中允许闹钟权限后接收闹钟提醒。" : "当前系统需要升级至 iOS 26，或继续编辑改用弹窗提醒。事项仍可保存。" : "事项和提醒时间可以保存，但要在系统设置中开启通知后，手机才会发送提醒。") }
        }
    }
    private var editorForm: some View {
            Form {
                Section {
                    ChoiceStrip(label: "类型", choices: EntryKind.allCases, selection: $draft.kind,
                                title: { $0.title }, identifier: { "kind-\($0.rawValue)" })
                    TextField(draft.kind == .note ? "笔记标题" : draft.kind == .schedule ? "日程标题" : "要做什么？", text: $draft.title, axis: .vertical)
                        .font(.title3.weight(.semibold)).lineLimit(1...4).focused($titleFocused)
                        .accessibilityIdentifier("entry-title")
                    if !expanded {
                        if !draft.category.isEmpty { LabeledContent("课程 / 分类", value: draft.category) }
                        if !draft.platform.isEmpty { LabeledContent("提交平台", value: draft.platform) }
                        Text("先写一句话保存，细节可以稍后补。") .font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Button("今天") { date = Calendar.current.date(bySettingHour: 23, minute: 59, second: 0, of: Date())!; hasDueDate = true; hasReminder = true }
                            Button("明天") { date = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.date(bySettingHour: 23, minute: 59, second: 0, of: Date())!)!; hasDueDate = true; hasReminder = true }
                            Button("无日期") { hasDueDate = false }
                        }.buttonStyle(.bordered).fontWeight(.semibold)
                        if hasDueDate {
                            Text("截止 \(Theme.dateLabel(date))").font(.caption).foregroundStyle(Theme.accent)
                            Toggle("到点提醒", isOn: $hasReminder)
                        }
                    }
                }
                if isNew && !expanded {
                    Section { Button("补充 DDL、平台、耗时或循环", systemImage: "slider.horizontal.3") { expanded = true; titleFocused = false; hideKeyboard() } }
                }
                if expanded {
                if draft.kind == .schedule { scheduleSection }
                Section("事项信息") {
                    TextField(draft.kind == .homework ? "科目 / 分类" : "分类（学习、生活、社团…）", text: $draft.category)
                        .accessibilityIdentifier("entry-category")
                    if draft.isTask {
                        Picker("优先级", selection: $draft.priority) { ForEach(EntryPriority.allCases) { Text($0.title).tag($0) } }.clearOptionText()
                        TextField("提交 / 处理平台（如学习通、邮箱）", text: $draft.platform)
                        TextField("处理地点（如校医院、洗衣房）", text: $draft.location)
                        if draft.kind != .schedule { Picker("预计耗时", selection: Binding(get: { draft.estimatedMinutes ?? 0 }, set: { draft.estimatedMinutes = $0 == 0 ? nil : $0 })) {
                            Text("暂不确定").tag(0)
                            ForEach([5, 10, 15, 30, 45, 60, 90, 120, 180], id: \.self) { Text("\($0) 分钟").tag($0) }
                            if let minutes = draft.estimatedMinutes, ![5, 10, 15, 30, 45, 60, 90, 120, 180].contains(minutes) { Text("\(minutes) 分钟").tag(minutes) }
                        }.clearOptionText() }
                    }
                }
                notesSection
                checklistSection
                if draft.isTask {
                    routineSection
                    reminderSection
                    Section {
                        if let start = draft.plannedStart, let end = draft.plannedEnd {
                            Label(draft.plannedAllDay ? "全天安排" : "执行时段", systemImage: "calendar")
                            Text("\(Theme.dateLabel(start)) — \(Theme.dateLabel(draft.plannedAllDay ? end.addingTimeInterval(-1) : end))").font(.subheadline)
                        }
                        Button(draft.calendarEvent == nil ? "保存并安排到苹果日历" : "保存并编辑日历日程", systemImage: "calendar.badge.plus") {
                            Task { await saveToCalendar() }
                        }.disabled(!canSave || draft.repeatRule != .never).accessibilityIdentifier("plan-in-calendar")
                    } header: { Text("实际安排 · 可选") } footer: {
                        Text(draft.isRoutine ? "常态在 Mikansei 中按规则重复。苹果日历来源的重复事件按每一次分别同步，避免双重重复。" : "按开始时间和持续时间保存日程即可；需要同步到苹果日历时再点此按钮。DDL 待办不必安排执行时段。")
                    }
                    if !isNew {
                        Section {
                            Toggle("标为已完成", isOn: Binding(get: { draft.isCompleted }, set: { draft.setCompleted($0) }))
                        }
                        if draft.startedAt != nil || draft.elapsedSeconds > 0 {
                            Section("专注计时") {
                                HStack {
                                    Text(draft.startedAt != nil ? "正在计时" : "累计用时")
                                    Spacer()
                                    FocusClock(entry: draft).foregroundStyle(Theme.accent)
                                }
                            }
                        }
                    }
                }
                if !draft.source.isEmpty {
                    Section("信息来源 · 请核对日期与平台") {
                        Text(draft.source).font(.subheadline).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }
                if let link = draft.calendarEvent {
                    Section {
                        LabeledContent("日历", value: link.event.identity.calendarTitle)
                        LabeledContent("账号", value: link.event.identity.sourceTitle)
                        Text(Theme.calendarLabel(link.event)).font(.subheadline)
                        if link.event.isCancelled { Text("原日历已取消，事项保留供你确认。") .font(.caption).foregroundStyle(Theme.warm) }
                        else if link.missingFromSource { Text("本次读取未在原日历中找到事件，事项已保留。") .font(.caption).foregroundStyle(Theme.warm) }
                    } header: { Text("来自系统日历") } footer: {
                        Text("日历调整时段会在下次同步更新；勾选或删除清单不会删除日历事件。完成状态与 Checklist 保留在 Mikansei。")
                    }
                }
                }
                if !isNew {
                    Section {
                        Text("创建于 \(Theme.dateLabel(draft.createdAt))").font(.caption).foregroundStyle(.secondary)
                        Button("删除\(draft.kind.title)", role: .destructive) { confirmDelete = true }
                    }
                }
            }
    }
    private var notesSection: some View {
                Section(draft.kind == .note ? "随手记" : "补充说明") {
                    TextField("写下细节、想法或需要记住的事…", text: $draft.body, axis: .vertical)
                        .lineLimit(5...14).accessibilityIdentifier("entry-body")
                }
    }
    private var checklistSection: some View {
                Section {
                    ForEach($draft.checklist) { $step in
                        HStack(alignment: .top, spacing: 10) {
                            Button {
                                step.isDone.toggle()
                                if !step.isDone { draft.isCompleted = false; draft.completedAt = nil }
                            } label: {
                                Image(systemName: step.isDone ? "checkmark.square.fill" : "square")
                                    .font(.title3).frame(width: 32, height: 36)
                            }.buttonStyle(.plain).accessibilityLabel(step.isDone ? "取消完成步骤" : "完成步骤")
                            TextField("步骤内容", text: $step.title, axis: .vertical).padding(.top, 6)
                            Button(role: .destructive) { draft.checklist.removeAll { $0.id == step.id } } label: {
                                Image(systemName: "minus.circle").frame(width: 32, height: 36)
                            }.buttonStyle(.plain).accessibilityLabel("删除步骤")
                        }
                    }
                    HStack {
                        Image(systemName: "plus").foregroundStyle(Theme.accent)
                        TextField("添加一个小步骤", text: $newStep).onSubmit(addStep).submitLabel(.done)
                            .accessibilityIdentifier("new-step")
                        Button("添加", action: addStep).disabled(newStep.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .accessibilityIdentifier("add-step")
                    }
                } header: { Text("Checklist · 逐项勾选") } footer: {
                    Text("步骤全部勾选后，仍可自行决定何时将整件事标为完成。")
                }
    }
    private var scheduleSection: some View {
        Section {
            DatePicker("开始时间", selection: Binding(get: { draft.plannedStart ?? date }, set: { value in
                draft.plannedStart = draft.plannedAllDay ? Calendar.current.startOfDay(for: value) : value
                draft.repeatAnchorDate = nil
            }), displayedComponents: draft.plannedAllDay ? [.date] : [.date, .hourAndMinute])
                .accessibilityIdentifier("schedule-start")
            Toggle("全天", isOn: Binding(get: { draft.plannedAllDay }, set: { value in
                draft.plannedAllDay = value
                if value {
                    draft.plannedStart = Calendar.current.startOfDay(for: draft.plannedStart ?? date)
                    durationMinutes = max(1, Int(ceil(Double(min(525600, max(1, durationMinutes))) / 1440))) * 1440
                } else { durationMinutes = 60 }
            }))
            HStack {
                Text("持续时间")
                Spacer()
                if draft.plannedAllDay {
                    TextField("天数", value: Binding(get: { max(1, durationMinutes / 1440) }, set: { durationMinutes = min(366, max(0, $0)) * 1440 }), format: .number)
                        .keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 80)
                    Text("天")
                } else {
                    TextField("分钟数", value: $durationMinutes, format: .number)
                        .keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 80)
                        .accessibilityIdentifier("schedule-duration")
                    Text("分钟")
                }
            }
            if !draft.plannedAllDay {
                Picker("常用时长", selection: $durationMinutes) {
                    ForEach(Array(Set([15, 30, 45, 60, 90, 120, durationMinutes])).sorted(), id: \.self) { Text("\($0) 分钟").tag($0) }
                }.clearOptionText()
            }
            if let end = candidate.plannedEnd {
                LabeledContent("自动结束于", value: Theme.dateLabel(draft.plannedAllDay ? end.addingTimeInterval(-1) : end))
            }
        } header: { Text("开始与持续时间") } footer: { Text("结束时间自动计算，不需要手动调整。日程不会被当作逾期 DDL。") }
    }
    private var routineSection: some View {
        Section {
            if draft.calendarEvent?.event.identity.occurrence.isEmpty == false {
                Label("常态 · 苹果日历重复", systemImage: "repeat")
                Text("重复规律由苹果日历管理，每次日程分别同步；在苹果日历中修改规律。")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Toggle("常态（Routine）", isOn: Binding(get: { draft.isRoutine }, set: { enabled in
                    draft.repeatRule = enabled ? .daily : .never
                    if enabled && candidate.recurrenceReferenceDate == nil { hasDueDate = true }
                    draft.repeatAnchorDate = nil
                    if enabled { draft.reminderPattern = .single }
                })).accessibilityIdentifier("routine-enabled")
                if draft.isRoutine {
                    Picker("发生规律", selection: $draft.repeatRule) {
                        ForEach(RepeatRule.allCases.filter { $0 != .never }) { Text($0.title).tag($0) }
                    }.clearOptionText().accessibilityIdentifier("routine-rule")
                    if draft.kind != .schedule && draft.plannedStart == nil {
                        DatePicker("首次发生时间", selection: $date, displayedComponents: [.date, .hourAndMinute])
                    }
                    if draft.repeatRule == .weekly {
                        HStack(spacing: 4) {
                            ForEach(1...7, id: \.self) { day in
                                let selected = draft.repeatWeekdays.contains(day)
                                Button(["一", "二", "三", "四", "五", "六", "日"][day - 1]) {
                                    if selected { draft.repeatWeekdays.removeAll { $0 == day } } else { draft.repeatWeekdays.append(day) }
                                }.buttonStyle(.bordered).tint(selected ? Theme.accent : .secondary)
                                    .accessibilityLabel("每周\(["一", "二", "三", "四", "五", "六", "日"][day - 1])")
                                    .accessibilityAddTraits(selected ? .isSelected : [])
                            }
                        }
                        Text("不选星期时，按首次发生的星期重复。") .font(.caption).foregroundStyle(.secondary)
                    }
                    if draft.repeatRule == .monthly {
                        Stepper("每 \(draft.repeatIntervalMonths) 个月", value: $draft.repeatIntervalMonths, in: 1...12)
                        Text("按首次发生的日期重复；该月没有此日期时在月末发生。") .font(.caption).foregroundStyle(.secondary)
                    }
                    if draft.repeatRule == .custom { Stepper("每 \(draft.repeatIntervalDays) 天", value: $draft.repeatIntervalDays, in: 1...365) }
                    if draft.repeatRule == .dates { RoutineDatePicker(dates: $draft.repeatDates, initialDate: draft.recurrenceReferenceDate ?? date) }
                }
            }
        } header: { Text("标签") } footer: {
            Text("常态可加在待办或日程上。完成当前事项后生成下一次，步骤和计时重新开始；日历会展示后续日期，点选可编辑常态规则。")
        }
    }
    private var reminderSection: some View {
                    Section {
                        if draft.kind != .schedule {
                        Toggle("设置截止时间（DDL）", isOn: $hasDueDate).accessibilityIdentifier("has-due-date")
                        if hasDueDate {
                            DatePicker("日期与时间", selection: $date, displayedComponents: [.date, .hourAndMinute])
                                .environment(\.locale, Locale(identifier: "zh_CN"))
                        }
                        }
                        if candidate.attentionDate != nil {
                            Toggle("提醒我", isOn: $hasReminder).accessibilityIdentifier("has-reminder")
                            if hasReminder {
                                if draft.kind != .schedule && hasDueDate && draft.plannedStart != nil {
                                    Picker("提醒基准", selection: $draft.reminderAnchor) { ForEach(ReminderAnchor.allCases) { Text($0.title).tag($0) } }.clearOptionText()
                                }
                                ReminderOptionsView(delivery: $draft.reminderDelivery, sound: $draft.reminderSound, snoozeMinutes: $draft.snoozeMinutes)
                                if draft.repeatRule == .never && draft.kind != .schedule {
                                    Picker("催办方式", selection: $draft.reminderPattern) { ForEach(ReminderPattern.allCases) { Text($0.title).tag($0) } }.clearOptionText()
                                }
                                if draft.reminderPattern == .single || draft.repeatRule != .never {
                                Picker("提醒时间", selection: $lead) { ForEach(ReminderLead.allCases) { Text($0.title).tag($0) } }.clearOptionText()
                                }
                                Text(draft.repeatRule == .never ? ((draft.reminderAnchor == .execution || !hasDueDate) ? draft.reminderPattern.explanation.replacingOccurrences(of: "截止", with: "安排") : draft.reminderPattern.explanation) : "按设定周期提醒；完成后自动生成下一次事项。未完成时也会在后续周期继续提醒。")
                                    .font(.caption).foregroundStyle(.secondary)
                                if draft.repeatRule != .never {
                                    if let next = NotificationPlan.pending(entries: [candidate], courses: [], limit: 1).first {
                                        Label("下一次提醒 \(Theme.dateLabel(next.date))", systemImage: "bell").font(.caption).foregroundStyle(.secondary)
                                    }
                                } else if draft.reminderPattern == .single, let reminderDate = candidate.reminderDate {
                                    Label(Theme.dateLabel(reminderDate), systemImage: "bell").font(.caption).foregroundStyle(.secondary)
                                    if reminderDate <= Date() {
                                        Text("提醒时间已经过去，请调整时间或关闭提醒。")
                                            .font(.caption).foregroundStyle(Theme.warm)
                                    }
                                }
                            }
                        }
                    } header: { Text("日程与提醒") } footer: {
                        Text(draft.kind == .schedule ? "日程按开始时间提醒，默认使用闹钟。闹钟需要 iOS 26 及授权；较早版本可改用弹窗。" : "截止时间只表示最晚何时完成，不会自动写入苹果日历。提醒开启时申请对应权限。")
                    }
    }
    private func addStep() {
        let title = newStep.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        draft.checklist.append(ChecklistItem(title: title))
        newStep = ""
    }
    private func saveToCalendar() async {
        guard canSave, validateSchedule() else { return }
        saving = true
        defer { saving = false }
        if candidate.reminderDate != nil, !(await notifications.requestAccess(for: candidate.reminderDelivery)) { notificationWarning = true; return }
        do {
            let session = try await calendarSync.preparePlan(for: candidate)
            guard store.save(candidate) else { validationError = store.error; return }
            calendarPlan = session
        } catch { validationError = error.localizedDescription }
    }
    private func save() async {
        guard canSave, validateSchedule() else { return }
        let entry = candidate
        if entry.repeatRule == .never && entry.reminderPattern == .single,
           let reminderDate = entry.reminderDate, reminderDate <= Date(), reminderDate != original.reminderDate {
            validationError = "提醒时间已过去。请调整日期、选择更短的提前时间，或关闭提醒。"
            return
        }
        saving = true
        if entry.reminderDate != nil {
            let allowed = await notifications.requestAccess(for: entry.reminderDelivery)
            if !allowed {
                saving = false
                notificationWarning = true
                return
            }
        }
        persist()
        saving = false
    }
    private func persist() {
        if store.save(candidate) { dismiss() }
        else { validationError = store.error ?? "未能保存，请重试。" }
    }
    private func validateSchedule() -> Bool {
        if draft.kind == .schedule && !(1...525600).contains(durationMinutes) {
            validationError = "请输入有效的持续时间（1 分钟至 365 天）。"; return false
        }
        if draft.repeatRule == .dates && draft.repeatDates.isEmpty {
            validationError = "请在日历上至少选择一个发生日期。"; return false
        }
        return true
    }
    private static func duration(of entry: Entry) -> Int {
        guard let start = entry.plannedStart, let end = entry.plannedEnd else { return 30 }
        if entry.plannedAllDay { return max(1, Calendar.current.dateComponents([.day], from: start, to: end).day ?? 1) * 1440 }
        return max(1, Int(ceil(end.timeIntervalSince(start) / 60)))
    }
    private func hideKeyboard() { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
    private func openSettings() { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
}

private struct RoutineDatePicker: View {
    @Binding var dates: [Date]
    @State private var month = Date()
    init(dates: Binding<[Date]>, initialDate: Date) { _dates = dates; _month = State(initialValue: initialDate) }
    private var calendar: Calendar { var value = Calendar.current; value.firstWeekday = 2; return value }
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Button { move(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }.accessibilityLabel("选日：上个月")
                Spacer()
                Text(month, format: .dateTime.year().month()).font(.headline)
                Spacer()
                Button { move(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }.accessibilityLabel("选日：下个月")
            }
            HStack { ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) { Text($0).font(.caption).frame(maxWidth: .infinity) } }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 6) {
                ForEach(CalendarDisplay.monthDays(containing: month, calendar: calendar), id: \.self) { day in
                    let selected = dates.contains { calendar.isDate($0, inSameDayAs: day) }
                    Button {
                        if selected { dates.removeAll { calendar.isDate($0, inSameDayAs: day) } }
                        else { dates.append(day); dates.sort() }
                    } label: {
                        Text("\(calendar.component(.day, from: day))").frame(maxWidth: .infinity, minHeight: 40)
                            .foregroundStyle(selected ? Color(uiColor: .systemBackground) : Color.primary)
                            .background(selected ? Theme.accent : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                            .opacity(calendar.isDate(day, equalTo: month, toGranularity: .month) ? 1 : 0.5)
                    }.buttonStyle(.plain).accessibilityLabel(day.formatted(.dateTime.year().month().day()))
                        .accessibilityAddTraits(selected ? .isSelected : [])
                        .accessibilityIdentifier("routine-date-\(Int(day.timeIntervalSince1970))")
                }
            }
            Text("点选任意日期，可跨月多选。已选 \(dates.count) 天，均沿用首次发生时间。")
                .font(.caption).foregroundStyle(.secondary)
        }.accessibilityIdentifier("routine-date-picker")
    }
    private func move(_ direction: Int) { if let next = calendar.date(byAdding: .month, value: direction, to: calendar.dateInterval(of: .month, for: month)!.start) { month = next } }
}
