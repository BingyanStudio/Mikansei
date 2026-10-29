import Foundation
import CoreFoundation

private final class LockedCloudArchiveDateParser: @unchecked Sendable {
    private let lock = NSLock()
    private let fractionalISO8601 = ISO8601DateFormatter()
    private let wholeSecondISO8601 = ISO8601DateFormatter()
    private let legacyMilliseconds = DateFormatter()
    private let legacyWholeSeconds = DateFormatter()

    init() {
        fractionalISO8601.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        wholeSecondISO8601.formatOptions = [.withInternetDateTime]

        for (formatter, format) in [
            (legacyMilliseconds, "yyyy-MM-dd'T'HH:mm:ss.SSS"),
            (legacyWholeSeconds, "yyyy-MM-dd'T'HH:mm:ss")
        ] {
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.timeZone = .current
            formatter.dateFormat = format
        }
    }

    func date(from text: String) -> Date? {
        lock.lock()
        defer { lock.unlock() }

        if let date = fractionalISO8601.date(from: text) { return date }
        if let date = wholeSecondISO8601.date(from: text) { return date }

        // Older Flutter archives omitted a timezone. Refresh the cached
        // formatter's timezone so these values continue to use the current
        // local timezone, as they did before caching.
        legacyMilliseconds.timeZone = .current
        if let date = legacyMilliseconds.date(from: text) { return date }
        legacyWholeSeconds.timeZone = .current
        return legacyWholeSeconds.date(from: text)
    }
}

/// JSON-compatible value retained from the shared Flutter archive. Keeping
/// these values beside the native archive lets a device edit known fields
/// without dropping fields that only another platform understands.
public indirect enum CloudJSONValue: Codable, Equatable {
    case null
    case bool(Bool)
    case integer(Int64)
    case number(Double)
    case string(String)
    case array([CloudJSONValue])
    case object([String: CloudJSONValue])

    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() {
            self = .null
        } else if let decoded = try? value.decode(Bool.self) {
            self = .bool(decoded)
        } else if let decoded = try? value.decode(Int64.self) {
            self = .integer(decoded)
        } else if let decoded = try? value.decode(Double.self) {
            self = .number(decoded)
        } else if let decoded = try? value.decode(String.self) {
            self = .string(decoded)
        } else if let decoded = try? value.decode([CloudJSONValue].self) {
            self = .array(decoded)
        } else if let decoded = try? value.decode([String: CloudJSONValue].self) {
            self = .object(decoded)
        } else {
            throw DecodingError.dataCorruptedError(
                in: value,
                debugDescription: "Unsupported JSON value in cloud archive."
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case .null: try value.encodeNil()
        case .bool(let item): try value.encode(item)
        case .integer(let item): try value.encode(item)
        case .number(let item): try value.encode(item)
        case .string(let item): try value.encode(item)
        case .array(let item): try value.encode(item)
        case .object(let item): try value.encode(item)
        }
    }

    fileprivate init?(foundationValue: Any) {
        if foundationValue is NSNull {
            self = .null
        } else if let number = foundationValue as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                self = .bool(number.boolValue)
            } else if String(cString: number.objCType) != "d",
                      String(cString: number.objCType) != "f" {
                self = .integer(number.int64Value)
            } else {
                self = .number(number.doubleValue)
            }
        } else if let string = foundationValue as? String {
            self = .string(string)
        } else if let array = foundationValue as? [Any] {
            var converted: [CloudJSONValue] = []
            converted.reserveCapacity(array.count)
            for item in array {
                guard let value = CloudJSONValue(foundationValue: item) else { return nil }
                converted.append(value)
            }
            self = .array(converted)
        } else if let object = foundationValue as? [String: Any] {
            var converted: [String: CloudJSONValue] = [:]
            converted.reserveCapacity(object.count)
            for (key, item) in object {
                guard let value = CloudJSONValue(foundationValue: item) else { return nil }
                converted[key] = value
            }
            self = .object(converted)
        } else {
            return nil
        }
    }

    fileprivate var foundationValue: Any {
        switch self {
        case .null: return NSNull()
        case .bool(let value): return NSNumber(value: value)
        case .integer(let value): return NSNumber(value: value)
        case .number(let value): return NSNumber(value: value)
        case .string(let value): return value
        case .array(let values): return values.map(\.foundationValue)
        case .object(let values): return values.mapValues(\.foundationValue)
        }
    }
}

