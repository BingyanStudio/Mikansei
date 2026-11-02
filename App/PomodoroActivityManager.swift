import ActivityKit
import SwiftUI
import UIKit

@MainActor
final class PomodoroActivityManager: ObservableObject {
    @Published private(set) var authorizationEnabled = ActivityAuthorizationInfo().areActivitiesEnabled
    @Published private(set) var status = "未开启"
    @Published private(set) var error: String?
    @Published private(set) var isCurrentActivityDismissed = false

    private let testing = ProcessInfo.processInfo.arguments.contains("--ui-testing")
    private let dismissedSessionDefaultsKey = "pomodoroLiveActivityDismissedSessionID"
    var isTesting: Bool { testing }
    private var revision = 0
    private var desiredSessionID: String?
    private var observedActivityID: String?
    private var observedSessionID: String?
    private var activityStateObserver: Task<Void, Never>?

    func reconcile(_ run: PomodoroRun?, forceShow: Bool = false) {
        guard !testing else {
            status = "测试模式 · 未启动系统实时活动"
            return
        }
        revision += 1
        let currentRevision = revision
        desiredSessionID = run?.id
        authorizationEnabled = ActivityAuthorizationInfo().areActivitiesEnabled
        isCurrentActivityDismissed = false
        if run == nil { stopObserving() }
        Task { [weak self] in
            guard let self, revision == currentRevision else { return }
            if let run {
                await reconcile(run, revision: currentRevision, forceShow: forceShow)
            } else {
                await endOrphanedActivities(revision: currentRevision)
            }
        }
    }

    func showAgain(_ run: PomodoroRun) {
        guard !testing else { return }
        if UserDefaults.standard.string(forKey: dismissedSessionDefaultsKey) == run.id {
            UserDefaults.standard.removeObject(forKey: dismissedSessionDefaultsKey)
        }
        if observedSessionID == run.id { stopObserving() }
        isCurrentActivityDismissed = false
        reconcile(run, forceShow: true)
    }

