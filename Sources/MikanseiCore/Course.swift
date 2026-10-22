import Foundation

public struct Course: Identifiable, Codable, Equatable {
    public var id: UUID = UUID()
    public var name: String = ""
    /// ISO weekday: Monday = 1, Sunday = 7.
    public var weekday: Int = 1
    public var startMinutes: Int = 8 * 60
    public var endMinutes: Int = 9 * 60 + 40
    public var location: String = ""
    public var platform: String = ""
    public var firstDate: Date = Date()
    public var lastDate: Date = Calendar.current.date(byAdding: .day, value: 112, to: Date())!
    public var reminderEnabled: Bool = true
    public var reminderDelivery: ReminderDelivery = .popup
    public var reminderSound: ReminderSound = .system
    public var snoozeMinutes = 5
    public init() {}
    private enum CodingKeys: String, CodingKey { case id, name, weekday, startMinutes, endMinutes, location, platform, firstDate, lastDate, reminderEnabled, reminderDelivery, reminderSound, snoozeMinutes }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id); name = try c.decode(String.self, forKey: .name)
        weekday = try c.decode(Int.self, forKey: .weekday); startMinutes = try c.decode(Int.self, forKey: .startMinutes); endMinutes = try c.decode(Int.self, forKey: .endMinutes)
        location = try c.decode(String.self, forKey: .location); platform = try c.decode(String.self, forKey: .platform)
        firstDate = try c.decode(Date.self, forKey: .firstDate); lastDate = try c.decode(Date.self, forKey: .lastDate)
        reminderEnabled = try c.decode(Bool.self, forKey: .reminderEnabled)
        reminderDelivery = try c.decodeIfPresent(ReminderDelivery.self, forKey: .reminderDelivery) ?? .popup
        reminderSound = try c.decodeIfPresent(ReminderSound.self, forKey: .reminderSound) ?? .system
        snoozeMinutes = try c.decodeIfPresent(Int.self, forKey: .snoozeMinutes) ?? 5
    }
    public var weekdayTitle: String { ["周一", "周二", "周三", "周四", "周五", "周六", "周日"][max(0, min(6, weekday - 1))] }
    public static func timeLabel(_ minutes: Int) -> String { String(format: "%02d:%02d", minutes / 60, minutes % 60) }
    public var timeLabel: String { "\(Self.timeLabel(startMinutes))–\(Self.timeLabel(endMinutes))" }
    public var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (1...7).contains(weekday) && (0..<1440).contains(startMinutes) &&
        (0..<1440).contains(endMinutes) && endMinutes > startMinutes && lastDate >= firstDate && [5, 10, 15].contains(snoozeMinutes)
    }
    public func occurrences(after now: Date, days: Int = 28, calendar: Calendar = .current) -> [Date] {
        guard isValid, reminderEnabled else { return [] }
        let start = calendar.startOfDay(for: now)
        return (0..<max(0, days)).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: start),
                  day >= calendar.startOfDay(for: firstDate), day <= calendar.startOfDay(for: lastDate),
                  (calendar.component(.weekday, from: day) + 5) % 7 + 1 == weekday,
                  let end = calendar.date(bySettingHour: endMinutes / 60, minute: endMinutes % 60, second: 0, of: day), end > now else { return nil }
            return end
        }
    }
    public func homeworkDraft() -> Entry {
        var entry = Entry(kind: .homework, category: name)
        entry.platform = platform
        entry.source = "课后登记：\(name) · \(weekdayTitle) \(timeLabel)"
        return entry
    }
}

public struct PlannedNotification: Identifiable, Equatable, Codable {
    public let id: String
    public let date: Date
    public let title: String
    public let body: String
    public let entryID: UUID?
    public let courseID: UUID?
    public var delivery: ReminderDelivery = .popup
    public var sound: ReminderSound = .system
    public var snoozeMinutes = 5
    public func isStillEnabled(entries: [Entry], courses: [Course]) -> Bool {
        let owners = entries.filter { $0.id == entryID }
        let courseOwners = courses.filter { $0.id == courseID }
        return NotificationPlan.pending(entries: owners, courses: courseOwners, now: date.addingTimeInterval(-1), limit: Int.max).contains(self)
    }
}

