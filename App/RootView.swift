import SwiftUI
import UIKit
import UniformTypeIdentifiers

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
    @EnvironmentObject private var pomodoro: PomodoroCoordinator
    @EnvironmentObject private var notifications: NotificationManager
    @EnvironmentObject private var calendarSync: CalendarSyncManager
    @EnvironmentObject private var deadlineActivity: DeadlineActivityManager
    @EnvironmentObject private var folderSync: FolderSyncManager
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("appearance") private var appearance = 0
    @State private var editing: EditingSession?
    @State private var noteEditing: EditingSession?
    @State private var settings = false
    @State private var showPomodoro = false
    @State private var pendingPomodoroPresentation = false
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
            if editing == nil && noteEditing == nil && !settings && !showPomodoro, let reminder = notifications.foregroundReminders.first { ReminderPopup(reminder: reminder) }
        }
        .sheet(item: $editing, onDismiss: applyPendingRoute) { session in EntryEditor(entry: session.entry, isNew: session.isNew) }
        // Notes edit on a full Apple-Notes style page instead of a sheet.
        .fullScreenCover(item: $noteEditing, onDismiss: applyPendingRoute) { session in
            NoteEditorView(entry: session.entry, isNew: session.isNew)
        }
        .sheet(isPresented: $settings, onDismiss: applyPendingRoute) { NavigationStack { SettingsView().toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { settings = false } } } } }
        .sheet(isPresented: $showPomodoro, onDismiss: applyPendingRoute) {
            NavigationStack { PomodoroFocusView() }
                .presentationDetents([.large])
        }
        .onOpenURL { url in
            if url.scheme?.lowercased() == "mikansei", url.host?.lowercased() == "pomodoro" {
                if let action = PomodoroURLAction(url: url) { _ = pomodoro.apply(action) }
                else { pomodoro.error = "无法识别这个专注计时链接。" }
                if settings { settings = false }
                pendingPomodoroPresentation = true
                presentPomodoroIfSafe()
                return
            }
            guard let route = AppRoute(url: url) else { return }
            // Preserve an existing unsaved draft; the widget destination opens after its sheet closes.
            if editing != nil || noteEditing != nil || settings { pendingRoute = route }
            else { open(route) }
        }
        .alert("操作未完成", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("知道了", role: .cancel) { store.error = nil }
        } message: { Text(store.error ?? "") }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                store.refreshNotifications()
                if store.syncReady { store.retrySave() }
                pomodoro.refresh()
                deadlineActivity.refresh(entries: store.readOnly ? [] : store.entries)
                if editing == nil && noteEditing == nil { Task { await calendarSync.sync(store: store, requestAccess: true) } }
            }
        }
        .task {
            if editing == nil && noteEditing == nil { await calendarSync.sync(store: store, requestAccess: true) }
            deadlineActivity.refresh(entries: store.readOnly ? [] : store.entries)
            if store.syncReady { store.retrySave() }
        }
        .onChange(of: store.hasUnsavedChanges) { _, pending in
            if !pending { folderSync.request(store) }
        }
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { _ in
            if scenePhase == .active { folderSync.request(store) }
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { tick in
            if scenePhase == .active, pomodoro.active?.mode == .countdown { pomodoro.refresh(at: tick) }
        }
        .onChange(of: store.entries) { _, entries in
            deadlineActivity.refresh(entries: store.readOnly ? [] : entries)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            deadlineActivity.refresh(entries: store.readOnly ? [] : store.entries)
        }
        .onReceive(notifications.$openedEntryID) { id in
            if let id, let entry = store.entries.first(where: { $0.id == id }) {
                if editing != nil || noteEditing != nil || settings { pendingRoute = .entry(id) } else { edit(entry) }
            }
            if id != nil { notifications.openedEntryID = nil }
        }
        .onReceive(notifications.$openedRoute) { route in
            if let route {
                if editing != nil || noteEditing != nil || settings { pendingRoute = route } else { open(route) }
            }
            if route != nil { notifications.openedRoute = nil }
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
        ToolbarItem(placement: .topBarLeading) { Button("专注", systemImage: "timer") { queuePomodoroPresentation() } }
        ToolbarItem(placement: .topBarTrailing) {
            Button { add(tab == .today ? .schedule : tab == .notes ? .note : .task) } label: {
                Image(systemName: "plus").font(.title3.weight(.medium)).frame(width: 36, height: 36)
            }.accessibilityLabel("新建事项").disabled(store.readOnly)
        }
    }
    private func edit(_ entry: Entry) {
        if entry.kind == .note { noteEditing = EditingSession(entry: entry, isNew: false) }
        else { editing = EditingSession(entry: entry, isNew: false) }
    }
    private func add(_ kind: EntryKind) {
        if kind == .note { noteEditing = EditingSession(entry: Entry(kind: kind), isNew: true) }
        else { editing = EditingSession(entry: Entry(kind: kind), isNew: true) }
    }
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
            presentPomodoroIfSafe()
            if editing == nil { await calendarSync.sync(store: store, requestAccess: true) }
        }
    }
    private func queuePomodoroPresentation() {
        pendingPomodoroPresentation = true
        presentPomodoroIfSafe()
    }
    private func presentPomodoroIfSafe() {
        guard pendingPomodoroPresentation, !showPomodoro,
              editing == nil, noteEditing == nil, !settings else { return }
        Task { @MainActor in
            await Task.yield()
            guard pendingPomodoroPresentation, !showPomodoro,
                  editing == nil, noteEditing == nil, !settings else { return }
            pendingPomodoroPresentation = false
            showPomodoro = true
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
    @State private var showPlanning = false
    @State private var pendingPlanningEdit: Entry?
    @StateObject private var dragReorder = EntryDragReorderState()
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let board = TaskBoard(entries: store.entries, now: context.date)
            VStack(spacing: 0) {
                VStack(spacing: 12) {
                    if page != 2 { HStack(spacing: 14) {
                        Text(context.date, format: .dateTime.month(.wide).day().weekday(.wide))
                            .font(.subheadline).foregroundStyle(.secondary)
                        Spacer()
                        Button { showPlanning = true } label: { Label("规划", systemImage: "calendar.badge.clock") }
                            .font(.subheadline).accessibilityIdentifier("planning-open")
                        NavigationLink("课表与登记") { CoursesView() }.font(.subheadline)
                    } }
                    ChoiceStrip(label: "日程视图", choices: [0, 1, 2], selection: $page,
                        title: { $0 == 0 ? "今日聚焦" : $0 == 1 ? "列表" : "日历" }, identifier: { "schedule-view-\($0)" })
                }.padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 12)
                if page == 2 {
                    CalendarScheduleView(entries: store.entries, now: context.date, edit: edit, add: addOnDate)
                } else if page == 1 {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            agenda(board, now: context.date)
                        }.padding(.horizontal, 20).padding(.bottom, 16)
                            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: board.open.map(\.id))
                    }
                } else {
                    focusList(board, now: context.date)
                }
            }.background(Theme.background).navigationTitle("日程")
                .navigationBarTitleDisplayMode(.inline)
                .sheet(isPresented: $showPlanning, onDismiss: presentPendingPlanningEdit) {
                    PlanningView(entries: store.entries, now: context.date, edit: { entry in
                                     pendingPlanningEdit = entry
                                     showPlanning = false
                                 },
                                 setPlannedDays: { store.setPlannedDays($0, $1) },
                                 setPlannedTime: { store.setPlannedTime($0, start: $1, end: $2) },
                                 restoreFromPlanning: { _ = store.restoreFromPlanning($0) },
                                 canEdit: !store.readOnly)
                }
        }
        .onDisappear { dragReorder.cancelActiveSession(reduceMotion: reduceMotion) }
    }
    /// 今日聚焦：分组滚动列表；长按整张卡片可在同组内排序。
    private func focusList(_ board: TaskBoard, now: Date) -> some View {
        let focus = board.focus
        let overdueIDs = Set(board.overdue.map(\.id))
        let todayIDs = Set(board.focusToday.map(\.id))
        let finishedIDs = Set(board.finishedToday.map(\.id))
        let groups: [(title: String, entries: [Entry], color: Color, movable: Bool)] = [
            ("已超时", focus.filter { overdueIDs.contains($0.id) }, .red, true),
            ("今天要做", focus.filter { todayIDs.contains($0.id) && !overdueIDs.contains($0.id) }, Theme.accent, true),
            ("随时可做", focus.filter { !overdueIDs.contains($0.id) && !todayIDs.contains($0.id) && !$0.isCompleted }, .secondary, true),
            ("今日已完成", focus.filter { finishedIDs.contains($0.id) }, Theme.accent, false)
        ]
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if focus.isEmpty {
                    EmptyCard(symbol: "sun.max", title: "今天可以从容一点", message: "给今天安排一件小事，或继续你的无日期清单。", actionTitle: "添加待办") { add(.task) }
                        .padding(.horizontal, 20).padding(.vertical, 8)
                } else {
                    ForEach(groups.filter { !$0.entries.isEmpty }, id: \.title) { group in
                        SectionLabel(title: group.title, count: group.entries.count, color: group.color)
                            .padding(.horizontal, 20)
                        let groupID = "focus:\(group.title)"
                        ForEach(dragReorder.displayedEntries(group.entries, groupID: groupID)) { entry in
                            EntryDragRow(entry: entry, group: group.entries, groupID: groupID, reorderState: dragReorder,
                                         movable: group.movable && !store.readOnly,
                                         onDrop: reorderWithin,
                                         onReorderCommit: commitReorder,
                                         onMoveToPlanning: !store.readOnly && group.movable && !entry.isCompleted
                                            ? { _ = store.moveToPlanning(entry.id) } : nil,
                                         reduceMotion: reduceMotion,
                                         content: { EntryCard(entry: entry, edit: { edit(entry) }, now: now, showsContextMenu: false) })
                                .padding(.horizontal, 20).padding(.vertical, 8)
                        }
                    }
                }
            }.padding(.top, 4).padding(.bottom, 16)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: board.focus.map(\.id))
        }
    }
    /// 拖拽落点：把拖拽卡移到目标卡的位置（限同一分组），按组内新顺序写 sortOrder。
    private func reorderWithin(_ dragged: Entry, _ target: Entry, _ group: [Entry], after: Bool) -> Bool {
        guard dragged.id != target.id,
              let from = group.firstIndex(where: { $0.id == dragged.id }),
              group.contains(where: { $0.id == target.id }) else { return false }
        var ids = group.map(\.id)
        let id = ids.remove(at: from)
        guard let targetIndex = ids.firstIndex(of: target.id) else { return false }
        ids.insert(id, at: targetIndex + (after ? 1 : 0))
        return store.reorder(ids)
    }
    private func commitReorder(_ ids: [UUID]) -> Bool {
        if reduceMotion { return store.reorder(ids) }
        return withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) { store.reorder(ids) }
    }
    private func presentPendingPlanningEdit() {
        guard let entry = pendingPlanningEdit else { return }
        pendingPlanningEdit = nil
        DispatchQueue.main.async { edit(entry) }
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
        entry.isTask && (self == .all || (self == .tasks && entry.kind == .task) || (self == .homework && entry.kind == .homework) || (self == .schedules && entry.kind == .schedule) || (self == .routine && entry.isRoutineSeriesMember))
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
    @StateObject private var dragReorder = EntryDragReorderState()
    private var categories: [String] { Array(Set(store.entries.filter(\.isTask).map(\.category).filter { !$0.isEmpty })).sorted() }
    private var filtered: [Entry] {
        let board = TaskBoard(entries: store.entries, now: now)
        return (showCompleted ? board.history : board.visible).filter {
            filter.includes($0) && $0.matches(query) && (category.isEmpty || $0.category == category)
        }
    }
    /// 分组只作用于当前清单；历史记录是平铺列表，不参与排序。
    private var groups: [(title: String, entries: [Entry], color: Color, movable: Bool)] {
        [
            ("已超时", filtered.filter { $0.isOverdue(at: now) }, .red, true),
            ("正在做", filtered.filter { !$0.isCompleted && !$0.isOverdue(at: now) && $0.startedAt != nil }, Theme.accent, true),
            ("待完成", filtered.filter { !$0.isCompleted && !$0.isOverdue(at: now) && $0.startedAt == nil }, .primary, true),
            ("今日已完成", filtered.filter(\.isCompleted), Theme.accent, false)
        ]
    }
    var body: some View {
        let visibleEntries = filtered
        // Fixed header like the 日程 tab: pull-down moves only the list, so the
        // two screens animate consistently.
        return VStack(spacing: 0) {
            VStack(spacing: 12) {
                ChoiceStrip(label: "事项类型", choices: TaskFilter.allCases, selection: $filter, title: { $0.rawValue })
                HStack(spacing: 14) {
                    Picker("状态", selection: $showCompleted) { Text("当前清单").tag(false); Text("历史记录").tag(true) }
                        .pickerStyle(.menu).clearOptionText().fontWeight(.semibold)
                        .accessibilityIdentifier("task-status-filter")
                    Spacer()
                    Menu {
                        Button("全部分类") { category = "" }
                        ForEach(categories, id: \.self) { value in Button(value) { category = value } }
                    } label: { Label(category.isEmpty ? "分类" : category, systemImage: "line.3.horizontal.decrease").foregroundStyle(.primary) }
                }.font(.subheadline)
            }.padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 12)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    listBody(visibleEntries)
                }.padding(.top, 4).padding(.bottom, 16)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: visibleEntries.map(\.id))
            }
        }.background(Theme.background).navigationTitle("待办")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "搜索事项、平台或地点")
            .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { now = $0 }
            .onAppear { now = Date() }
            .onChange(of: scenePhase) { _, phase in if phase == .active { now = Date() } }
            .onDisappear { dragReorder.cancelActiveSession(reduceMotion: reduceMotion) }
    }
    @ViewBuilder private func listBody(_ visibleEntries: [Entry]) -> some View {
        if visibleEntries.isEmpty {
            EmptyCard(symbol: showCompleted ? "checkmark.seal" : "checklist", title: query.isEmpty ? "清单里还没有事项" : "没有找到相关事项",
                      message: showCompleted ? "今天完成的事项先留在清单末尾，次日归入这里。" : "先记下来即可。不必设置时间，也可以只填截止日期，再逐项勾选。",
                      actionTitle: showCompleted ? nil : "添加\(filter == .homework ? "作业" : filter == .schedules ? "日程" : "待办")",
                      action: { add(filter == .homework ? .homework : filter == .schedules ? .schedule : .task) })
                .padding(.horizontal, 20).padding(.vertical, 8)
        } else if showCompleted {
            SectionLabel(title: "历史记录", count: visibleEntries.count, color: Theme.accent).padding(.horizontal, 20)
            ForEach(visibleEntries) { entry in
                EntryDragRow(entry: entry, group: [], groupID: "history", reorderState: dragReorder,
                             movable: false, onDrop: reorderWithin, onReorderCommit: commitReorder,
                             content: { EntryCard(entry: entry, edit: { edit(entry) }, now: now) })
                    .padding(.horizontal, 20).padding(.vertical, 8)
            }
        } else {
            ForEach(groups.filter { !$0.entries.isEmpty }, id: \.title) { group in
                SectionLabel(title: group.title, count: group.entries.count, color: group.color).padding(.horizontal, 20)
                let groupID = "tasks:\(group.title)"
                ForEach(dragReorder.displayedEntries(group.entries, groupID: groupID)) { entry in
                    EntryDragRow(entry: entry, group: group.entries, groupID: groupID, reorderState: dragReorder,
                                 movable: group.movable && !store.readOnly,
                                 onDrop: reorderWithin,
                                 onReorderCommit: commitReorder,
                                 content: { EntryCard(entry: entry, edit: { edit(entry) }, now: now, showsContextMenu: false) })
                        .padding(.horizontal, 20).padding(.vertical, 8)
                }
            }
        }
    }
    /// 拖拽落点：把拖拽卡移到目标卡的位置（限同一分组），按组内新顺序写 sortOrder。
    private func reorderWithin(_ dragged: Entry, _ target: Entry, _ group: [Entry], after: Bool) -> Bool {
        guard dragged.id != target.id,
              let from = group.firstIndex(where: { $0.id == dragged.id }),
              group.contains(where: { $0.id == target.id }) else { return false }
        var ids = group.map(\.id)
        let id = ids.remove(at: from)
        guard let targetIndex = ids.firstIndex(of: target.id) else { return false }
        ids.insert(id, at: targetIndex + (after ? 1 : 0))
        return store.reorder(ids)
    }

    private func commitReorder(_ ids: [UUID]) -> Bool {
        if reduceMotion { return store.reorder(ids) }
        return withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) { store.reorder(ids) }
    }
}

