import SwiftUI
import WidgetKit

private let pomodoroAccent = Color(uiColor: UIColor { traits in
    traits.userInterfaceStyle == .dark
        ? UIColor(red: 0.48, green: 0.85, blue: 0.70, alpha: 1)
        : UIColor(red: 0.12, green: 0.39, blue: 0.30, alpha: 1)
})

private struct PomodoroTimelineEntry: TimelineEntry {
    let date: Date
    let snapshot: PomodoroSnapshot?
    let readFailure: String?
    let isPreview: Bool
}

private struct PomodoroTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> PomodoroTimelineEntry {
        PomodoroTimelineEntry(date: Date(), snapshot: nil, readFailure: nil, isPreview: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (PomodoroTimelineEntry) -> Void) {
        if context.isPreview {
            completion(placeholder(in: context))
        } else {
            completion(readEntry(at: Date()))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PomodoroTimelineEntry>) -> Void) {
        let now = Date()
        let current = readEntry(at: now)
        var entries = [current]

        if let run = current.snapshot?.active,
           run.mode == .countdown,
           let runningSince = run.runningSince {
            let deadline = Date(timeIntervalSince1970: runningSince + run.targetSeconds - run.accumulatedSeconds)
            if deadline > now {
                entries.append(PomodoroTimelineEntry(date: deadline,
                                                      snapshot: current.snapshot,
                                                      readFailure: current.readFailure,
                                                      isPreview: false))
            }
        }

        let nextDay = Calendar.current.date(byAdding: .day,
                                            value: 1,
                                            to: Calendar.current.startOfDay(for: now)) ?? now.addingTimeInterval(86_400)
        entries.append(PomodoroTimelineEntry(date: nextDay,
                                              snapshot: current.snapshot,
                                              readFailure: current.readFailure,
                                              isPreview: false))
        completion(Timeline(entries: entries.sorted { $0.date < $1.date }, policy: .after(nextDay.addingTimeInterval(60))))
    }

    private func readEntry(at date: Date) -> PomodoroTimelineEntry {
        do {
            return PomodoroTimelineEntry(date: date, snapshot: try PomodoroSnapshotStore.load(), readFailure: nil, isPreview: false)
        } catch {
            return PomodoroTimelineEntry(date: date, snapshot: nil, readFailure: error.localizedDescription, isPreview: false)
        }
    }
}

