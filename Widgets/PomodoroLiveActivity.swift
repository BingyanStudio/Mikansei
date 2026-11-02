import ActivityKit
import SwiftUI
import WidgetKit

struct PomodoroLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PomodoroActivityAttributes.self) { context in
            PomodoroLockScreenCard(
                attributes: context.attributes,
                state: context.state,
                isStale: context.isStale
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .activityBackgroundTint(Color(uiColor: .secondarySystemBackground))
            .activitySystemActionForegroundColor(.green)
            .widgetURL(PomodoroActivityURL.open)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("专注", systemImage: "timer")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    PomodoroActivityClock(attributes: context.attributes, state: context.state, isStale: context.isStale)
                        .font(.title3.weight(.semibold).monospacedDigit())
                        .frame(minWidth: 82, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.subject)
                        .font(.headline)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(PomodoroActivityStatus.label(attributes: context.attributes, state: context.state, isStale: context.isStale))
                            .font(.caption)
                            .foregroundStyle(context.isStale ? .secondary : .primary)
                        Spacer(minLength: 4)
                        PomodoroActivityControls(sessionID: context.attributes.sessionID, isRunning: context.state.isRunning, isStale: context.isStale)
                    }
                }
            } compactLeading: {
                Image(systemName: "timer")
                    .foregroundStyle(.green)
            } compactTrailing: {
                PomodoroActivityClock(attributes: context.attributes, state: context.state, isStale: context.isStale)
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .frame(width: 72, alignment: .trailing)
            } minimal: {
                Image(systemName: "timer")
                    .foregroundStyle(.green)
            }
            .widgetURL(PomodoroActivityURL.open)
        }
    }
}

private struct PomodoroLockScreenCard: View {
    let attributes: PomodoroActivityAttributes
    let state: PomodoroActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Mikansei · 专注", systemImage: "timer")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.green)
                Spacer()
                Text(PomodoroActivityStatus.label(attributes: attributes, state: state, isStale: isStale))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Text(attributes.subject)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)

            PomodoroActivityClock(attributes: attributes, state: state, isStale: isStale)
                .font(.system(size: 38, weight: .medium, design: .rounded).monospacedDigit())
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .center)
                .accessibilityLabel(attributes.mode == .countdown ? "剩余时间" : "已专注时间")

            PomodoroActivityControls(sessionID: attributes.sessionID, isRunning: state.isRunning, isStale: isStale, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PomodoroActivityClock: View {
    let attributes: PomodoroActivityAttributes
    let state: PomodoroActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        Group {
            if isStale {
                Text(attributes.countdownExpiresBeforeSystemLimit(for: state) ? "已到时" : "打开 App")
                    .foregroundStyle(.secondary)
            } else if state.isRunning, attributes.mode == .countdown,
                      let deadline = state.countdownDeadline(target: attributes.targetSeconds) {
                if deadline > state.updatedAt {
                    Text(timerInterval: state.updatedAt...deadline, countsDown: true, showsHours: true)
                } else {
                    Text("已到时").foregroundStyle(.secondary)
                }
            } else if state.isRunning, attributes.mode == .countUp {
                Text(timerInterval: state.countUpAnchor(at: state.updatedAt)...Date.distantFuture,
                     countsDown: false, showsHours: true)
            } else if attributes.mode == .countdown {
                Text(Self.clock(state.remainingSeconds(target: attributes.targetSeconds, at: state.updatedAt)))
            } else {
                Text(Self.clock(state.elapsedSeconds(at: state.updatedAt)))
            }
        }
        .monospacedDigit()
    }

    private static func clock(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded(.up)))
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let remainder = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, remainder)
            : String(format: "%d:%02d", total / 60, remainder)
    }
}

private struct PomodoroActivityControls: View {
    let sessionID: String
    let isRunning: Bool
    let isStale: Bool
    var vertical = false

    var body: some View {
        HStack(spacing: 10) {
            if isStale {
                Link("打开 App 查看", destination: PomodoroActivityURL.open)
                    .font(.caption.weight(.semibold))
            } else if vertical {
                VStack(alignment: .leading, spacing: 1) {
                    Link(isRunning ? "暂停" : "继续", destination: PomodoroActivityURL.action(isRunning ? "pause" : "resume", sessionID: sessionID))
                        .font(.caption.weight(.semibold))
                    Link("结束并保存", destination: PomodoroActivityURL.action("finish", sessionID: sessionID))
                        .font(.caption.weight(.medium))
                }
            } else {
                Link(isRunning ? "暂停" : "继续", destination: PomodoroActivityURL.action(isRunning ? "pause" : "resume", sessionID: sessionID))
                    .font(.caption.weight(.semibold))
                Link("结束并保存", destination: PomodoroActivityURL.action("finish", sessionID: sessionID))
                    .font(.caption.weight(.medium))
            }
        }
    }
}

private enum PomodoroActivityStatus {
    static func label(attributes: PomodoroActivityAttributes, state: PomodoroActivityAttributes.ContentState, isStale: Bool) -> String {
        guard isStale else { return state.isRunning ? "进行中" : "已暂停" }
        if attributes.countdownExpiresBeforeSystemLimit(for: state) {
            return "时间已到 · 打开 App 保存记录"
        }
        return "实时活动时限已到 · 打开 App 查看"
    }
}

private enum PomodoroActivityURL {
    static let open = URL(string: "mikansei://pomodoro?action=open")!

    static func action(_ action: String, sessionID: String) -> URL {
        var components = URLComponents()
        components.scheme = "mikansei"
        components.host = "pomodoro"
        components.queryItems = [
            URLQueryItem(name: "action", value: action),
            URLQueryItem(name: "session", value: sessionID)
        ]
        return components.url!
    }
}
