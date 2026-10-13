import Foundation
import UserNotifications
import AlarmKit

@MainActor
final class NotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published private(set) var authorization: UNAuthorizationStatus = .notDetermined
    @Published private(set) var scheduledCount = 0
    @Published private(set) var error: String?
    @Published private(set) var alarmStatus = "需要 iOS 26 或更新版本"
    @Published private(set) var alarmCount = 0
    @Published private(set) var foregroundReminders: [ForegroundReminder] = []
    private let testing = ProcessInfo.processInfo.arguments.contains("--ui-testing")
    private var alarmScheduler: Any?
    var supportsAlarms: Bool { if #available(iOS 26.0, *) { return true }; return false }
    @available(iOS 26.0, *)
    private var alarms: NativeAlarmScheduler {
        if let existing = alarmScheduler as? NativeAlarmScheduler { return existing }
        let created = NativeAlarmScheduler(); alarmScheduler = created; return created
    }
    @Published var openedEntryID: UUID?
    @Published var openedCourseID: UUID?
    @Published var completedEntryID: UUID?
    private let center = UNUserNotificationCenter.current()
    private var latest: [Entry] = []
    private var latestCourses: [Course] = []
    private var generation = 0
    private var worker: Task<Void, Never>?
    // Persistent identifiers remain stable so existing reminders can still be cancelled.
    private let prefix = "qingdanji."

    override init() {
        super.init()
        center.delegate = self
        let done = UNNotificationAction(identifier: "complete", title: "标为完成", options: [.foreground])
        let snooze = UNNotificationAction(identifier: "snooze", title: "稍后提醒", options: [])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: "task", actions: [done, snooze], intentIdentifiers: []),
            UNNotificationCategory(identifier: "course", actions: [snooze], intentIdentifiers: [])
        ])
    }
    var isAuthorized: Bool { authorization == .authorized || authorization == .provisional || authorization == .ephemeral }
    var statusTitle: String {
        switch authorization {
        case .authorized, .provisional, .ephemeral: return "已开启"
        case .denied: return "未开启"
        default: return "尚未申请"
        }
    }
    func refresh() async {
        authorization = await center.notificationSettings().authorizationStatus
        if #available(iOS 26.0, *), !testing { alarmStatus = alarms.status }
    }
    func requestAccess(for delivery: ReminderDelivery) async -> Bool {
        if testing { return true }
        if delivery == .popup { return await requestAccess() }
        guard #available(iOS 26.0, *) else { error = "系统闹钟需要 iOS 26 或更新版本。"; return false }
        do { let allowed = try await alarms.requestAccess(); alarmStatus = alarms.status; return allowed }
        catch { self.error = "无法申请闹钟权限：\(error.localizedDescription)"; return false }
    }
    func requestAccess() async -> Bool {
        await refresh()
        if authorization == .notDetermined {
            do { _ = try await center.requestAuthorization(options: [.alert, .sound, .badge]) }
            catch { self.error = "无法申请通知权限：\(error.localizedDescription)" }
            await refresh()
        }
        return isAuthorized
    }
    func update(entries: [Entry], courses: [Course]) {
        latest = entries
        latestCourses = courses
        generation += 1
        guard worker == nil else { return }
        worker = Task { [weak self] in
            guard let self else { return }
            while true {
                let revision = generation
                let snapshot = latest
                let courseSnapshot = latestCourses
                await reconcile(snapshot, courses: courseSnapshot)
                if revision == generation { break }
            }
            worker = nil
        }
    }
    private func reconcile(_ entries: [Entry], courses: [Course]) async {
        guard !testing else { return }
        await refresh()
        foregroundReminders.removeAll { !isActive($0, entries: entries, courses: courses) }
        let requests = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: requests.filter { request in
            guard request.identifier.hasPrefix(prefix) else { return false }
            return request.content.userInfo["snoozed"] as? Bool != true || !isActive(ForegroundReminder(request), entries: entries, courses: courses)
        }.map(\.identifier))
        // Completed/deleted items should also disappear from Notification Center.
        let activeIDs = entries.filter { !$0.isCompleted && $0.reminderDelivery == .popup && $0.reminder != nil }.map { prefix + "entry." + $0.id.uuidString + "." } + courses.filter { $0.reminderEnabled && $0.reminderDelivery == .popup }.map { prefix + "course." + $0.id.uuidString + "." }
        let delivered = await center.deliveredNotifications()
        center.removeDeliveredNotifications(withIdentifiers: delivered.map { $0.request.identifier }.filter {
            let identifier = $0
            return identifier.hasPrefix(prefix) && !activeIDs.contains(where: { identifier.hasPrefix($0) })
        })
        scheduledCount = requests.filter { $0.content.userInfo["snoozed"] as? Bool == true && isActive(ForegroundReminder($0), entries: entries, courses: courses) }.count
        error = nil
        let capacity = max(0, 60 - scheduledCount)
        let plan = await Task.detached(priority: .utility) {
            NotificationPlan.pending(entries: entries, courses: courses, limit: capacity)
        }.value
        if #available(iOS 26.0, *) {
            let result = await alarms.reconcile(plan.filter { $0.delivery == .alarm }, entries: entries, courses: courses)
            alarmCount = result.0; error = result.1; alarmStatus = alarms.status
        } else if plan.contains(where: { $0.delivery == .alarm }) { error = "闹钟提醒需要 iOS 26；请编辑这些事项改用弹窗提醒。" }
        guard isAuthorized else { return }
        for event in plan where event.delivery == .popup {
            let content = UNMutableNotificationContent()
            content.title = event.title
            content.body = event.body
            content.sound = event.sound.fileName.map { UNNotificationSound(named: UNNotificationSoundName(rawValue: $0)) } ?? .default
            content.userInfo = ["snoozeMinutes": event.snoozeMinutes]
            if let data = try? JSONEncoder().encode(event) { content.userInfo["plannedEvent"] = data }
            if let id = event.entryID { content.userInfo["entryID"] = id.uuidString; content.categoryIdentifier = "task" }
            if let id = event.courseID { content.userInfo["courseID"] = id.uuidString; content.categoryIdentifier = "course" }
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: event.date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            do {
                try await center.add(UNNotificationRequest(identifier: prefix + event.id, content: content, trigger: trigger))
                scheduledCount += 1
            } catch { self.error = "部分提醒未能安排：\(error.localizedDescription)" }
        }
    }
    private func isActive(_ reminder: ForegroundReminder, entries: [Entry], courses: [Course]) -> Bool {
        if let event = reminder.plannedEvent { return event.delivery == .popup && event.isStillEnabled(entries: entries, courses: courses) }
        if let id = reminder.entryID { return entries.contains { $0.id == id && !$0.isCompleted && $0.reminder != nil && $0.reminderDelivery == .popup } }
        if let id = reminder.courseID { return courses.contains { $0.id == id && $0.reminderEnabled && $0.reminderDelivery == .popup } }
        return false
    }
    func dismissPopup(_ reminder: ForegroundReminder) { foregroundReminders.removeAll { $0.id == reminder.id } }
    func openPopup(_ reminder: ForegroundReminder) {
        dismissPopup(reminder)
        openedEntryID = reminder.entryID; openedCourseID = reminder.courseID
    }
    func completePopup(_ reminder: ForegroundReminder) { dismissPopup(reminder); completedEntryID = reminder.entryID }
    func snoozePopup(_ reminder: ForegroundReminder) async {
        guard isActive(reminder, entries: latest, courses: latestCourses) else { dismissPopup(reminder); return }
        let content = reminder.content.mutableCopy() as! UNMutableNotificationContent
        content.userInfo["snoozed"] = true
        let owner = reminder.entryID.map { "entry.\($0)" } ?? reminder.courseID.map { "course.\($0)" } ?? "popup"
        let request = UNNotificationRequest(identifier: prefix + owner + ".snooze." + UUID().uuidString, content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: Double(reminder.snoozeMinutes * 60), repeats: false))
        do { try await center.add(request); dismissPopup(reminder) }
        catch { self.error = "稍后提醒未能安排：\(error.localizedDescription)" }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        let request = notification.request
        guard request.identifier.hasPrefix("qingdanji.") else { return [.banner, .sound, .list] }
        await MainActor.run {
            let reminder = ForegroundReminder(request)
            if self.isActive(reminder, entries: self.latest, courses: self.latestCourses), !self.foregroundReminders.contains(where: { $0.id == reminder.id }) {
                self.foregroundReminders.append(reminder)
            }
        }
        return [.sound, .list]
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        if response.actionIdentifier == "snooze" {
            await snoozePopup(ForegroundReminder(response.notification.request))
            return
        }
        let info = response.notification.request.content.userInfo
        if let raw = info["entryID"] as? String, let id = UUID(uuidString: raw) {
            let complete = response.actionIdentifier == "complete"
            await MainActor.run {
                if complete { self.completedEntryID = id } else { self.openedEntryID = id }
            }
        } else if let raw = info["courseID"] as? String, let id = UUID(uuidString: raw) {
            await MainActor.run { self.openedCourseID = id }
        }
    }
}

struct ForegroundReminder: Identifiable {
    let id: String
    let content: UNNotificationContent
    var entryID: UUID? { (content.userInfo["entryID"] as? String).flatMap(UUID.init(uuidString:)) }
    var courseID: UUID? { (content.userInfo["courseID"] as? String).flatMap(UUID.init(uuidString:)) }
    var snoozeMinutes: Int { let value = content.userInfo["snoozeMinutes"] as? Int ?? 5; return [5, 10, 15].contains(value) ? value : 5 }
    var plannedEvent: PlannedNotification? { (content.userInfo["plannedEvent"] as? Data).flatMap { try? JSONDecoder().decode(PlannedNotification.self, from: $0) } }
    init(_ request: UNNotificationRequest) { id = request.identifier; content = request.content }
}
