import Foundation

public struct MessageParseResult {
    public let entry: Entry
    public let assumptions: [String]
}

/// Conservative local rules. Suggestions always pass through the editor before saving.
public enum MessageParser {
    public static func parse(_ text: String, now: Date = Date(), calendar: Calendar = .current) -> MessageParseResult {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let firstLine = raw.components(separatedBy: .newlines).first(where: { !$0.isEmpty }) ?? ""
        var entry = Entry(title: String(firstLine.prefix(80)), kind: raw.contains("作业") ? .homework : .task)
        entry.source = raw
        var assumptions: [String] = []
        let platforms = ["学习通", "雨课堂", "智慧树", "Moodle", "Canvas", "QQ群", "邮箱", "腾讯文档", "问卷星", "飞书", "钉钉"]
        entry.platform = platforms.first(where: { raw.localizedCaseInsensitiveContains($0) }) ?? ""
        if let parts = captures("[【\\[]([^】\\]]{1,20})[】\\]]", in: raw) { entry.category = parts[0] }
        if let values = captures("(?:预计|大约|约|耗时)\\s*(\\d{1,3})\\s*(分钟|小时)", in: raw), let amount = Int(values[0]) {
            let minutes = amount * (values[1] == "小时" ? 60 : 1)
            if (1...1440).contains(minutes) { entry.estimatedMinutes = minutes }
        }
        var components: DateComponents?
        if let values = captures("(20\\d{2})[-/年](\\d{1,2})[-/月](\\d{1,2})(?:日)?", in: raw),
           let year = Int(values[0]), let month = Int(values[1]), let day = Int(values[2]) {
            components = DateComponents(year: year, month: month, day: day)
        } else if let values = captures("(\\d{1,2})月(\\d{1,2})日", in: raw), let month = Int(values[0]), let day = Int(values[1]) {
            components = DateComponents(year: calendar.component(.year, from: now), month: month, day: day)
            assumptions.append("消息未写年份，按当前年份建议，请核对。")
        } else {
            let relative: [(String, Int)] = [("后天", 2), ("明天", 1), ("今天", 0)]
            if let match = relative.first(where: { raw.contains($0.0) }), let date = calendar.date(byAdding: .day, value: match.1, to: now) {
                components = calendar.dateComponents([.year, .month, .day], from: date)
                assumptions.append("相对日期按今天解析；旧群消息请手动改日期。")
            }
        }
        if var c = components {
            if let values = captures("(?<!\\d)([01]?\\d|2[0-3])[:：]([0-5]\\d)(?!\\d)", in: raw) {
                c.hour = Int(values[0]); c.minute = Int(values[1])
            } else { c.hour = 23; c.minute = 59; assumptions.append("未识别具体时刻，暂建议 23:59。") }
            c.second = 0
            if let date = calendar.date(from: c) {
                let check = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
                if check.year == c.year && check.month == c.month && check.day == c.day && check.hour == c.hour && check.minute == c.minute { entry.dueDate = date }
                else { assumptions.append("日期无效，未设置截止时间。") }
            }
        } else { assumptions.append("未可靠识别截止日期，请手动补充；星期和多日期消息需要人工确认。") }
        if entry.dueDate.map({ $0 < now }) == true { assumptions.append("建议日期已经过去，请确认这是不是旧消息。") }
        let datesPattern = "20\\d{2}[-/年]\\d{1,2}[-/月]\\d{1,2}(?:日)?|(?<![-/年])\\b\\d{1,2}月\\d{1,2}日|今天|明天|后天"
        if let regex = try? NSRegularExpression(pattern: datesPattern), regex.numberOfMatches(in: raw, range: NSRange(raw.startIndex..., in: raw)) > 1 {
            entry.dueDate = nil
            assumptions.append("消息包含多个日期，未自动设置 DDL，请在编辑时指定。")
        }
        if entry.dueDate.map({ $0 > now }) == true { entry.reminder = .atTime }
        return MessageParseResult(entry: entry, assumptions: assumptions)
    }
    private static func captures(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (1..<match.numberOfRanges).compactMap { Range(match.range(at: $0), in: text).map { String(text[$0]) } }
    }
}