/// 整卡拖动排序行：同组拖动时，源卡变成插入占位，其他卡片随位置变化让位。
struct EntryDragRow<Content: View>: View {
    @EnvironmentObject private var store: EntryStore
    let entry: Entry
    let group: [Entry]
    let groupID: String
    @ObservedObject var reorderState: EntryDragReorderState
    let movable: Bool
    /// 返回是否完成了移动，作为 drop 接收结果。
    let onDrop: (Entry, Entry, [Entry], Bool) -> Bool
    let onReorderCommit: ([UUID]) -> Bool
    var onMoveToPlanning: (() -> Void)? = nil
    var reduceMotion = false
    @ViewBuilder var content: () -> Content
    @State private var rowHeight: CGFloat = 0
    @State private var dragSessionActive = false
    @State private var hostedContentSize: CGSize?
    private var canDrag: Bool { movable && !store.readOnly }
    private var isInsertionPlaceholder: Bool { reorderState.isPlaceholder(entryID: entry.id, groupID: groupID) }

    @ViewBuilder private var rowContent: some View {
        let card = content()
        let draggableCard = EntryCardDragSource(entry: entry, isEnabled: canDrag, isDragging: $dragSessionActive,
                                                isPlaceholder: isInsertionPlaceholder,
                                                onSessionChange: { active in
                                                    if active {
                                                        reorderState.begin(entryID: entry.id, groupID: groupID, ids: group.map(\.id))
                                                    } else {
                                                        DispatchQueue.main.async {
                                                            reorderState.endSession(entryID: entry.id, groupID: groupID, reduceMotion: reduceMotion)
                                                        }
                                                    }
                                                },
                                                measuredContentSize: $hostedContentSize) {
            card.frame(maxWidth: .infinity)
        }
        Group {
            if let onMoveToPlanning {
                FocusSwipeRow(action: onMoveToPlanning, reduceMotion: reduceMotion, dragSessionActive: $dragSessionActive) {
                    if canDrag { draggableCard } else { card.frame(maxWidth: .infinity) }
                }.frame(maxWidth: .infinity)
            } else if canDrag {
                draggableCard
            } else {
                card.frame(maxWidth: .infinity)
            }
        }
        .background {
            GeometryReader { geometry in
                Color.clear
                    .onAppear { rowHeight = geometry.size.height }
                    .onChange(of: geometry.size.height) { _, height in rowHeight = height }
            }
        }
        .contentShape(Rectangle())
    }

