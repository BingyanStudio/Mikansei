import SwiftUI
import UniformTypeIdentifiers

enum MacPage: String, CaseIterable, Identifiable {
    case today = "今日", all = "我的清单", overdue = "已超时", homework = "作业", routine = "常态", schedule = "日程", notes = "笔记", history = "历史", courses = "课表"
    var id: Self { self }
    var symbol: String { switch self {
        case .today: return "sun.max"; case .all: return "checklist"; case .overdue: return "exclamationmark.circle"; case .homework: return "book.closed"; case .routine: return "repeat"; case .schedule: return "calendar"; case .notes: return "note.text"; case .history: return "clock.arrow.circlepath"; case .courses: return "graduationcap"
    } }
}

struct MacWorkspaceView: View {
    @EnvironmentObject private var store: MacWorkspaceStore
    @EnvironmentObject private var sync: FolderSyncManager
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("appearance") private var appearance = 0
    @State private var page: MacPage? = .today
    @State private var selection: UUID?
    @State private var query = ""
    @State private var editing: Entry?
    @State private var editingCourse: Course?
    @State private var scheduleDate = Date()
    @State private var importCourses = false
    @State private var importBackup = false
    @StateObject private var calendarImport = MacCalendarImport()
    var body: some View {
        NavigationSplitView {
            List(MacPage.allCases, selection: $page) { item in Label(item.rawValue, systemImage: item.symbol).tag(item) }
                .navigationSplitViewColumnWidth(min: 170, ideal: 190)
                .safeAreaInset(edge: .bottom) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(sync.status).font(.caption).foregroundStyle(.secondary)
                        SettingsLink { Label("设置", systemImage: "gearshape") }
                    }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                }
        } content: {
            VStack(spacing: 0) {
                if page == .schedule {
                    DatePicker("查看日期", selection: $scheduleDate, displayedComponents: .date).datePickerStyle(.graphical).padding(8)
                    Divider()
                }
                if page == .courses {
                    List(store.courses) { course in
                        Button { editingCourse = course } label: {
                            VStack(alignment: .leading) { Text(course.name); Text("\(course.weekdayTitle) · \(course.timeLabel)").font(.caption).foregroundStyle(.secondary) }
                        }.buttonStyle(.plain).contextMenu { Button("删除", role: .destructive) { store.deleteCourse(course.id) } }
                    }
                } else {
                    TimelineView(.periodic(from: .now, by: 30)) { clock in
                        let rows = filtered(at: clock.date)
                        List(selection: $selection) {
                            if rows.isEmpty { Text(query.isEmpty ? "清单是空的，按 ⌘N 记下一件事。" : "没有匹配事项").foregroundStyle(.secondary) }
                            ForEach(rows) { entry in
                                HStack(alignment: .top, spacing: 10) {
                                    if entry.isTask { Button { store.toggle(entry.id) } label: { Image(systemName: entry.isCompleted ? "checkmark.circle.fill" : "circle").foregroundStyle(entry.isCompleted ? .green : .secondary) }.buttonStyle(.borderless).accessibilityLabel("勾选：" + entry.title) }
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(entry.title).strikethrough(entry.isCompleted)
                                        HStack(spacing: 6) {
                                            if entry.priority != .normal { Text(entry.priority.title).foregroundStyle(entry.priority == .urgent ? .red : .orange) }
                                            if let date = entry.attentionDate { Text(date, format: .dateTime.month().day().hour().minute()) }
                                            if !entry.category.isEmpty { Text(entry.category) }
                                        }.font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if entry.startedAt != nil { Image(systemName: "timer").foregroundStyle(.green) }
                                }.padding(.vertical, 5).tag(entry.id)
                                .contextMenu {
                                    Button("编辑") { editing = entry }
                                    if entry.isTask { Button(entry.isCompleted ? "重新打开" : "完成") { store.toggle(entry.id) } }
                                    Button("删除", role: .destructive) { store.delete(entry.id) }
                                }
                            }
                        }
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: store.entries)
                    }
                }
            }
            .navigationTitle(page?.rawValue ?? "清单")
            .navigationSplitViewColumnWidth(min: 280, ideal: 360)
            .searchable(text: $query, prompt: "搜索事项、平台或地点")
        } detail: {
            if let entry = store.entries.first(where: { $0.id == selection }) {
                MacEntryDetail(entry: entry) { editing = entry }
            } else {
                ContentUnavailableView("选一件事，开始做", systemImage: "checklist", description: Text("清单在左侧，详情在这里。"))
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button("新建", systemImage: "plus") { newEntry() }.disabled(store.readOnly)
                Button("同步", systemImage: "arrow.triangle.2.circlepath") { sync.request(store) }.disabled(sync.folder == nil || sync.isSyncing)
                Menu("导入", systemImage: "square.and.arrow.down") {
                    Button("JSON 备份") { importBackup = true }
                    Button("CSV / ICS 课表") { importCourses = true }
                }
            }
        }
        .preferredColorScheme(appearance == 1 ? .light : appearance == 2 ? .dark : nil)
        .sheet(item: $editing) { entry in MacEntryEditor(entry: entry).environmentObject(store) }
        .sheet(item: $editingCourse) { course in MacCourseEditor(course: course).environmentObject(store) }
        .fileImporter(isPresented: $importCourses, allowedContentTypes: [.commaSeparatedText, .calendarEvent, .plainText]) { result in
            read(result) { data, url in try store.importCourses(data, isICS: url.pathExtension.lowercased() == "ics") }
        }
        .fileImporter(isPresented: $importBackup, allowedContentTypes: [.json]) { result in read(result) { data, _ in try store.importBackup(data) } }
        .focusedSceneValue(\.newEntryAction, store.readOnly || editing != nil || editingCourse != nil ? nil : { newEntry() })
        .onChange(of: store.reminderRoute?.id) { _, _ in handleReminder() }
        .onChange(of: editing?.id) { _, id in if id == nil { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { handleReminder() } } }
        .onChange(of: editingCourse?.id) { _, id in if id == nil { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { handleReminder() } } }
        .onChange(of: store.hasUnsavedChanges) { _, pending in if !pending { sync.request(store) } }
        .onChange(of: scenePhase) { _, state in if state == .active { sync.request(store); store.scheduleNotifications(); if editing == nil { Task { await calendarImport.refresh(store: store) } } } }
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { _ in if scenePhase == .active { sync.request(store) } }
        .task { handleReminder(); sync.request(store); await calendarImport.refresh(store: store) }
        .alert("操作尚未完成", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("重试保存") { store.persist() }; Button("关闭", role: .cancel) { store.error = nil }
        } message: { Text(store.error ?? "") }
    }
    private func newEntry() {
        if page == .courses { editingCourse = Course(); return }
        var entry = Entry(kind: page == .notes ? .note : page == .schedule ? .schedule : page == .homework ? .homework : .task)
        if page == .schedule { entry.plannedStart = scheduleDate; entry.plannedEnd = scheduleDate.addingTimeInterval(1800) }
        editing = entry
    }
    private func handleReminder() {
        guard editing == nil, editingCourse == nil, let route = store.reminderRoute else { return }
        if let id = route.entryID { page = .all; selection = id }
        if let id = route.courseID, let course = store.courses.first(where: { $0.id == id }) {
            var entry = Entry(kind: .homework, category: course.name)
            entry.platform = course.platform; editing = entry
        }
        store.reminderRoute = nil
    }
    private func read(_ result: Result<URL, Error>, action: (Data, URL) throws -> Void) {
        do {
            let url = try result.get(); let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            try action(Data(contentsOf: url), url)
        } catch { store.error = error.localizedDescription }
    }
    private func filtered(at now: Date) -> [Entry] {
        let board = TaskBoard(entries: store.entries, now: now)
        let items: [Entry]
        switch page ?? .today {
        case .today: items = board.focus
        case .overdue: items = board.overdue
        case .notes: items = store.entries.filter { $0.kind == .note }
        case .homework: items = board.open.filter { $0.kind == .homework } + board.finishedToday.filter { $0.kind == .homework }
        case .routine: items = store.entries.filter { $0.isRoutine && (!$0.isCompleted || board.finishedToday.contains($0)) }
        case .history: items = board.history
        case .schedule:
            let ids = Set(CalendarDisplay.items(on: scheduleDate, entries: store.entries).map { $0.entry.id })
            items = store.entries.filter { ids.contains($0.id) }
        case .all: items = board.open + board.finishedToday
        case .courses: items = []
        }
        return items.filter { $0.matches(query) }.sorted {
            if $0.isCompleted != $1.isCompleted { return !$0.isCompleted }
            if $0.isOverdue(at: now) != $1.isOverdue(at: now) { return $0.isOverdue(at: now) }
            return TaskBoard.order($0, $1)
        }
    }
}

