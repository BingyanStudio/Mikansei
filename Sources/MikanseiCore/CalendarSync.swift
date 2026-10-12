import Foundation

public enum CalendarImportTiming: String, CaseIterable, Codable, Identifiable {
    case start, end
    public var id: Self { self }
    public var title: String { self == .start ? "按开始时间安排" : "按结束时间截止" }
}

public struct CalendarSelection: Codable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var sourceTitle: String
    public init(id: String, title: String, sourceTitle: String) {
        self.id = id; self.title = title; self.sourceTitle = sourceTitle
    }
}

public struct CalendarEventIdentity: Codable, Equatable, Hashable {
    public let calendarID: String
    public let calendarTitle: String
    public let sourceTitle: String
    public let eventID: String
    public let localEventID: String?
    /// Original occurrence date for recurring events; empty for one-off events, even if moved.
    public let occurrence: String
    public init(calendarID: String, calendarTitle: String, sourceTitle: String, eventID: String, occurrence: String = "", localEventID: String? = nil) {
        self.calendarID = calendarID; self.calendarTitle = calendarTitle; self.sourceTitle = sourceTitle
        self.eventID = eventID; self.occurrence = occurrence; self.localEventID = localEventID
    }
    public func matches(_ other: Self, knownCalendarIDs: Set<String> = []) -> Bool {
        (eventID == other.eventID || (localEventID != nil && localEventID == other.localEventID)) && occurrence == other.occurrence &&
        (calendarID == other.calendarID ||
         (!(knownCalendarIDs.contains(calendarID) && knownCalendarIDs.contains(other.calendarID)) &&
          calendarTitle == other.calendarTitle && sourceTitle == other.sourceTitle))
    }
}

public struct CalendarEventRecord: Codable, Equatable {
    public let identity: CalendarEventIdentity
    public let title: String
    public let start: Date
    public let end: Date
    public let isAllDay: Bool
    public let notes: String
    public let location: String
    public let url: String
    public let isCancelled: Bool
    public init(identity: CalendarEventIdentity, title: String, start: Date, end: Date, isAllDay: Bool = false,
                notes: String = "", location: String = "", url: String = "", isCancelled: Bool = false) {
        self.identity = identity; self.title = title; self.start = start; self.end = end
        self.isAllDay = isAllDay; self.notes = notes; self.location = location; self.url = url; self.isCancelled = isCancelled
    }
    public var isValid: Bool { !identity.eventID.isEmpty && !identity.calendarID.isEmpty && end >= start }
    public func draft(timing: CalendarImportTiming, now: Date) -> Entry {
        let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        // Calendar all-day end dates are exclusive. Keep them actionable until the last day's end.
        let due: Date? = timing == .start ? nil : isAllDay ? max(start, end.addingTimeInterval(-1)) : end
        var entry = Entry(title: cleaned.isEmpty ? "未命名日程" : cleaned, body: notes, category: identity.calendarTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                          dueDate: due, createdAt: now, updatedAt: now)
        entry.plannedStart = start; entry.plannedEnd = end; entry.plannedAllDay = isAllDay
        entry.location = location.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.platform = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let minutes = Int(min(1441, max(0, ceil(end.timeIntervalSince(start) / 60))))
        if !isAllDay && (1...1440).contains(minutes) { entry.estimatedMinutes = minutes }
        return entry
    }
}

public struct CalendarEventLink: Codable, Equatable {
    public var event: CalendarEventRecord
    public var timing: CalendarImportTiming
    public var missingFromSource: Bool
    public init(event: CalendarEventRecord, timing: CalendarImportTiming, missingFromSource: Bool = false) {
        self.event = event; self.timing = timing; self.missingFromSource = missingFromSource
    }
}

public struct CalendarSyncSettings: Codable, Equatable {
    public var enabled = true
    public var timing = CalendarImportTiming.start
    public var selectionInitialized = false
    public var selected: [CalendarSelection] = []
    /// A deleted imported occurrence must not reappear on the next launch.
    public var suppressed: [CalendarEventIdentity] = []
    public init() {}
}

public struct CalendarSyncResult {
    public var entries: [Entry]
    public var added = 0
    public var updated = 0
}

public enum CalendarImport {
    /// Merge only fields that still equal the last imported value. Personal task state stays local.
    public static func merge(events: [CalendarEventRecord], into entries: [Entry], settings: CalendarSyncSettings,
                             now: Date = Date(), range: Range<Date>? = nil, availableCalendarIDs: Set<String> = [],
                             queriedCalendarIDs: Set<String>? = nil) -> CalendarSyncResult {
        var result = CalendarSyncResult(entries: entries)
        let known = availableCalendarIDs.union(events.map { $0.identity.calendarID })
        var seen: [CalendarEventIdentity] = []
        for event in events where event.isValid {
            guard !seen.contains(where: { $0.matches(event.identity, knownCalendarIDs: known) }) else { continue }
            seen.append(event.identity)
            guard !settings.suppressed.contains(where: { $0.matches(event.identity, knownCalendarIDs: known) }) else { continue }
            let matches = result.entries.indices.filter { result.entries[$0].calendarEvent?.event.identity.matches(event.identity, knownCalendarIDs: known) == true }
            if let index = matches.first, matches.count == 1 {
                let original = result.entries[index]
                guard original.isTask, let link = original.calendarEvent else { continue }
                let previous = link.event.draft(timing: link.timing, now: now)
                let incoming = event.draft(timing: settings.timing, now: now)
                var next = original
                if next.title == previous.title { next.title = incoming.title }
                if next.body == previous.body { next.body = incoming.body }
                if next.category == previous.category { next.category = incoming.category }
                if next.location == previous.location { next.location = incoming.location }
                if next.platform == previous.platform { next.platform = incoming.platform }
                if next.dueDate == previous.dueDate { next.dueDate = incoming.dueDate }
                if next.plannedStart == previous.plannedStart { next.plannedStart = incoming.plannedStart }
                if next.plannedEnd == previous.plannedEnd { next.plannedEnd = incoming.plannedEnd }
                if next.plannedAllDay == previous.plannedAllDay { next.plannedAllDay = incoming.plannedAllDay }
                if next.estimatedMinutes == previous.estimatedMinutes { next.estimatedMinutes = incoming.estimatedMinutes }
                next.calendarEvent = CalendarEventLink(event: event, timing: settings.timing)
                if next != original {
                    next.updatedAt = now
                    result.entries[index] = next
                    result.updated += 1
                }
            } else if matches.isEmpty && !event.isCancelled {
                var next = event.draft(timing: settings.timing, now: now)
                next.calendarEvent = CalendarEventLink(event: event, timing: settings.timing)
                result.entries.append(next)
                result.added += 1
            }
        }
        // A bounded query never deletes local tasks; absence can also mean an event was moved or isn't loaded.
        if let range {
            for index in result.entries.indices {
                guard var link = result.entries[index].calendarEvent,
                      !link.missingFromSource, (queriedCalendarIDs ?? availableCalendarIDs).contains(link.event.identity.calendarID),
                      link.event.start < range.upperBound, link.event.end > range.lowerBound,
                      !seen.contains(where: { $0.matches(link.event.identity, knownCalendarIDs: known) }) else { continue }
                link.missingFromSource = true
                result.entries[index].calendarEvent = link
                result.entries[index].updatedAt = now
                result.updated += 1
            }
        }
        return result
    }
}