/// Durable cloud-only state. It is stored in the local archive, but never
/// written as part of the cross-platform archive itself.
public struct CloudArchiveState: Codable, Equatable {
    public var accountKey: String?
    public var metadata: [String: CloudJSONValue]
    public var entryRecords: [String: CloudJSONValue]
    public var courseRecords: [String: CloudJSONValue]
    public var tombstones: [String: Date]
    public var courseTombstones: [String: Date]
    public var deletedCalendarOccurrences: [CalendarEventIdentity]

    public init(
        accountKey: String? = nil,
        metadata: [String: CloudJSONValue] = [:],
        entryRecords: [String: CloudJSONValue] = [:],
        courseRecords: [String: CloudJSONValue] = [:],
        tombstones: [String: Date] = [:],
        courseTombstones: [String: Date] = [:],
        deletedCalendarOccurrences: [CalendarEventIdentity] = []
    ) {
        self.accountKey = accountKey
        self.metadata = metadata
        self.entryRecords = entryRecords
        self.courseRecords = courseRecords
        self.tombstones = tombstones
        self.courseTombstones = courseTombstones
        self.deletedCalendarOccurrences = deletedCalendarOccurrences
    }
}

/// Typed result for applying a cloud archive to one native workspace.
public struct CloudArchiveMerge: Equatable {
    public let entries: [Entry]
    public let courses: [Course]
    public let state: CloudArchiveState
    public let deletedCalendarOccurrences: [CalendarEventIdentity]

    public init(
        entries: [Entry],
        courses: [Course],
        state: CloudArchiveState,
        deletedCalendarOccurrences: [CalendarEventIdentity]
    ) {
        self.entries = entries
        self.courses = courses
        self.state = state
        self.deletedCalendarOccurrences = deletedCalendarOccurrences
    }
}

public enum CloudArchiveError: LocalizedError {
    case invalidArchive
    case unsupportedVersion

    public var errorDescription: String? {
        switch self {
        case .invalidArchive:
            return "云端档案格式无效，本机数据未修改。"
        case .unsupportedVersion:
            return "云端档案版本较新，本机数据未修改。"
        }
    }
}

/// Codec for Mikanseta's version-1 archive protocol. Its entry timestamps and
/// top-level tombstones intentionally remain separate from WorkspaceReplica.
public enum CloudArchiveCodec {
    private static let dateParser = LockedCloudArchiveDateParser()

    private static let entryFields: Set<String> = [
        "id", "title", "body", "kind", "category", "priority", "checklist",
        "dueDate", "reminder", "isCompleted", "completedAt", "createdAt",
        "updatedAt", "platform", "location", "estimatedMinutes", "source",
        "repeatRule", "repeatIntervalDays", "repeatWeekdays",
        "repeatIntervalMonths", "repeatDates", "repeatAnchorDate",
        "reminderPattern", "previousOccurrenceID", "routineSeriesID",
        "routineOccurrenceID", "startedAt", "elapsedSeconds", "calendarEvent",
        "plannedStart", "plannedEnd", "plannedAllDay", "reminderDelivery",
        "reminderAnchor", "reminderSound", "snoozeMinutes", "sortOrder",
        "plannedDays", "isInPlanning"
    ]
    private static let courseFields: Set<String> = [
        "id", "name", "weekday", "startMinutes", "endMinutes", "location",
        "platform", "firstDate", "lastDate", "reminderEnabled",
        "reminderDelivery", "reminderSound", "snoozeMinutes"
    ]
    private static let archiveFields: Set<String> = [
        "version", "entries", "courses", "tombstones", "courseTombstones",
        "deletedCalendarOccurrences", "replica", "cloudArchiveState"
    ]

