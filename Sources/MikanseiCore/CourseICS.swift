import Foundation

/// A bounded iCalendar importer for timed class events. Unsupported recurrence rules
/// fail visibly rather than inventing weekly classes. Import expands to exact dates.
public enum CourseICS {
    private struct Property {
        let name: String
        let parameters: [String: String]
        let value: String
    }
    public static func parse(_ text: String, calendar: Calendar = .current) throws -> [Course] {
        let rawLines = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").components(separatedBy: "\n")
        var lines: [String] = []
        for line in rawLines {
            if (line.hasPrefix(" ") || line.hasPrefix("\t")), !lines.isEmpty { lines[lines.count - 1] += line.dropFirst() }
            else { lines.append(line) }
        }
        guard lines.contains("BEGIN:VCALENDAR"), lines.contains("END:VCALENDAR") else { throw failure("不是有效的 ICS 日历。") }
        var events: [[Property]] = [], current: [Property]? = nil, nested = 0
        for line in lines {
            if line == "BEGIN:VEVENT" {
                guard current == nil else { throw failure("ICS 事件嵌套无效。") }
                current = []; nested = 0
            } else if line == "END:VEVENT" {
                guard let event = current, nested == 0 else { throw failure("ICS 事件未正确结束。") }
                events.append(event); current = nil
            } else if current != nil {
                if line.hasPrefix("BEGIN:") { nested += 1; continue }
                if line.hasPrefix("END:") { nested -= 1; continue }
                if nested > 0 { continue } // VALARM is replaced with a class-registration prompt.
                guard let colon = line.firstIndex(of: ":") else { if line.isEmpty { continue }; throw failure("ICS 属性缺少冒号。") }
                let head = String(line[..<colon]).components(separatedBy: ";")
                var parameters: [String: String] = [:]
                for parameter in head.dropFirst() {
                    let parts = parameter.split(separator: "=", maxSplits: 1).map(String.init)
                    guard parts.count == 2 else { throw failure("ICS 属性参数无效。") }
                    parameters[parts[0].uppercased()] = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                }
                current!.append(Property(name: head[0].uppercased(), parameters: parameters, value: String(line[line.index(after: colon)...])))
            }
        }
        guard current == nil else { throw failure("ICS 事件未结束。") }
        var courses: [Course] = []
        for event in events {
            if event.contains(where: { $0.name == "RECURRENCE-ID" }) { throw failure("暂不支持带调课覆盖（RECURRENCE-ID）的 ICS，请先展开为逐次事件。") }
            if event.first(where: { $0.name == "STATUS" })?.value == "CANCELLED" { continue }
            guard let startProperty = event.first(where: { $0.name == "DTSTART" }),
                  let title = event.first(where: { $0.name == "SUMMARY" }) else { throw failure("课程缺少名称或开始时间。") }
            let start = try date(startProperty, fallback: calendar.timeZone)
            let end: Date
            if let endProperty = event.first(where: { $0.name == "DTEND" }) { end = try date(endProperty, fallback: calendar.timeZone) }
            else if let duration = event.first(where: { $0.name == "DURATION" }), let seconds = durationSeconds(duration.value) { end = start.addingTimeInterval(seconds) }
            else { throw failure("课程缺少结束时间（DTEND 或 DURATION）。") }
            guard end > start, end.timeIntervalSince(start) < 86400 else { throw failure("课程必须在同一天内结束。") }
            let rules = event.filter { $0.name == "RRULE" }
            guard rules.count <= 1 else { throw failure("暂不支持一节课含多条 RRULE。") }
            var starts: [Date] = [start]
            if let rule = rules.first {
                var recurrenceCalendar = calendar
                recurrenceCalendar.timeZone = try timeZone(startProperty, fallback: calendar.timeZone)
                starts = try expand(rule.value, start: start, calendar: recurrenceCalendar)
            }
            for property in event.filter({ $0.name == "RDATE" }) {
                for value in property.value.components(separatedBy: ",") {
                    starts.append(try date(Property(name: property.name, parameters: property.parameters, value: value), fallback: calendar.timeZone))
                }
            }
            var excluded: Set<Date> = []
            for property in event.filter({ $0.name == "EXDATE" }) {
                for value in property.value.components(separatedBy: ",") {
                    excluded.insert(try date(Property(name: property.name, parameters: property.parameters, value: value), fallback: calendar.timeZone))
                }
            }
            let startClock = calendar.dateComponents([.hour, .minute, .second], from: start)
            let endClock = calendar.dateComponents([.hour, .minute, .second], from: end)
            guard startClock.second == 0, endClock.second == 0 else { throw failure("课表只支持精确到分钟的开始和结束时间。") }
            for occurrence in Set(starts).subtracting(excluded).sorted() {
                // Derive the end by wall-clock duration in the source timezone, preserving DST.
                let occurrenceEnd = occurrence.addingTimeInterval(end.timeIntervalSince(start))
                guard calendar.isDate(occurrence, inSameDayAs: occurrenceEnd) else { throw failure("转换到手机时区后，课程跨天；请手动添加。") }
                let startParts = calendar.dateComponents([.hour, .minute], from: occurrence)
                let endParts = calendar.dateComponents([.hour, .minute], from: occurrenceEnd)
                var course = Course()
                course.name = unescape(title.value)
                course.weekday = (calendar.component(.weekday, from: occurrence) + 5) % 7 + 1
                course.startMinutes = startParts.hour! * 60 + startParts.minute!
                course.endMinutes = endParts.hour! * 60 + endParts.minute!
                course.firstDate = calendar.startOfDay(for: occurrence)
                course.lastDate = course.firstDate
                course.location = unescape(event.first(where: { $0.name == "LOCATION" })?.value ?? "")
                guard course.isValid else { throw failure("课程名称或时间无效。") }
                courses.append(course)
                guard courses.count <= 2048 else { throw failure("课表超过 2048 次课程，请按学期拆分导入。") }
            }
        }
        guard !courses.isEmpty else { throw failure("文件里没有可导入的课程。") }
        return courses
    }
    private static func expand(_ text: String, start: Date, calendar: Calendar) throws -> [Date] {
        var parts: [String: String] = [:]
        for item in text.components(separatedBy: ";") {
            let pair = item.split(separator: "=", maxSplits: 1).map(String.init)
            guard pair.count == 2, parts[pair[0]] == nil else { throw failure("RRULE 格式无效。") }
            parts[pair[0]] = pair[1]
        }
        guard Set(parts.keys).isSubset(of: ["FREQ", "INTERVAL", "BYDAY", "UNTIL", "COUNT", "WKST"]),
              let frequency = parts["FREQ"], ["WEEKLY", "DAILY"].contains(frequency) else { throw failure("仅支持有截止范围的 DAILY/WEEKLY 循环；复杂规则请导出逐次事件。") }
        let interval = Int(parts["INTERVAL"] ?? "1") ?? 0
        guard (1...52).contains(interval) else { throw failure("ICS 循环间隔无效。") }
        if let weekStart = parts["WKST"], weekStart != "MO" { throw failure("暂只支持以周一为起点的循环。") }
        let count: Int?
        if let rawCount = parts["COUNT"] {
            guard let value = Int(rawCount), (1...2048).contains(value) else { throw failure("ICS COUNT 范围必须为 1–2048。") }
            count = value
        } else { count = nil }
        let until: Date?
        if let value = parts["UNTIL"] { until = try date(Property(name: "UNTIL", parameters: [:], value: value), fallback: calendar.timeZone) }
        else { until = nil }
        guard count != nil || until != nil else { throw failure("无限循环的课程缺少 UNTIL 或 COUNT，请限定学期。") }
        guard !(count != nil && until != nil) else { throw failure("RRULE 不能同时包含 COUNT 和 UNTIL。") }
        let dayCodes = ["MO": 1, "TU": 2, "WE": 3, "TH": 4, "FR": 5, "SA": 6, "SU": 7]
        let defaultDay = (calendar.component(.weekday, from: start) + 5) % 7 + 1
        var weekdays = Set([defaultDay])
        if let byDay = parts["BYDAY"] {
            let codes = byDay.components(separatedBy: ",")
            guard codes.allSatisfy({ dayCodes[$0] != nil }) else { throw failure("暂不支持带序号的 BYDAY。") }
            weekdays = Set(codes.compactMap { dayCodes[$0] })
        }
        if frequency == "DAILY" && parts["BYDAY"] != nil { throw failure("暂不支持 DAILY 与 BYDAY 组合。") }
        if frequency == "WEEKLY" && !weekdays.contains(defaultDay) { throw failure("DTSTART 的星期与循环规则不一致，请检查课表。") }
        let hardEnd = calendar.date(byAdding: .year, value: 2, to: start)!
        if let until, until > hardEnd { throw failure("课程循环超过两年，请按学期拆分。") }
        let startDay = calendar.startOfDay(for: start)
        let clock = calendar.dateComponents([.hour, .minute, .second], from: start)
        var result: [Date] = []
        for offset in 0...732 {
            let day = calendar.date(byAdding: .day, value: offset, to: startDay)!
            let isoDay = (calendar.component(.weekday, from: day) + 5) % 7 + 1
            let weekNumber = (offset + defaultDay - 1) / 7
            let matches = frequency == "DAILY" ? offset % interval == 0 : weekNumber % interval == 0 && weekdays.contains(isoDay)
            guard matches else { continue }
            let occurrence = calendar.date(bySettingHour: clock.hour!, minute: clock.minute!, second: clock.second!, of: day)!
            if occurrence < start { continue }
            if occurrence > hardEnd || until.map({ occurrence > $0 }) == true { break }
            result.append(occurrence)
            if let count, result.count >= count { break }
        }
        if let count, result.count != count { throw failure("无法在两年范围内展开全部课程。") }
        return result
    }
    private static func timeZone(_ property: Property, fallback: TimeZone) throws -> TimeZone {
        if property.value.hasSuffix("Z") { return TimeZone(secondsFromGMT: 0)! }
        if let id = property.parameters["TZID"] {
            guard let zone = TimeZone(identifier: id) else { throw failure("无法识别 ICS 时区：\(id)。") }
            return zone
        }
        return fallback
    }
    private static func date(_ property: Property, fallback: TimeZone) throws -> Date {
        guard property.parameters["VALUE"] == nil || property.parameters["VALUE"] == "DATE-TIME",
              property.value.count == 15 || property.value.count == 16 else { throw failure("仅支持含具体时刻的课程，不支持全天事件。") }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = try timeZone(property, fallback: fallback)
        formatter.dateFormat = property.value.hasSuffix("Z") ? "yyyyMMdd'T'HHmmss'Z'" : "yyyyMMdd'T'HHmmss"
        formatter.isLenient = false
        guard let result = formatter.date(from: property.value), formatter.string(from: result) == property.value else { throw failure("ICS 日期或时间无效。") }
        return result
    }
    private static func durationSeconds(_ value: String) -> TimeInterval? {
        let pattern = "^PT(?:(\\d+)H)?(?:(\\d+)M)?(?:(\\d+)S)?$"
        guard let regex = try? NSRegularExpression(pattern: pattern), let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) else { return nil }
        let numbers = (1...3).map { index -> Int in
            guard let range = Range(match.range(at: index), in: value) else { return 0 }
            return Int(value[range]) ?? 0
        }
        let seconds = numbers[0] * 3600 + numbers[1] * 60 + numbers[2]
        return seconds > 0 ? Double(seconds) : nil
    }
    private static func unescape(_ value: String) -> String {
        value.replacingOccurrences(of: "\\n", with: "\n").replacingOccurrences(of: "\\N", with: "\n")
            .replacingOccurrences(of: "\\,", with: ",").replacingOccurrences(of: "\\;", with: ";").replacingOccurrences(of: "\\\\", with: "\\")
    }
    private static func failure(_ message: String) -> CourseImportError { .malformed(message) }
}
