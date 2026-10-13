import ActivityKit
import SwiftUI

@MainActor
final class DeadlineActivityManager: ObservableObject {
    @Published private(set) var enabled = UserDefaults.standard.bool(forKey: "deadlineLiveActivityEnabled")
    @Published private(set) var status = "未开启"
    @Published private(set) var error: String?
    private var desired: DeadlineActivitySnapshot?
    private var revision = 0
    private var worker: Task<Void, Never>?
    private var observer: Task<Void, Never>?
    private var observed: Activity<DeadlineActivityAttributes>?
    private let testing = ProcessInfo.processInfo.arguments.contains("--ui-testing") && !ProcessInfo.processInfo.arguments.contains("--deadline-activity-demo")

    init() {
        // A simulator-only, synthetic-data path for inspecting the real ActivityKit presentation.
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") && ProcessInfo.processInfo.arguments.contains("--deadline-activity-demo") {
            enabled = true
        }
    }

    func setEnabled(_ value: Bool, entries: [Entry]) {
        stopObserving()
        enabled = value
        UserDefaults.standard.set(value, forKey: "deadlineLiveActivityEnabled")
        UserDefaults.standard.removeObject(forKey: "deadlineLiveActivityDismissedDay")
        refresh(entries: entries)
    }
    func refresh(entries: [Entry]) {
        desired = enabled ? DeadlineActivitySnapshot.make(entries: entries) : nil
        revision += 1
        guard worker == nil else { return }
        worker = Task { [weak self] in
            guard let self else { return }
            while true {
                let current = revision
                await reconcile(desired)
                if current == revision { break }
            }
            worker = nil
        }
    }
    private func reconcile(_ snapshot: DeadlineActivitySnapshot?) async {
        error = nil
        guard !testing else { status = enabled ? snapshot == nil ? "今日暂无未完成事项" : "测试模式 · 未启动系统活动" : "未开启"; return }
        let all = Activity<DeadlineActivityAttributes>.activities
        guard let snapshot else {
            stopObserving()
            for activity in all { await activity.end(nil, dismissalPolicy: .immediate) }
            status = enabled ? "今日暂无未完成事项" : "未开启"
            return
        }
        let dayStart = Calendar.current.startOfDay(for: snapshot.updatedAt)
        if observed?.activityState == .dismissed {
            UserDefaults.standard.set(observed?.attributes.dayStart, forKey: "deadlineLiveActivityDismissedDay")
            stopObserving()
        }
        if UserDefaults.standard.object(forKey: "deadlineLiveActivityDismissedDay") as? Date == dayStart {
            status = "今日活动已收起，可点重新显示"
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            status = "系统实时活动未开启"
            error = "请在系统设置 → Mikansei 中允许实时活动。"
            return
        }
        let active = all.filter { ($0.activityState == .active || $0.activityState == .stale) && $0.attributes.dayStart == dayStart }
        let current = active.first
        for activity in all where activity.id != current?.id {
            if observed?.id == activity.id { stopObserving() }
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        let content = ActivityContent(state: snapshot, staleDate: snapshot.validUntil, relevanceScore: 0.8)
        if let current {
            await current.update(content)
            observe(current)
            status = "正在显示 · \(snapshot.totalCount) 件未完成"
        } else {
            guard UIApplication.shared.applicationState == .active else { status = "回到 App 后显示"; return }
            do {
                let activity = try Activity.request(attributes: DeadlineActivityAttributes(dayStart: dayStart), content: content, pushType: nil)
                observe(activity)
                status = "正在显示 · \(snapshot.totalCount) 件未完成"
            } catch {
                status = "暂未显示"
                self.error = "无法启动实时活动：\(error.localizedDescription)"
            }
        }
    }
    private func observe(_ activity: Activity<DeadlineActivityAttributes>) {
        guard observed?.id != activity.id else { return }
        stopObserving()
        observed = activity
        observer = Task { [weak self] in
            for await state in activity.activityStateUpdates {
                guard !Task.isCancelled, let self, observed?.id == activity.id else { return }
                if state == .dismissed {
                    UserDefaults.standard.set(activity.attributes.dayStart, forKey: "deadlineLiveActivityDismissedDay")
                    status = "今日活动已收起，可点重新显示"
                } else if state == .ended { status = "活动已结束，回到 App 后恢复" }
            }
        }
    }
    private func stopObserving() { observer?.cancel(); observer = nil; observed = nil }
}
