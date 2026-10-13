import SwiftUI

enum Theme {
    static let accent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.48, green: 0.85, blue: 0.70, alpha: 1)
            : UIColor(red: 0.12, green: 0.39, blue: 0.30, alpha: 1)
    })
    static let background = Color(uiColor: .systemGroupedBackground)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
    static let warm = Color(red: 0.76, green: 0.43, blue: 0.18)
    static func color(for kind: EntryKind) -> Color {
        switch kind {
        case .task, .schedule: return accent
        case .homework: return .indigo
        case .note: return warm
        }
    }
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.doesRelativeDateFormatting = true
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
    static func dateLabel(_ date: Date) -> String {
        dateFormatter.string(from: date)
    }
    static func calendarLabel(_ event: CalendarEventRecord) -> String {
        if event.isAllDay {
            let end = max(event.start, event.end.addingTimeInterval(-1))
            let first = event.start.formatted(.dateTime.month().day())
            return Calendar.current.isDate(event.start, inSameDayAs: end) ? "\(first) · 全天" : "\(first)–\(end.formatted(.dateTime.month().day())) · 全天"
        }
        if Calendar.current.isDate(event.start, inSameDayAs: event.end) {
            return "\(dateLabel(event.start))–\(event.end.formatted(date: .omitted, time: .shortened))"
        }
        return "\(dateLabel(event.start))–\(dateLabel(event.end))"
    }
}

/// Clear text and a filled selected state, including in dark appearance.
struct ChoiceStrip<Option: Hashable>: View {
    let label: String
    let choices: [Option]
    @Binding var selection: Option
    let title: (Option) -> String
    var identifier: (Option) -> String = { _ in "" }
    var body: some View {
        HStack(spacing: 4) {
            ForEach(choices, id: \.self) { choice in
                Button { selection = choice } label: {
                    Text(title(choice)).font(.subheadline.weight(.semibold))
                        .foregroundStyle(selection == choice ? Color(uiColor: .systemBackground) : .primary)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(selection == choice ? Theme.accent : .clear, in: RoundedRectangle(cornerRadius: 10))
                        .contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .accessibilityIdentifier(identifier(choice))
                    .accessibilityAddTraits(selection == choice ? .isSelected : [])
            }
        }.padding(4).background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 14))
            .accessibilityLabel(label)
    }
}

struct OptionText: ViewModifier {
    func body(content: Content) -> some View { content.foregroundStyle(.primary).tint(Theme.accent) }
}
extension View {
    func clearOptionText() -> some View { modifier(OptionText()) }
}

struct EmptyCard: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 38, weight: .light)).foregroundStyle(Theme.accent)
                .padding(16).background(Theme.accent.opacity(0.08), in: Circle())
            Text(title).font(.headline)
            Text(message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action).buttonStyle(.borderedProminent).padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 32).padding(.horizontal, 20)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 22))
    }
}

struct SectionLabel: View {
    let title: String
    let count: Int
    var color: Color = .secondary
    var body: some View {
        HStack {
            Text(title).font(.headline).foregroundStyle(color)
            Text("\(count)").font(.caption.bold()).foregroundStyle(color)
                .padding(.horizontal, 8).padding(.vertical, 3).background(color.opacity(0.09), in: Capsule())
            Spacer()
        }.padding(.top, 8).padding(.bottom, 3)
    }
}

