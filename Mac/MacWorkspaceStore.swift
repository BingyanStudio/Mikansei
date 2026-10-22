import SwiftUI
import UserNotifications

@MainActor
final class MacWorkspaceStore: ObservableObject, SyncWorkspace {
    @Published private(set) var entries: [Entry] = []
    @Published private(set) var courses: [Course] = []
    @Published private(set) var replica = WorkspaceReplica()
    @Published private(set) var readOnly = false
    @Published private(set) var hasUnsavedChanges = false
    @Published var error: String?
    @Published var calendarSettings = CalendarSyncSettings()
    @Published var reminderRoute: MacReminderRoute?
    private let writer: EntryArchiveWriter
    private var notificationDelegate: MacNotificationDelegate?
    private var notificationTask: Task<Void, Never>?
    private var revision = 0
    var syncReady: Bool { !readOnly && !hasUnsavedChanges }
    var archive: EntryArchive { EntryArchive(entries: entries, courses: courses, calendarSync: calendarSettings, replica: replica) }

    init() {
        let testing = ProcessInfo.processInfo.arguments.contains("--ui-testing")
        let base = testing ? FileManager.default.temporaryDirectory.appendingPathComponent("MikanseiMac-QA") :
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("MikanseiMac")
        let repository = EntryRepository(fileURL: base.appendingPathComponent("entries.json"))
        writer = EntryArchiveWriter(repository: repository)
        do {
            let saved = testing ? EntryArchive(entries: []) : try repository.loadArchive()
            entries = saved.entries; courses = saved.courses; calendarSettings = saved.calendarSync
            replica = saved.replica ?? WorkspaceReplica()
            if testing && ProcessInfo.processInfo.arguments.contains("--demo") {
                entries = [Entry(title: "整理今日作业", kind: .homework, priority: .urgent, dueDate: Date().addingTimeInterval(3600)), Entry(title: "给家里打电话"), Entry(title: "学习笔记", body: "用侧栏浏览，在详情中编辑。", kind: .note)]
            }
            replica.capture(entries: entries, courses: courses, suppressed: calendarSettings.suppressed)
        } catch { readOnly = true; self.error = "无法读取原数据，请保留 App：\(error.localizedDescription)" }
        persist()
        if !testing {
            let delegate = MacNotificationDelegate { [weak self] route in self?.reminderRoute = route }
            notificationDelegate = delegate
            UNUserNotificationCenter.current().delegate = delegate
        }
    }
    func persist() {
        guard !readOnly else { return }
        revision += 1; let current = revision
        hasUnsavedChanges = true
        writer.save(archive) { [weak self] result in
            DispatchQueue.main.async {
                guard let self, current == self.revision else { return }
                switch result {
                case .success: self.hasUnsavedChanges = false; self.error = nil; self.scheduleNotifications()
                case .failure(let error): self.error = "尚未保存，请重试：\(error.localizedDescription)"
                }
            }
        }
    }
    func save(_ input: Entry) {
        guard !readOnly else { return }
        var entry = input.normalized(); entry.updatedAt = Date()
        guard !entry.title.isEmpty else { return }
        let previous = entries.first { $0.id == entry.id }
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
