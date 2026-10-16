import AlarmKit
import ActivityKit
import SwiftUI
import WidgetKit

@available(iOS 26.0, *)
struct ReminderAlarmActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<ReminderAlarmMetadata>.self) { context in
            VStack(alignment: .leading, spacing: 12) {
                Label(context.attributes.metadata?.title ?? "待办提醒", systemImage: "alarm.fill").font(.headline).lineLimit(2)
                HStack {
                    clock(context).font(.title2.monospacedDigit())
                    Spacer()
                    controls(context)
                }
            }.padding().activityBackgroundTint(Color(uiColor: .systemBackground))
                .widgetURL(URL(string: context.attributes.metadata?.destination ?? "mikanseta://today"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Image(systemName: "alarm.fill").foregroundStyle(Color(red:0.50,green:0.34,blue:0.20)) }
                DynamicIslandExpandedRegion(.center) { Text(context.attributes.metadata?.title ?? "待办提醒").lineLimit(1) }
                DynamicIslandExpandedRegion(.trailing) { clock(context).monospacedDigit() }
                DynamicIslandExpandedRegion(.bottom) { controls(context) }
            } compactLeading: { Image(systemName: "alarm.fill").foregroundStyle(Color(red:0.50,green:0.34,blue:0.20)) }
            compactTrailing: { clock(context).monospacedDigit().frame(maxWidth: 64) }
            minimal: { Image(systemName: "alarm.fill") }
            .widgetURL(URL(string: context.attributes.metadata?.destination ?? "mikanseta://today"))
        }
    }
    @ViewBuilder private func clock(_ context: ActivityViewContext<AlarmAttributes<ReminderAlarmMetadata>>) -> some View {
        switch context.state.mode {
        case .countdown(let countdown):
            Text(timerInterval: countdown.startDate...max(countdown.startDate, countdown.fireDate), countsDown: true)
        case .paused(let paused):
            let seconds = Int(max(0, paused.totalCountdownDuration - paused.previouslyElapsedDuration))
            Text(String(format: "%d:%02d", seconds / 60, seconds % 60))
        case .alert: Text("提醒中")
        @unknown default: Text("提醒")
        }
    }
    @ViewBuilder private func controls(_ context: ActivityViewContext<AlarmAttributes<ReminderAlarmMetadata>>) -> some View {
        HStack {
            Button(intent: StopReminderAlarmIntent(id: context.state.alarmID)) { Label("停止", systemImage: "stop.fill") }
            switch context.state.mode {
            case .countdown:
                Button(intent: PauseReminderAlarmIntent(id: context.state.alarmID)) { Label("暂停", systemImage: "pause.fill") }
            case .paused:
                Button(intent: ResumeReminderAlarmIntent(id: context.state.alarmID)) { Label("继续", systemImage: "play.fill") }
            default: EmptyView()
            }
        }.buttonStyle(.bordered)
    }
}