    var body: some View {
        Group {
            if canDrag {
                rowContent
                    .accessibilityElement(children: .contain)
                    .accessibilityHint("长按整张卡片拖动排序，也可以使用上移或下移操作。")
                    .accessibilityAction(named: Text("上移")) { moveForAccessibility(by: -1) }
                    .accessibilityAction(named: Text("下移")) { moveForAccessibility(by: 1) }
                    .onDrop(of: [UTType.data], delegate: EntryRowReorderDropDelegate(
                        entryID: entry.id,
                        groupID: groupID,
                        rowHeight: max(rowHeight, hostedContentSize?.height ?? 0),
                        canDrop: !store.readOnly,
                        reduceMotion: reduceMotion,
                        state: reorderState,
                        currentGroupIDs: group.map(\.id),
                        onCommit: onReorderCommit
                    ))
            } else {
                rowContent
            }
        }
        .onChange(of: group.map(\.id)) { _, ids in
            reorderState.cancelIfGroupChanged(groupID: groupID, currentIDs: ids, reduceMotion: reduceMotion)
        }
    }

    private func moveForAccessibility(by offset: Int) {
        guard canDrag, let index = group.firstIndex(where: { $0.id == entry.id }) else { return }
        let targetIndex = index + offset
        guard group.indices.contains(targetIndex) else { return }
        let after = offset > 0
        if onDrop(entry, group[targetIndex], group, after) {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
    }
}

@MainActor
final class EntryDragReorderState: ObservableObject {
    @Published private(set) var activeEntryID: UUID?
    @Published private(set) var activeGroupID: String?
    @Published private(set) var previewOrder: [UUID] = []
    private var originalOrder: [UUID] = []
    private var dropCommitted = false