struct PomodoroWidget: Widget {
    let kind = "Mikansei.Pomodoro"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PomodoroTimelineProvider()) { entry in
            PomodoroWidgetView(entry: entry)
                .containerBackground(Color(uiColor: .systemBackground), for: .widget)
                .widgetURL(pomodoroURL(action: "open", session: entry.snapshot?.active?.id))
        }
        .configurationDisplayName("番茄专注")
        .description("显示当前专注主题与计时，点按进入专注页面。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

private struct PomodoroWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PomodoroTimelineEntry

    private var run: PomodoroRun? { entry.snapshot?.active }
    private var isCompact: Bool { family == .systemSmall }

    var body: some View {
        Group {
            if entry.isPreview {
                previewContent
            } else if let failure = entry.readFailure {
                unavailableContent(failure)
            } else if let run {
                activeContent(run)
            } else {
                emptyContent
            }
        }
        .privacySensitive()
    }

    @ViewBuilder
    private var previewContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("番茄专注", systemImage: "timer").font(.caption.bold()).foregroundStyle(pomodoroAccent)
            Text("专注主题示例").font(.caption.weight(.semibold)).lineLimit(1)
            Spacer(minLength: 0)
            Text("24:59")
                .font(.system(size: clockPointSize, weight: .bold, design: .rounded))
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .center)
                .foregroundStyle(pomodoroAccent)
            if family == .systemLarge {
                Spacer(minLength: 0)
                previewSummary
            }
        }
    }

    private var previewSummary: some View {
        HStack(spacing: 16) {
            summaryMetric(title: "今日记录", value: "1小时 25分")
            summaryMetric(title: "累计完成", value: "3 次")
            Spacer(minLength: 0)
        }
        .padding(.top, 8)
        .overlay(alignment: .top) { Rectangle().fill(.secondary.opacity(0.18)).frame(height: 1) }
    }

    private func unavailableContent(_ failure: String) -> some View {
        ViewThatFits(in: .vertical) {
            VStack(alignment: .leading, spacing: 8) {
                Label("专注状态不可用", systemImage: "exclamationmark.circle")
                    .font(.caption.bold()).foregroundStyle(pomodoroAccent).lineLimit(1)
                Text(failure).font(.caption).foregroundStyle(.secondary).lineLimit(family == .systemSmall ? 3 : 4)
                Spacer(minLength: 0)
                Link(destination: pomodoroURL(action: "open")) {
                    Label("打开专注页面", systemImage: "arrow.up.right.circle.fill")
                        .font(.caption.weight(.semibold)).foregroundStyle(pomodoroAccent)
                }
                if family == .systemLarge {
                    Text("打开 App 后重试共享状态。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                Label("专注状态不可用", systemImage: "exclamationmark.circle")
                    .font(.caption2.bold()).foregroundStyle(pomodoroAccent).lineLimit(1)
                Text(failure).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                Link("打开 App 重试", destination: pomodoroURL(action: "open"))
                    .font(.caption.weight(.semibold)).foregroundStyle(pomodoroAccent)
            }
        }
    }

    private var emptyContent: some View {
        ViewThatFits(in: .vertical) {
            VStack(alignment: .leading, spacing: family == .systemSmall ? 6 : 10) {
                Label("番茄专注", systemImage: "timer").font(.headline).foregroundStyle(pomodoroAccent)
                Spacer(minLength: 0)
                Text(entry.snapshot == nil ? "开始一段专注" : "准备好开始了吗？")
                    .font(family == .systemSmall ? .subheadline.weight(.semibold) : .title3.weight(.semibold))
                    .lineLimit(2)
                Text("输入专注主题，也可关联一项任务。")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                Spacer(minLength: 0)
                Link(destination: pomodoroURL(action: "open")) {
                    Label("选择主题", systemImage: "plus.circle.fill")
                        .font(.caption.weight(.semibold)).foregroundStyle(pomodoroAccent)
                }
                if family == .systemLarge { savedSummary(for: entry.snapshot) }
            }

            VStack(alignment: .leading, spacing: 6) {
                Label("番茄专注", systemImage: "timer").font(.caption.bold()).foregroundStyle(pomodoroAccent)
                Text("开始一段专注")
                    .font(.subheadline.weight(.semibold)).lineLimit(1)
                Spacer(minLength: 0)
                Link(destination: pomodoroURL(action: "open")) {
                    Label("输入专注主题", systemImage: "plus.circle.fill")
                        .font(.caption.weight(.semibold)).foregroundStyle(pomodoroAccent)
                }
                if family == .systemLarge { savedSummary(for: entry.snapshot) }
            }
        }
    }

    private func activeContent(_ run: PomodoroRun) -> some View {
        ViewThatFits(in: .vertical) {
            heroActiveContent(run)
            compactActiveContent(run, includeSummary: family == .systemLarge)
            compactActiveContent(run, includeSummary: false)
        }
    }

    private var clockPointSize: CGFloat {
        if family == .systemLarge { return 86 }
        if family == .systemMedium { return 62 }
        return 49
    }

    private var compactClockPointSize: CGFloat {
        if family == .systemLarge { return 72 }
        if family == .systemMedium { return 54 }
        return 46
    }

    @ViewBuilder
    private func heroActiveContent(_ run: PomodoroRun) -> some View {
        if family == .systemSmall {
            smallHeroContent(run)
        } else if family == .systemLarge {
            largeHeroContent(run)
        } else {
            mediumHeroContent(run)
        }
    }

    private func smallHeroContent(_ run: PomodoroRun) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 5) {
                Text(run.subject.isEmpty ? "未命名专注" : run.subject)
                    .font(.caption.weight(.semibold)).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(status(for: run))
                    .font(.caption2.weight(.semibold)).foregroundStyle(statusColor(for: run))
                    .lineLimit(1).fixedSize(horizontal: true, vertical: false)
            }
            Spacer(minLength: 0)
            timerReadout(run, size: clockPointSize)
            Spacer(minLength: 0)
            controls(for: run, compact: true)
        }
    }

    private func mediumHeroContent(_ run: PomodoroRun) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 6) {
                Text(run.subject.isEmpty ? "未命名专注" : run.subject)
                    .font(.subheadline.weight(.semibold)).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(status(for: run))
                    .font(.caption2.weight(.semibold)).foregroundStyle(statusColor(for: run))
                    .lineLimit(1).fixedSize(horizontal: true, vertical: false)
            }
            Spacer(minLength: 0)
            timerReadout(run, size: clockPointSize)
            Spacer(minLength: 0)
            controls(for: run, vertical: true)
        }
    }

    private func largeHeroContent(_ run: PomodoroRun) -> some View {
        VStack(alignment: .center, spacing: 5) {
            HStack(spacing: 5) {
                Label("番茄专注", systemImage: "timer").font(.caption.bold()).foregroundStyle(pomodoroAccent)
                Spacer(minLength: 0)
                Text(status(for: run)).font(.caption2.weight(.semibold)).foregroundStyle(statusColor(for: run))
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            Text(run.subject.isEmpty ? "未命名专注" : run.subject)
                .font(.headline.weight(.semibold)).lineLimit(2).multilineTextAlignment(.center)
                .minimumScaleFactor(0.85)
            if let linkedEntryID = run.linkedEntryID, !linkedEntryID.isEmpty {
                Label("已关联任务", systemImage: "checkmark.circle")
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            timerReadout(run, size: clockPointSize)
            Spacer(minLength: 0)
            controls(for: run, vertical: true)
            summary(for: entry.snapshot)
        }
    }

    private func compactActiveContent(_ run: PomodoroRun, includeSummary: Bool) -> some View {
        VStack(alignment: .center, spacing: 4) {
            HStack(spacing: 5) {
                Text(run.subject.isEmpty ? "未命名专注" : run.subject)
                    .font(.caption.weight(.semibold)).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(status(for: run)).font(.caption2.weight(.semibold)).foregroundStyle(statusColor(for: run))
                    .lineLimit(1).fixedSize(horizontal: true, vertical: false)
            }
            timerReadout(run, size: compactClockPointSize)
            controls(for: run, compact: true)
            if family == .systemLarge, includeSummary { summary(for: entry.snapshot) }
        }
    }

    private func timerReadout(_ run: PomodoroRun, size: CGFloat) -> some View {
        PomodoroTimerReadout(run: run, date: entry.date, compact: isCompact)
            .font(.system(size: size, weight: .bold, design: .rounded))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(maxWidth: .infinity, alignment: .center)
            .foregroundStyle(statusColor(for: run))
    }

    @ViewBuilder
    private func controls(for run: PomodoroRun, compact: Bool = false, vertical: Bool = false) -> some View {
        if vertical {
            VStack(spacing: 3) {
                if !countdownHasEnded(run, at: entry.date) {
                    if run.runningSince != nil {
                        actionLink("pause", session: run.id, title: "暂停", symbol: "pause.fill", compact: compact)
                    } else {
                        actionLink("resume", session: run.id, title: "继续", symbol: "play.fill", compact: compact)
                    }
                }
                actionLink("finish", session: run.id, title: "结束并保存", symbol: "stop.fill", isSecondary: true, compact: compact)
            }
        } else {
            HStack(spacing: family == .systemSmall ? 10 : 14) {
                if !countdownHasEnded(run, at: entry.date) {
                    if run.runningSince != nil {
                        actionLink("pause", session: run.id, title: "暂停", symbol: "pause.fill", compact: compact)
                    } else {
                        actionLink("resume", session: run.id, title: "继续", symbol: "play.fill", compact: compact)
                    }
                }
                actionLink("finish", session: run.id, title: "结束并保存", symbol: "stop.fill", isSecondary: true, compact: compact)
            }
        }
    }

    private func actionLink(_ action: String, session: String, title: String, symbol: String,
                            isSecondary: Bool = false, compact: Bool = false) -> some View {
        Link(destination: pomodoroURL(action: action, session: session)) {
            Group {
                if compact {
                    Image(systemName: symbol)
                        .font(.caption.weight(.semibold))
                        .accessibilityLabel(title)
                        .frame(minWidth: 44, minHeight: 44)
                        .background(isSecondary ? Color.secondary.opacity(0.10) : pomodoroAccent.opacity(0.12), in: Capsule())
                } else {
                    Label(title, systemImage: symbol)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, family == .systemSmall ? 8 : 11)
                        .padding(.vertical, 5)
                        .background(isSecondary ? Color.secondary.opacity(0.10) : pomodoroAccent.opacity(0.12), in: Capsule())
                }
            }
            .foregroundStyle(isSecondary ? Color.secondary : pomodoroAccent)
        }
    }

    private func summary(for snapshot: PomodoroSnapshot?) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 18) {
                summaryMetrics(snapshot)
            }
            VStack(alignment: .leading, spacing: 6) {
                summaryMetric(title: "今日记录", value: todayRecordedDuration(snapshot, at: entry.date))
                summaryMetric(title: "累计完成", value: "\(max(0, snapshot?.completedCount ?? 0)) 次")
            }
        }
        .padding(.top, 8)
        .overlay(alignment: .top) { Rectangle().fill(.secondary.opacity(0.18)).frame(height: 1) }
    }

    @ViewBuilder
    private func summaryMetrics(_ snapshot: PomodoroSnapshot?) -> some View {
        summaryMetric(title: "今日记录", value: todayRecordedDuration(snapshot, at: entry.date))
        summaryMetric(title: "累计完成", value: "\(max(0, snapshot?.completedCount ?? 0)) 次")
        Spacer(minLength: 0)
    }

    @ViewBuilder
    private func savedSummary(for snapshot: PomodoroSnapshot?) -> some View {
        if let snapshot {
            summary(for: snapshot)
        } else {
            Text("开始专注后，这里会显示今日累计与完成次数。")
                .font(.caption).foregroundStyle(.secondary)
                .padding(.top, 8)
                .overlay(alignment: .top) { Rectangle().fill(.secondary.opacity(0.18)).frame(height: 1) }
        }
    }

    private func summaryMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.75)
        }
    }

    private func todayRecordedDuration(_ snapshot: PomodoroSnapshot?, at date: Date) -> String {
        guard let snapshot else { return "—" }
        let savedAt = Date(timeIntervalSince1970: snapshot.savedAt)
        guard Calendar.current.isDate(savedAt, inSameDayAs: date) else { return "打开 App 更新" }
        return focusDuration(snapshot.todaySeconds)
    }

    private func status(for run: PomodoroRun) -> String {
        if countdownHasEnded(run, at: entry.date) { return "时间到" }
        return run.runningSince == nil ? "已暂停" : "专注中"
    }

    private func statusColor(for run: PomodoroRun) -> Color {
        countdownHasEnded(run, at: entry.date) ? .orange : pomodoroAccent
    }

    private func countdownHasEnded(_ run: PomodoroRun, at date: Date) -> Bool {
        guard run.mode == .countdown else { return false }
        let elapsed = run.accumulatedSeconds + (run.runningSince.map { max(0, date.timeIntervalSince1970 - $0) } ?? 0)
        return elapsed >= run.targetSeconds
    }
}