public enum NotificationPlan {
    public static func pending(entries: [Entry], courses: [Course], now: Date = Date(), limit: Int = 60, calendar: Calendar = .current) -> [PlannedNotification] {
        var events: [PlannedNotification] = []
        let successors = Entry.successorDates(in: entries)
        for entry in entries {
            guard entry.isTask, !entry.isCompleted, entry.reminder != nil, let due = entry.reminderReferenceDate else { continue }
            var dates: [Date]
            if entry.allowsLocalSuccessorGeneration {
                let horizon = calendar.date(byAdding: .day, value: 28, to: now)!
                let lead = Double(entry.reminder!.rawValue)
                let offset = due.timeIntervalSince(entry.recurrenceReferenceDate ?? due)
                // Enumerate using the same rules as the calendar, including selected dates and month ends.
                let start = now.addingTimeInterval(lead - offset)
                let end = min(horizon.addingTimeInterval(lead - offset + 1), successors[entry.id] ?? .distantFuture)
                dates = entry.occurrenceDates(in: start..<max(start, end), calendar: calendar)
                    .compactMap { entry.occurrence(at: $0, calendar: calendar).reminderDate }
                    .filter { $0 <= horizon }
            } else {
            switch entry.reminderPattern {
            case .single: dates = entry.reminderDate.map { [$0] } ?? []
            case .stepped: dates = [-86400.0, -7200, 0, 7200].map { due.addingTimeInterval($0) }
            case .persistent:
                dates = [-86400.0, -7200, 0].map { due.addingTimeInterval($0) }
                dates += (1...12).map { due.addingTimeInterval(Double($0 * 7200)) }
            }
            }
            for date in dates where date > now {
                let overdue = entry.repeatRule == .never && entry.dueDate != nil && entry.reminderAnchor == .deadline && date > due
                let minutes = entry.estimatedMinutes.map { " · 约 \($0) 分钟" } ?? ""
                let details = [entry.category, entry.platform, entry.location].filter { !$0.isEmpty }.joined(separator: " · ")
                events.append(PlannedNotification(id: "entry.\(entry.id).\(Int(date.timeIntervalSince1970))", date: date,
                    title: overdue ? "尚未完成：\(entry.title)" : entry.title,
                    body: "\(entry.repeatRule != .never ? "例行事项 · " + entry.repeatLabel : overdue ? "已过截止时间" : "\(entry.reminderAnchor == .execution || entry.dueDate == nil ? "安排" : "截止") \(due.formatted(.dateTime.month().day().hour().minute()))")\(minutes)\(details.isEmpty ? "" : "\n" + details)", entryID: entry.id, courseID: nil, delivery: entry.reminderDelivery, sound: entry.reminderSound, snoozeMinutes: entry.snoozeMinutes))
            }
        }
        for course in courses {
            for date in course.occurrences(after: now, calendar: calendar) {
                events.append(PlannedNotification(id: "course.\(course.id).\(Int(date.timeIntervalSince1970))", date: date,
                    title: "\(course.name)下课了，登记一下？", body: "有什么作业？DDL 是什么时候？在哪提交？大约需要多久？点击快速记下。", entryID: nil, courseID: course.id, delivery: course.reminderDelivery, sound: course.reminderSound, snoozeMinutes: course.snoozeMinutes))
            }
        }
        return Array(events.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }.prefix(max(0, limit)))
    }
}

public enum CourseImportError: LocalizedError {
    case malformed(String)
    public var errorDescription: String? { if case .malformed(let message) = self { return message }; return nil }
}

public enum CourseCSV {
    public static let header = "课程,星期,开始时间,结束时间,地点,提交平台,开始日期,结束日期"
    public static func parse(_ text: String, calendar: Calendar = .current) throws -> [Course] {
        let rows = try CSV.rows(text.replacingOccurrences(of: "\u{FEFF}", with: ""))
        guard let first = rows.first, first == header.components(separatedBy: ",") else {
            throw CourseImportError.malformed("请使用课表 CSV 模板的 8 列表头。")
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return try rows.dropFirst().enumerated().map { index, row in
            guard row.count == 8, let weekday = Int(row[1]), let start = minutes(row[2]), let end = minutes(row[3]),
                  let firstDate = formatter.date(from: row[6]), let lastDate = formatter.date(from: row[7]) else {
                throw CourseImportError.malformed("第 \(index + 2) 行格式错误：星期用 1–7，时间用 HH:mm，日期用 yyyy-MM-dd。")
            }
            var course = Course()
            course.name = row[0].trimmingCharacters(in: .whitespacesAndNewlines)
            course.weekday = weekday
            course.startMinutes = start
            course.endMinutes = end
            course.location = row[4]
            course.platform = row[5]
            course.firstDate = firstDate
            course.lastDate = lastDate
            guard course.isValid else { throw CourseImportError.malformed("第 \(index + 2) 行的课程名、时间或日期范围无效。") }
            return course
        }
    }
    private static func minutes(_ text: String) -> Int? {
        let parts = text.split(separator: ":")
        guard parts.count == 2, let hours = Int(parts[0]), let minutes = Int(parts[1]), (0..<24).contains(hours), (0..<60).contains(minutes) else { return nil }
        return hours * 60 + minutes
    }
}

private enum CSV {
    static func rows(_ text: String) throws -> [[String]] {
        var result: [[String]] = [], row: [String] = [], field = ""
        var quoted = false, afterQuote = false
        let chars = Array(text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n"))
        var i = 0
        while i < chars.count {
            let char = chars[i]
            if quoted {
                if char == "\"" {
                    if i + 1 < chars.count && chars[i + 1] == "\"" { field.append("\""); i += 1 }
                    else { quoted = false; afterQuote = true }
                } else { field.append(char) }
            } else if char == "," {
                row.append(field); field = ""; afterQuote = false
            } else if char == "\n" {
                row.append(field)
                if !row.allSatisfy({ $0.isEmpty }) { result.append(row) }
                row = []; field = ""; afterQuote = false
            } else if char == "\"" && field.isEmpty && !afterQuote { quoted = true }
            else if afterQuote { throw CourseImportError.malformed("CSV 引号后的字符无效。") }
            else if char == "\"" { throw CourseImportError.malformed("CSV 引号位置无效。") }
            else { field.append(char) }
            i += 1
        }
        guard !quoted else { throw CourseImportError.malformed("CSV 有未闭合的引号。") }
        row.append(field)
        if !row.allSatisfy({ $0.isEmpty }) { result.append(row) }
        return result
    }
}
