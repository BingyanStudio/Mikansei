import Foundation

public enum EntryKind: String, CaseIterable, Codable, Identifiable {
    case task, schedule, homework, note
    public var id: Self { self }
    public var title: String {
        switch self {
        case .task: return "待办"
        case .schedule: return "日程"
        case .homework: return "作业"
        case .note: return "笔记"
        }
    }
    public var symbol: String {
        switch self {
        case .task: return "checkmark.circle"
        case .schedule: return "calendar"
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
    case never, daily, everyThreeDays, weekly, biweekly, monthly, custom, dates
    public var id: Self { self }
    public var days: Int {
        switch self { case .never, .monthly, .dates: return 0; case .daily, .custom: return 1; case .everyThreeDays: return 3; case .weekly: return 7; case .biweekly: return 14 }
    }
    public var title: String {
        switch self { case .never: return "不重复"; case .daily: return "每天"; case .everyThreeDays: return "每 3 天"; case .weekly: return "每周"; case .biweekly: return "每两周"; case .monthly: return "每月"; case .custom: return "自定义间隔"; case .dates: return "日历选日" }
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
    public var repeatWeekdays: [Int] = [] // ISO weekdays: Monday = 1.
    public var repeatIntervalMonths: Int = 1
    public var repeatDates: [Date] = []
    public var repeatAnchorDate: Date? = nil
    public var reminderPattern: ReminderPattern = .single
    public var previousOccurrenceID: UUID? = nil
    /// Cross-device routine identity. Provider series use a JSON array beginning with "calendar".
    public var routineSeriesID: String? = nil
    /// Original provider occurrence used for completion identity and chronological ordering.
    public var routineOccurrenceID: String? = nil
    public var startedAt: Date? = nil
    public var elapsedSeconds: TimeInterval = 0
    public var calendarEvent: CalendarEventLink? = nil
    /// 手动排序值，越小越靠前；nil 表示未排序，参与排序时视为最大。
    public var sortOrder: Int? = nil
    /// 规划的执行日期（按天），与 plannedStart 区间并列参与“今天要做”判定。
    public var plannedDays: [Date]? = nil
    /// 已从今日聚焦移入规划页；持续保留，直到用户手动恢复或重新安排。
    public var isInPlanning = false

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
        if kind == .schedule {
            plannedStart = dueDate ?? Date(timeIntervalSince1970: (createdAt.addingTimeInterval(3600).timeIntervalSince1970 / 60).rounded(.up) * 60)
            plannedEnd = plannedStart!.addingTimeInterval(1800)
            self.dueDate = nil
            self.reminder = reminder ?? .atTime
            reminderDelivery = .alarm
            reminderAnchor = .execution
        }
    }

    public var isTask: Bool { kind != .note }
    /// Routines include locally defined rules and source-managed calendar series.
    /// Provider occurrences remain individual entries for completion and checklist state.
    public var isRoutine: Bool { isLocalRoutine || isCalendarBackedRoutine }
    public var isLocalRoutine: Bool { isTask && repeatRule != .never }
    public var isCalendarBackedRoutine: Bool { isTask && (isRecurringCalendarOccurrence || isProviderRoutineSeries) }
    /// EventKit records a stable series event identifier plus a nonempty original occurrence.
    /// The full calendar/source scope avoids merging the same ICS identifier in copied calendars.
    public var isRecurringCalendarOccurrence: Bool {
        isTask && calendarEvent?.event.identity.occurrence.isEmpty == false
    }
    public var isRoutineSeriesMember: Bool {
        isRoutine || isRecurringCalendarOccurrence ||
            routineSeriesID?.isEmpty == false || routineOccurrenceID?.isEmpty == false
    }
    public var isProviderRoutineSeries: Bool {
        guard let routineSeriesID, let data = routineSeriesID.data(using: .utf8),
              let parts = try? JSONSerialization.jsonObject(with: data) as? [String],
              let mechanism = parts.first else { return false }
        return mechanism.caseInsensitiveCompare("calendar") == .orderedSame
    }
    public var allowsLocalSuccessorGeneration: Bool {
        isLocalRoutine && !isRecurringCalendarOccurrence && !isProviderRoutineSeries
    }
    public var repeatDays: Int { repeatRule == .custom ? max(1, repeatIntervalDays) : repeatRule.days }
    public var repeatLabel: String {
        if isCalendarBackedRoutine { return "日历来源重复" }
        if repeatRule == .dates { return "已选 \(Set(repeatDates.map { Calendar.current.startOfDay(for: $0) }).count) 天" }
        if repeatRule == .monthly { return "每 \(repeatIntervalMonths) 月" }
        if repeatRule == .weekly && !repeatWeekdays.isEmpty {
            let names = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]
            return repeatWeekdays.sorted().filter { (1...7).contains($0) }.map { names[$0 - 1] }.joined(separator: "、")
        }
        return repeatRule == .custom ? "每 \(repeatDays) 天" : repeatRule.title
    }
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
    public var attentionDate: Date? { kind == .schedule ? plannedStart : [dueDate, plannedStart].compactMap { $0 }.min() }
    /// Schedules belong to a day only while their execution interval covers it.
    /// Missing or invalid ends fall back to the start's local day.
    public func scheduleOccurs(on date: Date, calendar: Calendar = .current) -> Bool {
        guard kind == .schedule, let start = plannedStart,
              let day = calendar.dateInterval(of: .day, for: date) else { return false }
        guard let end = plannedEnd, end > start else {
            return calendar.isDate(start, inSameDayAs: date)
        }
        return start < day.end && end > day.start
    }
    public var reminderReferenceDate: Date? { kind == .schedule || reminderAnchor == .execution ? plannedStart ?? dueDate : dueDate ?? plannedStart }
    public var reminderDate: Date? {
        guard isTask, !isCompleted, let dueDate = reminderReferenceDate, let reminder else { return nil }
        return dueDate.addingTimeInterval(-Double(reminder.rawValue))
    }
    public func isOverdue(at now: Date = Date()) -> Bool {
        isTask && kind != .schedule && !isCompleted && dueDate.map { $0 < now } == true
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
        result.repeatIntervalMonths = max(1, min(12, repeatIntervalMonths))
        result.repeatWeekdays = Array(Set(repeatWeekdays.filter { (1...7).contains($0) })).sorted()
        result.repeatDates = Array(Set(repeatDates.map { Calendar.current.startOfDay(for: $0) })).sorted()
        result.plannedDays = plannedDays.map { Array(Set($0.map { Calendar.current.startOfDay(for: $0) })).sorted() }
        result.checklist = checklist.compactMap { step in
            let title = step.title.trimmingCharacters(in: .whitespacesAndNewlines)
            return title.isEmpty ? nil : ChecklistItem(id: step.id, title: title, isDone: step.isDone)
        }
        if kind == .note {
            result.dueDate = nil
            result.plannedStart = nil; result.plannedEnd = nil; result.plannedAllDay = false
            result.plannedDays = nil
            result.reminder = nil
            result.isCompleted = false
            result.completedAt = nil
            result.repeatRule = .never
            result.startedAt = nil
            result.elapsedSeconds = 0
            result.isInPlanning = false
        } else {
            if kind == .schedule {
                result.dueDate = nil
                result.reminderAnchor = .execution
                result.reminderPattern = .single
            }
            if result.attentionDate == nil { result.reminder = nil; result.repeatRule = .never }
            if result.isLocalRoutine && result.repeatAnchorDate == nil { result.repeatAnchorDate = result.recurrenceReferenceDate }
        }
        result.snoozeMinutes = [5, 10, 15].contains(snoozeMinutes) ? snoozeMinutes : 5
        result.updatedAt = now
        return result
    }

    public func nextOccurrence(after now: Date = Date(), calendar: Calendar = .current) -> Entry? {
        guard allowsLocalSuccessorGeneration, let base = recurrenceReferenceDate else { return nil }
        let upperBound = repeatRule == .dates
            ? repeatDates.max().flatMap { calendar.date(byAdding: .day, value: 1, to: $0) }
            : calendar.date(byAdding: .year, value: 5, to: max(now, base))
        guard let end = upperBound,
              end > max(now, base).addingTimeInterval(1),
              let nextDate = occurrenceDates(in: max(now, base).addingTimeInterval(1)..<end, calendar: calendar, limit: 1).first else { return nil }
        var next = occurrence(at: nextDate, calendar: calendar)
        next.id = UUID()
        next.previousOccurrenceID = id
        next.repeatAnchorDate = repeatAnchorDate ?? base
        next.createdAt = now
        next.updatedAt = now
        next.isCompleted = false
        next.completedAt = nil
        next.startedAt = nil
        next.elapsedSeconds = 0
        next.calendarEvent = nil
        next.isInPlanning = false
        next.checklist = checklist.map { ChecklistItem(title: $0.title) }
        return next
    }

    // Defaults allow archives produced by the first version to keep loading.
    private enum CodingKeys: String, CodingKey {
        case id, title, body, kind, category, priority, checklist, dueDate, reminder,
             isCompleted, completedAt, createdAt, updatedAt, platform, location,
             estimatedMinutes, source, repeatRule, repeatIntervalDays, repeatWeekdays, repeatIntervalMonths, repeatDates, repeatAnchorDate, reminderPattern, previousOccurrenceID, routineSeriesID, routineOccurrenceID, startedAt, elapsedSeconds, calendarEvent, plannedStart, plannedEnd, plannedAllDay, reminderDelivery, reminderAnchor, reminderSound, snoozeMinutes, sortOrder, plannedDays, isInPlanning
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
        repeatWeekdays = try c.decodeIfPresent([Int].self, forKey: .repeatWeekdays) ?? []
        repeatIntervalMonths = try c.decodeIfPresent(Int.self, forKey: .repeatIntervalMonths) ?? 1
        repeatDates = try c.decodeIfPresent([Date].self, forKey: .repeatDates) ?? []
        repeatAnchorDate = try c.decodeIfPresent(Date.self, forKey: .repeatAnchorDate)
        reminderPattern = try c.decodeIfPresent(ReminderPattern.self, forKey: .reminderPattern) ?? .single
        previousOccurrenceID = try c.decodeIfPresent(UUID.self, forKey: .previousOccurrenceID)
        routineSeriesID = try c.decodeIfPresent(String.self, forKey: .routineSeriesID)
        routineOccurrenceID = try c.decodeIfPresent(String.self, forKey: .routineOccurrenceID)
        if (routineSeriesID == nil || routineOccurrenceID == nil),
           let legacy = try? decoder.container(keyedBy: LegacyAndroidKeys.self),
           let android = try? legacy.decodeIfPresent(LegacyAndroidCalendarLink.self, forKey: .androidCalendarLink),
           let identity = Self.legacyProviderIdentity(android) {
            if routineSeriesID == nil { routineSeriesID = identity.seriesID }
            if routineOccurrenceID == nil { routineOccurrenceID = identity.occurrenceID }
        }
        startedAt = try c.decodeIfPresent(Date.self, forKey: .startedAt)
        elapsedSeconds = try c.decodeIfPresent(TimeInterval.self, forKey: .elapsedSeconds) ?? 0
        calendarEvent = try c.decodeIfPresent(CalendarEventLink.self, forKey: .calendarEvent)
        plannedStart = try c.decodeIfPresent(Date.self, forKey: .plannedStart)
        plannedEnd = try c.decodeIfPresent(Date.self, forKey: .plannedEnd)
        plannedAllDay = try c.decodeIfPresent(Bool.self, forKey: .plannedAllDay) ?? false
        sortOrder = try c.decodeIfPresent(Int.self, forKey: .sortOrder)
        plannedDays = try c.decodeIfPresent([Date].self, forKey: .plannedDays)
        isInPlanning = try c.decodeIfPresent(Bool.self, forKey: .isInPlanning) ?? false
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

    private enum LegacyAndroidKeys: String, CodingKey { case androidCalendarLink }
    private struct LegacyAndroidCalendarLink: Decodable {
        let deviceID: String?
        let key: String?
        let calendarID: String?
        let seriesID: String?
        let recurring: Bool?
        let originalOccurrence: String?
    }

    private struct LegacyProviderIdentity {
        let seriesID: String
        let occurrenceID: String
    }

    private static func legacyProviderIdentity(_ link: LegacyAndroidCalendarLink) -> LegacyProviderIdentity? {
        guard link.recurring != false else { return nil }
        let keyParts: (calendarID: String?, seriesID: String?, occurrence: String?)?
        if let key = link.key, let firstSlash = key.firstIndex(of: "/"),
           let lastSlash = key.lastIndex(of: "/"), firstSlash < lastSlash {
            keyParts = (nonempty(String(key[..<firstSlash])),
                        nonempty(String(key[key.index(after: firstSlash)..<lastSlash])),
                        nonempty(String(key[key.index(after: lastSlash)...])))
        } else {
            keyParts = nil
        }
        let keyOccurrence = keyParts?.occurrence
        let originalOccurrence = link.originalOccurrence.flatMap(nonempty)
        guard originalOccurrence?.caseInsensitiveCompare("single") != .orderedSame,
              keyOccurrence?.caseInsensitiveCompare("single") != .orderedSame else { return nil }
        let occurrence = originalOccurrence ?? keyOccurrence
        let numericOccurrence = occurrence.map(isSafeProviderOccurrence) == true
        guard link.recurring == true || numericOccurrence else { return nil }
        var calendarID = link.calendarID.flatMap(nonempty)
        var seriesID = link.seriesID.flatMap(nonempty)
        if let keyParts {
            if calendarID == nil { calendarID = keyParts.calendarID }
            if seriesID == nil, numericOccurrence { seriesID = keyParts.seriesID }
        }
        guard let calendarID, let seriesID, let occurrence,
              let data = try? JSONSerialization.data(
                withJSONObject: ["calendar", link.deviceID ?? "", calendarID, seriesID],
                options: [.withoutEscapingSlashes]
              ) else {
            return nil
        }
        guard let series = String(data: data, encoding: .utf8) else { return nil }
        return LegacyProviderIdentity(seriesID: series, occurrenceID: occurrence)
    }

    private static func isSafeProviderOccurrence(_ value: String) -> Bool {
        let digits = value.first == "-" ? value.dropFirst() : Substring(value)
        guard (9...19).contains(digits.count), digits.allSatisfy({ ("0"..."9").contains($0) }),
              let parsed = Double(value) else { return false }
        let milliseconds = value.count >= 12 ? parsed : parsed * 1000
        return milliseconds.isFinite && abs(milliseconds) <= 8_640_000_000_000_000
    }

    private static func nonempty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

public extension Entry {
    static func successorDates(in entries: [Entry]) -> [UUID: Date] {
        var result: [UUID: Date] = [:]
        for entry in entries {
            if let parent = entry.previousOccurrenceID, let date = entry.recurrenceReferenceDate {
                result[parent] = min(result[parent] ?? .distantFuture, date)
            }
        }
        return result
    }
    /// Routines retain a type (task or schedule); repetition is an independent tag.
    var recurrenceReferenceDate: Date? { kind == .schedule ? plannedStart : dueDate ?? plannedStart }

    func occurrenceDates(in range: Range<Date>, calendar: Calendar = .current, limit: Int = 1000) -> [Date] {
        guard isRoutine, let base = recurrenceReferenceDate, range.lowerBound < range.upperBound, limit > 0 else { return [] }
        let anchor = repeatAnchorDate ?? base
        let anchorDay = calendar.startOfDay(for: anchor)
        let anchorMonth = calendar.dateInterval(of: .month, for: anchor)!.start
        let time = calendar.dateComponents([.hour, .minute, .second], from: base)
        let chosen = Set(repeatDates.map { calendar.startOfDay(for: $0) })
        if repeatRule == .dates {
            return Array(chosen.sorted().compactMap { day in
                calendar.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: time.second ?? 0, of: day)
            }.filter { $0 >= base && range.contains($0) }.prefix(limit))
        }
        var day = calendar.startOfDay(for: max(base, range.lowerBound))
        var dates: [Date] = []
        while day < range.upperBound && dates.count < limit {
            let gap = calendar.dateComponents([.day], from: anchorDay, to: day).day ?? -1
            let weekday = (calendar.component(.weekday, from: day) + 5) % 7 + 1
            var matches = false
            switch repeatRule {
            case .never: break
            case .dates: matches = chosen.contains(day)
            case .monthly:
                let month = calendar.dateInterval(of: .month, for: day)!.start
                let months = calendar.dateComponents([.month], from: anchorMonth, to: month).month ?? -1
                let lastDay = calendar.range(of: .day, in: .month, for: day)!.count
                matches = months >= 0 && months % max(1, repeatIntervalMonths) == 0 &&
                    calendar.component(.day, from: day) == min(calendar.component(.day, from: anchor), lastDay)
            case .weekly where !repeatWeekdays.isEmpty:
                matches = gap >= 0 && repeatWeekdays.contains(weekday)
            default:
                matches = gap >= 0 && gap % max(1, repeatDays) == 0
            }
            if matches, let value = calendar.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0,
                                                  second: time.second ?? 0, of: day),
               value >= base, range.contains(value) { dates.append(value) }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day), next > day else { break }
            day = next
        }
        return dates
    }

