import Foundation

/// Only the information displayed by widgets; notes, source messages and checklist bodies stay in the app.
public struct WidgetSnapshot: Codable {
    public let version: Int
    public let savedAt: Date
    public let tasks: [TaskSummary]

    public init(entries: [Entry], now: Date = Date(), calendar: Calendar = .current) {
        version = 1
        savedAt = now
        let board = TaskBoard(entries: entries, now: now, calendar: calendar)
        tasks = (board.open + board.finishedToday).map(TaskSummary.init)
    }

    public func board(at date: Date, calendar: Calendar = .current) -> TaskBoard {
        TaskBoard(entries: tasks.map(\.entry), now: date, calendar: calendar)
    }
    public func focusedTask(at date: Date = Date(), calendar: Calendar = .current) -> Entry? {
        let board = board(at: date, calendar: calendar)
        let entries = board.open + board.finishedToday
        if let active = entries.filter({ !$0.isCompleted && $0.startedAt != nil }).max(by: { $0.startedAt! < $1.startedAt! }) {
            return active
        }
        return entries.filter { $0.elapsedSeconds > 0 }.max(by: { $0.updatedAt < $1.updatedAt })
    }
    /// 最近的规划时段：开始时间在未来 60 分钟内的最早未完成任务，供锁屏倒计时使用。
    public func nextPlannedBlock(at date: Date = Date()) -> Entry? {
        tasks.filter { !$0.isCompleted && $0.plannedStart.map { $0 > date && $0 <= date.addingTimeInterval(3600) } == true }
            .min { ($0.plannedStart ?? .distantFuture) < ($1.plannedStart ?? .distantFuture) }?.entry
    }

    public struct TaskSummary: Codable {
        public let id: UUID
        public let title: String
        public let kind: EntryKind
        public let priority: EntryPriority
        public let dueDate: Date?
        public let plannedStart: Date?
        public let plannedEnd: Date?
        public let plannedAllDay: Bool
        public let isCompleted: Bool
        public let completedAt: Date?
        public let createdAt: Date
        public let startedAt: Date?
        public let elapsedSeconds: TimeInterval
        public let updatedAt: Date

        init(_ entry: Entry) {
            id = entry.id; title = String(entry.title.prefix(160)); kind = entry.kind
            priority = entry.priority; dueDate = entry.dueDate; plannedStart = entry.plannedStart; plannedEnd = entry.plannedEnd; plannedAllDay = entry.plannedAllDay; isCompleted = entry.isCompleted
            completedAt = entry.completedAt; createdAt = entry.createdAt; startedAt = entry.startedAt
            elapsedSeconds = entry.elapsedSeconds; updatedAt = entry.updatedAt
        }
        public var entry: Entry {
            var value = Entry(id: id, title: title, kind: kind, priority: priority, dueDate: dueDate,
                              isCompleted: isCompleted, completedAt: completedAt, createdAt: createdAt, updatedAt: updatedAt)
            value.plannedStart = plannedStart; value.plannedEnd = plannedEnd; value.plannedAllDay = plannedAllDay
            value.startedAt = startedAt
            value.elapsedSeconds = elapsedSeconds
            return value
        }
        private enum CodingKeys: String, CodingKey {
            case id, title, kind, priority, dueDate, isCompleted, completedAt, createdAt, startedAt, elapsedSeconds, updatedAt, plannedStart, plannedEnd, plannedAllDay
        }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(UUID.self, forKey: .id); title = try c.decode(String.self, forKey: .title)
            kind = try c.decode(EntryKind.self, forKey: .kind); priority = try c.decode(EntryPriority.self, forKey: .priority)
            dueDate = try c.decodeIfPresent(Date.self, forKey: .dueDate)
            plannedStart = try c.decodeIfPresent(Date.self, forKey: .plannedStart)
            plannedEnd = try c.decodeIfPresent(Date.self, forKey: .plannedEnd)
            plannedAllDay = try c.decodeIfPresent(Bool.self, forKey: .plannedAllDay) ?? false
            isCompleted = try c.decode(Bool.self, forKey: .isCompleted)
            completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
            createdAt = try c.decode(Date.self, forKey: .createdAt)
            startedAt = try c.decodeIfPresent(Date.self, forKey: .startedAt)
            elapsedSeconds = try c.decodeIfPresent(TimeInterval.self, forKey: .elapsedSeconds) ?? 0
            updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        }
    }
}
