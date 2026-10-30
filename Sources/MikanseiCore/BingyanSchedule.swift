import Foundation
import CryptoKit

/// The shape returned by Bingyan's documented GET /v1/schedule/days endpoint.
public struct BingyanScheduleResponse: Decodable {
    public let days: [BingyanScheduleDay]
}

public struct BingyanScheduleDay: Decodable {
    public let date: String
    public let weekday: Int
    public let inTerm: Bool
    public let periodTable: String
    public let termId: String?
    public let week: Int?
    public let lessons: [BingyanScheduleLesson]
    public let events: [BingyanScheduleEvent]
}

public struct BingyanScheduleLesson: Decodable {
    public let course: String
    public let startPeriod: Int
    public let endPeriod: Int
    public let startTime: String?
    public let endTime: String?
    public let location: String?
    public let teacher: String?
}

public struct BingyanScheduleEvent: Decodable {
    public let name: String
    public let date: String
    public let period: Int
    public let content: String?
    public let startTime: String?
    public let endTime: String?
}

public struct BingyanSchedulePreviewItem: Identifiable {
    public let id: String
    public let title: String
    public let start: Date
    public let end: Date
    public let location: String
    public let details: String
    public let isCourse: Bool
}

public struct BingyanScheduleImportBatch {
    public let courses: [Course]
    public let schedules: [Entry]
    public let items: [BingyanSchedulePreviewItem]
    public let skippedCount: Int

    public var hasImportableItems: Bool { !schedules.isEmpty }
}

public enum BingyanScheduleImportError: LocalizedError {
    case invalidJSON
    case invalidDateRange
    case tooManyCourseOccurrences

    public var errorDescription: String? {
        switch self {
        case .invalidJSON: return "文件不是冰岩每日课表 JSON（需要包含 days 数组）。"
        case .invalidDateRange: return "日期范围无效，或超过 200 天。"
        case .tooManyCourseOccurrences: return "课程展开后超过 2,048 次日程，请缩短日期范围。"
        }
    }
}

/// Direct read-only client for the documented Bingyan API. API keys are supplied
/// by the caller and are never persisted by this type.
public struct BingyanScheduleClient {
    public static let apiBaseURL = URL(string: "https://open-api.bingyan.net")!

    public init() {}

    public func fetch(from: String, to: String, periodTable: String?, apiKey: String) async throws -> BingyanScheduleResponse {
        var shanghaiCalendar = Calendar(identifier: .gregorian)
        shanghaiCalendar.timeZone = BingyanScheduleDate.timeZone
        guard let fromDate = BingyanScheduleDate.parseDay(from),
              let toDate = BingyanScheduleDate.parseDay(to),
              toDate >= fromDate,
              let dayCount = shanghaiCalendar.dateComponents([.day], from: fromDate, to: toDate).day,
              dayCount < 200 else { throw BingyanScheduleImportError.invalidDateRange }
        guard let trimmedKey = apiKey.nilIfBlank else {
            throw BingyanScheduleHTTPError(statusCode: 401, message: "请先填写冰岩个人 API Key。")
        }
        var components = URLComponents(url: Self.apiBaseURL
            .appendingPathComponent("v1")
            .appendingPathComponent("schedule")
            .appendingPathComponent("days"),
                                       resolvingAgainstBaseURL: false)!
        var query = [
            URLQueryItem(name: "from", value: from),
            URLQueryItem(name: "to", value: to)
        ]
        if let periodTable, ["winter", "summer", "cyber"].contains(periodTable) {
            query.append(URLQueryItem(name: "period_table", value: periodTable))
        }
        components.queryItems = query
        guard let url = components.url else { throw BingyanScheduleImportError.invalidDateRange }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpShouldHandleCookies = false
        request.httpShouldUsePipelining = false
        request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let requestSession = URLSession(configuration: configuration)
        defer { requestSession.finishTasksAndInvalidate() }
        let (data, response) = try await requestSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw BingyanScheduleHTTPError(statusCode: 0, message: "冰岩课表服务没有返回有效响应。")
        }
        guard (200..<300).contains(http.statusCode) else {
            let apiError = try? JSONDecoder().decode(BingyanScheduleAPIError.self, from: data)
            let message = apiError?.error.message ?? "冰岩课表读取失败（HTTP \(http.statusCode)）。"
            throw BingyanScheduleHTTPError(statusCode: http.statusCode, message: message)
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do { return try decoder.decode(BingyanScheduleResponse.self, from: data) }
        catch { throw BingyanScheduleImportError.invalidJSON }
    }
}

public struct BingyanScheduleHTTPError: LocalizedError {
    public let statusCode: Int
    public let message: String
    public var errorDescription: String? { message }
}

private struct BingyanScheduleAPIError: Decodable {
    struct Detail: Decodable {
        let code: String
        let message: String
    }
    let error: Detail
}

