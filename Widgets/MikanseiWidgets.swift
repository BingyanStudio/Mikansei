import SwiftUI
import WidgetKit

private let widgetAccent = Color(uiColor: UIColor { traits in
    traits.userInterfaceStyle == .dark
        ? UIColor(red: 0.48, green: 0.85, blue: 0.70, alpha: 1)
        : UIColor(red: 0.12, green: 0.39, blue: 0.30, alpha: 1)
})

struct ChecklistTimelineEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    var board: TaskBoard { snapshot?.board(at: date) ?? TaskBoard(entries: [], now: date) }
}
private func widgetExampleTasks(at now: Date) -> [Entry] {
    var homework = Entry(title: "完成今天的作业", kind: .homework, priority: .important, dueDate: now.addingTimeInterval(3600))
    homework.startedAt = now.addingTimeInterval(-600)
    return [homework, Entry(title: "给家里打电话"), Entry(title: "洗衣服")]
}

struct ChecklistProvider: TimelineProvider {
    func placeholder(in context: Context) -> ChecklistTimelineEntry {
        let now = Date()
        return ChecklistTimelineEntry(date: now, snapshot: WidgetSnapshot(entries: widgetExampleTasks(at: now), now: now))
    }
    func getSnapshot(in context: Context, completion: @escaping (ChecklistTimelineEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : ChecklistTimelineEntry(date: Date(), snapshot: try? WidgetSnapshotStore.load()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<ChecklistTimelineEntry>) -> Void) {
        let now = Date()
        let snapshot = try? WidgetSnapshotStore.load()
        // Precomputed entries let completed tasks leave the widget at midnight without launching the app.
        // Due-time transitions are also included; WidgetKit controls the actual refresh budget.
        let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now))!
        var dates = [now, nextDay]
        dates += snapshot?.tasks.compactMap { task in
            guard !task.isCompleted, let due = task.dueDate, due >= now, due < nextDay else { return nil }
            return due.addingTimeInterval(1)
        } ?? []
        let entries = Set(dates).sorted().map { ChecklistTimelineEntry(date: $0, snapshot: snapshot) }
        completion(Timeline(entries: entries, policy: .after(nextDay.addingTimeInterval(60))))
    }
}

