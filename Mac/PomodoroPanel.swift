import AppKit
import SwiftUI

@MainActor
final class MacPomodoroPanelController: NSObject, ObservableObject, NSWindowDelegate {
    private let coordinator: PomodoroCoordinator
    private let workspace: MacWorkspaceStore
    private var panel: NSPanel?
    private let frameKey = "Mikansei.PomodoroPanel.frame"

    init(coordinator: PomodoroCoordinator, workspace: MacWorkspaceStore) {
        self.coordinator = coordinator
        self.workspace = workspace
    }

    func show() {
        let floating = panel ?? makePanel()
        panel = floating
        if !floating.isVisible {
            floating.setFrame(Self.restoredFrame(key: frameKey, screen: NSScreen.main), display: true)
        }
        NSApp.activate(ignoringOtherApps: true)
        floating.makeKeyAndOrderFront(nil)
    }

    func hide() { panel?.orderOut(nil) }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        saveFrame(sender.frame)
        sender.orderOut(nil)
        return false
    }

    func windowDidMove(_ notification: Notification) { saveVisibleFrame() }
    func windowDidResize(_ notification: Notification) { saveVisibleFrame() }

    private func makePanel() -> NSPanel {
        let screen = NSScreen.main
        let frame = Self.restoredFrame(key: frameKey, screen: screen)
        let result = NSPanel(contentRect: frame,
                             styleMask: [.titled, .closable, .miniaturizable, .resizable, .utilityWindow],
                             backing: .buffered, defer: false)
        result.title = "专注计时"
        result.titleVisibility = .visible
        result.level = .floating
        result.isFloatingPanel = true
        result.hidesOnDeactivate = false
        result.isReleasedWhenClosed = false
        result.minSize = NSSize(width: 260, height: 220)
        result.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        result.backgroundColor = .windowBackgroundColor
        result.delegate = self
        result.setFrameAutosaveName("MikanseiPomodoroFloatingPanel")
        result.contentView = NSHostingView(rootView: MacPomodoroMiniPanelView()
            .environmentObject(coordinator)
            .environmentObject(workspace))
        return result
    }

    private func saveVisibleFrame() {
        guard let panel, panel.isVisible else { return }
        saveFrame(panel.frame)
    }

    private func saveFrame(_ frame: NSRect) {
        UserDefaults.standard.set(NSStringFromRect(frame), forKey: frameKey)
    }

    private static func restoredFrame(key: String, screen: NSScreen?) -> NSRect {
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        guard let stored = UserDefaults.standard.string(forKey: key) else {
            return NSRect(x: visible.maxX - 360, y: visible.maxY - 420, width: 340, height: 390)
        }
        var frame = NSRectFromString(stored)
        guard !frame.isEmpty, frame.width.isFinite, frame.height.isFinite else {
            return NSRect(x: visible.maxX - 360, y: visible.maxY - 420, width: 340, height: 390)
        }
        frame.size.width = min(max(260, frame.width), visible.width)
        frame.size.height = min(max(220, frame.height), visible.height)
        frame.origin.x = min(max(frame.minX, visible.minX), visible.maxX - frame.width)
        frame.origin.y = min(max(frame.minY, visible.minY), visible.maxY - frame.height)
        return frame
    }
}

struct MacPomodoroMiniPanelView: View {
    @EnvironmentObject private var coordinator: PomodoroCoordinator
    @EnvironmentObject private var store: MacWorkspaceStore
    @State private var subject = ""
    @State private var mode: PomodoroMode = .countdown
    @State private var durationMinutes = 25
    @State private var linkedEntryID = ""
    @State private var confirmEarlyFinish = false
    @ScaledMetric(relativeTo: .largeTitle) private var timerScale: CGFloat = 1

    private var linkableEntries: [Entry] {
        store.entries.filter { $0.isTask && !$0.isCompleted }.sorted {
            $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }

    var body: some View {
        Group {
            if let active = coordinator.active { activeSession(active) }
            else { startForm }
        }
        .frame(minWidth: 260, maxWidth: .infinity, minHeight: 180, maxHeight: .infinity)
        .background(.regularMaterial)
        .tint(MacTheme.accent)
        .confirmationDialog("提前结束本次专注？", isPresented: $confirmEarlyFinish, titleVisibility: .visible) {
            Button("提前结束并保存", role: .destructive) {
                if let active = coordinator.active { _ = coordinator.finish(sessionID: active.id) }
            }
            Button("继续专注", role: .cancel) { }
        } message: {
            Text("已专注时间会写入本机历史，完成次数不会增加。")
        }
        .alert("专注计时", isPresented: Binding(get: { coordinator.error != nil }, set: { if !$0 { coordinator.clearError() } })) {
            Button("知道了", role: .cancel) { coordinator.clearError() }
        } message: { Text(coordinator.error ?? "") }
    }

    private var startForm: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 11) {
                Text("开始专注").font(.headline)
                TextField("专注主题（必填）", text: $subject)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1)
                    .accessibilityLabel("专注主题")