public enum BingyanScheduleImportBuilder {
    /// Turns only entries with exact API-provided wall times into importable rows.
    /// Missing times are counted and excluded; no section-time table is inferred.
    public static func build(_ response: BingyanScheduleResponse,
                             calendar: Calendar = .current,
                             courseRemindersEnabled: Bool = true) -> BingyanScheduleImportBatch {
        var courses: [Course] = []
        var schedules: [Entry] = []
        var items: [BingyanSchedulePreviewItem] = []
        var skipped = 0
        var seenSources = Set<String>()

        for day in response.days {
            let dateText = day.date
            let identityScope = (day.termId?.nilIfBlank ?? day.periodTable)
            let sortedLessons = day.lessons.sorted {
                if $0.startPeriod != $1.startPeriod { return $0.startPeriod < $1.startPeriod }
                if $0.endPeriod != $1.endPeriod { return $0.endPeriod < $1.endPeriod }
                if $0.course != $1.course { return $0.course.localizedStandardCompare($1.course) == .orderedAscending }
                if ($0.location ?? "") != ($1.location ?? "") { return ($0.location ?? "") < ($1.location ?? "") }
                return ($0.teacher ?? "") < ($1.teacher ?? "")
            }
            for lesson in sortedLessons {
                guard let startTime = lesson.startTime, let endTime = lesson.endTime,
                      let start = BingyanScheduleDate.parse(date: dateText, time: startTime),
                      let end = BingyanScheduleDate.parse(date: dateText, time: endTime),
                      end > start,
                      BingyanScheduleDate.sameShanghaiDay(start, end) else {
                    skipped += 1
                    continue
                }
                let title = lesson.course.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty,
                      let course = makeCourse(name: title, location: lesson.location ?? "",
                                              start: start, end: end, calendar: calendar) else {
                    skipped += 1
                    continue
                }
                let source = BingyanScheduleIdentity.source(fields: [
                    "v1", identityScope, dateText, "lesson", BingyanScheduleIdentity.normalized(title),
                    String(lesson.startPeriod), String(lesson.endPeriod)
                ])
                guard seenSources.insert(source).inserted else { continue }
                courses.append(course)
                var details = ["第 \(lesson.startPeriod)–\(lesson.endPeriod) 节"]
                if let teacher = lesson.teacher?.nilIfBlank { details.append(teacher) }
                if let location = lesson.location?.nilIfBlank { details.append(location) }
                let entry = makeSchedule(title: title, detail: details.joined(separator: " · "),
                                         location: lesson.location ?? "", start: start, end: end,
                                         source: source, reminderEnabled: false)
                schedules.append(entry)
                items.append(BingyanSchedulePreviewItem(id: source, title: title, start: start, end: end,
                                                         location: lesson.location ?? "",
                                                         details: details.joined(separator: " · "), isCourse: true))
            }

            let sortedEvents = day.events.sorted {
                if $0.period != $1.period { return $0.period < $1.period }
                if $0.name != $1.name { return $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                return ($0.content ?? "") < ($1.content ?? "")
            }
            for event in sortedEvents {
                guard let startTime = event.startTime, let endTime = event.endTime,
                      let start = BingyanScheduleDate.parse(date: event.date, time: startTime),
                      let end = BingyanScheduleDate.parse(date: event.date, time: endTime),
                      end > start,
                      BingyanScheduleDate.sameShanghaiDay(start, end) else {
                    skipped += 1
                    continue
                }
                let title = event.name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty else { skipped += 1; continue }
                let source = BingyanScheduleIdentity.source(fields: [
                    "v1", identityScope, event.date, "event", BingyanScheduleIdentity.normalized(title),
                    String(event.period)
                ])
                guard seenSources.insert(source).inserted else { continue }
                let detail = event.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let entry = makeSchedule(title: title, detail: detail, location: "",
                                         start: start, end: end, source: source, reminderEnabled: false)
                schedules.append(entry)
                items.append(BingyanSchedulePreviewItem(id: source, title: title, start: start, end: end,
                                                         location: "", details: detail, isCourse: false))
            }
        }

        if courseRemindersEnabled == false {
            courses = courses.map { course in var copy = course; copy.reminderEnabled = false; return copy }
        }
        let order: (BingyanSchedulePreviewItem, BingyanSchedulePreviewItem) -> Bool = {
            if $0.start != $1.start { return $0.start < $1.start }
            if $0.title != $1.title { return $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            return $0.id < $1.id
        }
        items.sort(by: order)
        schedules.sort {
            if $0.plannedStart != $1.plannedStart { return ($0.plannedStart ?? .distantPast) < ($1.plannedStart ?? .distantPast) }
            return $0.source < $1.source
        }
        return BingyanScheduleImportBatch(courses: courses, schedules: schedules, items: items, skippedCount: skipped)
    }

    private static func makeCourse(name: String, location: String, start: Date, end: Date,
                                   calendar: Calendar) -> Course? {
        let startParts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: start)
        let endParts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: end)
        guard startParts.year == endParts.year, startParts.month == endParts.month,
              startParts.day == endParts.day, let hour = startParts.hour, let minute = startParts.minute,
              let endHour = endParts.hour, let endMinute = endParts.minute,
              let day = calendar.date(from: DateComponents(year: startParts.year, month: startParts.month, day: startParts.day)) else { return nil }
        var course = Course()
        course.name = name
        course.weekday = (calendar.component(.weekday, from: day) + 5) % 7 + 1
        course.startMinutes = hour * 60 + minute
        course.endMinutes = endHour * 60 + endMinute
        course.location = location
        course.firstDate = calendar.startOfDay(for: day)
        course.lastDate = course.firstDate
        return course.isValid ? course : nil
    }

