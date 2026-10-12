import Foundation

public struct CalendarDisplayItem: Identifiable, Equatable {
    public enum Kind { case execution, deadline }
    public let entry: Entry
    public let kind: Kind
    public let date: Date
    public let end: Date?
    public var id: String { entry.id.uuidString + (kind == .execution ? ".execution" : ".deadline") }
    public var isAllDay: Bool { kind == .execution && entry.plannedAllDay }
}

public enum CalendarDisplay {
    public static func monthDays(containing date: Date, calendar: Calendar = .current) -> [Date] {
        guard let month = calendar.dateInterval(of: .month, for: date) else { return [] }
        let offset = (calendar.component(.weekday, from: month.start) - calendar.firstWeekday + 7) % 7
        guard let start = calendar.date(byAdding: .day, value: -offset, to: month.start) else { return [] }
        return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }
    public static func items(on date: Date, entries: [Entry], showCompleted: Bool = true, calendar: Calendar = .current) -> [CalendarDisplayItem] {
        guard let day = calendar.dateInterval(of: .day, for: date) else { return [] }
        var items: [CalendarDisplayItem] = []
        for entry in entries where entry.isTask && (showCompleted || !entry.isCompleted) {
            if let start = entry.plannedStart, let end = entry.plannedEnd,
               start < day.end && (end > day.start || (start == end && day.contains(start))) {
                items.append(CalendarDisplayItem(entry: entry, kind: .execution, date: start, end: end))
            }
            if let due = entry.dueDate, due >= day.start, due < day.end {
                items.append(CalendarDisplayItem(entry: entry, kind: .deadline, date: due, end: nil))
            }
        }
        return items.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }
    }
}

public struct CalendarBlock: Identifiable {
    public let item: CalendarDisplayItem
    public let startMinute: Double
    public let endMinute: Double
    public var column: Int
    public var columnCount: Int
    public var id: String { item.id }
}

public enum CalendarTimelineLayout {
    /// Lay out execution blocks only. A deadline is a point, not reserved execution time.
    public static func blocks(on date: Date, items: [CalendarDisplayItem], calendar: Calendar = .current) -> [CalendarBlock] {
        guard let day = calendar.dateInterval(of: .day, for: date) else { return [] }
        let total = day.duration / 60
        var blocks = items.filter { $0.kind == .execution && !$0.isAllDay }.map { item in
            let start = max(0, min(total - 1, item.date.timeIntervalSince(day.start) / 60))
            let end = min(total, max(start + 1, (item.end ?? item.date).timeIntervalSince(day.start) / 60))
            return CalendarBlock(item: item, startMinute: start, endMinute: end, column: 0, columnCount: 1)
        }.sorted {
            if $0.startMinute != $1.startMinute { return $0.startMinute < $1.startMinute }
            if $0.endMinute != $1.endMinute { return $0.endMinute > $1.endMinute }
            return $0.id < $1.id
        }
        var active: [Int: Double] = [:]
        var group: [Int] = []
        var width = 1
        func finishGroup() { for index in group { blocks[index].columnCount = width } }
        for index in blocks.indices {
            active = active.filter { $0.value > blocks[index].startMinute }
            if active.isEmpty { finishGroup(); group = []; width = 1 }
            var column = 0
            while active[column] != nil { column += 1 }
            blocks[index].column = column
            // Small events need a readable tap target; reserve that visual footprint too.
            active[column] = max(blocks[index].endMinute, blocks[index].startMinute + 20)
            group.append(index)
            width = max(width, column + 1)
        }
        finishGroup()
        return blocks
    }
}