struct EntryCard: View {
    @EnvironmentObject private var store: EntryStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let entry: Entry
    let edit: () -> Void
    var now: Date = Date()
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if entry.isTask {
                Button(action: complete) {
                    Image(systemName: entry.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 25, weight: .light))
                        .foregroundStyle(entry.isCompleted ? Theme.accent : Color.primary.opacity(0.65))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain).disabled(store.readOnly)
                .accessibilityLabel(entry.isCompleted ? "重新打开：\(entry.title)" : "完成：\(entry.title)")
            }
            VStack(alignment: .leading, spacing: 10) {
                Button(action: edit) {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(entry.title).font(.body.weight(.semibold)).foregroundStyle(.primary)
                                .strikethrough(entry.isCompleted).multilineTextAlignment(.leading)
                            if entry.priority != .normal {
                                Label(entry.priority.title, systemImage: "flag.fill").font(.caption)
                                    .foregroundStyle(entry.priority == .urgent ? .red : Theme.warm)
                            }
                        }
                        if !entry.body.isEmpty {
                            Text(entry.body).font(.subheadline).foregroundStyle(.secondary).lineLimit(entry.kind == .note ? 3 : 1)
                                .multilineTextAlignment(.leading)
                        }
                        ViewThatFits(in: .horizontal) {
                            metadata
                            VStack(alignment: .leading, spacing: 5) { typeLabel; dateLabel }
                        }
                        if entry.isTask {
                            if let link = entry.calendarEvent {
                                if link.event.isCancelled {
                                    Label("原日历已取消，请核对", systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(Theme.warm)
                                } else if link.missingFromSource {
                                    Label("原日历未找到，已保留待办", systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(Theme.warm)
                                }
                            }
                            if !entry.platform.isEmpty || !entry.location.isEmpty {
                                Text([entry.platform, entry.location].filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            HStack(spacing: 10) {
                                if let minutes = entry.estimatedMinutes { Label("约 \(minutes) 分钟", systemImage: "clock").font(.caption).foregroundStyle(.secondary) }
                                if entry.isRoutine { Label("常态 · \(entry.repeatLabel)", systemImage: "repeat").font(.caption).foregroundStyle(Theme.accent) }
                                if entry.startedAt != nil && !entry.isCompleted { Text("正在做").font(.caption.bold()).foregroundStyle(Theme.accent) }
                            }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("entry-\(entry.id)")
                if !entry.checklist.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView(value: entry.progress).tint(Theme.color(for: entry.kind)).frame(maxWidth: 100)
                        Text("\(entry.completedSteps)/\(entry.checklist.count) 项").font(.caption).foregroundStyle(.secondary)
                    }.accessibilityElement(children: .combine)
                    ForEach(entry.checklist.prefix(3)) { step in
                        Button { withAnimation(reduceMotion ? nil : .smooth(duration: 0.35)) { store.toggleStep(entryID: entry.id, stepID: step.id) } } label: {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: step.isDone ? "checkmark.square.fill" : "square")
                                    .foregroundStyle(step.isDone ? Theme.accent : .primary)
                                Text(step.title).strikethrough(step.isDone).foregroundStyle(step.isDone ? .secondary : .primary).multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                            }.font(.subheadline).padding(.vertical, 4).frame(minHeight: 32).contentShape(Rectangle())
                        }.buttonStyle(.plain).disabled(store.readOnly)
                            .accessibilityLabel("\(step.isDone ? "取消完成" : "完成")步骤：\(step.title)")
                    }
                    if entry.checklist.count > 3 {
                        Button("查看全部 \(entry.checklist.count) 个步骤", action: edit).font(.caption)
                    }
                }
                if entry.isTask && !entry.isCompleted {
                    HStack(spacing: 12) {
                        Button { withAnimation(reduceMotion ? nil : .smooth) { store.start(entry.id) } } label: {
                            Label(entry.startedAt == nil ? (entry.elapsedSeconds > 0 ? "继续做" : "开始做") : "暂停", systemImage: entry.startedAt == nil ? "play.fill" : "pause")
                                .font(.caption.weight(.semibold)).padding(.vertical, 4)
                        }.buttonStyle(.bordered).disabled(store.readOnly)
                            .accessibilityLabel("\(entry.startedAt == nil ? "开始" : "暂停")计时：\(entry.title)")
                        if entry.startedAt != nil || entry.elapsedSeconds > 0 {
                            FocusClock(entry: entry).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                                .accessibilityIdentifier("focus-clock")
                        }
                    }
                } else if entry.isTask && entry.elapsedSeconds > 0 {
                    Text("用时 \(entry.focusTimeLabel())").font(.caption).foregroundStyle(.secondary)
                }
            }.padding(.top, entry.isTask ? 8 : 0)
        }
        .padding(16).background(Theme.card, in: RoundedRectangle(cornerRadius: 18))
        .contextMenu { Button("编辑", systemImage: "pencil", action: edit) }
    }
    private func complete() {
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) { store.toggleCompletion(entry.id) }
    }
    private var metadata: some View { HStack(spacing: 10) { typeLabel; dateLabel } }
    private var typeLabel: some View {
        Label(entry.category.isEmpty ? entry.kind.title : entry.category, systemImage: entry.kind.symbol)
            .font(.caption).foregroundStyle(Theme.color(for: entry.kind))
    }
    @ViewBuilder private var dateLabel: some View {
        if let due = entry.dueDate {
            Label("DDL \(Theme.dateLabel(due))", systemImage: entry.reminder == nil ? "flag" : "bell")
                .font(.caption).foregroundStyle(entry.isOverdue(at: now) ? .red : .secondary)
        } else if let link = entry.calendarEvent, entry.isTask {
            Label(Theme.calendarLabel(link.event), systemImage: "calendar")
                .font(.caption).foregroundStyle(.secondary)
        } else if let start = entry.plannedStart {
            Label("安排 \(Theme.dateLabel(start))", systemImage: "calendar").font(.caption).foregroundStyle(.secondary)
        } else if entry.kind == .note {
            Text(entry.updatedAt, format: .dateTime.month().day()).font(.caption).foregroundStyle(.secondary)
        }
    }
}