    func displayedEntries(_ entries: [Entry], groupID: String) -> [Entry] {
        let currentIDs = entries.map(\.id)
        guard activeGroupID == groupID, originalOrder == currentIDs,
              previewOrder.count == currentIDs.count, Set(previewOrder) == Set(currentIDs) else { return entries }
        let entriesByID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
        let displayed = previewOrder.compactMap { entriesByID[$0] }
        return displayed.count == entries.count ? displayed : entries
    }

    func isActive(in groupID: String) -> Bool { activeEntryID != nil && activeGroupID == groupID }

    func isPlaceholder(entryID: UUID, groupID: String) -> Bool {
        activeEntryID == entryID && activeGroupID == groupID
    }

    func begin(entryID: UUID, groupID: String, ids: [UUID]) {
        guard activeEntryID == nil, ids.contains(entryID) else { return }
        activeEntryID = entryID
        activeGroupID = groupID
        originalOrder = ids
        previewOrder = ids
        dropCommitted = false
    }

    func movePlaceholder(to targetID: UUID, after: Bool, in groupID: String, reduceMotion: Bool) {
        guard activeGroupID == groupID, let sourceID = activeEntryID,
              sourceID != targetID, let sourceIndex = previewOrder.firstIndex(of: sourceID) else { return }
        var next = previewOrder
        next.remove(at: sourceIndex)
        guard let targetIndex = next.firstIndex(of: targetID) else { return }
        next.insert(sourceID, at: targetIndex + (after ? 1 : 0))
        guard next != previewOrder else { return }
        if reduceMotion { previewOrder = next }
        else { withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) { previewOrder = next } }
    }

