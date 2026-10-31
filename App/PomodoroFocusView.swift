import SwiftUI

struct PomodoroFocusView: View {
    @EnvironmentObject private var coordinator: PomodoroCoordinator
    @EnvironmentObject private var store: EntryStore
    @Environment(\.dismiss) private var dismiss
    @State private var subject = ""
    @State private var mode: PomodoroMode = .countdown
    @State private var durationMinutes = 25
    @State private var linkedEntryID = ""
    @State private var confirmEarlyFinish = false

    private var linkableEntries: [Entry] {
        store.entries.filter { $0.isTask && !$0.isCompleted }.sorted {
            $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if let active = coordinator.active { activeSession(active) }
                else { startForm }
                history
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .frame(maxWidth: 620, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background)
        .navigationTitle("专注")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("完成") { dismiss() }
            }
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { tick in
            coordinator.refresh(at: tick)
        }
        .alert("专注计时", isPresented: Binding(get: { coordinator.error != nil }, set: { if !$0 { coordinator.clearError() } })) {
            Button("知道了", role: .cancel) { coordinator.clearError() }
        } message: { Text(coordinator.error ?? "") }
        .confirmationDialog("提前结束本次专注？", isPresented: $confirmEarlyFinish, titleVisibility: .visible) {
            Button("提前结束并保存", role: .destructive) {
                if let active = coordinator.active { _ = coordinator.finish(sessionID: active.id) }
            }
            Button("继续专注", role: .cancel) { }
        } message: {
            Text("本次已专注的时间会保存在本机历史中，完成次数不会增加。")
        }
    }

    private var startForm: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("开始一段专注", systemImage: "timer")
                .font(.title3.weight(.semibold))
            TextField("专注主题（必填）", text: $subject, axis: .vertical)
                .font(.title3)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...3)
                .accessibilityLabel("专注主题")

            Picker("计时方式", selection: $mode) {
                Text("倒计时").tag(PomodoroMode.countdown)
                Text("正计时").tag(PomodoroMode.countUp)
            }
            .pickerStyle(.segmented)

            if mode == .countdown {
                Stepper(value: $durationMinutes, in: 1...240, step: 1) {
                    LabeledContent("时长", value: "\(durationMinutes) 分钟")
                }
            } else {
                Label("不设时长，结束时保存实际专注时间。", systemImage: "infinity")
                    .font(.subheadline).foregroundStyle(.secondary)
            }

            Picker("关联任务（选填）", selection: $linkedEntryID) {
                Text("不关联任务").tag("")
                ForEach(linkableEntries) { entry in
                    Text(entry.title).tag(entry.id.uuidString)
                }
            }
            .onChange(of: linkedEntryID) { _, id in
                guard subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      let entry = linkableEntries.first(where: { $0.id.uuidString == id }) else { return }
                subject = entry.title
            }

            Button {
                _ = coordinator.start(subject: subject, mode: mode,
                                     targetSeconds: mode == .countdown ? Double(durationMinutes * 60) : 0,
                                     linkedEntryID: linkedEntryID.isEmpty ? nil : linkedEntryID)
            } label: {
                Label("开始专注", systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
            }
            .buttonStyle(.borderedProminent)
            .disabled(coordinator.readOnly || subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if coordinator.readOnly {
                Label("专注历史无法读取，已暂停修改以保护原文件。", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote).foregroundStyle(.orange)
            }
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func activeSession(_ run: PomodoroRun) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { tick in
            let seconds = run.mode == .countdown ? (run.remainingSeconds(at: tick.date) ?? 0) : run.elapsedSeconds(at: tick.date)
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    Label(run.mode == .countdown ? "倒计时" : "正计时", systemImage: "timer")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    Text(run.isRunning ? "进行中" : "已暂停")
                        .font(.caption.weight(.medium)).foregroundStyle(run.isRunning ? .green : .secondary)
                }
                Text(run.subject)
                    .font(.title2.weight(.semibold))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                if let linked = linkedTask(for: run) {
                    Label(linked, systemImage: "link")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Text(Self.clock(seconds))
                    .font(.system(.largeTitle, design: .rounded).weight(.medium).monospacedDigit())
                    .minimumScaleFactor(0.55)
                    .lineLimit(1)
                    .accessibilityLabel(run.mode == .countdown ? "剩余时间" : "已专注时间")
                HStack(spacing: 12) {
                    Button {
                        if run.isRunning { _ = coordinator.pause(sessionID: run.id) }
                        else { _ = coordinator.resume(sessionID: run.id) }
                    } label: {
                        Label(run.isRunning ? "暂停" : "继续", systemImage: run.isRunning ? "pause.fill" : "play.fill")
                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                    }
                    .buttonStyle(.borderedProminent)
                    Button(run.mode == .countdown ? "提前结束" : "结束并保存") {
                        if run.mode == .countdown { confirmEarlyFinish = true }
                        else { _ = coordinator.finish(sessionID: run.id) }
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(18)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .onChange(of: tick.date) { _, date in coordinator.refresh(at: date) }
        }
    }

    private var history: some View {
        let todayStart = Calendar.current.startOfDay(for: Date()).timeIntervalSince1970
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date()))?.timeIntervalSince1970 ?? todayStart + 86_400
        let todayRecords = coordinator.history.filter { $0.endedAt >= todayStart && $0.endedAt < tomorrow }
        let todaySeconds = todayRecords.reduce(0) { $0 + $1.durationSeconds }

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("专注历史").font(.title3.weight(.semibold))
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text("今日记录 \(Self.clock(todaySeconds))")
                        .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                    Text("已完成 \(coordinator.completedCount) 次")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Text("按结束日期统计 · 仅保存在本机")
                .font(.caption).foregroundStyle(.secondary)
            if coordinator.history.isEmpty {
                ContentUnavailableView("还没有专注记录", systemImage: "clock", description: Text("完成或提前结束一段专注后，会在这里留下记录。"))
                    .frame(minHeight: 120)
            } else {
                VStack(spacing: 0) {
                    ForEach(coordinator.history) { record in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: record.outcome == "completed" ? "checkmark.circle.fill" : "pause.circle")
                                .foregroundStyle(record.outcome == "completed" ? .green : .secondary)
                                .padding(.top, 2)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(record.run.subject).font(.body.weight(.medium)).lineLimit(3)
                                Text(Date(timeIntervalSince1970: record.endedAt), format: .dateTime.month().day().hour().minute())
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 6)
                            VStack(alignment: .trailing, spacing: 4) {
                                Text(Self.clock(record.durationSeconds)).font(.subheadline.monospacedDigit())
                                Text(record.outcome == "completed" ? "已完成" : "提前结束")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 11)
                        if record.id != coordinator.history.last?.id { Divider() }
                    }
                }
                .padding(.horizontal, 14)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    private func linkedTask(for run: PomodoroRun) -> String? {
        guard let id = run.linkedEntryID, let uuid = UUID(uuidString: id),
              let entry = store.entries.first(where: { $0.id == uuid }) else { return nil }
        return entry.title
    }

    private static func clock(_ seconds: Double) -> String {
        let whole = max(0, Int(seconds.rounded(.down)))
        let hours = whole / 3600
        let minutes = (whole % 3600) / 60
        let remainder = whole % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, remainder)
            : String(format: "%02d:%02d", minutes, remainder)
    }
}
