import Foundation

public struct CalendarDisplayItem: Identifiable, Equatable {
    public enum Kind { case execution, deadline }
    public let entry: Entry
    public let kind: Kind
    public let date: Date
    public let end: Date?
    public var id: String { entry.id.uuidString + (kind == .execution ? ".execution" : ".deadline") + ".\(Int(date.timeIntervalSince1970))" }
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
        let successors = Entry.successorDates(in: entries)
        for entry in entries where entry.isTask && (showCompleted || !entry.isCompleted) {
            var occurrences: [Entry]
            if entry.isCalendarBackedRoutine {
                // Source providers already materialize each occurrence; project the stored instance as-is.
                occurrences = [entry]
            } else if entry.allowsLocalSuccessorGeneration && !entry.isCompleted {
                let base = entry.recurrenceReferenceDate ?? day.start
                let startOffset = entry.plannedStart?.timeIntervalSince(base) ?? 0
                let endOffset = entry.plannedEnd?.timeIntervalSince(base) ?? 0
                let from = day.start.addingTimeInterval(-max(0, endOffset))
                let to = min(day.end.addingTimeInterval(-min(0, startOffset)), successors[entry.id] ?? .distantFuture)
                let dates = entry.occurrenceDates(in: from..<max(from, to), calendar: calendar)
                occurrences = dates.map { entry.occurrence(at: $0, calendar: calendar) }
            } else {
                occurrences = [entry]
            }
            for occurrence in occurrences {
                if let start = occurrence.plannedStart, let end = occurrence.plannedEnd,
                   start < day.end && (end > day.start || (start == end && day.contains(start))) {
                    items.append(CalendarDisplayItem(entry: entry, kind: .execution, date: start, end: end))
                }
                if let due = occurrence.dueDate, due >= day.start, due < day.end {
                    items.append(CalendarDisplayItem(entry: entry, kind: .deadline, date: due, end: nil))
                }
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
    /// Position-based creation snaps to 15 minutes and remains in the pressed day, including DST.
    public static func start(on date: Date, minuteOffset: Double, calendar: Calendar = .current) -> Date? {
        guard minuteOffset.isFinite, let day = calendar.dateInterval(of: .day, for: date) else { return nil }
        let minutes = min(max(0, floor(minuteOffset / 15) * 15), day.duration / 60 - 15)
        return day.start.addingTimeInterval(minutes * 60)
    }
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