    /// Ends only the ActivityKit record that belongs to this archived session.
    func end(sessionID: String) {
        guard !testing else { return }
        if desiredSessionID == sessionID {
            desiredSessionID = nil
            revision += 1
            isCurrentActivityDismissed = false
        }
        if observedSessionID == sessionID { stopObserving() }
        let currentRevision = revision
        Task { [weak self] in
            guard let self else { return }
            let matches = Activity<PomodoroActivityAttributes>.activities.filter {
                $0.attributes.sessionID == sessionID && self.isPresentable($0.activityState)
            }
            for activity in matches {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            if desiredSessionID == nil, revision == currentRevision {
                status = "专注活动已结束"
                error = nil
            }
        }
    }

    private func reconcile(_ run: PomodoroRun, revision currentRevision: Int, forceShow: Bool) async {
        authorizationEnabled = ActivityAuthorizationInfo().areActivitiesEnabled
        error = nil
        guard authorizationEnabled else {
            status = "系统实时活动未开启"
            error = "仍可在本机计时和保存历史。请到系统设置中的 Mikansei 页面开启“实时活动”。"
            return
        }

        let all = Activity<PomodoroActivityAttributes>.activities
        let matches = all.filter {
            $0.attributes.sessionID == run.id && isPresentable($0.activityState)
        }
        if !forceShow, matches.isEmpty,
           UserDefaults.standard.string(forKey: dismissedSessionDefaultsKey) == run.id {
            isCurrentActivityDismissed = true
            status = "已收起 · 可在 App 重新显示"
            stopObserving()
            return
        }
        if UserDefaults.standard.string(forKey: dismissedSessionDefaultsKey) != nil {
            UserDefaults.standard.removeObject(forKey: dismissedSessionDefaultsKey)
        }
        if !forceShow, matches.isEmpty, let dismissed = all.first(where: {
            $0.attributes.sessionID == run.id && $0.activityState == .dismissed
        }) {
            rememberDismissal(of: dismissed)
            return
        }
        if forceShow, UserDefaults.standard.string(forKey: dismissedSessionDefaultsKey) == run.id {
            UserDefaults.standard.removeObject(forKey: dismissedSessionDefaultsKey)
        }
        isCurrentActivityDismissed = false
        let current = matches.first

        // A single local Pomodoro run is supported. Clean up only this Live Activity type;
        // the independent deadline Live Activity has a different ActivityAttributes type.
        for activity in all where activity.id != current?.id && isPresentable(activity.activityState) {
            await activity.end(nil, dismissalPolicy: .immediate)
            guard revision == currentRevision else { return }
        }

        if let current {
            observe(current)
            let content = makeContent(for: run, attributes: current.attributes)
            await current.update(content)
            guard revision == currentRevision else { return }
            status = current.activityState == .stale
                ? "实时活动已过期 · 专注计时仍在本机继续"
                : "正在显示 · 锁屏与灵动岛"
            return
        }

        guard revision == currentRevision else { return }
        guard UIApplication.shared.applicationState == .active else {
            status = "回到 App 后显示"
            return
        }

        let now = Date()
        let attributes = PomodoroActivityAttributes(run: run, activityStartedAt: now)
        let content = makeContent(for: run, attributes: attributes, now: now)
        do {
            let activity = try Activity.request(attributes: attributes, content: content, pushType: nil)
            observe(activity)
            guard revision == currentRevision else {
                Task { await activity.end(nil, dismissalPolicy: .immediate) }
                return
            }
            status = "正在显示 · 锁屏与灵动岛"
            error = nil
        } catch {
            guard revision == currentRevision else { return }
            status = "暂未显示"
            self.error = "无法启动系统实时活动：\(error.localizedDescription)"
        }
    }

    private func endOrphanedActivities(revision currentRevision: Int) async {
        error = nil
        isCurrentActivityDismissed = false
        let matches = Activity<PomodoroActivityAttributes>.activities.filter { isPresentable($0.activityState) }
        guard !matches.isEmpty else {
            status = "未开启"
            return
        }
        for activity in matches {
            await activity.end(nil, dismissalPolicy: .immediate)
            guard revision == currentRevision else { return }
        }
        status = "专注活动已结束"
    }

    private func makeContent(
        for run: PomodoroRun,
        attributes: PomodoroActivityAttributes,
        now: Date = Date()
    ) -> ActivityContent<PomodoroActivityAttributes.ContentState> {
        let state = attributes.contentState(for: run, at: now)
        return ActivityContent(
            state: state,
            staleDate: attributes.staleDate(for: state),
            relevanceScore: 1
        )
    }

    private func isPresentable(_ state: ActivityState) -> Bool {
        state == .active || state == .stale
    }

    private func observe(_ activity: Activity<PomodoroActivityAttributes>) {
        guard observedActivityID != activity.id else { return }
        stopObserving()
        observedActivityID = activity.id
        observedSessionID = activity.attributes.sessionID
        activityStateObserver = Task { [weak self] in
            for await state in activity.activityStateUpdates {
                guard !Task.isCancelled, let self, observedActivityID == activity.id else { return }
                if state == .dismissed {
                    rememberDismissal(of: activity)
                    return
                }
                if state == .ended, desiredSessionID == activity.attributes.sessionID {
                    status = "实时活动已结束 · 专注计时仍在本机继续"
                    error = nil
                }
            }
        }
    }

    private func rememberDismissal(of activity: Activity<PomodoroActivityAttributes>) {
        UserDefaults.standard.set(activity.attributes.sessionID, forKey: dismissedSessionDefaultsKey)
        guard desiredSessionID == activity.attributes.sessionID else { return }
        isCurrentActivityDismissed = true
        status = "已收起 · 可在 App 重新显示"
        error = nil
    }

    private func stopObserving() {
        activityStateObserver?.cancel()
        activityStateObserver = nil
        observedActivityID = nil
        observedSessionID = nil
    }
}