private struct PomodoroTimerReadout: View {
    let run: PomodoroRun
    let date: Date
    let compact: Bool

    var body: some View {
        Group {
            if let runningSince = run.runningSince, run.mode == .countUp {
                let anchor = Date(timeIntervalSince1970: runningSince - max(0, run.accumulatedSeconds))
                Text(timerInterval: anchor...Date.distantFuture, countsDown: false, showsHours: showsHours)
            } else if let runningSince = run.runningSince, run.mode == .countdown {
                let deadline = Date(timeIntervalSince1970: runningSince + run.targetSeconds - run.accumulatedSeconds)
                Text(timerInterval: date...max(date, deadline), countsDown: true, showsHours: showsHours)
            } else {
                Text(staticDuration)
            }
        }
    }

    /// Small widgets use minutes-only below one hour; elapsed hours remain visible
    /// once the stored run has reached that range.
    private var showsHours: Bool {
        if !compact { return true }
        if run.mode == .countdown { return run.targetSeconds >= 3_600 }
        let elapsed = run.accumulatedSeconds + (run.runningSince.map { max(0, date.timeIntervalSince1970 - $0) } ?? 0)
        return elapsed >= 3_600
    }

    private var staticDuration: String {
        let seconds: Double
        if run.mode == .countdown {
            seconds = max(0, run.targetSeconds - run.accumulatedSeconds)
        } else {
            seconds = max(0, run.accumulatedSeconds)
        }
        let total = Int(seconds.rounded(.down))
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let remainder = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, remainder)
            : String(format: "%02d:%02d", minutes, remainder)
    }
}

private func focusDuration(_ seconds: Double) -> String {
    let totalMinutes = max(0, Int(seconds / 60))
    let hours = totalMinutes / 60
    let minutes = totalMinutes % 60
    return hours > 0 ? "\(hours)小时\(minutes)分" : "\(minutes)分钟"
}

private func pomodoroURL(action: String, session: String? = nil) -> URL {
    var components = URLComponents()
    components.scheme = "mikansei"
    components.host = "pomodoro"
    var query = [URLQueryItem(name: "action", value: action)]
    if let session { query.append(URLQueryItem(name: "session", value: session)) }
    components.queryItems = query
    return components.url ?? URL(string: "mikansei://pomodoro?action=open")!
}
