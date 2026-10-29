import SwiftUI
import UserNotifications

@MainActor
final class MacWorkspaceStore: ObservableObject, SyncWorkspace, CloudSyncWorkspace {
    @Published private(set) var entries: [Entry] = []
    @Published private(set) var courses: [Course] = []
    @Published private(set) var replica = WorkspaceReplica()
    @Published private(set) var readOnly = false
    @Published private(set) var hasUnsavedChanges = false
    @Published var error: String?
    @Published var calendarSettings = CalendarSyncSettings()
    @Published private(set) var cloudArchiveState: CloudArchiveState?
    @Published var reminderRoute: MacReminderRoute?
    private let writer: EntryArchiveWriter
    private var notificationDelegate: MacNotificationDelegate?
    private var notificationTask: Task<Void, Never>?
    private var revision = 0
    private var cloudSyncWriteFailed = false
    private var cloudSyncCommitObserver: (@MainActor () -> Void)?
    private var cloudSyncWaiters: [CheckedContinuation<Bool, Never>] = []
    private var deletionSnapshotInitialized = false
    private var deletionSnapshotEntries: [Entry] = []
    private var deletionSnapshotCourses: [Course] = []
    var syncReady: Bool { !readOnly && !hasUnsavedChanges }
    var cloudSyncArchive: EntryArchive {
        EntryArchive(entries: entries, courses: courses, calendarSync: calendarSettings,
                     replica: replica, cloudArchiveState: cloudArchiveState)
    }
    var archive: EntryArchive { cloudSyncArchive }
    var cloudSyncReady: Bool { !readOnly }
    var cloudSyncSaveFailed: Bool { cloudSyncWriteFailed }

