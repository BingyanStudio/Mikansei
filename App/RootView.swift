import SwiftUI

struct EditingSession: Identifiable {
    let id = UUID()
    let entry: Entry
    let isNew: Bool
}
private enum AppTab: Hashable { case tasks, today, notes }

private struct AgendaOccurrence: Identifiable {
    let entry: Entry
    let date: Date
    let isDeadline: Bool
    var id: String { entry.id.uuidString + (isDeadline ? ".deadline" : ".execution") }
}

struct RootView: View {
    @EnvironmentObject private var store: EntryStore
    @EnvironmentObject private var notifications: NotificationManager
    @EnvironmentObject private var calendarSync: CalendarSyncManager
    @EnvironmentObject private var deadlineActivity: DeadlineActivityManager
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("appearance") private var appearance = 0
    @State private var editing: EditingSession?
    @State private var settings = false
    @State private var messageImport = false
    @State private var tab = AppTab.tasks
    @AppStorage("schedulePage") private var todayPage = 0
    @State private var todayNavigationID = UUID()
    @State private var pendingRoute: AppRoute?
    var body: some View {
        TabView(selection: $tab) {
            NavigationStack { TasksView(edit: edit, add: add).toolbar { addToolbar } }
                .tabItem { Label("待办", systemImage: "checklist") }
                .tag(AppTab.tasks)
            NavigationStack { TodayView(edit: edit, add: add, addOnDate: addOnDate, page: $todayPage).toolbar { addToolbar } }
                .id(todayNavigationID)
                .tabItem { Label("日程", systemImage: "calendar") }
                .tag(AppTab.today)
            NavigationStack { NotesView(edit: edit, add: add).toolbar { addToolbar } }
                .tabItem { Label("笔记", systemImage: "note.text") }
                .tag(AppTab.notes)
        }
        .preferredColorScheme(appearance == 1 ? .light : appearance == 2 ? .dark : nil)
        .safeAreaInset(edge: .top, spacing: 0) {
            if store.readOnly {
                Text("本地数据读取失败，已暂停修改以保护原文件。")
                    .font(.caption).frame(maxWidth: .infinity).padding(10).background(.orange.opacity(0.18))
            } else if store.saveFailed {
                HStack {
                    Text("更改尚未写入手机")
                    Spacer()
                    Button("重试保存") { store.retrySave() }
                }.font(.caption).padding(10).background(.orange.opacity(0.18))
            } else if notifications.authorization == .denied && (store.entries.contains(where: { $0.reminder != nil && !$0.isCompleted && $0.reminderDelivery == .popup }) || store.courses.contains(where: { $0.reminderEnabled && $0.reminderDelivery == .popup })) {
                HStack {
                    Label("提醒未开启", systemImage: "bell.slash")
                    Spacer()
                    Button("去设置") { settings = true }
                }.font(.caption).padding(.horizontal, 20).padding(.vertical, 8).background(.orange.opacity(0.12))
            }
        }
        .overlay {
            if editing == nil && !settings && !messageImport, let reminder = notifications.foregroundReminders.first { ReminderPopup(reminder: reminder) }
        }
        .sheet(item: $editing, onDismiss: applyPendingRoute) { session in EntryEditor(entry: session.entry, isNew: session.isNew) }
        .sheet(isPresented: $settings, onDismiss: applyPendingRoute) { NavigationStack { SettingsView().toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { settings = false } } } } }
        .sheet(isPresented: $messageImport, onDismiss: applyPendingRoute) { MessageImportView() }
        .onOpenURL { url in
            guard let route = AppRoute(url: url) else { return }
            // Preserve an existing unsaved draft; the widget destination opens after its sheet closes.
            if editing != nil || settings || messageImport { pendingRoute = route }
            else { open(route) }
        }
        .alert("操作未完成", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("知道了", role: .cancel) { store.error = nil }
        } message: { Text(store.error ?? "") }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                store.refreshNotifications()
                deadlineActivity.refresh(entries: store.readOnly ? [] : store.entries)
                if editing == nil { Task { await calendarSync.sync(store: store, requestAccess: true) } }
            }
        }
        .task {
            if editing == nil { await calendarSync.sync(store: store, requestAccess: true) }
            deadlineActivity.refresh(entries: store.readOnly ? [] : store.entries)
        }
        .onChange(of: store.entries) { _, entries in
            deadlineActivity.refresh(entries: store.readOnly ? [] : entries)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            deadlineActivity.refresh(entries: store.readOnly ? [] : store.entries)
        }
        .onReceive(notifications.$openedEntryID) { id in
            if let id, let entry = store.entries.first(where: { $0.id == id }) {
                if editing != nil || settings || messageImport { pendingRoute = .entry(id) } else { edit(entry) }
            }
            if id != nil { notifications.openedEntryID = nil }
        }
        .onReceive(notifications.$openedCourseID) { id in
            if let id, let course = store.courses.first(where: { $0.id == id }) {
                editing = EditingSession(entry: course.homeworkDraft(), isNew: true)
            }
            if id != nil { notifications.openedCourseID = nil }
        }
        .onReceive(notifications.$completedEntryID) { id in
            if let id, let entry = store.entries.first(where: { $0.id == id }), !entry.isCompleted { store.toggleCompletion(id) }
            if id != nil { notifications.completedEntryID = nil }
        }
    }
    @ToolbarContentBuilder private var addToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) { Button("设置", systemImage: "gearshape") { settings = true } }
        ToolbarItem(placement: .topBarTrailing) {
            Button("从消息添加", systemImage: "text.badge.plus") { messageImport = true }.disabled(store.readOnly)
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button { add(tab == .today ? .schedule : .task) } label: {
                Image(systemName: "plus").font(.title3.weight(.medium)).frame(width: 36, height: 36)
            }.accessibilityLabel("新建事项").disabled(store.readOnly)
        }
    }
    private func edit(_ entry: Entry) { editing = EditingSession(entry: entry, isNew: false) }
    private func add(_ kind: EntryKind) { editing = EditingSession(entry: Entry(kind: kind), isNew: true) }
    private func addOnDate(_ date: Date, execution: Bool) {
        var entry = Entry(kind: execution ? .schedule : .task)
        if execution {
            entry.plannedStart = date
            entry.plannedEnd = date.addingTimeInterval(1800)
        } else {
            entry.dueDate = Calendar.current.date(bySettingHour: 23, minute: 59, second: 0, of: date)
        }
        editing = EditingSession(entry: entry, isNew: true)
    }
    private func applyPendingRoute() {
        let route = pendingRoute
        pendingRoute = nil
        // Wait until the outgoing sheet has released its presentation slot.
        Task { @MainActor in
            await Task.yield()
            if let route { open(route) }
            if editing == nil { await calendarSync.sync(store: store, requestAccess: true) }
        }
    }
    private func open(_ route: AppRoute) {
        switch route {
        case .today: tab = .today; todayPage = 0; todayNavigationID = UUID()
        case .tasks: tab = .tasks
        case .new(let kind): tab = kind == .note ? .notes : .tasks; add(kind)
        case .entry(let id):
            guard let entry = store.entries.first(where: { $0.id == id }) else { tab = .tasks; return }
            tab = entry.kind == .note ? .notes : .tasks
            edit(entry)
        case .focus(let id, let action):
            tab = .tasks
            store.setFocus(id, running: action == .start)
            if let entry = store.entries.first(where: { $0.id == id }) { edit(entry) }
        }
    }
}

