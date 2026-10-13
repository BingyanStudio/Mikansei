import Foundation

/// Logical revisions converge even when offline devices have different wall clocks.
public struct SyncRevision: Codable, Equatable, Comparable {
    public let counter: UInt64
    public let device: UUID
    public static func < (a: Self, b: Self) -> Bool {
        a.counter == b.counter ? a.device.uuidString < b.device.uuidString : a.counter < b.counter
    }
}

public struct SyncedRecord<Value: Codable & Equatable>: Codable, Equatable {
    public let id: UUID
    public let revision: SyncRevision
    /// nil is a permanent deletion marker, so an offline device cannot resurrect it.
    public let value: Value?
}

public struct WorkspaceSyncDocument: Codable, Equatable {
    public var version = 1
    public var entries: [SyncedRecord<Entry>] = []
    public var courses: [SyncedRecord<Course>] = []
    public var deletedCalendarOccurrences: [CalendarEventIdentity]?
    public init() {}
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }
    public static func decode(_ data: Data) throws -> Self {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let doc = try decoder.decode(Self.self, from: data)
        guard doc.version == 1 else { throw ArchiveError.unsupportedVersion }
        guard Set(doc.entries.map(\.id)).count == doc.entries.count,
              Set(doc.courses.map(\.id)).count == doc.courses.count,
              (doc.entries.map(\.revision) + doc.courses.map(\.revision)).allSatisfy({ $0.counter > 0 && $0.counter < 1_000_000_000_000 }),
              doc.entries.allSatisfy({ $0.value == nil || $0.id == $0.value!.id }),
              doc.courses.allSatisfy({ $0.value == nil || $0.id == $0.value!.id }) else { throw ArchiveError.invalidEntries }
        _ = try EntryArchive.decode(EntryArchive(entries: doc.entries.compactMap(\.value), courses: doc.courses.compactMap(\.value)).encoded())
        return doc
    }
    public mutating func merge(_ remote: Self) {
        entries = Self.mergeRecords(entries, remote.entries)
        courses = Self.mergeRecords(courses, remote.courses)
        var deleted = deletedCalendarOccurrences ?? []
        for identity in remote.deletedCalendarOccurrences ?? [] where !deleted.contains(identity) { deleted.append(identity) }
        deletedCalendarOccurrences = deleted.isEmpty ? nil : deleted.sorted {
            [$0.eventID, $0.occurrence, $0.calendarID, $0.localEventID ?? "", $0.calendarTitle, $0.sourceTitle].lexicographicallyPrecedes(
                [$1.eventID, $1.occurrence, $1.calendarID, $1.localEventID ?? "", $1.calendarTitle, $1.sourceTitle])
        }
    }
    private static func mergeRecords<T: Codable & Equatable>(_ local: [SyncedRecord<T>], _ remote: [SyncedRecord<T>]) -> [SyncedRecord<T>] {
        var result = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })
        for record in remote {
            if let existing = result[record.id], existing.revision >= record.revision { continue }
            result[record.id] = record
        }
        return result.values.sorted { $0.id.uuidString < $1.id.uuidString }
    }
}