    func proposedOrder(in groupID: String) -> [UUID]? {
        guard isActive(in: groupID), previewOrder.count == originalOrder.count,
              Set(previewOrder) == Set(originalOrder) else { return nil }
        return previewOrder
    }

    func matchesCurrentGroup(groupID: String, currentIDs: [UUID]) -> Bool {
        isActive(in: groupID) && originalOrder == currentIDs &&
            previewOrder.count == currentIDs.count && Set(previewOrder) == Set(currentIDs)
    }

    func cancelIfGroupChanged(groupID: String, currentIDs: [UUID], reduceMotion: Bool) {
        guard let entryID = activeEntryID, activeGroupID == groupID,
              !matchesCurrentGroup(groupID: groupID, currentIDs: currentIDs) else { return }
        endSession(entryID: entryID, groupID: groupID, reduceMotion: reduceMotion)
    }

    func markDropCommitted(in groupID: String) {
        guard isActive(in: groupID) else { return }
        dropCommitted = true
    }

    func endSession(entryID: UUID, groupID: String, reduceMotion: Bool) {
        guard activeEntryID == entryID, activeGroupID == groupID else { return }
        let shouldRestore = !dropCommitted
        let clear = {
            if shouldRestore { self.previewOrder = self.originalOrder }
            self.activeEntryID = nil
            self.activeGroupID = nil
            self.previewOrder = []
            self.originalOrder = []
            self.dropCommitted = false
        }
        if reduceMotion { clear() } else { withAnimation { clear() } }
    }