                Picker("计时方式", selection: $mode) {
                    Text("倒计时").tag(PomodoroMode.countdown)
                    Text("正计时").tag(PomodoroMode.countUp)
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                if mode == .countdown {
                    Stepper(value: $durationMinutes, in: 1...240) {
                        HStack { Text("时长"); Spacer(minLength: 4); Text("\(durationMinutes) 分钟").monospacedDigit().foregroundStyle(.secondary) }
                    }
                } else {
                    Label("不设时长", systemImage: "infinity").font(.subheadline).foregroundStyle(.secondary)
                }

                Picker(selection: $linkedEntryID) {
                    Text("不关联任务").tag("")
                    ForEach(linkableEntries) { entry in Text(entry.title).tag(entry.id.uuidString) }
                } label: {
                    Label(selectedTaskTitle ?? "关联任务（选填）", systemImage: "link")
                        .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                }
                .pickerStyle(.menu)
                .onChange(of: linkedEntryID) { _, id in suggestSubject(for: id) }

                Button {
                    _ = coordinator.start(subject: subject, mode: mode,
                                         targetSeconds: mode == .countdown ? Double(durationMinutes * 60) : 0,
                                         linkedEntryID: linkedEntryID.isEmpty ? nil : linkedEntryID)
                } label: {
                    Label("开始", systemImage: "play.fill")
                        .frame(maxWidth: .infinity).padding(.vertical, 3)
                }
                .buttonStyle(.borderedProminent)
                .disabled(coordinator.readOnly || subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if coordinator.readOnly { Text("专注历史无法读取，修改已暂停。").font(.caption).foregroundStyle(.orange) }
            }
            .padding(15)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func activeSession(_ run: PomodoroRun) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { tick in
            let seconds = run.mode == .countdown ? (run.remainingSeconds(at: tick.date) ?? 0) : run.elapsedSeconds(at: tick.date)
            GeometryReader { geometry in
                let compact = geometry.size.height < 285 || geometry.size.width < 300
                activeContent(run, seconds: seconds, size: geometry.size, compact: compact)
            }
            .onChange(of: tick.date) { _, date in coordinator.refresh(at: date) }
        }
    }

    private func activeContent(_ run: PomodoroRun, seconds: Double, size: CGSize, compact: Bool) -> some View {
        let baseClockSize = min(compact ? 80 : 120, max(compact ? 64 : 90, size.height * (compact ? 0.40 : 0.36)))
        let clockSize = baseClockSize * timerScale
        return VStack(spacing: 0) {
            HStack {
                Label(run.mode == .countdown ? "倒计时" : "正计时", systemImage: "timer")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Text(run.isRunning ? "进行中" : "已暂停")
                    .font(.caption).foregroundStyle(run.isRunning ? .green : .secondary)
            }
            Text(run.subject)
                .font(.system(size: compact ? 15 : 19, weight: .semibold))
                .multilineTextAlignment(.center)
                .lineLimit(compact ? 1 : 2).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .padding(.top, compact ? 3 : 8)
            if !compact, let title = linkedTaskTitle(for: run) {
                Label(title, systemImage: "link").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    .frame(maxWidth: .infinity).padding(.top, 3)
            }
            Spacer(minLength: 0)
            Text(Self.clock(seconds))
                .font(.system(size: clockSize, weight: .medium, design: .rounded).monospacedDigit())
                .minimumScaleFactor(0.45).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .center)
                .accessibilityLabel(run.mode == .countdown ? "剩余时间" : "已专注时间")
            Spacer(minLength: 0)
            VStack(spacing: compact ? 5 : 7) {
                Button {
                    if run.isRunning { _ = coordinator.pause(sessionID: run.id) }
                    else { _ = coordinator.resume(sessionID: run.id) }
                } label: {
                    Label(run.isRunning ? "暂停" : "继续", systemImage: run.isRunning ? "pause.fill" : "play.fill")
                        .font(.system(size: compact ? 12 : 14, weight: .medium))
                        .frame(maxWidth: .infinity).frame(height: compact ? 25 : 31)
                }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
                Button {
                    if run.mode == .countdown { confirmEarlyFinish = true }
                    else { _ = coordinator.finish(sessionID: run.id) }
                } label: {
                    Text(run.mode == .countdown ? "提前结束" : "结束并保存")
                        .font(.system(size: compact ? 12 : 14, weight: .medium))
                        .frame(maxWidth: .infinity).frame(height: compact ? 25 : 31)
                }
                .controlSize(.small)
                .buttonStyle(.bordered)
            }
        }
        .padding(compact ? 8 : 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var selectedTaskTitle: String? {
        linkableEntries.first { $0.id.uuidString == linkedEntryID }?.title
    }

    private func suggestSubject(for id: String) {
        guard subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let entry = linkableEntries.first(where: { $0.id.uuidString == id }) else { return }
        subject = entry.title
    }

    private func linkedTaskTitle(for run: PomodoroRun) -> String? {
        guard let id = run.linkedEntryID else { return nil }
        return store.entries.first { $0.id.uuidString == id }?.title
    }

    private static func clock(_ seconds: Double) -> String {
        let whole = max(0, Int(seconds.rounded(.down)))
        let hours = whole / 3600
        let minutes = (whole % 3600) / 60
        let remainder = whole % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, remainder) : String(format: "%02d:%02d", minutes, remainder)
    }
}

