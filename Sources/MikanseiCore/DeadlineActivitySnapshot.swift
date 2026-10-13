import Foundation

/// A small, private-details-free payload for the lock screen and Dynamic Island.
public struct DeadlineActivitySnapshot: Codable, Hashable, Sendable {
    public struct Item: Codable, Hashable, Identifiable, Sendable {
        public let id: UUID
        public let title: String
        public let deadline: Date?
        public let priority: Int
        public let isSchedule: Bool
    }
    public let items: [Item]
    public let totalCount: Int
    public let updatedAt: Date
    public let dayEnd: Date
    public let validUntil: Date

    public var primary: Item? { items.first }
    public static func make(entries: [Entry], now: Date = Date(), calendar: Calendar = .current) -> Self? {
        let board = TaskBoard(entries: entries, now: now, calendar: calendar)
        let remaining = board.focus.filter { !$0.isCompleted }.sorted { a, b in
            if a.priority != b.priority { return a.priority.rawValue > b.priority.rawValue }
            let left = (a.kind == .schedule ? a.plannedStart : a.dueDate) ?? .distantFuture
            let right = (b.kind == .schedule ? b.plannedStart : b.dueDate) ?? .distantFuture
            if left != right { return left < right }
            return TaskBoard.order(a, b)
        }
        guard !remaining.isEmpty,
              let dayEnd = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) else { return nil }
        let items = remaining.prefix(3).map {
            Item(id: $0.id, title: String($0.title.prefix(64)), deadline: $0.kind == .schedule ? $0.plannedStart : $0.dueDate,
                 priority: $0.priority.rawValue, isSchedule: $0.kind == .schedule)
        }
        return Self(items: items, totalCount: remaining.count, updatedAt: now, dayEnd: dayEnd,
                    validUntil: dayEnd)
    }
}