    func cancelActiveSession(reduceMotion: Bool) {
        guard let entryID = activeEntryID, let groupID = activeGroupID else { return }
        endSession(entryID: entryID, groupID: groupID, reduceMotion: reduceMotion)
    }
}

private struct EntryRowReorderDropDelegate: DropDelegate {
    let entryID: UUID
    let groupID: String
    let rowHeight: CGFloat
    let canDrop: Bool
    let reduceMotion: Bool
    let state: EntryDragReorderState
    let currentGroupIDs: [UUID]
    let onCommit: ([UUID]) -> Bool

    func validateDrop(info: DropInfo) -> Bool {
        guard canDrop else { return false }
        guard state.matchesCurrentGroup(groupID: groupID, currentIDs: currentGroupIDs) else {
            state.cancelIfGroupChanged(groupID: groupID, currentIDs: currentGroupIDs, reduceMotion: reduceMotion)
            return false
        }
        return true
    }

    func dropEntered(info: DropInfo) {
        guard validateDrop(info: info) else { return }
        updatePreview(at: info.location)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard validateDrop(info: info) else { return DropProposal(operation: .forbidden) }
        updatePreview(at: info.location)
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard validateDrop(info: info) else { return false }
        updatePreview(at: info.location)
        guard let finalOrder = state.proposedOrder(in: groupID),
              Set(finalOrder) == Set(currentGroupIDs), finalOrder.count == currentGroupIDs.count else {
            state.cancelIfGroupChanged(groupID: groupID, currentIDs: currentGroupIDs, reduceMotion: reduceMotion)
            return false
        }
        let committed = onCommit(finalOrder)
        if committed { state.markDropCommitted(in: groupID) }
        return committed
    }