struct TodayView: View {
    @EnvironmentObject private var store: EntryStore
    let edit: (Entry) -> Void
    let add: (EntryKind) -> Void
    let addOnDate: (Date, Bool) -> Void
    @Binding var page: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let board = TaskBoard(entries: store.entries, now: context.date)
            VStack(spacing: 0) {
                VStack(spacing: 12) {
                    if page != 2 { HStack {
                        Text(context.date, format: .dateTime.month(.wide).day().weekday(.wide))
                            .font(.subheadline).foregroundStyle(.secondary)
                        Spacer()
                        NavigationLink("课表与登记") { CoursesView() }.font(.subheadline)
                    } }
                    ChoiceStrip(label: "日程视图", choices: [0, 1, 2], selection: $page,
                        title: { $0 == 0 ? "今日聚焦" : $0 == 1 ? "列表" : "日历" }, identifier: { "schedule-view-\($0)" })
                }.padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 12)
                if page == 2 {
                    CalendarScheduleView(entries: store.entries, now: context.date, edit: edit, add: addOnDate)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            if page == 0 { focus(board, now: context.date) }
                            else { agenda(board, now: context.date) }
                        }.padding(.horizontal, 20).padding(.bottom, 16)
                            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: board.focus.map(\.id))
                    }
                }
            }.background(Theme.background).navigationTitle("日程")
                .navigationBarTitleDisplayMode(page == 2 ? .inline : .large)
        }
    }
    @ViewBuilder private func focus(_ board: TaskBoard, now: Date) -> some View {
        if !board.overdue.isEmpty { group("已超时", entries: board.overdue, color: .red, now: now) }
        if !board.today.isEmpty { group("今天要做", entries: board.today, color: Theme.accent, now: now) }
        if board.focus.isEmpty {
            EmptyCard(symbol: "sun.max", title: "今天可以从容一点", message: "给今天安排一件小事，或继续你的无日期清单。", actionTitle: "添加待办") { add(.task) }
        }
        if !board.unplannedOrPast.isEmpty { group("随时可做", entries: board.unplannedOrPast, now: now) }
        if !board.finishedToday.isEmpty { group("今日已完成", entries: board.finishedToday, color: Theme.accent, now: now) }
    }
    private func group(_ title: String, entries: [Entry], color: Color = .secondary, now: Date) -> some View {
        Group {
            SectionLabel(title: title, count: entries.count, color: color)
            ForEach(entries) { entry in
                EntryCard(entry: entry, edit: { edit(entry) }, now: now)
            }
        }
    }
    @ViewBuilder private func agenda(_ board: TaskBoard, now: Date) -> some View {
        let dated = board.open.flatMap { entry -> [AgendaOccurrence] in
            var result: [AgendaOccurrence] = []
            if let start = entry.plannedStart { result.append(AgendaOccurrence(entry: entry, date: start, isDeadline: false)) }
            if let due = entry.dueDate { result.append(AgendaOccurrence(entry: entry, date: due, isDeadline: true)) }
            return result
        }
        let groups = Dictionary(grouping: dated) { Calendar.current.startOfDay(for: $0.date) }
        if groups.isEmpty {
            EmptyCard(symbol: "calendar", title: "日程还是空白的", message: "已安排的时段和截止日期显示在这里；无日期事项始终留在待办清单。", actionTitle: "添加日程") { add(.schedule) }
        } else {
            ForEach(groups.keys.sorted(), id: \.self) { day in
                VStack(spacing: 10) {
                    HStack {
                        Text(day, format: .dateTime.month().day().weekday(.wide)).font(.headline)
                        if Calendar.current.isDate(day, inSameDayAs: now) { Text("今天").font(.caption).foregroundStyle(Theme.accent) }
                        Spacer()
                        Text("\(groups[day]!.count) 件").font(.caption).foregroundStyle(.secondary)
                    }.padding(.top, 8)
                    ForEach(groups[day]!.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }) { occurrence in
                        VStack(alignment: .leading, spacing: 6) {
                            Label(occurrence.isDeadline ? "截止 · \(Theme.dateLabel(occurrence.date))" : "执行 · \(Theme.dateLabel(occurrence.date))", systemImage: occurrence.isDeadline ? "flag" : "calendar")
                                .font(.caption.weight(.semibold)).foregroundStyle(occurrence.isDeadline ? Theme.warm : Theme.accent)
                            EntryCard(entry: occurrence.entry, edit: { edit(occurrence.entry) }, now: now)
                        }
                    }
                }
            }
        }
    }
}