    /// Merge the remote archive into the durable native snapshot. A nil remote
    /// value means the account has no row yet.
    public static func merge(
        remoteContent: String?,
        local: EntryArchive,
        accountKey: String,
        now: Date = Date()
    ) throws -> CloudArchiveMerge {
        let remote = try remoteContent.map(readArchive) ?? emptyRemoteArchive()
        var state: CloudArchiveState
        if let previous = local.cloudArchiveState,
           previous.accountKey == nil || previous.accountKey == accountKey {
            state = previous
        } else {
            // A previous account's extension fields and tombstones must never
            // affect a different Supabase project/user pair.
            state = CloudArchiveState()
        }
        state.accountKey = accountKey

        let localEntryValues = Dictionary(uniqueKeysWithValues: local.entries.map {
            ($0.id.uuidString.uppercased(), $0)
        })
        let localCourseValues = Dictionary(uniqueKeysWithValues: local.courses.map {
            ($0.id.uuidString.uppercased(), $0)
        })

        var remoteEntryValues: [String: Entry] = [:]
        var remoteEntryRecords: [String: CloudJSONValue] = [:]
        for (entry, raw) in zip(remote.archive.entries, remote.rawEntries) {
            let key = entry.id.uuidString.uppercased()
            remoteEntryValues[key] = entry
            if let value = CloudJSONValue(foundationValue: raw) {
                remoteEntryRecords[key] = value
            }
        }
        var remoteCourseValues: [String: Course] = [:]
        var remoteCourseRecords: [String: CloudJSONValue] = [:]
        for (course, raw) in zip(remote.archive.courses, remote.rawCourses) {
            let key = course.id.uuidString.uppercased()
            remoteCourseValues[key] = course
            if let value = CloudJSONValue(foundationValue: raw) {
                remoteCourseRecords[key] = value
            }
        }

        for (id, record) in remoteEntryRecords {
            if let old = state.entryRecords[id],
               let oldDate = timestamp(in: old, key: "updatedAt"),
               let newDate = timestamp(in: record, key: "updatedAt"),
               newDate <= oldDate {
                continue
            }
            state.entryRecords[id] = record
        }
        for (id, record) in remoteCourseRecords {
            state.courseRecords[id] = record
        }

        state.tombstones = mergedMarkers(state.tombstones, remote.tombstones)
        state.courseTombstones = mergedMarkers(state.courseTombstones, remote.courseTombstones)
        for (key, value) in remote.metadata { state.metadata[key] = value }
        state.metadata.removeValue(forKey: "replica")

        var winningEntries: [String: Entry] = remoteEntryValues
        for (id, entry) in localEntryValues {
            if let remoteEntry = remoteEntryValues[id], remoteEntry.updatedAt > entry.updatedAt {
                continue
            }
            winningEntries[id] = entry
            let base = state.entryRecords[id] ?? remoteEntryRecords[id]
            let raw = try materialize(entry, base: base, fields: entryFields)
            guard let record = CloudJSONValue(foundationValue: raw) else {
                throw CloudArchiveError.invalidArchive
            }
            state.entryRecords[id] = record
        }

        var winningCourses: [String: Course] = remoteCourseValues
        for (id, course) in localCourseValues {
            // Flutter's archive merge gives the current local course precedence.
            winningCourses[id] = course
            let base = state.courseRecords[id] ?? remoteCourseRecords[id]
            let raw = try materialize(course, base: base, fields: courseFields)
            guard let record = CloudJSONValue(foundationValue: raw) else {
                throw CloudArchiveError.invalidArchive
            }
            state.courseRecords[id] = record
        }

        winningEntries = winningEntries.filter { id, entry in
            guard let marker = state.tombstones[id] else { return true }
            return entry.updatedAt > marker
        }
        winningCourses = winningCourses.filter { id, _ in
            state.courseTombstones[id] == nil
        }

        let deletedOccurrences = mergedCalendarOccurrences(
            state.deletedCalendarOccurrences,
            local.replica?.document.deletedCalendarOccurrences ?? [],
            remote.deletedCalendarOccurrences
        )
        state.deletedCalendarOccurrences = deletedOccurrences

        return CloudArchiveMerge(
            entries: winningEntries.values.sorted(by: stableEntryOrder),
            courses: winningCourses.values.sorted { $0.id.uuidString < $1.id.uuidString },
            state: state,
            deletedCalendarOccurrences: deletedOccurrences
        )
    }