struct MacPomodoroSummaryView: View {
    @EnvironmentObject private var coordinator: PomodoroCoordinator
    @EnvironmentObject private var pomodoroPanel: MacPomodoroPanelController

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("专注", systemImage: "timer").font(.title2.weight(.semibold))
            if let active = coordinator.active {
                Text(active.subject).font(.headline).lineLimit(3)
                Label(active.isRunning ? "正在计时" : "已暂停", systemImage: active.isRunning ? "play.circle.fill" : "pause.circle")
                    .font(.subheadline).foregroundStyle(active.isRunning ? .green : .secondary)
            } else {
                Text("当前没有进行中的计时。")
                    .font(.body).foregroundStyle(.secondary)
            }
            Button("打开专注浮窗", systemImage: "arrow.up.right.square") { pomodoroPanel.show() }
                .buttonStyle(.borderedProminent)
            Text("今日记录按结束日期统计。完成次数：\(coordinator.completedCount)")
                .font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct MacPomodoroHistoryView: View {
    @EnvironmentObject private var coordinator: PomodoroCoordinator

    private var todayRecords: [PomodoroRecord] {
        let start = Calendar.current.startOfDay(for: Date()).timeIntervalSince1970
        let end = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date()))?.timeIntervalSince1970 ?? start + 86_400
        return coordinator.history.filter { $0.endedAt >= start && $0.endedAt < end }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("专注历史").font(.title2.weight(.semibold))
                        Spacer(minLength: 8)
                        Text("今日记录 \(Self.clock(todayRecords.reduce(0) { $0 + $1.durationSeconds }))")
                            .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        Text("专注历史").font(.title2.weight(.semibold))
                        Text("今日记录 \(Self.clock(todayRecords.reduce(0) { $0 + $1.durationSeconds }))")
                            .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
                Text("按结束日期统计 · 仅保存在本机 · 已完成 \(coordinator.completedCount) 次")
                    .font(.caption).foregroundStyle(.secondary)
                if let active = coordinator.active {
                    HStack {
                        Label("当前专注：\(active.subject)", systemImage: "timer")
                        Spacer()
                        Text(active.isRunning ? "进行中" : "已暂停").foregroundStyle(.secondary)
                    }
                    .padding(14).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
                if coordinator.history.isEmpty {
                    ContentUnavailableView("还没有专注记录", systemImage: "clock", description: Text("完成或提前结束后，记录会保存在这里。"))
                        .frame(minHeight: 220)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(coordinator.history) { record in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: record.outcome == "completed" ? "checkmark.circle.fill" : "pause.circle")
                                    .foregroundStyle(record.outcome == "completed" ? .green : .secondary)
                                    .padding(.top, 2)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(record.run.subject).font(.body.weight(.medium)).lineLimit(3)
                                    Text(Date(timeIntervalSince1970: record.endedAt), format: .dateTime.year().month().day().hour().minute())
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 4) {
                                    Text(Self.clock(record.durationSeconds)).font(.subheadline.monospacedDigit())
                                    Text(record.outcome == "completed" ? "已完成" : "提前结束")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .padding(14)
                            if record.id != coordinator.history.last?.id { Divider() }
                        }
                    }
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                }
            }
            .padding(22)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        .alert("专注计时", isPresented: Binding(get: { coordinator.error != nil }, set: { if !$0 { coordinator.clearError() } })) {
            Button("知道了", role: .cancel) { coordinator.clearError() }
        } message: { Text(coordinator.error ?? "") }
        }
    }

    private static func clock(_ seconds: Double) -> String {
        let whole = max(0, Int(seconds.rounded(.down)))
        let hours = whole / 3600
        let minutes = (whole % 3600) / 60
        let remainder = whole % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, remainder) : String(format: "%02d:%02d", minutes, remainder)
    }
}