    /// Keep wall-clock times across DST; timed schedules preserve their elapsed duration.
    func occurrence(at date: Date, calendar: Calendar = .current) -> Entry {
        guard let base = recurrenceReferenceDate else { return self }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: base), to: calendar.startOfDay(for: date)).day ?? 0
        var next = self
        next.dueDate = dueDate.flatMap { calendar.date(byAdding: .day, value: days, to: $0) }
        next.plannedStart = plannedStart.flatMap { calendar.date(byAdding: .day, value: days, to: $0) }
        if let start = next.plannedStart, let oldStart = plannedStart, let oldEnd = plannedEnd {
            next.plannedEnd = plannedAllDay ? calendar.date(byAdding: .day, value: days, to: oldEnd) : start.addingTimeInterval(oldEnd.timeIntervalSince(oldStart))
        }
        return next
    }
}

public struct TaskBoard {
    public let entries: [Entry]
    public let now: Date
    public let calendar: Calendar
    private let openEntries: [Entry]
    private let focusOpenEntries: [Entry]
    public init(entries: [Entry], now: Date = Date(), calendar: Calendar = .current) {
        self.entries = entries
        self.now = now
        self.calendar = calendar
        self.openEntries = Self.frontierOpenEntries(entries, calendar: calendar)
        self.focusOpenEntries = Self.frontierOpenEntries(entries, prioritizingSchedulesOn: now, calendar: calendar)
    }
    public var open: [Entry] { openEntries }
    public var routines: [Entry] {
        open.filter(\.isRoutineSeriesMember) + finishedToday.filter(\.isRoutineSeriesMember)
    }
    public var overdue: [Entry] { open.filter { $0.isOverdue(at: now) } }
    public var today: [Entry] {
        return focusOpenEntries.filter { entry in
            guard !entry.isOverdue(at: now) else { return false }
            if entry.kind == .schedule { return entry.scheduleOccurs(on: now, calendar: calendar) }
            let day = calendar.startOfDay(for: now)
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: day)!
            return entry.dueDate.map { calendar.isDate($0, inSameDayAs: now) } == true ||
                (entry.plannedStart.map { $0 < tomorrow } == true && entry.plannedEnd.map { $0 > day } == true) ||
                entry.plannedDays?.contains { calendar.isDate($0, inSameDayAs: now) } == true
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
    public var unplannedOrPast: [Entry] {
        let todayIDs = Set(today.map(\.id))
        let start = calendar.startOfDay(for: now)
        return open.filter { entry in !entry.isOverdue(at: now) && !todayIDs.contains(entry.id) && (entry.attentionDate == nil || entry.attentionDate! < start) }
    }
    public var focusToday: [Entry] {
        focusOpenEntries.filter { entry in
            guard !entry.isOverdue(at: now) else { return false }
            if entry.kind == .schedule { return entry.scheduleOccurs(on: now, calendar: calendar) }
            let day = calendar.startOfDay(for: now)
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: day)!
            return entry.dueDate.map { calendar.isDate($0, inSameDayAs: now) } == true ||
                (entry.plannedStart.map { $0 < tomorrow } == true && entry.plannedEnd.map { $0 > day } == true) ||
                entry.plannedDays?.contains { calendar.isDate($0, inSameDayAs: now) } == true
        }
    }
    public var focus: [Entry] {
        let focusOverdue = focusOpenEntries.filter { $0.isOverdue(at: now) }
        let currentDayEntries = focusToday
        let focusTodayIDs = Set(currentDayEntries.map(\.id))
        let dayStart = calendar.startOfDay(for: now)
        let focusUnplannedOrPast = focusOpenEntries.filter { entry in
            entry.kind != .schedule && !entry.isOverdue(at: now) && !focusTodayIDs.contains(entry.id) &&
                (entry.attentionDate == nil || entry.attentionDate! < dayStart)
        }
        let focusFinishedToday = finishedToday.filter {
            $0.kind != .schedule || $0.scheduleOccurs(on: now, calendar: calendar)
        }
        return (focusOverdue + currentDayEntries + focusUnplannedOrPast + focusFinishedToday).filter { !$0.isInPlanning }
    }
    public var completedToday: Int { finishedToday.count }