    /// Encode a cloud-protocol archive, overlaying current native known fields
    /// on the last winning raw records while retaining their platform fields.
    public static func encode(archive: EntryArchive, accountKey: String) throws -> String {
        var state = archive.cloudArchiveState ?? CloudArchiveState()
        if let existingKey = state.accountKey, existingKey != accountKey {
            state = CloudArchiveState(accountKey: accountKey)
        } else {
            state.accountKey = accountKey
        }

        var root = state.metadata.mapValues(\.foundationValue)
        root["version"] = 1
        root["entries"] = try archive.entries
            .sorted(by: stableEntryOrder)
            .map { entry in
                let key = entry.id.uuidString.uppercased()
                return try materialize(entry, base: state.entryRecords[key], fields: entryFields)
            }
        root["courses"] = try archive.courses
            .sorted { $0.id.uuidString < $1.id.uuidString }
            .map { course in
                let key = course.id.uuidString.uppercased()
                return try materialize(course, base: state.courseRecords[key], fields: courseFields)
            }
        root["tombstones"] = markerObject(state.tombstones)
        root["courseTombstones"] = markerObject(state.courseTombstones)
        if !state.deletedCalendarOccurrences.isEmpty {
            let encoder = JSONEncoder()
            let data = try encoder.encode(state.deletedCalendarOccurrences)
            guard let occurrences = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                throw CloudArchiveError.invalidArchive
            }
            root["deletedCalendarOccurrences"] = occurrences
        } else {
            root.removeValue(forKey: "deletedCalendarOccurrences")
        }
        root.removeValue(forKey: "replica")
        root.removeValue(forKey: "cloudArchiveState")

        guard JSONSerialization.isValidJSONObject(root) else { throw CloudArchiveError.invalidArchive }
        let data = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    /// Record a native local delete. The stamp is whole-second UTC and strictly
    /// newer than both the removed entry and any prior marker.
    public static func recordingLocalDeletions(
        state original: CloudArchiveState?,
        removedEntries: [Entry],
        removedCourses: [Course],
        now: Date = Date()
    ) -> CloudArchiveState {
        var state = original ?? CloudArchiveState()
        let current = wholeSecond(now)
        for entry in removedEntries {
            let id = entry.id.uuidString.uppercased()
            state.tombstones[id] = deletionStamp(
                now: current,
                previous: state.tombstones[id],
                lastUpdate: entry.updatedAt
            )
        }
        for course in removedCourses {
            let id = course.id.uuidString.uppercased()
            state.courseTombstones[id] = deletionStamp(
                now: current,
                previous: state.courseTombstones[id],
                lastUpdate: nil
            )
        }
        return state
    }

    /// Date parser shared with EntryArchive's decoder. It accepts Dart's
    /// whole-second UTC timestamps, fractional ISO-8601 timestamps, offsets,
    /// and its date-only planning/course keys.
    public static func decodeDate(_ text: String) -> Date? {
        if text.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil {
            let pieces = text.split(separator: "-").compactMap { Int($0) }
            guard pieces.count == 3 else { return nil }
            var parts = DateComponents()
            parts.year = pieces[0]; parts.month = pieces[1]; parts.day = pieces[2]
            return Calendar.current.date(from: parts)
        }
        return dateParser.date(from: text)
    }

    private struct ReadArchive {
        let archive: EntryArchive
        let rawEntries: [[String: Any]]
        let rawCourses: [[String: Any]]
        let metadata: [String: CloudJSONValue]
        let tombstones: [String: Date]
        let courseTombstones: [String: Date]
        let deletedCalendarOccurrences: [CalendarEventIdentity]
    }

    private static func emptyRemoteArchive() throws -> ReadArchive {
        try readArchive(#"{"version":1,"entries":[],"courses":[]}"#)
    }

    private static func readArchive(_ content: String) throws -> ReadArchive {
        guard let data = content.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CloudArchiveError.invalidArchive
        }
        guard (root["version"] as? NSNumber)?.intValue == 1 else {
            throw CloudArchiveError.unsupportedVersion
        }
        guard let rawEntries = root["entries"] as? [[String: Any]] else {
            throw CloudArchiveError.invalidArchive
        }
        let rawCourses: [[String: Any]]
        if let value = root["courses"], !(value is NSNull) {
            guard let courses = value as? [[String: Any]] else { throw CloudArchiveError.invalidArchive }
            rawCourses = courses
        } else {
            rawCourses = []
        }
        let validationRoot: [String: Any] = [
            "version": 1,
            "entries": rawEntries,
            "courses": rawCourses
        ]
        let validationData = try JSONSerialization.data(withJSONObject: validationRoot, options: [.sortedKeys])
        let archive: EntryArchive
        do {
            archive = try EntryArchive.decode(validationData)
        } catch {
            throw CloudArchiveError.invalidArchive
        }

        var metadata: [String: CloudJSONValue] = [:]
        for (key, value) in root where !archiveFields.contains(key) {
            if let converted = CloudJSONValue(foundationValue: value) {
                metadata[key] = converted
            } else {
                throw CloudArchiveError.invalidArchive
            }
        }
        return ReadArchive(
            archive: archive,
            rawEntries: rawEntries,
            rawCourses: rawCourses,
            metadata: metadata,
            tombstones: readMarkers(root["tombstones"]),
            courseTombstones: readMarkers(root["courseTombstones"]),
            deletedCalendarOccurrences: readDeletedCalendarOccurrences(root)
        )
    }