private enum TaskFilter: String, CaseIterable, Identifiable {
    case all = "全部", tasks = "待办", schedules = "日程", homework = "作业", routine = "常态"
    var id: Self { self }
    func includes(_ entry: Entry) -> Bool {
        entry.isTask && (self == .all || (self == .tasks && entry.kind == .task) || (self == .homework && entry.kind == .homework) || (self == .schedules && entry.kind == .schedule) || (self == .routine && entry.isRoutine))
    }
}

/// One flat list with stable identities so a card keeps its view while it moves between groups.
private enum TaskRow: Identifiable {
    case section(String, Int, Color)
    case entry(Entry)
    var id: String {
        switch self {
        case .section(let title, _, _): return "section-\(title)"
        case .entry(let entry): return "entry-\(entry.id.uuidString)"
        }
    }
}

struct TasksView: View {
    @EnvironmentObject private var store: EntryStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let edit: (Entry) -> Void
    let add: (EntryKind) -> Void
    @State private var query = ""
    @State private var filter = TaskFilter.all
    @State private var showCompleted = false
    @State private var category = ""
    @State private var now = Date()
    private var categories: [String] { Array(Set(store.entries.filter(\.isTask).map(\.category).filter { !$0.isEmpty })).sorted() }
    private var filtered: [Entry] {
        let board = TaskBoard(entries: store.entries, now: now)
        return (showCompleted ? board.history : board.visible).filter {
            filter.includes($0) && $0.matches(query) && (category.isEmpty || $0.category == category)
        }
    }
    var body: some View {
        let visibleEntries = filtered
        let rows = taskRows(visibleEntries)
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                ChoiceStrip(label: "事项类型", choices: TaskFilter.allCases, selection: $filter, title: { $0.rawValue })
                HStack {
                    Picker("状态", selection: $showCompleted) { Text("当前清单").tag(false); Text("历史记录").tag(true) }
                        .pickerStyle(.menu).clearOptionText().fontWeight(.semibold)
                        .accessibilityIdentifier("task-status-filter")
                    Spacer()
                    Menu {
                        Button("全部分类") { category = "" }
                        ForEach(categories, id: \.self) { value in Button(value) { category = value } }
                    } label: { Label(category.isEmpty ? "分类" : category, systemImage: "line.3.horizontal.decrease").foregroundStyle(.primary) }
                }.font(.subheadline)
                SectionLabel(title: showCompleted ? "历史记录" : "我的清单", count: showCompleted ? visibleEntries.count : visibleEntries.filter { !$0.isCompleted }.count, color: Theme.accent)
                if visibleEntries.isEmpty {
                    EmptyCard(symbol: showCompleted ? "checkmark.seal" : "checklist", title: query.isEmpty ? "清单里还没有事项" : "没有找到相关事项",
                              message: showCompleted ? "今天完成的事项先留在清单末尾，次日归入这里。" : "先记下来即可。不必设置时间，也可以只填截止日期，再逐项勾选。",
                              actionTitle: showCompleted ? nil : "添加\(filter == .homework ? "作业" : filter == .schedules ? "日程" : "待办")",
                              action: { add(filter == .homework ? .homework : filter == .schedules ? .schedule : .task) })
                } else {
                    ForEach(rows) { row in
                        switch row {
                        case .section(let title, let count, let color): SectionLabel(title: title, count: count, color: color)
                        case .entry(let entry): EntryCard(entry: entry, edit: { edit(entry) }, now: now)
                        }
                    }
                }
            }.padding(20).padding(.bottom, 16)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: rows.map(\.id))
        }.background(Theme.background).navigationTitle("待办")
            .searchable(text: $query, prompt: "搜索事项、平台或地点")
            .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { now = $0 }
            .onAppear { now = Date() }
            .onChange(of: scenePhase) { _, phase in if phase == .active { now = Date() } }
    }
    private func taskRows(_ entries: [Entry]) -> [TaskRow] {
        guard !showCompleted else { return entries.map(TaskRow.entry) }
        let groups: [(String, [Entry], Color)] = [
            ("已超时", entries.filter { $0.isOverdue(at: now) }, .red),
            ("正在做", entries.filter { !$0.isCompleted && !$0.isOverdue(at: now) && $0.startedAt != nil }, Theme.accent),
            ("待完成", entries.filter { !$0.isCompleted && !$0.isOverdue(at: now) && $0.startedAt == nil }, .primary),
            ("今日已完成", entries.filter(\.isCompleted), Theme.accent)
        ]
        var rows: [TaskRow] = []
        for (title, group, color) in groups where !group.isEmpty {
            rows.append(.section(title, group.count, color))
            rows.append(contentsOf: group.map(TaskRow.entry))
        }
        return rows
    }
}

struct NotesView: View {
    @EnvironmentObject private var store: EntryStore
    let edit: (Entry) -> Void
    let add: (EntryKind) -> Void
    @State private var query = ""
    private var notes: [Entry] { store.entries.filter { $0.kind == .note && $0.matches(query) }.sorted { $0.updatedAt > $1.updatedAt } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("先记下来，再慢慢整理。").font(.subheadline).foregroundStyle(.secondary)
                if notes.isEmpty {
                    EmptyCard(symbol: "square.and.pencil", title: query.isEmpty ? "给想法留一个位置" : "没有找到相关笔记",
                              message: "随手记录灵感、课堂重点，或一份旅行清单。", actionTitle: "写一条笔记") { add(.note) }
                } else { ForEach(notes) { entry in EntryCard(entry: entry, edit: { edit(entry) }) } }
            }.padding(20).padding(.bottom, 16)
        }.background(Theme.background).navigationTitle("笔记").searchable(text: $query, prompt: "搜索笔记与清单")
    }
}
