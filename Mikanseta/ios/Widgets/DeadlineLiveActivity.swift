import ActivityKit
import SwiftUI
import WidgetKit

struct DeadlineLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DeadlineActivityAttributes.self) { context in
            DeadlineActivityCard(state: context.state, isStale: context.isStale)
                .padding(16)
                .activityBackgroundTint(Color(uiColor: .secondarySystemBackground))
                .activitySystemActionForegroundColor(.primary)
                .widgetURL(AppRoute.today.url)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("今日待办", systemImage: "checklist").font(.caption).foregroundStyle(.mint)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    DeadlineActivityClock(state: context.state, isStale: context.isStale).frame(width: 94)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.primary?.title ?? "今日待办").font(.headline).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    DeadlineActivityList(state: context.state, isStale: context.isStale)
                }
            } compactLeading: {
                HStack(spacing: 3) {
                    Image(systemName: "flag.fill").foregroundStyle(.mint)
                    Text(String((context.state.primary?.title ?? "待办").prefix(4))).lineLimit(1)
                }.font(.caption2)
            } compactTrailing: {
                DeadlineActivityClock(state: context.state, isStale: context.isStale).font(.caption2).frame(width: 64)
            } minimal: {
                Image(systemName: "checklist").foregroundStyle(.mint)
            }
            .widgetURL(context.state.primary.map { AppRoute.entry($0.id).url } ?? AppRoute.today.url)
        }
    }
}

private struct DeadlineActivityCard: View {
    let state: DeadlineActivitySnapshot
    let isStale: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Mikanseta · 今日未办", systemImage: "checklist").font(.caption.weight(.semibold))
                Spacer()
                Text("\(state.totalCount) 件").font(.caption)
            }.foregroundStyle(.secondary)
            if let first = state.primary {
                HStack(alignment: .center, spacing: 12) {
                    Link(destination: AppRoute.entry(first.id).url) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(first.title).font(.headline).lineLimit(2).foregroundStyle(.primary)
                            HStack(spacing: 6) {
                                if first.priority > 0 { Text(first.priority == 2 ? "紧急" : "重要").foregroundStyle(first.priority == 2 ? .red : .orange) }
                                if let date = first.deadline {
                                    Text(first.isSchedule ? "开始" : "DDL")
                                    Text(date, style: .time)
                                } else { Text("无时限") }
                            }.font(.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    DeadlineActivityClock(state: state, isStale: isStale)
                        .font(.title2.weight(.semibold)).frame(width: 108)
                }
            }
            DeadlineActivityList(state: state, isStale: isStale)
        }.privacySensitive()
    }
}

private struct DeadlineActivityList: View {
    let state: DeadlineActivitySnapshot
    let isStale: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if isStale && state.validUntil == state.dayEnd {
                Text("当天清单已结束，打开 App 更新今日事项。").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(state.items.dropFirst()) { item in
                    Link(destination: AppRoute.entry(item.id).url) {
                        HStack(spacing: 7) {
                            Image(systemName: "circle").font(.caption2)
                            Text(item.title).lineLimit(1)
                            Spacer(minLength: 0)
                        }.font(.subheadline).foregroundStyle(.primary)
                    }
                }
                if state.totalCount > state.items.count {
                    Text("还有 \(state.totalCount - state.items.count) 件 · 点入查看").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct DeadlineActivityClock: View {
    let state: DeadlineActivitySnapshot
    let isStale: Bool
    var body: some View {
        Group {
            if isStale && state.validUntil == state.dayEnd {
                Text("待更新")
            } else if let first = state.primary, let due = first.deadline {
                if due <= state.updatedAt || (isStale && due <= state.validUntil) {
                    Text(first.isSchedule ? "已开始" : "已超时").foregroundStyle(.red)
                } else {
                    // The system ticks this text after the app is suspended; it stops at zero.
                    Text(timerInterval: state.updatedAt...due, countsDown: true)
                        .monospacedDigit().multilineTextAlignment(.trailing)
                }
            } else { Text("无时限").font(.caption) }
        }.accessibilityLabel("截止或开始时间倒计时")
    }
}