    private static func readMarkers(_ value: Any?) -> [String: Date] {
        guard let markers = value as? [String: Any] else { return [:] }
        var result: [String: Date] = [:]
        for (id, marker) in markers {
            guard let string = marker as? String, let date = decodeDate(string) else { continue }
            result[id.uppercased()] = date
        }
        return result
    }

    private static func readDeletedCalendarOccurrences(_ root: [String: Any]) -> [CalendarEventIdentity] {
        var values: [[String: Any]] = []
        if let direct = root["deletedCalendarOccurrences"] as? [[String: Any]] {
            values.append(contentsOf: direct)
        }
        if let replica = root["replica"] as? [String: Any],
           let document = replica["document"] as? [String: Any],
           let records = document["deletedCalendarOccurrences"] as? [[String: Any]] {
            values.append(contentsOf: records)
        }
        var result: [CalendarEventIdentity] = []
        for raw in values {
            guard let data = try? JSONSerialization.data(withJSONObject: raw),
                  let identity = try? JSONDecoder().decode(CalendarEventIdentity.self, from: data),
                  !result.contains(where: { $0.matches(identity) }) else { continue }
            result.append(identity)
        }
        return result
    }

    private static func mergedMarkers(_ local: [String: Date], _ remote: [String: Date]) -> [String: Date] {
        var result = local
        for (id, date) in remote {
            if result[id].map({ date > $0 }) ?? true { result[id] = date }
        }
        return result
    }

    private static func mergedCalendarOccurrences(
        _ existing: [CalendarEventIdentity],
        _ localReplica: [CalendarEventIdentity],
        _ remote: [CalendarEventIdentity]
    ) -> [CalendarEventIdentity] {
        var result: [CalendarEventIdentity] = []
        for identity in existing + localReplica + remote
        where !result.contains(where: { $0.matches(identity) }) {
            result.append(identity)
        }
        return result.sorted {
            [
                $0.eventID, $0.occurrence, $0.calendarID, $0.localEventID ?? "",
                $0.calendarTitle, $0.sourceTitle
            ].lexicographicallyPrecedes([
                $1.eventID, $1.occurrence, $1.calendarID, $1.localEventID ?? "",
                $1.calendarTitle, $1.sourceTitle
            ])
        }
    }

    private static func timestamp(in record: CloudJSONValue, key: String) -> Date? {
        guard case .object(let object) = record,
              case .string(let value)? = object[key] else { return nil }
        return decodeDate(value)
    }

    private static func timestamp(in record: [String: Any], key: String) -> Date? {
        guard let value = record[key] as? String else { return nil }
        return decodeDate(value)
    }

    private static func markerObject(_ markers: [String: Date]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: markers.map { ($0.key, tombstoneDate($0.value)) })
    }

    private static func deletionStamp(now: Date, previous: Date?, lastUpdate: Date?) -> Date {
        var candidates = [now]
        if let previous { candidates.append(wholeSecond(previous).addingTimeInterval(1)) }
        if let lastUpdate { candidates.append(wholeSecond(lastUpdate).addingTimeInterval(1)) }
        return candidates.max() ?? now
    }

    private static func wholeSecond(_ date: Date) -> Date {
        Date(timeIntervalSince1970: floor(date.timeIntervalSince1970))
    }

    private static func tombstoneDate(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: wholeSecond(date))
    }

    private static func stableEntryOrder(_ lhs: Entry, _ rhs: Entry) -> Bool {
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func materialize<T: Encodable>(
        _ value: T,
        base: CloudJSONValue?,
        fields: Set<String>
    ) throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(isoDate(date))
        }
        let data = try encoder.encode(value)
        guard var current = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CloudArchiveError.invalidArchive
        }
        var result: [String: Any]
        if case .object(let object)? = base {
            result = object.mapValues(\.foundationValue)
        } else {
            result = [:]
        }
        for field in fields { result.removeValue(forKey: field) }
        for (key, value) in current { result[key] = value }
        current.removeAll(keepingCapacity: false)
        guard let id = result["id"] as? String, !id.isEmpty else {
            throw CloudArchiveError.invalidArchive
        }
        return result
    }

    private static func isoDate(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
