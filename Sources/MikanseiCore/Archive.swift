import Foundation

public enum ArchiveError: LocalizedError {
    case unsupportedVersion, invalidEntries
    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion: return "备份版本较新，请先更新Mikansei。"
        case .invalidEntries: return "备份含有重复编号或无效事项，未导入数据。"
        }
    }
}

public struct EntryArchive: Codable {
    public let version: Int
    public var entries: [Entry]
    public var courses: [Course]
    public var calendarSync: CalendarSyncSettings
    public init(entries: [Entry], courses: [Course] = [], calendarSync: CalendarSyncSettings = CalendarSyncSettings()) {
        self.version = 1; self.entries = entries; self.courses = courses; self.calendarSync = calendarSync
    }
    private enum CodingKeys: String, CodingKey { case version, entries, courses, calendarSync }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        entries = try c.decode([Entry].self, forKey: .entries)
        courses = try c.decodeIfPresent([Course].self, forKey: .courses) ?? []
        calendarSync = try c.decodeIfPresent(CalendarSyncSettings.self, forKey: .calendarSync) ?? CalendarSyncSettings()
    }
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }
    public static func decode(_ data: Data) throws -> EntryArchive {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let archive = try decoder.decode(Self.self, from: data)
        guard archive.version == 1 else { throw ArchiveError.unsupportedVersion }
        guard Set(archive.entries.map(\.id)).count == archive.entries.count,
              Set(archive.courses.map(\.id)).count == archive.courses.count,
              archive.courses.allSatisfy(\.isValid),
              Set(archive.calendarSync.selected.map(\.id)).count == archive.calendarSync.selected.count,
              archive.entries.allSatisfy({ entry in
                  !entry.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                  Set(entry.checklist.map(\.id)).count == entry.checklist.count &&
                  (entry.repeatRule == .never || (entry.isTask && entry.dueDate != nil)) &&
                  (1...365).contains(entry.repeatIntervalDays) &&
                  (entry.estimatedMinutes == nil || (1...1440).contains(entry.estimatedMinutes!)) &&
                  entry.elapsedSeconds.isFinite && entry.elapsedSeconds >= 0 &&
                  (entry.calendarEvent == nil || entry.calendarEvent!.event.isValid) &&
                  [5, 10, 15].contains(entry.snoozeMinutes) &&
                  ((entry.plannedStart == nil && entry.plannedEnd == nil) || (entry.isTask && entry.plannedStart != nil && entry.plannedEnd != nil && entry.plannedEnd! >= entry.plannedStart!)) &&
                  (entry.reminder == nil || (entry.isTask && entry.attentionDate != nil))
              }) else { throw ArchiveError.invalidEntries }
        return archive
    }
    /// A backup import never removes existing items and keeps the newest version of each item.
    public func merging(into current: [Entry]) -> [Entry] {
        var result = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0) })
        for entry in entries {
            if let existing = result[entry.id], existing.updatedAt >= entry.updatedAt { continue }
            result[entry.id] = entry
        }
        return result.values.sorted { $0.createdAt < $1.createdAt }
    }
}

public enum ReminderPlan {
    /// Leave space below iOS's pending notification limit; select the nearest reminders first.
    public static func pending(entries: [Entry], now: Date = Date(), limit: Int = 60) -> [Entry] {
        Array(entries.filter { $0.reminderDate.map { $0 > now } == true }
            .sorted { $0.reminderDate! < $1.reminderDate! }.prefix(max(0, limit)))
    }
}

public struct EntryRepository {
    public let fileURL: URL
    public init(fileURL: URL) { self.fileURL = fileURL }
    public func load() throws -> [Entry] {
        try loadArchive().entries
    }
    public func loadArchive() throws -> EntryArchive {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return EntryArchive(entries: []) }
        return try EntryArchive.decode(Data(contentsOf: fileURL))
    }
    public func save(_ entries: [Entry]) throws {
        try saveArchive(EntryArchive(entries: entries))
    }
    public func saveArchive(_ archive: EntryArchive) throws {
        let data = try archive.encoded()
        // Validate before writing so malformed content cannot replace a usable archive.
        _ = try EntryArchive.decode(data)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        #if os(iOS)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: fileURL, options: .atomic)
        #endif
    }
}
