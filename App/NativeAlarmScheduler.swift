import AlarmKit
import ActivityKit
import SwiftUI

@available(iOS 26.0, *)
@MainActor
final class NativeAlarmScheduler {
    private let manager = AlarmManager.shared
    private let key = "Mikansei.AlarmRecords.v1"
    private var records: [AlarmRecord]
    init() {
        records = UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode([AlarmRecord].self, from: $0) } ?? []
    }
    var status: String {
        switch manager.authorizationState {
        case .authorized: return "已开启"
        case .denied: return "未允许"
        case .notDetermined: return "尚未申请"
        @unknown default: return "暂不可用"
        }
    }
    var authorized: Bool { manager.authorizationState == .authorized }
    func requestAccess() async throws -> Bool {
        if manager.authorizationState == .notDetermined { _ = try await manager.requestAuthorization() }
        return authorized
    }
    private func persist() throws { UserDefaults.standard.set(try JSONEncoder().encode(records), forKey: key) }
    func reconcile(_ desired: [PlannedNotification], entries: [Entry], courses: [Course]) async -> (Int, String?) {
        guard authorized else { return (0, desired.isEmpty ? nil : "闹钟权限未开启，选为闹钟的事项尚未安排。") }
        do {
            let liveIDs = Set(try manager.alarms.map(\.id))
            let retained = AlarmReconciliation.retained(records, liveIDs: liveIDs, desired: desired, entries: entries, courses: courses, now: Date())
            for record in records where !retained.contains(record) && liveIDs.contains(record.id) {
                try manager.cancel(id: record.id)
            }
            records = retained
            try persist()
            var failures: String?
            for event in desired where !records.contains(where: { $0.event == event }) {
                guard event.date > Date() else { continue }
                let record = AlarmRecord(event: event)
                // Persist the identifier first so a crash cannot leave an untracked system alarm.
                records.append(record)
                try persist()
                do {
                    _ = try await manager.schedule(id: record.id, configuration: configuration(for: event, id: record.id))
                } catch {
                    records.removeAll { $0.id == record.id }
                    try persist()
                    if let alarmError = error as? AlarmManager.AlarmError, alarmError == .maximumLimitReached {
                        failures = "系统闹钟数量已达上限，部分提醒尚未安排。完成事项后或再次打开 App 会补充。"
                        break
                    }
                    failures = "部分闹钟未能安排：\(error.localizedDescription)"
                }
            }
            return (records.count, failures)
        } catch { return (0, "无法更新系统闹钟：\(error.localizedDescription)") }
    }
    private func configuration(for event: PlannedNotification, id: UUID) -> AlarmManager.AlarmConfiguration<ReminderAlarmMetadata> {
        let title = LocalizedStringResource(stringLiteral: event.title)
        let snooze = AlarmButton(text: "稍后提醒", textColor: .white, systemImageName: "zzz")
        let alert: AlarmPresentation.Alert
        if #available(iOS 26.1, *) {
            alert = AlarmPresentation.Alert(title: title, secondaryButton: snooze, secondaryButtonBehavior: .countdown)
        } else {
            alert = AlarmPresentation.Alert(title: title, stopButton: AlarmButton(text: "停止", textColor: .white, systemImageName: "stop.fill"), secondaryButton: snooze, secondaryButtonBehavior: .countdown)
        }
        let countdown = AlarmPresentation.Countdown(title: title, pauseButton: AlarmButton(text: "暂停", textColor: .white, systemImageName: "pause.fill"))
        let paused = AlarmPresentation.Paused(title: title, resumeButton: AlarmButton(text: "继续", textColor: .white, systemImageName: "play.fill"))
        let destination = event.entryID.map { "mikansei://entry/\($0)" } ?? "mikansei://today"
        let attributes = AlarmAttributes(presentation: AlarmPresentation(alert: alert, countdown: countdown, paused: paused),
            metadata: ReminderAlarmMetadata(title: event.title, destination: destination), tintColor: Theme.accent)
        return AlarmManager.AlarmConfiguration(countdownDuration: Alarm.CountdownDuration(preAlert: nil, postAlert: Double(event.snoozeMinutes * 60)),
            schedule: .fixed(event.date), attributes: attributes, stopIntent: StopReminderAlarmIntent(id: id),
            sound: event.sound.fileName.map { .named($0) } ?? .default)
    }
}
