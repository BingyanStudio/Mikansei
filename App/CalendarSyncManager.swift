import EventKit
import SwiftUI

struct CalendarOption: Identifiable {
    let selection: CalendarSelection
    let color: Color
    let isBirthday: Bool
    var id: String { selection.id }
}

@MainActor
final class CalendarSyncManager: ObservableObject {
    @Published private(set) var calendars: [CalendarOption] = []
    @Published private(set) var authorization: EKAuthorizationStatus = .notDetermined
    @Published private(set) var isSyncing = false
    @Published private(set) var lastSync: Date?
    @Published private(set) var message = "首次使用需要允许读取系统日历。"
    @Published private(set) var error: String?
    private lazy var eventStore = EKEventStore()
    private let testing = ProcessInfo.processInfo.arguments.contains("--ui-testing")
    private let demo = ProcessInfo.processInfo.arguments.contains("--calendar-demo")
    private let demoStart = Date(timeIntervalSince1970: Date().addingTimeInterval(3600).timeIntervalSince1970.rounded())

    var statusTitle: String {
        switch authorization {
        case .fullAccess: return "已允许读取"
        case .writeOnly: return "只有写入权限，无法读取"
        case .denied: return "未允许"
        case .restricted: return "系统限制"
        case .notDetermined: return "尚未授权"
        @unknown default: return "暂不可用"
        }
    }
    func sync(store: EntryStore, requestAccess: Bool = false, manual: Bool = false) async {
        authorization = demo ? .fullAccess : EKEventStore.authorizationStatus(for: .event)
        if !store.calendarSync.enabled && !manual { message = "自动同步已关闭，可点立即同步手动导入。" }
        guard !isSyncing, !store.readOnly, store.calendarSync.enabled || manual else { return }
        guard !testing || demo else { return } // UI tests never inspect personal calendars.
        isSyncing = true
        error = nil
        defer { isSyncing = false }
        if !demo && requestAccess && (authorization == .notDetermined || authorization == .writeOnly) {
            do {
                _ = try await eventStore.requestFullAccessToEvents()
                authorization = EKEventStore.authorizationStatus(for: .event)
            } catch {
                self.error = "无法申请日历权限：\(error.localizedDescription)"
                return
            }
        }
        guard authorization == .fullAccess else {
            message = "允许读取日历后，打开 App 时自动导入。"
            return
        }
        guard store.calendarSync.enabled || manual else { return }
        let now = Date()
        let start = Calendar.current.startOfDay(for: now)
        let end = Calendar.current.date(byAdding: .day, value: 30, to: start)!
        let range = start..<end
        var events: [CalendarEventRecord]
        var queried: Set<String>
        if demo {
            _ = refreshChoices(store: store)
            let selection = calendars[0].selection
            guard initializeSelection(store: store) else { return }
            queried = Set(store.calendarSync.selected.map(\.id))
            events = queried.isEmpty ? [] : [CalendarEventRecord(
                identity: CalendarEventIdentity(calendarID: selection.id, calendarTitle: selection.title,
                                                sourceTitle: selection.sourceTitle, eventID: "demo-event"),
                title: "日历同步演示", start: demoStart, end: demoStart.addingTimeInterval(3600),
                notes: "来自系统日历的备注", location: "图书馆")]
        } else {
            let available = refreshChoices(store: store)
            guard initializeSelection(store: store) else { return }
            queried = Set(store.calendarSync.selected.map(\.id)).intersection(available.map(\.calendarIdentifier))
            guard !queried.isEmpty else { message = "请在下面选择要导入的日历。"; return }
            let selected = available.filter { queried.contains($0.calendarIdentifier) }
            let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: selected)
            let fetched = eventStore.events(matching: predicate)
            guard fetched.count <= 5000 else {
                error = "这段时间的日程过多，请减少勾选的日历后重试。"
                return
            }
            events = fetched.compactMap(Self.record)
        }
        guard !queried.isEmpty else { message = "请先选择要导入的日历。"; return }
        guard let result = store.importCalendarEvents(events, range: range, calendars: queried, availableCalendars: Set(calendars.map(\.id))) else {
            error = store.error ?? "本地数据暂不可写入。"
            return
        }
        lastSync = now
        message = result.added == 0 && result.updated == 0 ? "已同步，没有新的变更。" : "新增 \(result.added) 件，更新 \(result.updated) 件。"
    }
    func preparePlan(for entry: Entry) async throws -> CalendarPlanSession {
        guard !testing else { throw CalendarPlanError.unavailable("自动化测试不会写入个人日历。") }
        var state = EKEventStore.authorizationStatus(for: .event)
        if state == .notDetermined || state == .writeOnly {
            _ = try await eventStore.requestFullAccessToEvents()
            state = EKEventStore.authorizationStatus(for: .event)
        }
        authorization = state
        guard state == .fullAccess else { throw CalendarPlanError.unavailable("请在系统设置中允许 Mikansei 访问日历，然后重试。") }
        var event: EKEvent?
        if let link = entry.calendarEvent {
            let available = eventStore.calendars(for: .event)
            let matched = available.filter { $0.calendarIdentifier == link.event.identity.calendarID }
            let fallback = available.filter { $0.title == link.event.identity.calendarTitle && $0.source.title == link.event.identity.sourceTitle }
            let calendars = matched.isEmpty && fallback.count == 1 ? fallback : matched
            let predicate = eventStore.predicateForEvents(withStart: link.event.start.addingTimeInterval(-86400), end: link.event.end.addingTimeInterval(86400), calendars: calendars)
            let candidates = calendars.isEmpty ? [] : eventStore.events(matching: predicate).filter { candidate in
                Self.record(candidate)?.identity.matches(link.event.identity, knownCalendarIDs: Set(available.map(\.calendarIdentifier))) == true
            }
            guard candidates.count == 1 else { throw CalendarPlanError.unavailable("暂未找到原日历事件。请先同步日历；原事件可能已移动、删除或账号未加载。") }
            event = candidates[0]
            guard event?.calendar.allowsContentModifications == true else { throw CalendarPlanError.unavailable("此日历只允许读取，请在苹果日历中查看或联系日历提供者修改。") }
        }
        let target = event ?? EKEvent(eventStore: eventStore)
        if event == nil {
            guard let writable = eventStore.defaultCalendarForNewEvents, writable.allowsContentModifications else {
                throw CalendarPlanError.unavailable("尚无可写日历，请先在苹果日历中设置默认日历。")
            }
            target.calendar = writable
            let start = entry.plannedStart ?? Date(timeIntervalSince1970: (Date().addingTimeInterval(3600).timeIntervalSince1970 / 60).rounded(.up) * 60)
            target.startDate = start
            target.endDate = entry.plannedEnd ?? start.addingTimeInterval(Double(entry.estimatedMinutes ?? 30) * 60)
            target.isAllDay = entry.plannedAllDay
            target.alarms = [] // Mikansei controls reminders; avoid duplicate Calendar alerts.
        }
        target.title = entry.title; target.notes = entry.body; target.location = entry.location
        if let url = URL(string: entry.platform), ["https", "http"].contains(url.scheme?.lowercased() ?? "") { target.url = url }
        return CalendarPlanSession(entryID: entry.id, event: target, eventStore: eventStore)
    }
    @discardableResult
    func refreshChoices(store: EntryStore) -> [EKCalendar] {
        authorization = demo ? .fullAccess : EKEventStore.authorizationStatus(for: .event)
        guard !testing || demo, authorization == .fullAccess else { calendars = []; return [] }
        if demo {
            let selection = CalendarSelection(id: "calendar-demo", title: "学习", sourceTitle: "演示日历")
            calendars = [CalendarOption(selection: selection, color: .indigo, isBirthday: false)]
            return []
        }
        eventStore.reset()
        let available = eventStore.calendars(for: .event)
        calendars = available.map {
            CalendarOption(selection: CalendarSelection(id: $0.calendarIdentifier, title: $0.title, sourceTitle: $0.source.title),
                           color: Color(cgColor: $0.cgColor), isBirthday: $0.type == .birthday)
        }.sorted { ($0.selection.sourceTitle, $0.selection.title) < ($1.selection.sourceTitle, $1.selection.title) }
        return available
    }
    private func initializeSelection(store: EntryStore) -> Bool {
        var settings = store.calendarSync
        if !settings.selectionInitialized {
            guard !calendars.isEmpty else { return true }
            settings.selected = calendars.filter { !$0.isBirthday }.map(\.selection)
            settings.selectionInitialized = true
        } else {
            // EventKit calendar IDs can change after an account resync. Rebind only an unambiguous match.
            settings.selected = settings.selected.map { old in
                if let same = calendars.first(where: { $0.id == old.id }) { return same.selection }
                let matches = calendars.filter { $0.selection.title == old.title && $0.selection.sourceTitle == old.sourceTitle }
                return matches.count == 1 ? matches[0].selection : old
            }
            settings.selected = settings.selected.reduce(into: []) { result, choice in
                if !result.contains(where: { $0.id == choice.id }) { result.append(choice) }
            }
        }
        return store.saveCalendarSyncSettings(settings)
    }
    static func record(_ event: EKEvent) -> CalendarEventRecord? {
        guard let calendar = event.calendar, let rawStart = event.startDate, let rawEnd = event.endDate else { return nil }
        // Match the archive's whole-second ISO dates so subsecond values don't produce a change every launch.
        let start = Date(timeIntervalSince1970: rawStart.timeIntervalSince1970.rounded(.down))
        let end = Date(timeIntervalSince1970: rawEnd.timeIntervalSince1970.rounded(.down))
        let external = event.calendarItemExternalIdentifier
        let eventID = external?.isEmpty == false ? external! : event.calendarItemIdentifier
        var occurrence = ""
        if event.hasRecurrenceRules || event.isDetached {
            let original = event.occurrenceDate ?? start
            if event.isAllDay {
                let formatter = DateFormatter()
                formatter.calendar = Calendar(identifier: .gregorian)
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.dateFormat = "yyyy-MM-dd"
                occurrence = "day:\(formatter.string(from: original))"
            } else { occurrence = "time:\(Int64(original.timeIntervalSince1970.rounded()))" }
        }
        return CalendarEventRecord(identity: CalendarEventIdentity(calendarID: calendar.calendarIdentifier,
            calendarTitle: calendar.title, sourceTitle: calendar.source.title, eventID: eventID, occurrence: occurrence,
            localEventID: event.calendarItemIdentifier.isEmpty ? nil : event.calendarItemIdentifier),
            title: event.title ?? "", start: start, end: end, isAllDay: event.isAllDay, notes: event.notes ?? "",
            location: event.location ?? "", url: event.url?.absoluteString ?? "", isCancelled: event.status == .canceled)
    }
}

private enum CalendarPlanError: LocalizedError {
    case unavailable(String)
    var errorDescription: String? { if case .unavailable(let text) = self { return text }; return nil }
}
