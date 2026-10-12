import AlarmKit
import Foundation
import AppIntents

@available(iOS 26.0, *)
struct ReminderAlarmMetadata: AlarmMetadata {
    let title: String
    let destination: String
}

@available(iOS 26.0, *)
struct StopReminderAlarmIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "停止提醒"
    @Parameter(title: "闹钟编号") var alarmID: String
    init() {}
    init(id: UUID) { alarmID = id.uuidString }
    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: alarmID) { try AlarmManager.shared.stop(id: id) }
        return .result()
    }
}

@available(iOS 26.0, *)
struct PauseReminderAlarmIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "暂停稍后提醒"
    @Parameter(title: "闹钟编号") var alarmID: String
    init() {}
    init(id: UUID) { alarmID = id.uuidString }
    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: alarmID) { try AlarmManager.shared.pause(id: id) }
        return .result()
    }
}

@available(iOS 26.0, *)
struct ResumeReminderAlarmIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "继续稍后提醒"
    @Parameter(title: "闹钟编号") var alarmID: String
    init() {}
    init(id: UUID) { alarmID = id.uuidString }
    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: alarmID) { try AlarmManager.shared.resume(id: id) }
        return .result()
    }
}