public struct WorkspaceReplica: Codable, Equatable {
    public private(set) var device = UUID()
    public private(set) var counter: UInt64 = 0
    public private(set) var document = WorkspaceSyncDocument()
    public init() {}
    public mutating func capture(entries: [Entry], courses: [Course], suppressed: [CalendarEventIdentity] = []) {
        let currentEntries = Dictionary(uniqueKeysWithValues: document.entries.map { ($0.id, $0) })
        let currentCourses = Dictionary(uniqueKeysWithValues: document.courses.map { ($0.id, $0) })
        let nextEntries = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
        let nextCourses = Dictionary(uniqueKeysWithValues: courses.map { ($0.id, $0) })
        let entryIDs = Set(currentEntries.keys).union(nextEntries.keys)
        let courseIDs = Set(currentCourses.keys).union(nextCourses.keys)
        let changedEntries = entryIDs.filter { !Self.sameSyncedValue(currentEntries[$0]?.value, nextEntries[$0]) }
        let changedCourses = courseIDs.filter { currentCourses[$0]?.value != nextCourses[$0] }
        let newSuppressed = suppressed.filter { identity in !(document.deletedCalendarOccurrences ?? []).contains(where: { $0.matches(identity) }) }
        guard !changedEntries.isEmpty || !changedCourses.isEmpty || !newSuppressed.isEmpty else { return }
        counter += 1
        let revision = SyncRevision(counter: counter, device: device)
        var delta = WorkspaceSyncDocument()
        delta.deletedCalendarOccurrences = newSuppressed.isEmpty ? nil : newSuppressed
        delta.entries = changedEntries.map { SyncedRecord(id: $0, revision: revision, value: nextEntries[$0]) }
        delta.courses = changedCourses.map { SyncedRecord(id: $0, revision: revision, value: nextCourses[$0]) }
        document.merge(delta)
    }
    public mutating func receive(_ remote: WorkspaceSyncDocument) {
        document.merge(remote)
        counter = max(counter, (remote.entries.map { $0.revision.counter } + remote.courses.map { $0.revision.counter }).max() ?? 0)
    }
    public var entries: [Entry] {
        let live = document.entries.filter { $0.value != nil }
        // Separate devices may import the same calendar occurrence or generate the same routine successor offline.
        // Collapse only untouched duplicates; independently customized copies remain available to the user.
        let visible = live.filter { record in
            guard let entry = record.value else { return false }
            let cleanCalendar = CalendarImport.canClean(entry, selectedIDs: [])
            if cleanCalendar, let identity = entry.calendarEvent?.event.identity,
               (document.deletedCalendarOccurrences ?? []).contains(where: { $0.matches(identity) }) { return false }
            return !live.contains { other in
                guard other.id != record.id, let value = other.value else { return false }
                let calendarDuplicate = cleanCalendar && value.calendarEvent.map { entry.calendarEvent!.event.identity.matches($0.event.identity) } == true
                if calendarDuplicate && !CalendarImport.canClean(value, selectedIDs: []) { return true }
                let routineDuplicate = Self.sameUntouchedSuccessor(entry, value)
                guard calendarDuplicate || routineDuplicate else { return false }
                return record.revision < other.revision || (record.revision == other.revision && record.id.uuidString < other.id.uuidString)
            }
        }
        var result = visible.compactMap(\.value).sorted { $0.createdAt == $1.createdAt ? $0.id.uuidString < $1.id.uuidString : $0.createdAt < $1.createdAt }
        let running = visible.filter { $0.value?.startedAt != nil && $0.value?.isCompleted == false }
        if let winner = running.max(by: { $0.revision == $1.revision ? $0.id.uuidString < $1.id.uuidString : $0.revision < $1.revision }),
           let start = winner.value?.startedAt {
            for index in result.indices where result[index].id != winner.id && result[index].startedAt != nil {
                result[index].pauseFocus(at: max(result[index].startedAt!, start))
            }
        }
        return result
    }
    private static func sameUntouchedSuccessor(_ a: Entry, _ b: Entry) -> Bool {
        guard let parent = a.previousOccurrenceID, parent == b.previousOccurrenceID,
              !a.isCompleted, !b.isCompleted, a.elapsedSeconds == 0, b.elapsedSeconds == 0,
              a.startedAt == nil, b.startedAt == nil, a.checklist.count == b.checklist.count,
              zip(a.checklist, b.checklist).allSatisfy({ !$0.isDone && !$1.isDone && $0.title == $1.title }) else { return false }
        var copy = a
        copy.id = b.id; copy.createdAt = b.createdAt; copy.updatedAt = b.updatedAt; copy.checklist = b.checklist
        return copy == b
    }
    public var courses: [Course] { document.courses.compactMap(\.value).sorted { $0.name < $1.name } }
    private static func sameSyncedValue(_ a: Entry?, _ b: Entry?) -> Bool {
        if a == b { return true }
        guard let a, var b, let old = a.calendarEvent, let incoming = b.calendarEvent,
              old.event.identity.matches(incoming.event.identity) else { return false }
        let event = incoming.event
        // EventKit's local identifiers differ by device. Rebinding the same event alone is not a new task edit.
        b.calendarEvent = CalendarEventLink(event: CalendarEventRecord(identity: old.event.identity, title: event.title,
            start: event.start, end: event.end, isAllDay: event.isAllDay, notes: event.notes, location: event.location,
            url: event.url, isCancelled: event.isCancelled), timing: incoming.timing,
            missingFromSource: incoming.missingFromSource, wasAutomaticallyImported: incoming.wasAutomaticallyImported)
        b.updatedAt = a.updatedAt
        return a == b
    }
}
