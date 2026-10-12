import Foundation

public enum EntryKind: String, CaseIterable, Codable, Identifiable {
    case task, homework, note
    public var id: Self { self }
    public var title: String {
        switch self {
        case .task: return "待办"
        case .homework: return "作业"
        case .note: return "笔记"
        }
    }
    public var symbol: String {
        switch self {
        case .task: return "checkmark.circle"
        case .homework: return "book.closed"
        case .note: return "note.text"
        }
    }
}

public enum EntryPriority: Int, CaseIterable, Codable, Identifiable {
    case normal = 0, important = 1, urgent = 2
    public var id: Self { self }
    public var title: String {
        switch self {
        case .normal: return "普通"
        case .important: return "重要"
        case .urgent: return "紧急"
        }
    }
}

public enum ReminderLead: Int, CaseIterable, Codable, Identifiable {
    case atTime = 0, fiveMinutes = 300, fifteenMinutes = 900, oneHour = 3600, oneDay = 86400
    public var id: Self { self }
    public var title: String {
        switch self {
        case .atTime: return "到点提醒"
        case .fiveMinutes: return "提前 5 分钟"
        case .fifteenMinutes: return "提前 15 分钟"
        case .oneHour: return "提前 1 小时"
        case .oneDay: return "提前 1 天"
        }
    }
}

public enum RepeatRule: String, CaseIterable, Codable, Identifiable {
    case never, daily, everyThreeDays, weekly, biweekly, custom
    public var id: Self { self }
    public var days: Int {
        switch self { case .never: return 0; case .daily, .custom: return 1; case .everyThreeDays: return 3; case .weekly: return 7; case .biweekly: return 14 }
    }
    public var title: String {
        switch self { case .never: return "不重复"; case .daily: return "每天"; case .everyThreeDays: return "每 3 天"; case .weekly: return "每周"; case .biweekly: return "每两周"; case .custom: return "自定义间隔" }
    }
}

public enum ReminderPattern: String, CaseIterable, Codable, Identifiable {
    case single, stepped, persistent
    public var id: Self { self }
    public var title: String {
        switch self { case .single: return "单次提醒"; case .stepped: return "分阶段催办"; case .persistent: return "逾期持续催办" }
    }
    public var explanation: String {
        switch self {
        case .single: return "按选择的提前时间提醒一次。"
        case .stepped: return "截止前一天、两小时、到点及逾期两小时各提醒一次。"
        case .persistent: return "分阶段提醒后，每两小时催办一次，持续至截止后 24 小时。完成后取消后续提醒。"
        }
    }
}

public struct ChecklistItem: Identifiable, Codable, Equatable {
    public var id: UUID
    public var title: String
    public var isDone: Bool
    public init(id: UUID = UUID(), title: String, isDone: Bool = false) {
        self.id = id
        self.title = title
        self.isDone = isDone
    }
}

public struct Entry: Identifiable, Codable, Equatable {
    public var id: UUID
    public var title: String
    public var body: String
    public var kind: EntryKind
    public var category: String
    public var priority: EntryPriority
    public var checklist: [ChecklistItem]
    public var dueDate: Date?
    public var plannedStart: Date? = nil
    public var plannedEnd: Date? = nil
    public var plannedAllDay = false
    public var reminderDelivery: ReminderDelivery = .popup
    public var reminderAnchor: ReminderAnchor = .deadline
    public var reminderSound: ReminderSound = .system
    public var snoozeMinutes = 5
    public var reminder: ReminderLead?
    public var isCompleted: Bool
    public var completedAt: Date?
    public var createdAt: Date
    public var updatedAt: Date
    public var platform: String = ""
    public var location: String = ""
    public var estimatedMinutes: Int? = nil
    public var source: String = ""
    public var repeatRule: RepeatRule = .never
    public var repeatIntervalDays: Int = 1
    public var reminderPattern: ReminderPattern = .single
    public var previousOccurrenceID: UUID? = nil
    public var startedAt: Date? = nil
    public var elapsedSeconds: TimeInterval = 0
    public var calendarEvent: CalendarEventLink? = nil

