import SwiftUI
import WidgetKit

@MainActor
final class EntryStore: ObservableObject, SyncWorkspace, CloudSyncWorkspace {
    @Published private(set) var entries: [Entry] = []
    @Published private(set) var courses: [Course] = []
    @Published private(set) var readOnly = false
    @Published var error: String?
    @Published private(set) var widgetSyncError: String?
    @Published private(set) var calendarSync = CalendarSyncSettings()
    @Published private(set) var hasUnsavedChanges = false
    @Published private(set) var saveFailed = false
    @Published private(set) var replica = WorkspaceReplica()
    var syncReady: Bool { !readOnly && !hasUnsavedChanges }
    @Published private(set) var cloudArchiveState: CloudArchiveState?
    var cloudSyncArchive: EntryArchive {
        EntryArchive(entries: entries, courses: courses, calendarSync: calendarSync,
                     replica: replica, cloudArchiveState: cloudArchiveState)
    }
    var cloudSyncReady: Bool { !readOnly }
    var cloudSyncSaveFailed: Bool { saveFailed }
    private let repository: EntryRepository
    private let writer: EntryArchiveWriter
    private var writeRevision = 0
    private var cloudSyncCommitObserver: (@MainActor () -> Void)?
    private var cloudSyncWaiters: [CheckedContinuation<Bool, Never>] = []
    private var backgroundWrite: UIBackgroundTaskIdentifier = .invalid
    private let widgetQueue = DispatchQueue(label: "Mikansei.widget-writer", qos: .utility)
    private var widgetRefresh: Task<Void, Never>?
    let notifications: NotificationManager