struct TodayChecklistWidget: Widget {
    let kind = "Mikansei.TodayChecklist"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ChecklistProvider()) { entry in
            TodayChecklistWidgetView(entry: entry)
                .containerBackground(Color(uiColor: .systemBackground), for: .widget)
                .widgetURL(AppRoute.today.url)
        }
        .configurationDisplayName("今日清单")
        .description("查看已超时、今天截止和随时可做的事项，点入查看或添加。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct TodayChecklistWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ChecklistTimelineEntry
    private var limit: Int { family == .systemLarge ? 7 : family == .systemMedium ? 3 : 2 }
    var body: some View {
        VStack(alignment: .leading, spacing: family == .systemMedium ? 4 : 8) {
            HStack {
                Link(destination: AppRoute.today.url) {
                    Label("今日清单", systemImage: "checklist").font(.headline).foregroundStyle(widgetAccent)
                }
                Spacer(minLength: 2)
                Link(destination: AppRoute.new(.task).url) {
                    Image(systemName: "plus.circle.fill").font(.title3).foregroundStyle(widgetAccent)
                }.accessibilityLabel("添加待办")
            }
            if entry.snapshot == nil {
                Text("打开 App 同步清单").font(.subheadline).foregroundStyle(.primary)
                Text("首次使用或重启后，请先解锁并打开 Mikansei。")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            } else {
                let tasks = entry.board.focus
                HStack(spacing: 8) {
                    Text("\(tasks.filter { !$0.isCompleted }.count) 件待办").foregroundStyle(.primary)
                    if entry.board.completedToday > 0 { Text("完成 \(entry.board.completedToday)").foregroundStyle(widgetAccent) }
                    if let saved = entry.snapshot?.savedAt, family == .systemMedium {
                        Spacer(minLength: 0)
                        Text("同步 \(saved.formatted(date: .omitted, time: .shortened))")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }.font(.caption.weight(.medium))
                if tasks.isEmpty {
                    Text("今天暂无待办").font(.subheadline.weight(.medium))
                    Text("点 + 记下一件事").font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(tasks.prefix(limit)) { task in
                        Link(destination: AppRoute.entry(task.id).url) { taskRow(task) }
                    }
                }
                Spacer(minLength: 0)
                if family == .systemLarge {
                    HStack {
                        if tasks.count > limit { Text("还有 \(tasks.count - limit) 件 · 点入查看") }
                        Spacer(minLength: 0)
                        if let saved = entry.snapshot?.savedAt { Text("同步 \(saved.formatted(date: .omitted, time: .shortened))") }
                    }.font(.caption2).foregroundStyle(.secondary)
                }
            }
        }.privacySensitive()
    }
    private func taskRow(_ task: Entry) -> some View {
        HStack(spacing: 7) {
            Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(task.isCompleted ? widgetAccent : .primary)
            Text(task.title).strikethrough(task.isCompleted).lineLimit(1)
                .foregroundStyle(task.isCompleted ? .secondary : .primary)
            if family != .systemSmall {
                Spacer(minLength: 3)
                if task.isOverdue(at: entry.date) { Text("超时").foregroundStyle(.red).font(.caption2.bold()) }
                else if task.priority == .urgent && !task.isCompleted { Text("紧急").foregroundStyle(.red).font(.caption2.bold()) }
                else if let due = task.attentionDate, !task.isCompleted { Text(due, style: .time).font(.caption2).foregroundStyle(.secondary) }
            }
        }.font(.subheadline).frame(minHeight: 22)
    }
}

struct QuickAddWidget: Widget {
    let kind = "Mikansei.QuickAdd"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ChecklistProvider()) { _ in
            QuickAddWidgetView().containerBackground(Color(uiColor: .systemBackground), for: .widget)
                .widgetURL(AppRoute.new(.task).url)
        }
        .configurationDisplayName("快速添加")
        .description("一键打开待办、作业或笔记录入，写一句话就能保存。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
struct QuickAddWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("随手记一件事").font(.headline).foregroundStyle(.primary)
            if family == .systemSmall {
                ForEach(EntryKind.allCases) { kind in button(kind) }
            } else {
                HStack(spacing: 10) { ForEach(EntryKind.allCases) { kind in button(kind).frame(maxWidth: .infinity) } }
                Text("先记下来，细节稍后补。") .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private func button(_ kind: EntryKind) -> some View {
        Link(destination: AppRoute.new(kind).url) {
            Label("添加\(kind.title)", systemImage: kind.symbol)
                .font(.subheadline.weight(.semibold)).foregroundStyle(widgetAccent)
                .frame(maxWidth: .infinity, minHeight: family == .systemSmall ? 24 : 48, alignment: .leading)
                .padding(.horizontal, 8).background(widgetAccent.opacity(0.10), in: RoundedRectangle(cornerRadius: 9))
        }
    }
}

struct TodayProgressWidget: Widget {
    let kind = "Mikansei.TodayProgress"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ChecklistProvider()) { entry in
            TodayProgressWidgetView(entry: entry)
                .containerBackground(Color(uiColor: .systemBackground), for: .widget)
                .widgetURL(AppRoute.today.url)
        }
        .configurationDisplayName("今日进度")
        .description("查看完成进度与下一件事，也可添加到锁屏。")
        .supportedFamilies([.systemSmall, .accessoryInline, .accessoryCircular, .accessoryRectangular])
    }
}
struct TodayProgressWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ChecklistTimelineEntry
    private var remaining: [Entry] { entry.board.focus.filter { !$0.isCompleted } }
    private var completed: Int { entry.board.completedToday }
    private var progress: Double {
        let total = remaining.count + completed
        return total == 0 ? 0 : Double(completed) / Double(total)
    }
    var body: some View {
        Group {
            if entry.snapshot == nil {
                Label("打开 App 同步", systemImage: "checklist").font(.caption)
            } else {
                switch family {
                case .accessoryInline:
                    Text("待办 \(remaining.count) · 完成 \(completed)")
                case .accessoryCircular:
                    Gauge(value: progress) { Image(systemName: "checklist") } currentValueLabel: { Text("\(remaining.count)") }
                        .gaugeStyle(.accessoryCircularCapacity)
                case .accessoryRectangular:
                    VStack(alignment: .leading) {
                        Text("待办 \(remaining.count) · 完成 \(completed)").font(.headline)
                        Text(remaining.first?.title ?? "今日事项已完成").font(.caption).lineLimit(2)
                    }
                default:
                    VStack(alignment: .leading, spacing: 6) {
                        Text("今日进度").font(.headline).foregroundStyle(widgetAccent)
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("\(completed)").font(.largeTitle.bold())
                            Text("/ \(completed + remaining.count)").font(.headline).foregroundStyle(.secondary)
                        }
                        ProgressView(value: progress).tint(widgetAccent)
                        Text(remaining.first.map { "接下来：\($0.title)" } ?? "今日事项已完成")
                            .font(.caption).lineLimit(2)
                        Spacer(minLength: 0)
                    }
                }
            }
        }.privacySensitive()
    }
}