    private func updatePreview(at location: CGPoint) {
        guard canDrop else { return }
        state.movePlaceholder(to: entryID, after: location.y >= rowHeight / 2, in: groupID, reduceMotion: reduceMotion)
    }
}

/// A horizontal action layer that resets and yields while a native card drag is active.
private struct FocusSwipeRow<Content: View>: View {
    private enum Direction { case horizontal, vertical }
    private let actionWidth: CGFloat = 132
    private let fullSwipeDistance: CGFloat = 220
    let action: () -> Void
    let reduceMotion: Bool
    @Binding var dragSessionActive: Bool
    @ViewBuilder let content: () -> Content
    @State private var offset: CGFloat = 0
    @State private var dragStartOffset: CGFloat = 0
    @State private var direction: Direction?

    var body: some View {
        ZStack(alignment: .trailing) {
            Button(action: performAction) {
                Label("移到规划", systemImage: "calendar.badge.clock")
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(Theme.accent.opacity(0.18), in: RoundedRectangle(cornerRadius: 18))
            }
            .buttonStyle(.plain)
            .frame(width: actionWidth)
            .opacity(offset < -8 ? 1 : 0)
            .accessibilityHidden(offset == 0)

            content()
                .offset(x: offset)
                .contentShape(Rectangle())
                .simultaneousGesture(
                    DragGesture(minimumDistance: 14)
                        .onChanged { value in
                            guard !dragSessionActive else { return }
                            let dx = value.translation.width
                            let dy = value.translation.height
                            if direction == nil {
                                direction = abs(dx) > abs(dy) ? .horizontal : .vertical
                                dragStartOffset = offset
                            }
                            guard direction == .horizontal else { return }
                            offset = min(0, max(-actionWidth, dragStartOffset + dx))
                        }
                        .onEnded { value in
                            guard !dragSessionActive else {
                                offset = 0
                                dragStartOffset = 0
                                direction = nil
                                return
                            }
                            let endedDirection = direction
                            direction = nil
                            guard endedDirection == .horizontal else { return }
                            if dragStartOffset + value.translation.width <= -fullSwipeDistance {
                                performAction()
                            } else {
                                setOffset(offset <= -actionWidth / 2 ? -actionWidth : 0)
                            }
                        }
                )
        }
        .clipped()
        .onChange(of: dragSessionActive) { _, active in
            guard active else { return }
            offset = 0
            dragStartOffset = 0
            direction = nil
        }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: Text("移到规划")) { performAction() }
    }

    private func performAction() {
        guard !dragSessionActive else { return }
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
        setOffset(0)
        action()
    }

    private func setOffset(_ value: CGFloat) {
        if reduceMotion { offset = value }
        else { withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) { offset = value } }
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
        }.background(Theme.background).navigationTitle("笔记").navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "搜索笔记与清单")
    }
}