    private static func makeSchedule(title: String, detail: String, location: String,
                                     start: Date, end: Date, source: String,
                                     reminderEnabled: Bool) -> Entry {
        var entry = Entry(title: title, kind: .schedule, dueDate: start)
        entry.body = detail
        entry.category = "课程"
        entry.location = location
        entry.plannedStart = start
        entry.plannedEnd = end
        entry.plannedAllDay = false
        entry.reminder = reminderEnabled ? .atTime : nil
        entry.reminderDelivery = .popup
        entry.reminderAnchor = .execution
        entry.source = source
        return entry
    }
}

/// Optional conversion for imported or manually-created recurring Course rows.
public enum CourseScheduleConversion {
    public static let occurrenceLimit = 2_048

    public static func schedules(for courses: [Course], calendar: Calendar = .current) throws -> [Entry] {
        var entries: [Entry] = []
        var known = Set<String>()
        for course in courses where course.isValid {
            var day = calendar.startOfDay(for: course.firstDate)
            let lastDay = calendar.startOfDay(for: course.lastDate)
            var walked = 0
            while day <= lastDay {
                walked += 1
                guard walked <= 732 else { throw BingyanScheduleImportError.tooManyCourseOccurrences }
                let weekday = (calendar.component(.weekday, from: day) + 5) % 7 + 1
                if weekday == course.weekday,
                   let start = calendar.date(bySettingHour: course.startMinutes / 60,
                                             minute: course.startMinutes % 60, second: 0, of: day),
                   let end = calendar.date(bySettingHour: course.endMinutes / 60,
                                           minute: course.endMinutes % 60, second: 0, of: day),
                   end > start {
                    let dateKey = BingyanScheduleDate.string(from: day, calendar: calendar)
                    let source = BingyanScheduleIdentity.source(fields: [
                        "v1", "course", dateKey, "lesson",
                        BingyanScheduleIdentity.normalized(course.name),
                        String(course.startMinutes), String(course.endMinutes),
                        BingyanScheduleIdentity.normalized(course.location)
                    ])
                    if known.insert(source).inserted {
                        var entry = Entry(title: course.name, kind: .schedule, dueDate: start)
                        entry.body = course.weekdayTitle + " · " + course.timeLabel
                        entry.category = "课程"
                        entry.location = course.location
                        entry.plannedStart = start
                        entry.plannedEnd = end
                        entry.plannedAllDay = false
                        entry.reminder = nil
                        entry.reminderDelivery = .popup
                        entry.reminderAnchor = .execution
                        entry.source = source
                        entries.append(entry)
                        guard entries.count <= occurrenceLimit else {
                            throw BingyanScheduleImportError.tooManyCourseOccurrences
                        }
                    }
                }
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }
        }
        return entries
    }
}

public enum BingyanScheduleIdentity {
    public static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping
    }

    /// Length-prefixed UTF-8 fields avoid ambiguity; SHA-256 keeps Entry.source compact.
    public static func source(fields: [String]) -> String {
        let canonical = fields.map { "\($0.utf8.count):\($0)" }.joined()
        let digest = SHA256.hash(data: Data(canonical.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "bingyan.schedule:\(hex)"
    }
}

public enum BingyanScheduleDate {
    public static let timeZone = TimeZone(identifier: "Asia/Shanghai")!
    public static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    public static func parseDay(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard let date = formatter.date(from: value), formatter.string(from: date) == value else { return nil }
        return date
    }

    public static func parse(date: String, time: String) -> Date? {
        guard time.range(of: #"^\d{2}:\d{2}$"#, options: .regularExpression) != nil,
              let day = parseDay(date) else { return nil }
        let parts = time.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2, (0..<24).contains(parts[0]), (0..<60).contains(parts[1]) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = self.timeZone
        return calendar.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: day)
    }

    public static func sameShanghaiDay(_ lhs: Date, _ rhs: Date) -> Bool {
        self.calendar.isDate(lhs, inSameDayAs: rhs)
    }

    public static func string(from date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = parts.year, let month = parts.month, let day = parts.day else { return "" }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