    private struct CalendarSeriesKey: Hashable {
        let calendarID: String
        let sourceTitle: String
        let eventID: String
    }

    private enum OccurrenceKey: Hashable {
        case calendar(String)
        case providerOccurrence(String)
        case provider(Date)
        case local(UUID?, Date)
    }

    private struct CompletedOccurrence: Hashable {
        let family: UUID
        let occurrence: OccurrenceKey
    }

    /// Lists expose one actionable point per routine while retaining every source occurrence in `entries`.
    private static func frontierOpenEntries(
        _ entries: [Entry],
        prioritizingSchedulesOn date: Date? = nil,
        calendar: Calendar
    ) -> [Entry] {
        let tasks = entries.filter(\.isTask)
        guard !tasks.isEmpty else { return [] }

        var parents: [UUID: UUID] = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0.id) })
        var ranks: [UUID: UInt8] = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, 0) })
        func root(_ id: UUID) -> UUID {
            var current = id
            var path: [UUID] = []
            while let parent = parents[current], parent != current {
                path.append(current)
                current = parent
            }
            let top = current
            for node in path { parents[node] = top }
            return top
        }
        func union(_ a: UUID, _ b: UUID) {
            let ra = root(a), rb = root(b)
            guard ra != rb else { return }
            let rankA = ranks[ra] ?? 0, rankB = ranks[rb] ?? 0
            if rankA < rankB { parents[ra] = rb }
            else {
                parents[rb] = ra
                if rankA == rankB { ranks[ra] = rankA &+ 1 }
            }
        }

        // Only explicit lineage is used. Missing parents still group their successors together.
        for entry in tasks {
            guard let previous = entry.previousOccurrenceID else { continue }
            parents[previous] = parents[previous] ?? previous
            union(entry.id, previous)
        }

        var calendarSeries: [CalendarSeriesKey: UUID] = [:]
        for entry in tasks {
            guard entry.isRecurringCalendarOccurrence, let identity = entry.calendarEvent?.event.identity else { continue }
            let key = CalendarSeriesKey(calendarID: identity.calendarID, sourceTitle: identity.sourceTitle,
                                        eventID: identity.eventID)
            if let first = calendarSeries[key] { union(entry.id, first) }
            else { calendarSeries[key] = entry.id }
        }
        var sharedSeries: [String: UUID] = [:]
        for entry in tasks {
            guard let seriesID = entry.routineSeriesID, !seriesID.isEmpty else { continue }
            if let first = sharedSeries[seriesID] { union(entry.id, first) }
            else { sharedSeries[seriesID] = entry.id }
        }

        let completedEntries = tasks.filter(\.isCompleted)
        let completedOccurrences = Set(completedEntries.map {
            CompletedOccurrence(family: root($0.id),
                                occurrence: duplicateOccurrenceKey($0, calendar: calendar))
        })
        let open = tasks.filter { entry in
            guard !entry.isCompleted else { return false }
            let key = CompletedOccurrence(family: root(entry.id),
                                          occurrence: duplicateOccurrenceKey(entry, calendar: calendar))
            guard completedOccurrences.contains(key) else { return true }
            return false
        }
        let grouped = Dictionary(grouping: open) { root($0.id) }
        let frontier = grouped.values.compactMap { members -> Entry? in
            let ids = Set(members.map(\.id))
            let roots = members.filter { entry in
                guard let previous = entry.previousOccurrenceID else { return true }
                return !ids.contains(previous)
            }
            let candidates = roots.isEmpty ? members : roots
            // Calendar providers can deliver recurring occurrences as independent
            // records. Prefer today's actual schedule so an older occurrence cannot
            // mask it in the focus board.
            if let date,
               let current = members.filter({ $0.scheduleOccurs(on: date, calendar: calendar) })
                    .min(by: { frontierOrder($0, $1, calendar: calendar) }) {
                return current
            }
            return candidates.min { lhs, rhs in
                frontierOrder(lhs, rhs, calendar: calendar)
            }
        }
        return frontier.sorted(by: order)
    }

    private static func frontierOrder(_ lhs: Entry, _ rhs: Entry, calendar: Calendar) -> Bool {
        let leftDate = logicalOccurrenceDate(lhs, calendar: calendar)
        let rightDate = logicalOccurrenceDate(rhs, calendar: calendar)
        if leftDate != rightDate { return leftDate < rightDate }
        if (lhs.startedAt != nil) != (rhs.startedAt != nil) { return lhs.startedAt != nil }
        if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func logicalOccurrenceDate(_ entry: Entry, calendar: Calendar) -> Date {
        if let occurrence = entry.calendarEvent?.event.identity.occurrence,
           let date = providerOccurrenceDate(occurrence, calendar: calendar) {
            return date
        }
        if let occurrence = entry.routineOccurrenceID,
           let date = providerOccurrenceDate(occurrence, calendar: calendar) {
            return date
        }
        return entry.attentionDate ?? entry.createdAt
    }

    private static func providerOccurrenceDate(_ occurrence: String, calendar: Calendar) -> Date? {
        if occurrence.hasPrefix("time:"), let seconds = TimeInterval(occurrence.dropFirst(5)),
           seconds.isFinite, abs(seconds) <= 8_640_000_000_000 {
            return Date(timeIntervalSince1970: seconds)
        }
        if occurrence.hasPrefix("day:") {
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = calendar.timeZone
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.date(from: String(occurrence.dropFirst(4)))
        }
        let digits = occurrence.first == "-" ? occurrence.dropFirst() : Substring(occurrence)
        guard (9...19).contains(digits.count), digits.allSatisfy({ ("0"..."9").contains($0) }),
              let value = Double(occurrence) else { return nil }
        let milliseconds = occurrence.count >= 12 ? value : value * 1000
        guard milliseconds.isFinite, abs(milliseconds) <= 8_640_000_000_000_000 else { return nil }
        return Date(timeIntervalSince1970: milliseconds / 1000)
    }

    private static func duplicateOccurrenceKey(_ entry: Entry, calendar: Calendar) -> OccurrenceKey {
        if entry.isRecurringCalendarOccurrence, let occurrence = entry.calendarEvent?.event.identity.occurrence {
            return .calendar(occurrence)
        }
        if let occurrence = entry.routineOccurrenceID, !occurrence.isEmpty {
            return .providerOccurrence(occurrence)
        }
        let date = logicalOccurrenceDate(entry, calendar: calendar)
        if entry.isProviderRoutineSeries { return .provider(date) }
        return .local(entry.previousOccurrenceID, date)
    }

    public static func order(_ lhs: Entry, _ rhs: Entry) -> Bool {
        // 手动排序优先；未设置的被视为最大，仍按原规则比较。
        if lhs.sortOrder ?? Int.max != rhs.sortOrder ?? Int.max { return (lhs.sortOrder ?? Int.max) < (rhs.sortOrder ?? Int.max) }
        if lhs.priority != rhs.priority { return lhs.priority.rawValue > rhs.priority.rawValue }
        if lhs.attentionDate != rhs.attentionDate { return (lhs.attentionDate ?? .distantFuture) < (rhs.attentionDate ?? .distantFuture) }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
