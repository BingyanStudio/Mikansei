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
    public var isReferenceCalendar: Bool {
        ["节假日", "节日", "假日", "holiday", "生日", "birthday"].contains { title.localizedCaseInsensitiveContains($0) }
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
    /// Provider-backed identity shared by every occurrence in one source calendar series.
    /// The local EventKit identifier is intentionally omitted so separate devices converge.
    public var routineSeriesID: String? {
        guard !occurrence.isEmpty, !calendarID.isEmpty, !eventID.isEmpty,
              let data = try? JSONSerialization.data(
                withJSONObject: ["calendar", "", calendarID, eventID],
                options: [.withoutEscapingSlashes]
              ) else { return nil }
        return String(data: data, encoding: .utf8)
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
        var entry = Entry(title: cleaned.isEmpty ? "未命名日程" : cleaned, body: notes, kind: timing == .start ? .schedule : .task, category: identity.calendarTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                          dueDate: due, createdAt: now, updatedAt: now)
        entry.plannedStart = start; entry.plannedEnd = end; entry.plannedAllDay = isAllDay
        // Importing a whole calendar must not enable hundreds of unsolicited alarms.
        entry.reminder = nil
        entry.location = location.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.platform = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if !identity.occurrence.isEmpty {
            entry.routineSeriesID = identity.routineSeriesID
            entry.routineOccurrenceID = identity.occurrence
        }
        let minutes = Int(min(1441, max(0, ceil(end.timeIntervalSince(start) / 60))))
        if !isAllDay && (1...1440).contains(minutes) { entry.estimatedMinutes = minutes }
        return entry
    }
}

public struct CalendarEventLink: Codable, Equatable {
    public var event: CalendarEventRecord
    public var timing: CalendarImportTiming
    public var missingFromSource: Bool
    public var wasAutomaticallyImported: Bool?
    public init(event: CalendarEventRecord, timing: CalendarImportTiming, missingFromSource: Bool = false, wasAutomaticallyImported: Bool? = true) {
        self.event = event; self.timing = timing; self.missingFromSource = missingFromSource; self.wasAutomaticallyImported = wasAutomaticallyImported
    }
}

public struct CalendarSyncSettings: Codable, Equatable {
    public var enabled = true
    public var timing = CalendarImportTiming.start
    public var selectionInitialized = false
    public var selectionPolicyVersion = 1
    public var selected: [CalendarSelection] = []
    /// A deleted imported occurrence must not reappear on the next launch.
    public var suppressed: [CalendarEventIdentity] = []
    public init() {}
    private enum CodingKeys: String, CodingKey { case enabled, timing, selectionInitialized, selectionPolicyVersion, selected, suppressed }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        timing = try c.decodeIfPresent(CalendarImportTiming.self, forKey: .timing) ?? .start
        selectionInitialized = try c.decodeIfPresent(Bool.self, forKey: .selectionInitialized) ?? false
        selectionPolicyVersion = try c.decodeIfPresent(Int.self, forKey: .selectionPolicyVersion) ?? 0
        selected = try c.decodeIfPresent([CalendarSelection].self, forKey: .selected) ?? []
        suppressed = try c.decodeIfPresent([CalendarEventIdentity].self, forKey: .suppressed) ?? []
    }
    public func refreshed(available: [CalendarSelection], referenceIDs: Set<String> = []) -> Self {
        var next = self
        if !selectionInitialized {
            // First-time access is opt-in: calendar colors/names are sources, not task tags.
            next.selected = []
            next.selectionInitialized = !available.isEmpty
        } else {
            next.selected = selected.map { old in
                if let same = available.first(where: { $0.id == old.id }) { return same }
                let matches = available.filter { $0.title == old.title && $0.sourceTitle == old.sourceTitle }
                return matches.count == 1 ? matches[0] : old
            }
        }
        if selectionPolicyVersion == 0 {
            next.selected.removeAll { $0.isReferenceCalendar || referenceIDs.contains($0.id) }
        }
        next.selected = next.selected.reduce(into: []) { result, choice in
            if !result.contains(where: { $0.id == choice.id }) { result.append(choice) }
        }
        next.selectionPolicyVersion = 1
        return next
    }
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
            if let queriedCalendarIDs, !queriedCalendarIDs.contains(event.identity.calendarID) { continue }
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
                if original.kind == previous.kind && original.dueDate == previous.dueDate {
                    next.kind = incoming.kind
                    if next.reminderAnchor == previous.reminderAnchor { next.reminderAnchor = incoming.reminderAnchor }
                }
                if next.plannedStart == previous.plannedStart { next.plannedStart = incoming.plannedStart }
                if next.plannedEnd == previous.plannedEnd { next.plannedEnd = incoming.plannedEnd }
                if next.plannedAllDay == previous.plannedAllDay { next.plannedAllDay = incoming.plannedAllDay }
                if next.estimatedMinutes == previous.estimatedMinutes { next.estimatedMinutes = incoming.estimatedMinutes }
                if let seriesID = event.identity.routineSeriesID {
                    if next.routineSeriesID == nil { next.routineSeriesID = seriesID }
                    if next.isProviderRoutineSeries && next.routineOccurrenceID == nil {
                        next.routineOccurrenceID = event.identity.occurrence
                    }
                }
                next.calendarEvent = CalendarEventLink(event: event, timing: settings.timing, wasAutomaticallyImported: link.wasAutomaticallyImported)
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

    /// Only untouched open imports are eligible for cleanup; local edits/history are retained.
    public static func canClean(_ entry: Entry, selectedIDs: Set<String>) -> Bool {
        guard let link = entry.calendarEvent, !selectedIDs.contains(link.event.identity.calendarID),
              link.wasAutomaticallyImported == true || (link.wasAutomaticallyImported == nil && CalendarSelection(id: link.event.identity.calendarID, title: link.event.identity.calendarTitle, sourceTitle: link.event.identity.sourceTitle).isReferenceCalendar),
              !entry.isCompleted, !entry.isInPlanning, !entry.isLocalRoutine, entry.checklist.isEmpty, entry.elapsedSeconds == 0,
              entry.startedAt == nil, entry.reminder == nil, entry.priority == .normal, entry.source.isEmpty,
              entry.reminderSound == .system, entry.snoozeMinutes == 5, entry.reminderPattern == .single else { return false }
        let imported = link.event.draft(timing: link.timing, now: entry.createdAt)
        return entry.isTask && entry.title == imported.title && entry.body == imported.body &&
            entry.category == imported.category && entry.platform == imported.platform && entry.location == imported.location &&
            entry.dueDate == imported.dueDate && entry.plannedStart == imported.plannedStart &&
            entry.plannedEnd == imported.plannedEnd && entry.plannedAllDay == imported.plannedAllDay && entry.estimatedMinutes == imported.estimatedMinutes
    }
}