struct FocusTimerWidget: Widget {
    let kind = "Mikansei.FocusTimer"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ChecklistProvider()) { entry in
            FocusTimerWidgetView(entry: entry)
                .containerBackground(Color(uiColor: .systemBackground), for: .widget)
                .widgetURL(entry.snapshot?.focusedTask(at: entry.date).map { AppRoute.entry($0.id).url } ?? AppRoute.tasks.url)
        }
        .configurationDisplayName("正在做 · 计时")
        .description("显示当前事项与累计用时。点暂停或继续，会打开 App 并同步计时状态。")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}
struct FocusTimerWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ChecklistTimelineEntry
    private var task: Entry? { entry.snapshot?.focusedTask(at: entry.date) }
    var body: some View {
        Group {
            if let task {
                if family == .accessoryRectangular {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(status(task)) · \(task.title)").font(.headline).lineLimit(1)
                        FocusClock(entry: task).font(.title3.weight(.semibold))
                    }
                } else if family == .systemMedium {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top, spacing: 16) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(status(task)).font(.caption.bold()).foregroundStyle(widgetAccent)
                                Text(task.title).font(.headline).lineLimit(2)
                            }
                            Spacer(minLength: 0)
                            FocusClock(entry: task).font(.system(size: 32, weight: .semibold, design: .rounded)).minimumScaleFactor(0.6)
                        }
                        Spacer(minLength: 0)
                        controls(task)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(status(task)).font(.caption.bold()).foregroundStyle(widgetAccent)
                        Text(task.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                        FocusClock(entry: task).font(.system(size: 30, weight: .semibold, design: .rounded)).minimumScaleFactor(0.6)
                        Spacer(minLength: 0)
                        controls(task)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Label("正在做 · 计时", systemImage: "timer").font(.headline).foregroundStyle(widgetAccent)
                    Text(entry.snapshot == nil ? "打开 App 同步" : "选择一件事开始做")
                        .font(.subheadline).foregroundStyle(.primary)
                    if family != .accessoryRectangular {
                        Link("打开我的清单", destination: AppRoute.tasks.url).font(.caption.bold()).foregroundStyle(widgetAccent)
                    }
                }
            }
        }.privacySensitive()
    }
    private func status(_ task: Entry) -> String {
        task.isCompleted ? "计时已结束" : task.startedAt == nil ? "已暂停" : "正在做"
    }
    private func controls(_ task: Entry) -> some View {
        HStack {
            if !task.isCompleted {
                let running = task.startedAt != nil
                Link(destination: AppRoute.focus(task.id, running ? .pause : .start).url) {
                    Label(running ? "暂停" : "继续", systemImage: running ? "pause.fill" : "play.fill")
                        .font(.caption.weight(.semibold)).foregroundStyle(widgetAccent)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(widgetAccent.opacity(0.12), in: Capsule())
                }
            } else { Label("已完成", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(widgetAccent) }
            Spacer(minLength: 0)
            if family == .systemMedium {
                Link("查看事项", destination: AppRoute.entry(task.id).url).font(.caption.weight(.semibold)).foregroundStyle(.primary)
            }
        }
    }
}

@main
struct MikanseiWidgets: WidgetBundle {
    var body: some Widget {
        TodayChecklistWidget()
        QuickAddWidget()
        TodayProgressWidget()
        FocusTimerWidget()
        if #available(iOS 26.0, *) { ReminderAlarmActivity() }
    }
}