    init() {
        let testing = ProcessInfo.processInfo.arguments.contains("--ui-testing")
        let base = testing ? FileManager.default.temporaryDirectory.appendingPathComponent("MikanseiMac-QA") :
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("MikanseiMac")
        let repository = EntryRepository(fileURL: base.appendingPathComponent("entries.json"))
        writer = EntryArchiveWriter(repository: repository)
        // 首次安装（档案文件原本不存在）时内置一份使用说明笔记；testing 保持空档案，绝不播种。
        let seedGuide = !testing && !FileManager.default.fileExists(atPath: repository.fileURL.path)
        do {
            let saved = testing ? EntryArchive(entries: []) : try repository.loadArchive()
            entries = saved.entries; courses = saved.courses; calendarSettings = saved.calendarSync
            cloudArchiveState = saved.cloudArchiveState
            replica = saved.replica ?? WorkspaceReplica()
            if testing && ProcessInfo.processInfo.arguments.contains("--demo") {
                entries = [Entry(title: "整理今日作业", kind: .homework, priority: .urgent, dueDate: Date().addingTimeInterval(3600)), Entry(title: "给家里打电话"), Entry(title: "学习笔记", body: "用侧栏浏览，在详情中编辑。", kind: .note)]
            }
            if seedGuide { entries = [Entry.builtInGuideNote()] }
            replica.capture(entries: entries, courses: courses, suppressed: calendarSettings.suppressed)
        } catch { readOnly = true; self.error = "无法读取原数据，请保留 App：\(error.localizedDescription)" }
        deletionSnapshotEntries = entries
        deletionSnapshotCourses = courses
        deletionSnapshotInitialized = true
        persist()
        if !testing {
            let delegate = MacNotificationDelegate { [weak self] route in self?.reminderRoute = route }
            notificationDelegate = delegate
            UNUserNotificationCenter.current().delegate = delegate
        }
    }
    func persist(recordingLocalDeletions: Bool = true) {
        guard !readOnly else { return }
        if recordingLocalDeletions && deletionSnapshotInitialized {
            let currentEntryIDs = Set(entries.map(\.id))
            let currentCourseIDs = Set(courses.map(\.id))
            let removedEntries = deletionSnapshotEntries.filter { !currentEntryIDs.contains($0.id) }
            let removedCourses = deletionSnapshotCourses.filter { !currentCourseIDs.contains($0.id) }
            if !removedEntries.isEmpty || !removedCourses.isEmpty {
                cloudArchiveState = CloudArchiveCodec.recordingLocalDeletions(
                    state: cloudArchiveState,
                    removedEntries: removedEntries,
                    removedCourses: removedCourses
                )
            }
        }
        deletionSnapshotEntries = entries
        deletionSnapshotCourses = courses
        revision += 1; let current = revision
        hasUnsavedChanges = true
        writer.save(archive) { [weak self] result in
            DispatchQueue.main.async {
                guard let self, current == self.revision else { return }
                switch result {
                case .success:
                    self.hasUnsavedChanges = false
                    self.cloudSyncWriteFailed = false
                    self.error = nil
                    self.scheduleNotifications()
                    self.finishCloudSyncWaiters(success: true)
                    self.cloudSyncCommitObserver?()
                case .failure(let error):
                    self.cloudSyncWriteFailed = true
                    self.error = "尚未保存，请重试：\(error.localizedDescription)"
                    self.finishCloudSyncWaiters(success: false)
                }
            }
        }
    }
    func save(_ input: Entry) {
        guard !readOnly else { return }
        var entry = input.normalized(); entry.updatedAt = Date()
        guard !entry.title.isEmpty else { return }
        let previous = entries.first { $0.id == entry.id }
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
        if let i = entries.firstIndex(where: { $0.id == entry.id }) { entries[i] = entry } else { entries.append(entry) }
        if entry.isCompleted && previous?.isCompleted != true && entry.allowsLocalSuccessorGeneration,
           !entries.contains(where: { $0.previousOccurrenceID == entry.id }), let next = entry.nextOccurrence() {
            entries.append(next)
        }
        changed()
    }
    func delete(_ id: UUID) {
        guard !readOnly else { return }
        if let event = entries.first(where: { $0.id == id })?.calendarEvent?.event.identity, !calendarSettings.suppressed.contains(event) { calendarSettings.suppressed.append(event) }
        entries.removeAll { $0.id == id }; changed()
    }
    func toggle(_ id: UUID) {
        guard var entry = entries.first(where: { $0.id == id }), entry.isTask else { return }
        entry.setCompleted(!entry.isCompleted); save(entry)
    }
    /// 规划的执行日期（按天）；空数组表示清除。kind 不变。
    func setPlannedDays(_ id: UUID, _ days: [Date]) {
        guard !readOnly, var entry = entries.first(where: { $0.id == id }), entry.isTask else { return }
        entry.plannedDays = days.isEmpty ? nil : days
        if !days.isEmpty { entry.isInPlanning = false }
        save(entry)
    }
    /// 规划的执行时段；kind 不变，显式时间会取消全天。
    func setPlannedTime(_ id: UUID, start: Date, end: Date) {
        guard !readOnly, var entry = entries.first(where: { $0.id == id }), entry.isTask, end > start else { return }
        entry.plannedStart = start; entry.plannedEnd = end; entry.plannedAllDay = false
        entry.isInPlanning = false
        save(entry)
    }
    func moveToPlanning(_ id: UUID) {
        guard !readOnly, var entry = entries.first(where: { $0.id == id }),
              entry.isTask, !entry.isCompleted, !entry.isInPlanning else { return }
        entry.isInPlanning = true
        save(entry)
    }
    func restoreFromPlanning(_ id: UUID) {
        guard !readOnly, var entry = entries.first(where: { $0.id == id }),
              entry.isTask, entry.isInPlanning else { return }
        entry.isInPlanning = false
        save(entry)
    }
    /// 拖动排序：按给定顺序写 sortOrder 0..n，单次 persist。
    func reorder(_ ids: [UUID]) {
        guard !readOnly else { return }
        var order = 0
        for id in ids {
            guard let index = entries.firstIndex(where: { $0.id == id }) else { continue }
            entries[index].sortOrder = order
            entries[index].updatedAt = Date()
            order += 1
        }
        changed()
    }
    func focus(_ id: UUID) {
        guard !readOnly, let current = entries.first(where: { $0.id == id }), let next = FocusSession.updating(entries, id: id, isRunning: current.startedAt == nil) else { return }
        entries = next; changed()
    }
    func saveCourse(_ course: Course) {
        guard !readOnly, course.isValid else { return }
        if let i = courses.firstIndex(where: { $0.id == course.id }) { courses[i] = course } else { courses.append(course) }; changed()
    }
    func deleteCourse(_ id: UUID) { guard !readOnly else { return }; courses.removeAll { $0.id == id }; changed() }
    func importBackup(_ data: Data) throws {
        guard !readOnly else { return }
        let incoming = try EntryArchive.decode(data)
        entries = incoming.merging(into: entries)
        let known = Set(courses.map(\.id)); courses += incoming.courses.filter { !known.contains($0.id) }
        changed()
    }
    func importCourses(_ data: Data, isICS: Bool) throws {
        guard let text = String(data: data, encoding: .utf8) else { throw CocoaError(.fileReadInapplicableStringEncoding) }
        let incoming = isICS ? try CourseICS.parse(text) : try CourseCSV.parse(text)
        for course in incoming where !courses.contains(where: {
            $0.name == course.name && $0.weekday == course.weekday && $0.startMinutes == course.startMinutes &&
            $0.endMinutes == course.endMinutes && Calendar.current.isDate($0.firstDate, inSameDayAs: course.firstDate) &&
            Calendar.current.isDate($0.lastDate, inSameDayAs: course.lastDate)
        }) { saveCourse(course) }
    }
    func applySync(_ document: WorkspaceSyncDocument) {
        guard !readOnly else { return }
        var merged = replica; merged.receive(document)
        guard merged != replica else { return }
        replica = merged; entries = merged.entries; courses = merged.courses
        for identity in merged.document.deletedCalendarOccurrences ?? [] where !calendarSettings.suppressed.contains(where: { $0.matches(identity) }) { calendarSettings.suppressed.append(identity) }
        replica.capture(entries: entries, courses: courses, suppressed: calendarSettings.suppressed)
        persist()
    }
    func changed() { replica.capture(entries: entries, courses: courses, suppressed: calendarSettings.suppressed); persist() }
    func applyCloudArchive(_ merge: CloudArchiveMerge) -> Bool {
        guard !readOnly else { return false }
        var settings = calendarSettings
        for identity in merge.deletedCalendarOccurrences
        where !settings.suppressed.contains(where: { $0.matches(identity) }) {
            settings.suppressed.append(identity)
        }
        var nextReplica = replica
        nextReplica.capture(entries: merge.entries, courses: merge.courses, suppressed: settings.suppressed)
        let resolvedEntries = nextReplica.entries
        let resolvedCourses = nextReplica.courses
        guard resolvedEntries != entries || resolvedCourses != courses ||
              settings != calendarSettings || nextReplica != replica ||
              merge.state != cloudArchiveState else { return false }
        entries = resolvedEntries
        courses = resolvedCourses
        calendarSettings = settings
        replica = nextReplica
        cloudArchiveState = merge.state
        replica.capture(entries: entries, courses: courses, suppressed: calendarSettings.suppressed)
        persist(recordingLocalDeletions: false)
        return true
    }
    func waitForCloudSyncDurability() async -> Bool {
        guard !readOnly, !cloudSyncWriteFailed else { return false }
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
    func scheduleNotifications() {
        guard !ProcessInfo.processInfo.arguments.contains("--ui-testing") else { return }
        let entries = entries; let courses = courses
        notificationTask?.cancel()
        notificationTask = Task {
            let center = UNUserNotificationCenter.current()
            guard await center.notificationSettings().authorizationStatus == .authorized else { return }
            let pending = await center.pendingNotificationRequests()
            guard !Task.isCancelled else { return }
            center.removePendingNotificationRequests(withIdentifiers: pending.filter { $0.identifier.hasPrefix("mikansei.") }.map(\.identifier))
            for notification in NotificationPlan.pending(entries: entries, courses: courses) {
                guard !Task.isCancelled else { return }
                let content = UNMutableNotificationContent(); content.title = notification.title; content.body = notification.body; content.sound = .default
                if let id = notification.entryID { content.userInfo["entryID"] = id.uuidString }
                if let id = notification.courseID { content.userInfo["courseID"] = id.uuidString }
                let trigger = UNCalendarNotificationTrigger(dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: notification.date), repeats: false)
                try? await center.add(UNNotificationRequest(identifier: "mikansei." + notification.id, content: content, trigger: trigger))
            }
        }
    }
}