    public init(id: UUID = UUID(), title: String = "", body: String = "",
                kind: EntryKind = .task, category: String = "",
                priority: EntryPriority = .normal, checklist: [ChecklistItem] = [],
                dueDate: Date? = nil, reminder: ReminderLead? = nil,
                isCompleted: Bool = false, completedAt: Date? = nil,
                createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.body = body
        self.kind = kind
        self.category = category
        self.priority = priority
        self.checklist = checklist
        self.dueDate = dueDate
        self.reminder = reminder
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var isTask: Bool { kind != .note }
    public var repeatDays: Int { repeatRule == .custom ? max(1, repeatIntervalDays) : repeatRule.days }
    public var repeatLabel: String { repeatRule == .custom ? "每 \(repeatDays) 天" : repeatRule.title }
    public var completedSteps: Int { checklist.filter(\.isDone).count }
    public var progress: Double {
        checklist.isEmpty ? (isCompleted ? 1 : 0) : Double(completedSteps) / Double(checklist.count)
    }
    public func focusDuration(at now: Date = Date()) -> TimeInterval {
        max(0, elapsedSeconds) + (startedAt.map { max(0, now.timeIntervalSince($0)) } ?? 0)
    }
    public func focusTimeLabel(at now: Date = Date()) -> String {
        let seconds = Int(min(focusDuration(at: now), TimeInterval(Int.max / 2)))
        return seconds >= 3600
            ? String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
            : String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
    public mutating func pauseFocus(at now: Date = Date()) {
        guard startedAt != nil else { return }
        elapsedSeconds = focusDuration(at: now)
        startedAt = nil
        updatedAt = now
    }
    public var attentionDate: Date? { [dueDate, plannedStart].compactMap { $0 }.min() }
    public var reminderReferenceDate: Date? { reminderAnchor == .execution ? plannedStart ?? dueDate : dueDate ?? plannedStart }
    public var reminderDate: Date? {
        guard isTask, !isCompleted, let dueDate = reminderReferenceDate, let reminder else { return nil }
        return dueDate.addingTimeInterval(-Double(reminder.rawValue))
    }
    public func isOverdue(at now: Date = Date()) -> Bool {
        isTask && !isCompleted && dueDate.map { $0 < now } == true
    }
    public func matches(_ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return q.isEmpty || ([title, body, category, platform, location, source] + checklist.map(\.title)).contains {
            $0.localizedCaseInsensitiveContains(q)
        }
    }
    public mutating func setCompleted(_ done: Bool, at now: Date = Date()) {
        isCompleted = done
        completedAt = done ? now : nil
        if done { pauseFocus(at: now) }
        updatedAt = now
        // Marking the parent complete checks every step; reopening preserves step history.
        if done {
            for index in checklist.indices { checklist[index].isDone = true }
        }
    }
    public mutating func toggleStep(_ id: UUID, at now: Date = Date()) {
        guard let index = checklist.firstIndex(where: { $0.id == id }) else { return }
        checklist[index].isDone.toggle()
        if !checklist[index].isDone && isCompleted {
            isCompleted = false
            completedAt = nil
        }
        updatedAt = now
    }
    public func normalized(at now: Date = Date()) -> Entry {
        var result = self
        result.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        result.category = category.trimmingCharacters(in: .whitespacesAndNewlines)
        result.platform = platform.trimmingCharacters(in: .whitespacesAndNewlines)
        result.location = location.trimmingCharacters(in: .whitespacesAndNewlines)
        result.repeatIntervalDays = max(1, min(365, repeatIntervalDays))
        result.checklist = checklist.compactMap { step in
            let title = step.title.trimmingCharacters(in: .whitespacesAndNewlines)
            return title.isEmpty ? nil : ChecklistItem(id: step.id, title: title, isDone: step.isDone)
        }
        if kind == .note {
            result.dueDate = nil
            result.plannedStart = nil; result.plannedEnd = nil; result.plannedAllDay = false
            result.reminder = nil
            result.isCompleted = false
            result.completedAt = nil
            result.repeatRule = .never
            result.startedAt = nil
            result.elapsedSeconds = 0
        } else {
            if attentionDate == nil { result.reminder = nil }
            if dueDate == nil { result.repeatRule = .never }
        }
        result.snoozeMinutes = [5, 10, 15].contains(snoozeMinutes) ? snoozeMinutes : 5
        result.updatedAt = now
        return result
    }

    public func nextOccurrence(after now: Date = Date(), calendar: Calendar = .current) -> Entry? {
        guard isTask, repeatRule != .never, let dueDate else { return nil }
        let gap = max(0, calendar.dateComponents([.day], from: dueDate, to: now).day ?? 0)
        var nextDate = calendar.date(byAdding: .day, value: (gap / repeatDays + 1) * repeatDays, to: dueDate)!
        if nextDate <= now { nextDate = calendar.date(byAdding: .day, value: repeatDays, to: nextDate)! }
        var next = self
        next.id = UUID()
        next.previousOccurrenceID = id
        next.dueDate = nextDate
        next.createdAt = now
        next.updatedAt = now
        next.isCompleted = false
        next.completedAt = nil
        next.startedAt = nil
        next.elapsedSeconds = 0
        next.calendarEvent = nil
        next.plannedStart = nil; next.plannedEnd = nil; next.plannedAllDay = false
        next.checklist = checklist.map { ChecklistItem(title: $0.title) }
        return next
    }

    // Defaults allow archives produced by the first version to keep loading.
    private enum CodingKeys: String, CodingKey {
        case id, title, body, kind, category, priority, checklist, dueDate, reminder,
             isCompleted, completedAt, createdAt, updatedAt, platform, location,
             estimatedMinutes, source, repeatRule, repeatIntervalDays, reminderPattern, previousOccurrenceID, startedAt, elapsedSeconds, calendarEvent, plannedStart, plannedEnd, plannedAllDay, reminderDelivery, reminderAnchor, reminderSound, snoozeMinutes
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        body = try c.decode(String.self, forKey: .body)
        kind = try c.decode(EntryKind.self, forKey: .kind)
        category = try c.decode(String.self, forKey: .category)
        priority = try c.decode(EntryPriority.self, forKey: .priority)
        checklist = try c.decode([ChecklistItem].self, forKey: .checklist)
        dueDate = try c.decodeIfPresent(Date.self, forKey: .dueDate)
        reminder = try c.decodeIfPresent(ReminderLead.self, forKey: .reminder)
        isCompleted = try c.decode(Bool.self, forKey: .isCompleted)
        completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        platform = try c.decodeIfPresent(String.self, forKey: .platform) ?? ""
        location = try c.decodeIfPresent(String.self, forKey: .location) ?? ""
        estimatedMinutes = try c.decodeIfPresent(Int.self, forKey: .estimatedMinutes)
        source = try c.decodeIfPresent(String.self, forKey: .source) ?? ""
        repeatRule = try c.decodeIfPresent(RepeatRule.self, forKey: .repeatRule) ?? .never
        repeatIntervalDays = try c.decodeIfPresent(Int.self, forKey: .repeatIntervalDays) ?? 1
        reminderPattern = try c.decodeIfPresent(ReminderPattern.self, forKey: .reminderPattern) ?? .single
        previousOccurrenceID = try c.decodeIfPresent(UUID.self, forKey: .previousOccurrenceID)
        startedAt = try c.decodeIfPresent(Date.self, forKey: .startedAt)
        elapsedSeconds = try c.decodeIfPresent(TimeInterval.self, forKey: .elapsedSeconds) ?? 0
        calendarEvent = try c.decodeIfPresent(CalendarEventLink.self, forKey: .calendarEvent)
        plannedStart = try c.decodeIfPresent(Date.self, forKey: .plannedStart)
        plannedEnd = try c.decodeIfPresent(Date.self, forKey: .plannedEnd)
        plannedAllDay = try c.decodeIfPresent(Bool.self, forKey: .plannedAllDay) ?? false
        reminderDelivery = try c.decodeIfPresent(ReminderDelivery.self, forKey: .reminderDelivery) ?? .popup
        reminderAnchor = try c.decodeIfPresent(ReminderAnchor.self, forKey: .reminderAnchor) ?? .deadline
        reminderSound = try c.decodeIfPresent(ReminderSound.self, forKey: .reminderSound) ?? .system
        snoozeMinutes = try c.decodeIfPresent(Int.self, forKey: .snoozeMinutes) ?? 5
        // Migrate calendar imports whose start time used to be stored as a deadline.
        if !c.contains(.plannedAllDay), isTask, let link = calendarEvent {
            plannedStart = link.event.start; plannedEnd = link.event.end; plannedAllDay = link.event.isAllDay
            let oldDue = link.event.isAllDay ? max(link.event.start, link.event.end.addingTimeInterval(-1)) : link.timing == .start ? link.event.start : link.event.end
            if link.timing == .start, dueDate == oldDue { dueDate = nil }
        }
    }
}

public struct TaskBoard {
    public let entries: [Entry]
    public let now: Date
    public let calendar: Calendar
    public init(entries: [Entry], now: Date = Date(), calendar: Calendar = .current) {
        self.entries = entries
        self.now = now
        self.calendar = calendar
    }
    public var open: [Entry] { entries.filter { $0.isTask && !$0.isCompleted }.sorted(by: Self.order) }
    public var overdue: [Entry] { open.filter { $0.isOverdue(at: now) } }
    public var today: [Entry] {
        let day = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: day)!
        return open.filter { entry in
            !entry.isOverdue(at: now) && (entry.dueDate.map { calendar.isDate($0, inSameDayAs: now) } == true ||
                (entry.plannedStart.map { $0 < tomorrow } == true && entry.plannedEnd.map { $0 > day } == true))
        }
    }
    public var upcoming: [Entry] {
        open.filter {  $0.attentionDate.map { $0 > now && !calendar.isDate($0, inSameDayAs: now) } == true }
    }
    public var unscheduled: [Entry] { open.filter { $0.attentionDate == nil } }
    public var finishedToday: [Entry] {
        entries.filter { $0.isTask && $0.isCompleted && $0.completedAt.map { calendar.isDate($0, inSameDayAs: now) } == true }
            .sorted {
                if $0.completedAt != $1.completedAt { return ($0.completedAt ?? .distantPast) < ($1.completedAt ?? .distantPast) }
                return $0.id.uuidString < $1.id.uuidString
            }
    }
    public var history: [Entry] {
        entries.filter { $0.isTask && $0.isCompleted && $0.completedAt.map { !calendar.isDate($0, inSameDayAs: now) } != false }
            .sorted {
                if $0.completedAt != $1.completedAt { return ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
                return $0.id.uuidString < $1.id.uuidString
            }
    }
    public var visible: [Entry] { overdue + open.filter { !$0.isOverdue(at: now) } + finishedToday }
    public var unplannedOrPast: [Entry] { open.filter { entry in !entry.isOverdue(at: now) && !today.contains(where: { $0.id == entry.id }) && (entry.attentionDate == nil || entry.attentionDate! < calendar.startOfDay(for: now)) } }
    public var focus: [Entry] { overdue + today + unplannedOrPast + finishedToday }
    public var completedToday: Int { finishedToday.count }
    public static func order(_ lhs: Entry, _ rhs: Entry) -> Bool {
        if lhs.priority != rhs.priority { return lhs.priority.rawValue > rhs.priority.rawValue }
        if lhs.attentionDate != rhs.attentionDate { return (lhs.attentionDate ?? .distantFuture) < (rhs.attentionDate ?? .distantFuture) }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