struct MacEntryDetail: View {
    @EnvironmentObject private var store: MacWorkspaceStore
    let entry: Entry
    let edit: () -> Void
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(entry.title).font(.largeTitle.weight(.semibold)).strikethrough(entry.isCompleted).textSelection(.enabled)
                HStack { Label(entry.kind.title, systemImage: entry.kind.symbol); if entry.priority != .normal { Text(entry.priority.title).foregroundStyle(.orange) }; Spacer(); Button("编辑", action: edit) }
                if let date = entry.dueDate { LabeledContent("DDL", value: date.formatted()) }
                if let start = entry.plannedStart { LabeledContent("开始", value: start.formatted()) }
                if let end = entry.plannedEnd { LabeledContent("结束", value: end.formatted()) }
                if !entry.platform.isEmpty { LabeledContent("平台", value: entry.platform) }
                if !entry.location.isEmpty { LabeledContent("地点", value: entry.location) }
                if let minutes = entry.estimatedMinutes { LabeledContent("估时", value: "\(minutes) 分钟") }
                if entry.isRoutine { LabeledContent("常态", value: entry.repeatLabel) }
                if !entry.body.isEmpty { Text(entry.body).textSelection(.enabled) }
                ForEach(entry.checklist) { step in
                    Button {
                        var current = store.entries.first { $0.id == entry.id } ?? entry
                        current.toggleStep(step.id); store.save(current)
                    } label: { Label(step.title, systemImage: step.isDone ? "checkmark.square.fill" : "square").strikethrough(step.isDone) }.buttonStyle(.plain)
                }
                if entry.isTask {
                    HStack {
                        Button(entry.isCompleted ? "重新打开" : "完成事项") { store.toggle(entry.id) }
                        if !entry.isCompleted { Button(entry.startedAt == nil ? "开始做" : "暂停") { store.focus(entry.id) } }
                    }
                    TimelineView(.periodic(from: .now, by: 1)) { tick in Text(entry.focusTimeLabel(at: tick.date)).font(.title.monospacedDigit()).foregroundStyle(.secondary) }
                }
                Spacer()
            }.padding(30).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