    init(notifications: NotificationManager) {
        self.notifications = notifications
        let testing = ProcessInfo.processInfo.arguments.contains("--ui-testing")
        // Keep the original on-device directory so a name change retains existing data.
        let base = testing ? FileManager.default.temporaryDirectory.appendingPathComponent("Mikansei-UITests") :
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("QingdanJi")
        repository = EntryRepository(fileURL: base.appendingPathComponent("entries.json"))
        writer = EntryArchiveWriter(repository: repository)
        if testing {
            entries = ProcessInfo.processInfo.arguments.contains("--deadline-activity-demo") ? Self.deadlineActivityExamples() :
                ProcessInfo.processInfo.arguments.contains("--calendar-view-demo") ? Self.calendarViewExamples() :
                ProcessInfo.processInfo.arguments.contains("--demo") ? Self.examples() : []
        } else {
            // 首次安装（档案文件原本不存在）时内置一份使用说明笔记；testing 走上面的分支，绝不播种。
            let seedGuide = !FileManager.default.fileExists(atPath: repository.fileURL.path)
            do { let archive = try repository.loadArchive(); entries = archive.entries; courses = archive.courses; calendarSync = archive.calendarSync; replica = archive.replica ?? WorkspaceReplica(); cloudArchiveState = archive.cloudArchiveState
                if seedGuide { entries = [Entry.builtInGuideNote()]; _ = commit(entries) }
            }
            catch {
                readOnly = true
                self.error = "无法读取本地数据，原文件已保留。请勿卸载 App，以免丢失数据。\n\(error.localizedDescription)"
            }
        }
        if !readOnly { replica.capture(entries: entries, courses: courses, suppressed: calendarSync.suppressed); notifications.update(entries: entries, courses: courses); refreshWidgets() }
    }
    @discardableResult
    private func commit(_ next: [Entry], courses nextCourses: [Course]? = nil,
                        calendarSync nextSync: CalendarSyncSettings? = nil,
                        mergedReplica: WorkspaceReplica? = nil,
                        cloudArchiveState nextCloudState: CloudArchiveState? = nil,
                        replaceCloudArchiveState: Bool = false,
                        recordLocalDeletions: Bool = true) -> Bool {
        guard !readOnly else { return false }
        let priorEntries = entries
        let priorCourses = courses
        var nextReplica = mergedReplica ?? replica
        nextReplica.capture(entries: next, courses: nextCourses ?? courses, suppressed: (nextSync ?? calendarSync).suppressed)
        var nextDurableCloudState = replaceCloudArchiveState ? nextCloudState : cloudArchiveState
        if recordLocalDeletions {
            let nextEntryIDs = Set(next.map(\.id))
            let nextCourseIDs = Set((nextCourses ?? courses).map(\.id))
            let removedEntries = priorEntries.filter { !nextEntryIDs.contains($0.id) }
            let removedCourses = priorCourses.filter { !nextCourseIDs.contains($0.id) }
            if !removedEntries.isEmpty || !removedCourses.isEmpty {
                nextDurableCloudState = CloudArchiveCodec.recordingLocalDeletions(
                    state: nextDurableCloudState,
                    removedEntries: removedEntries,
                    removedCourses: removedCourses
                )
            }
        }
        let archive = EntryArchive(entries: next, courses: nextCourses ?? courses,
                                   calendarSync: nextSync ?? calendarSync, replica: nextReplica,
                                   cloudArchiveState: nextDurableCloudState)
        writeRevision += 1
        let revision = writeRevision
        entries = archive.entries; courses = archive.courses; calendarSync = archive.calendarSync
        replica = nextReplica
        cloudArchiveState = archive.cloudArchiveState
        hasUnsavedChanges = true
        saveFailed = false
        error = nil
        notifications.update(entries: next, courses: courses)
        if backgroundWrite == .invalid {
            backgroundWrite = UIApplication.shared.beginBackgroundTask(withName: "保存事项") { [weak self] in
                Task { @MainActor in
                    guard let self, self.backgroundWrite != .invalid else { return }
                    UIApplication.shared.endBackgroundTask(self.backgroundWrite)
                    self.backgroundWrite = .invalid
                }
            }
        }
        writer.save(archive) { [weak self] result in
            DispatchQueue.main.async {
                guard let self, revision == self.writeRevision else { return }
                if self.backgroundWrite != .invalid {
                    UIApplication.shared.endBackgroundTask(self.backgroundWrite)
                    self.backgroundWrite = .invalid
                }
                switch result {
                case .success:
                    self.hasUnsavedChanges = false
                    self.saveFailed = false
                    self.refreshWidgets()
                    self.finishCloudSyncWaiters(success: true)
                    self.cloudSyncCommitObserver?()
                case .failure(let error):
                    self.saveFailed = true
                    self.error = "保存失败，修改暂时只在内存中，请点击重试保存：\(error.localizedDescription)"
                    self.finishCloudSyncWaiters(success: false)
                }
            }
        }
        return true // Accepted in memory; failures remain visible and can be retried.
    }
    func applyCloudArchive(_ merge: CloudArchiveMerge) -> Bool {
        guard !readOnly else { return false }
        var settings = calendarSync
        for identity in merge.deletedCalendarOccurrences
        where !settings.suppressed.contains(where: { $0.matches(identity) }) {
            settings.suppressed.append(identity)
        }
        var nextReplica = replica
        nextReplica.capture(entries: merge.entries, courses: merge.courses, suppressed: settings.suppressed)
        let resolvedEntries = nextReplica.entries
        let resolvedCourses = nextReplica.courses
        guard resolvedEntries != entries || resolvedCourses != courses ||
              settings != calendarSync || nextReplica != replica ||
              merge.state != cloudArchiveState else { return false }
        return commit(resolvedEntries, courses: resolvedCourses, calendarSync: settings,
                      mergedReplica: nextReplica, cloudArchiveState: merge.state,
                      replaceCloudArchiveState: true, recordLocalDeletions: false)
    }
    func waitForCloudSyncDurability() async -> Bool {
        guard !readOnly, !saveFailed else { return false }
        if !hasUnsavedChanges { return true }
        return await withCheckedContinuation { continuation in
            cloudSyncWaiters.append(continuation)
        }
    }
    func setCloudSyncCommitObserver(_ observer: (@MainActor () -> Void)?) {
        cloudSyncCommitObserver = observer
    }
    private func finishCloudSyncWaiters(success: Bool) {
        let pending = cloudSyncWaiters
        cloudSyncWaiters.removeAll()
        pending.forEach { $0.resume(returning: success) }
    }
    func retrySave() { _ = commit(entries) }
    func applySync(_ document: WorkspaceSyncDocument) {
        guard !readOnly else { return }
        var merged = replica; merged.receive(document)
        guard merged != replica else { return }
        var settings = calendarSync
        for identity in merged.document.deletedCalendarOccurrences ?? [] where !settings.suppressed.contains(where: { $0.matches(identity) }) { settings.suppressed.append(identity) }
        _ = commit(merged.entries, courses: merged.courses, calendarSync: settings, mergedReplica: merged)
    }
    @discardableResult
    func save(_ draft: Entry) -> Bool {
        var entry = draft.normalized()
        guard !entry.title.isEmpty else { return false }
        var next = entries
        let previous = next.first(where: { $0.id == entry.id })
        let wasCompleted = previous?.isCompleted ?? false
        if let previous, previous.isInPlanning, entry.isInPlanning {
            let oldPlan = previous.normalized(at: previous.updatedAt)
            let startChanged = oldPlan.plannedStart != entry.plannedStart
            let endChanged = oldPlan.plannedEnd != entry.plannedEnd
            let allDayChanged = oldPlan.plannedAllDay != entry.plannedAllDay
            let hasNewDays = !(entry.plannedDays ?? []).isEmpty && oldPlan.plannedDays != entry.plannedDays
            let hasValidNewTime = entry.plannedStart.map { start in
                (entry.plannedEnd.map { $0 > start } ?? startChanged) &&
                    (startChanged || endChanged || allDayChanged)
            } ?? false
            if hasNewDays || hasValidNewTime {
                entry.isInPlanning = false
            }
        }
        if let index = next.firstIndex(where: { $0.id == entry.id }) { next[index] = entry }
        else { next.append(entry) }
        // Provider-backed recurring occurrences advance from their source; one-off links may still have a local routine.
        if entry.isCompleted && !wasCompleted && entry.allowsLocalSuccessorGeneration &&
           !next.contains(where: { $0.previousOccurrenceID == entry.id }),
           let occurrence = entry.nextOccurrence() { next.append(occurrence) }
        return commit(next)
    }
    func toggleCompletion(_ id: UUID) {
        guard var entry = entries.first(where: { $0.id == id }), entry.isTask else { return }
        entry.setCompleted(!entry.isCompleted)
        _ = save(entry)
    }
    func toggleStep(entryID: UUID, stepID: UUID) {
        guard var entry = entries.first(where: { $0.id == entryID }) else { return }
        entry.toggleStep(stepID)
        _ = save(entry)
    }
    /// 规划的执行日期（按天）；空数组表示清除。kind 不变。
    @discardableResult
    func setPlannedDays(_ id: UUID, _ days: [Date]) -> Bool {
        guard var entry = entries.first(where: { $0.id == id }), entry.isTask else { return false }
        entry.plannedDays = days.isEmpty ? nil : days
        if !days.isEmpty { entry.isInPlanning = false }
        return save(entry) // save 走 normalized()，负责去重、取整天序并提交。
    }
    /// 规划的执行时段；kind 不变，显式时间会取消全天。
    @discardableResult
    func setPlannedTime(_ id: UUID, start: Date, end: Date) -> Bool {
        guard var entry = entries.first(where: { $0.id == id }), entry.isTask, end > start else { return false }
        entry.plannedStart = start
        entry.plannedEnd = end
        entry.plannedAllDay = false
        entry.isInPlanning = false
        return save(entry)
    }
    @discardableResult
    func moveToPlanning(_ id: UUID) -> Bool {
        guard !readOnly, var entry = entries.first(where: { $0.id == id }),
              entry.isTask, !entry.isCompleted, !entry.isInPlanning else { return false }
        entry.isInPlanning = true
        return save(entry)
    }
    @discardableResult
    func restoreFromPlanning(_ id: UUID) -> Bool {
        guard !readOnly, var entry = entries.first(where: { $0.id == id }),
              entry.isTask, entry.isInPlanning else { return false }
        entry.isInPlanning = false
        return save(entry)
    }
    /// 拖动排序：按给定顺序写 sortOrder 0..n，单次 commit。
    @discardableResult
    func reorder(_ ids: [UUID]) -> Bool {
        var next = entries
        var order = 0
        for id in ids {
            guard let index = next.firstIndex(where: { $0.id == id }) else { continue }
            next[index].sortOrder = order
            next[index].updatedAt = Date()
            order += 1
        }
        guard next != entries else { return true }
        return commit(next)
    }
    @discardableResult
    func delete(_ id: UUID) -> Bool {
        var sync = calendarSync
        if let identity = entries.first(where: { $0.id == id })?.calendarEvent?.event.identity,
           !sync.suppressed.contains(identity) { sync.suppressed.append(identity) }
        return commit(entries.filter { $0.id != id }, calendarSync: sync)
    }
    @discardableResult
    func saveCalendarSyncSettings(_ settings: CalendarSyncSettings) -> Bool {
        guard settings != calendarSync else { return true }
        return commit(entries, calendarSync: settings)
    }
    func importCalendarEvents(_ events: [CalendarEventRecord], range: Range<Date>, calendars: Set<String>, availableCalendars: Set<String>? = nil) -> CalendarSyncResult? {
        guard !readOnly else { return nil }
        let result = CalendarImport.merge(events: events, into: entries, settings: calendarSync,
                                          range: range, availableCalendarIDs: availableCalendars ?? calendars, queriedCalendarIDs: calendars)
        guard result.entries != entries else { return result }
        return commit(result.entries) ? result : nil
    }
    @discardableResult
    func linkCalendarEvent(_ record: CalendarEventRecord, entryID: UUID) -> Bool {
        guard var entry = entries.first(where: { $0.id == entryID }) else { return false }
        // A scheduled execution block is independent of the existing deadline and Checklist.
        entry.title = record.draft(timing: .start, now: Date()).title
        entry.body = record.notes
        entry.location = record.location.trimmingCharacters(in: .whitespacesAndNewlines)
        if !record.url.isEmpty || entry.platform == entry.calendarEvent?.event.url { entry.platform = record.url }
        entry.plannedStart = record.start; entry.plannedEnd = record.end; entry.plannedAllDay = record.isAllDay
        entry.calendarEvent = CalendarEventLink(event: record, timing: .start, wasAutomaticallyImported: false)
        var settings = calendarSync
        settings.suppressed.removeAll { $0.matches(record.identity) }
        var next = entries
        if let index = next.firstIndex(where: { $0.id == entryID }) { next[index] = entry.normalized() }
        return commit(next, calendarSync: settings)
    }
    var cleanableCalendarEntries: [Entry] {
        let ids = Set(calendarSync.selected.map(\.id))
        return entries.filter { CalendarImport.canClean($0, selectedIDs: ids) }
    }
    @discardableResult
    func cleanUnselectedCalendarImports() -> Bool {
        let ids = Set(cleanableCalendarEntries.map(\.id))
        // Re-selecting a source later may import it again; cleanup doesn't suppress those events.
        return commit(entries.filter { !ids.contains($0.id) })
    }
    @discardableResult
    func importBackup(_ data: Data) -> Bool {
        do {
            let archive = try EntryArchive.decode(data)
            let known = Set(courses.map(\.id))
            var sync = calendarSync
            // Restoring a fresh install also restores calendar selection and deletion exclusions.
            if entries.isEmpty && sync == CalendarSyncSettings() { sync = archive.calendarSync }
            else {
                for id in archive.calendarSync.suppressed where !sync.suppressed.contains(id) { sync.suppressed.append(id) }
            }
            return commit(archive.merging(into: entries), courses: courses + archive.courses.filter { !known.contains($0.id) }, calendarSync: sync)
        }
        catch { self.error = "导入失败：\(error.localizedDescription)"; return false }
    }
    func addExamples() { _ = commit(entries + Self.examples()) }
    func refreshNotifications() {
        if !readOnly { notifications.update(entries: entries, courses: courses); refreshWidgets() }
    }
    private func refreshWidgets() {
        guard !ProcessInfo.processInfo.arguments.contains("--ui-testing") else { return }
        widgetRefresh?.cancel()
        widgetRefresh = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
            guard let self, !hasUnsavedChanges else { return }
            let snapshot = WidgetSnapshot(entries: entries)
            widgetQueue.async { [weak self] in
                let failure: String?
                do { try WidgetSnapshotStore.save(snapshot); WidgetCenter.shared.reloadAllTimelines(); failure = nil }
                catch { failure = "小组件清单暂未同步，请重新打开 App 后重试。\n\(error.localizedDescription)" }
                DispatchQueue.main.async { self?.widgetSyncError = failure }
            }
        }
    }
    func start(_ id: UUID) {
        guard let entry = entries.first(where: { $0.id == id }) else { return }
        setFocus(id, running: entry.startedAt == nil)
    }
    func setFocus(_ id: UUID, running: Bool) {
        guard let next = FocusSession.updating(entries, id: id, isRunning: running), next != entries else { return }
        _ = commit(next)
    }
    @discardableResult
    func saveCourse(_ course: Course) -> Bool {
        guard course.isValid else { return false }
        var next = courses
        if let index = next.firstIndex(where: { $0.id == course.id }) { next[index] = course }
        else { next.append(course) }
        return commit(entries, courses: next)
    }
    func deleteCourse(_ id: UUID) { _ = commit(entries, courses: courses.filter { $0.id != id }) }
    @discardableResult
    func importCourses(_ imported: [Course]) -> Bool {
        var next = courses
        for course in imported {
            if !next.contains(where: { $0.name == course.name && $0.weekday == course.weekday && $0.startMinutes == course.startMinutes && $0.endMinutes == course.endMinutes && Calendar.current.isDate($0.firstDate, inSameDayAs: course.firstDate) && Calendar.current.isDate($0.lastDate, inSameDayAs: course.lastDate) }) { next.append(course) }
        }
        return commit(entries, courses: next)
    }

    /// Import course calendar rows and their matching in-app schedule entries atomically.
    /// `source` is a stable importer key with the `bingyan.schedule:` prefix.
    @discardableResult
    func importCourseSchedules(_ imported: [Course], schedules: [Entry]) -> Bool {
        guard !readOnly else { return false }
        var nextCourses = courses
        for course in imported where course.isValid {
            let exists = nextCourses.contains {
                $0.name == course.name && $0.weekday == course.weekday &&
                $0.startMinutes == course.startMinutes && $0.endMinutes == course.endMinutes &&
                Calendar.current.isDate($0.firstDate, inSameDayAs: course.firstDate) &&
                Calendar.current.isDate($0.lastDate, inSameDayAs: course.lastDate)
            }
            if !exists { nextCourses.append(course) }
        }

        let sourcePrefix = "bingyan.schedule:"
        var knownIDs = Set(entries.map(\.id))
        var knownScheduleSources = Set(entries.filter { $0.source.hasPrefix(sourcePrefix) }.map(\.source))
        var nextEntries = entries
        for candidate in schedules where candidate.kind == .schedule && candidate.source.hasPrefix(sourcePrefix) {
            guard let start = candidate.plannedStart, let end = candidate.plannedEnd, end > start else { continue }
            let schedule = candidate.normalized()
            guard !schedule.title.isEmpty, knownIDs.insert(schedule.id).inserted,
                  knownScheduleSources.insert(schedule.source).inserted else { continue }
            nextEntries.append(schedule)
        }
        guard nextEntries != entries || nextCourses != courses else { return true }
        return commit(nextEntries, courses: nextCourses)
    }

    private static func calendarViewExamples(now: Date = Date()) -> [Entry] {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: now)
        func timed(_ title: String, start: Int, end: Int) -> Entry {
            var entry = Entry(title: title)
            entry.plannedStart = calendar.date(bySettingHour: start, minute: 0, second: 0, of: day)
            entry.plannedEnd = calendar.date(bySettingHour: end, minute: 0, second: 0, of: day)
            return entry
        }
        var allDay = Entry(title: "校园活动日")
        allDay.plannedStart = day; allDay.plannedEnd = calendar.date(byAdding: .day, value: 1, to: day); allDay.plannedAllDay = true
        return [timed("图书馆自习", start: 9, end: 11), timed("社团讨论", start: 10, end: 11), allDay,
                Entry(title: "报告 DDL", dueDate: calendar.date(bySettingHour: 22, minute: 0, second: 0, of: day)), Entry(title: "买一盏阅读灯")]
    }

    private static func deadlineActivityExamples(now: Date = Date()) -> [Entry] {
        let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now))!
        return [Entry(title: "紧急作业", kind: .homework, priority: .urgent, dueDate: min(now.addingTimeInterval(600), dayEnd.addingTimeInterval(-1))),
                Entry(title: "提交社团材料", priority: .important, dueDate: min(now.addingTimeInterval(1800), dayEnd.addingTimeInterval(-1))),
                Entry(title: "给家里打电话"), Entry(title: "洗衣服")]
    }

    static func examples(now: Date = Date()) -> [Entry] {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)!
        let tonight = calendar.date(bySettingHour: 23, minute: 0, second: 0, of: now)!
        return [
            Entry(title: "完成英语阅读作业", body: "读完文章，把不熟悉的词整理到笔记里。", kind: .homework, category: "英语", priority: .important,
                  checklist: [ChecklistItem(title: "阅读课文", isDone: true), ChecklistItem(title: "完成课后练习"), ChecklistItem(title: "检查并提交")], dueDate: tonight),
            Entry(title: "给自己留半小时运动", category: "生活", dueDate: tonight.addingTimeInterval(-1800)),
            Entry(title: "准备明天的学习资料", kind: .task, category: "学习", checklist: [ChecklistItem(title: "整理课本"), ChecklistItem(title: "带好笔记本")], dueDate: tomorrow),
            Entry(title: "买一盏阅读灯", body: "记得量一下书桌的宽度。", category: "生活"),
            Entry(title: "一个好用的学习方法", body: "先拆成小步骤，再开始第一步。\n\n学习结束时，写下今天学到的三件事。", kind: .note, category: "灵感")
        ]
    }
}
