#if canImport(UIKit)
import UIKit
#endif
import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

/// 本地拖拽载体：Entry 已是 Codable，补上 Transferable 让待办能拖入时间轴。
/// 只在编译本文件的两个 App 目标生效，不影响小组件目标。
extension Entry: Transferable {
    public static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .data)
    }
}

/// 「规划」入口：日程按天涂色 + 小时时间轴安排。
/// 同一视图编译进 iPhone 与 Mac 目标：iPhone 支持把待办拖入时间轴；
/// Mac 不做拖拽，小时规划退化为时间字段快捷编辑（页面有注明）。
/// 因此配色与分段控件就地实现，数值与 App/Theme.swift 保持一致（Mac 目标不编译 Theme）。
struct PlanningView: View {
    enum Mode: Int, CaseIterable {
        case days, hours
        var title: String { self == .days ? "日程规划" : "小时规划" }
    }
    let entries: [Entry]
    let now: Date
    let edit: (Entry) -> Void
    let setPlannedDays: (UUID, [Date]) -> Void
    let setPlannedTime: (UUID, Date, Date) -> Void
    let restoreFromPlanning: (UUID) -> Void
    var canEdit = true
    /// Mac 目标传 false：隐藏时间轴拖拽，改用字段编辑。
    var supportsDrag = true

    @Environment(\.dismiss) private var dismiss
    @State private var mode: Mode = .days
    @State private var selectedID: UUID?
    @State private var draftDays: [Date] = []

    private var board: TaskBoard { TaskBoard(entries: entries, now: now) }
    private var selected: Entry? { entries.first { $0.id == selectedID } }
    /// 横滑选事项：全部未完成事项（含常态，选中后提示走重复规则）。
    private var deferredCandidates: [Entry] {
        entries.filter { $0.isTask && !$0.isCompleted && $0.isInPlanning }
            .sorted(by: TaskBoard.order)
    }
    private var candidates: [Entry] {
        var byID = Dictionary(uniqueKeysWithValues: board.open.map { ($0.id, $0) })
        for entry in deferredCandidates { byID[entry.id] = entry }
        return byID.values.sorted(by: TaskBoard.order)
    }

    var body: some View {
        #if os(macOS)
        navigationContent
            .frame(minWidth: 620, idealWidth: 680, minHeight: 560, idealHeight: 620)
        #else
        navigationContent.navigationBarTitleDisplayMode(.inline)
        #endif
    }
    private var navigationContent: some View {
        NavigationStack {
            VStack(spacing: 0) {
                PlanningSegment(mode: $mode)
                    .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 8)
                deferredSection
                if mode == .days { daysPane } else { hoursPane }
            }
            .background(PlanningPalette.page)
            .navigationTitle("规划")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }.accessibilityIdentifier("planning-close")
                }
            }
        }
    }

    @ViewBuilder private var deferredSection: some View {
        if !deferredCandidates.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("待重新规划 · \(deferredCandidates.count)")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(deferredCandidates) { entry in
                            VStack(alignment: .leading, spacing: 6) {
                                Button {
                                    selectedID = entry.id
                                    draftDays = entry.plannedDays ?? []
                                } label: {
                                    Text(entry.title).font(.caption.weight(.semibold)).lineLimit(2)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }.buttonStyle(.plain)
                                    .accessibilityLabel("选择待重新规划事项：\(entry.title)")
                                Button("移回今日聚焦") { restoreFromPlanning(entry.id) }
                                    .font(.caption).buttonStyle(.bordered)
                                    .disabled(!canEdit)
                                    .accessibilityLabel("移回今日聚焦：\(entry.title)")
                            }
                            .padding(10)
                            .background(PlanningPalette.card, in: RoundedRectangle(cornerRadius: 12))
                            .frame(width: 180, alignment: .leading)
                        }
                    }.padding(.horizontal, 20)
                }
            }.padding(.bottom, 10)
        }
    }

    // MARK: - 日程规划（按天涂色）

    @ViewBuilder private var daysPane: some View {
        ScrollView {
            VStack(spacing: 14) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(candidates) { entry in chip(entry) }
                        if candidates.isEmpty {
                            Text("还没有可规划的事项。").font(.subheadline).foregroundStyle(.secondary)
                                .padding(.vertical, 12)
                        }
                    }.padding(.horizontal, 20)
                }
                if let entry = selected {
                    if entry.isCalendarBackedRoutine {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("常态 · 日历来源重复", systemImage: "repeat")
                                .font(.subheadline.weight(.semibold)).foregroundStyle(PlanningPalette.accent)
                            Text("重复规律由来源日历管理；每次都保留独立的完成状态与清单，无需逐次规划。")
                                .font(.subheadline).foregroundStyle(.secondary)
                            if let start = entry.plannedStart {
                                Text("本次：\(start.formatted(date: .complete, time: .shortened))" +
                                     (entry.plannedEnd.map { $0 > start ? " — \($0.formatted(date: .omitted, time: .shortened))" : "" } ?? ""))
                                    .font(.subheadline)
                            } else if let due = entry.dueDate {
                                Text("本次截止：\(due.formatted(date: .complete, time: .shortened))")
                                    .font(.subheadline)
                            }
                            Button("编辑本次日历事项") { dismiss(); edit(entry) }
                                .buttonStyle(.bordered).disabled(!canEdit)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16).background(PlanningPalette.card, in: RoundedRectangle(cornerRadius: 18))
                            .padding(.horizontal, 20)
                    } else if entry.isRoutine {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("常态 · 按重复规则自动规划", systemImage: "repeat")
                                .font(.subheadline.weight(.semibold)).foregroundStyle(PlanningPalette.accent)
                            Text("「\(entry.title)」的发生日期由重复规则决定，无需逐日涂色。")
                                .font(.subheadline).foregroundStyle(.secondary)
                            // 先收起规划页再开编辑器，避免同一处两个 sheet 抢展示位。
                            Button("打开编辑器") { dismiss(); edit(entry) }.buttonStyle(.bordered)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16).background(PlanningPalette.card, in: RoundedRectangle(cornerRadius: 18))
                            .padding(.horizontal, 20)
                    } else if entry.kind == .schedule {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("日程按执行时段显示", systemImage: "calendar")
                                .font(.subheadline.weight(.semibold)).foregroundStyle(PlanningPalette.accent)
                            if let start = entry.plannedStart {
                                Text("开始：\(start.formatted(date: .complete, time: .shortened))")
                                    .font(.subheadline)
                                if let end = entry.plannedEnd, end > start {
                                    Text("结束：\(end.formatted(date: .complete, time: .shortened))")
                                        .font(.subheadline)
                                } else {
                                    Text("没有有效结束时间时，按开始日期归类。")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Text("只有执行时段覆盖当天的日程才会进入今日聚焦。")
                                .font(.subheadline).foregroundStyle(.secondary)
                            Button("调整日程时间") { dismiss(); edit(entry) }
                                .buttonStyle(.bordered).disabled(!canEdit)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16).background(PlanningPalette.card, in: RoundedRectangle(cornerRadius: 18))
                            .padding(.horizontal, 20)
                    } else {
                        VStack(spacing: 14) {
                            PlanningMonthPicker(dates: $draftDays, initialDate: now, today: now)
                            HStack {
                                Text("所选日子会进入「今天要做」。").font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Button("保存规划") { setPlannedDays(entry.id, draftDays) }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(!canEdit || draftDays == (entry.plannedDays ?? []))
                                    .accessibilityIdentifier("planning-save")
                            }
                        }.padding(16).background(PlanningPalette.card, in: RoundedRectangle(cornerRadius: 18))
                            .padding(.horizontal, 20)
                    }
                } else {
                    Text("选择一件事，为它涂上计划执行的日子。")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20).padding(.top, 4)
                }
            }.padding(.vertical, 6).padding(.bottom, 16)
        }
    }
    private func chip(_ entry: Entry) -> some View {
        let isSelected = entry.id == selectedID
        return Button {
            selectedID = entry.id
            draftDays = entry.plannedDays ?? []
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                Text(entry.title).font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.primary).lineLimit(2).multilineTextAlignment(.leading)
                if entry.isCalendarBackedRoutine {
                    Text("常态 · 来源日历重复").font(.caption2).foregroundStyle(PlanningPalette.accent)
                } else if entry.kind == .schedule, let start = entry.plannedStart {
                    Text(start.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2).foregroundStyle(.secondary)
                } else if entry.isRoutine {
                    Text("常态 · \(entry.repeatLabel)").font(.caption2).foregroundStyle(PlanningPalette.accent)
                } else if let days = entry.plannedDays, !days.isEmpty {
                    Text("已规划 \(days.count) 天").font(.caption2).foregroundStyle(.secondary)
                }
            }.padding(12).frame(width: 150, alignment: .topLeading)
                .background(isSelected ? PlanningPalette.accent.opacity(0.14) : PlanningPalette.card,
                            in: RoundedRectangle(cornerRadius: 14))
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(isSelected ? PlanningPalette.accent : Color.clear, lineWidth: 1)
                }
        }.buttonStyle(.plain)
            .accessibilityLabel(entry.title)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityIdentifier("planning-entry-\(entry.id)")
    }

    // MARK: - 小时规划

    @ViewBuilder private var hoursPane: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Label(now.formatted(date: .complete, time: .omitted), systemImage: "calendar")
                    .font(.subheadline.weight(.semibold))
                Text("今天")
                    .font(.caption.weight(.bold)).foregroundStyle(.red)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Color.red.opacity(0.1), in: Capsule())
                Spacer()
            }
            .padding(.horizontal, 12).padding(.top, 6)
            if supportsDrag {
                HStack(alignment: .top, spacing: 0) {
                    todayColumn.frame(width: 150)
                    Divider()
                    HourDropTimeline(date: now, items: dayItems, now: now, calendar: Calendar.current,
                                     edit: edit, drop: drop, canEdit: canEdit)
                }
            } else {
                MacHourFields(targets: board.today, now: now, setPlannedTime: setPlannedTime)
                    .disabled(!canEdit)
            }
        }
    }
    /// 左列：今天要做、还没有执行时段的待办，可拖入右侧时间轴。
    private var unscheduledToday: [Entry] { board.today.filter { $0.plannedStart == nil } }
    private var dayItems: [CalendarDisplayItem] { CalendarDisplay.items(on: now, entries: entries, showCompleted: false) }
    private func drop(_ entry: Entry, at start: Date) {
        setPlannedTime(entry.id, start, start.addingTimeInterval(duration(of: entry)))
    }
    /// 落点建块时长：优先沿用旧时段长度，其次预计耗时，默认 30 分钟。
    private func duration(of entry: Entry) -> TimeInterval {
        if let start = entry.plannedStart, let end = entry.plannedEnd, end > start { return end.timeIntervalSince(start) }
        return Double(max(5, entry.estimatedMinutes ?? 30)) * 60
    }
    private var todayColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("今日待办").font(.subheadline.weight(.semibold))
                    .padding(.top, 12).padding(.bottom, 2)
                ForEach(unscheduledToday) { entry in
                    todoCard(entry)
                }
                if unscheduledToday.isEmpty {
                    Text("今天的待办都已有时段。").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }.padding(.horizontal, 12)
        }
    }
    @ViewBuilder private func todoCard(_ entry: Entry) -> some View {
        let card = VStack(alignment: .leading, spacing: 4) {
            Text(entry.title).font(.caption.weight(.semibold))
                .foregroundStyle(Color.primary).lineLimit(3).multilineTextAlignment(.leading)
            if let due = entry.dueDate {
                Label("DDL " + due.formatted(date: .omitted, time: .shortened), systemImage: "flag")
                    .font(.caption2).foregroundStyle(PlanningPalette.warm)
            }
        }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(PlanningPalette.card, in: RoundedRectangle(cornerRadius: 10))
            .accessibilityIdentifier("planning-todo-\(entry.id)")
        #if canImport(UIKit)
        if canEdit && supportsDrag {
            EntryCardDragSource(entry: entry) { card }
                .accessibilityHint("长按事项卡片可拖入下方时间轴。")
        } else {
            card
        }
        #else
        if canEdit && supportsDrag { card.draggable(entry) } else { card }
        #endif
    }
}

/// 24 小时自绘时间轴：小时行接住拖入的待办（15 分钟对齐），已有块点按打开编辑。
/// 块来自当日日历展开（CalendarDisplay），任务类块带「待办」徽标。
private struct HourDropTimeline: View {
    let date: Date
    let items: [CalendarDisplayItem]
    let now: Date
    let calendar: Calendar
    let edit: (Entry) -> Void
    /// 落点已对齐到 15 分钟。
    let drop: (Entry, Date) -> Void
    let canEdit: Bool
    private let hourHeight: CGFloat = 64
    @State private var hoveringHour: Int?

    private var day: DateInterval { calendar.dateInterval(of: .day, for: date)! }
    private var blocks: [CalendarBlock] { CalendarTimelineLayout.blocks(on: date, items: items, calendar: calendar) }

    var body: some View {
        GeometryReader { geo in
            ScrollViewReader { proxy in
                ScrollView {
                    ZStack(alignment: .topLeading) {
                        rows
                        ForEach(blocks) { block in blockView(block, width: geo.size.width) }
                        nowLine
                    }
                    .frame(width: geo.size.width, height: CGFloat(24) * hourHeight, alignment: .topLeading)
                    // 整轴兜底接放：拖在已有时段块上时，行目标接不到，落到这里按绝对位置对齐。
                    .dropDestination(for: Entry.self) { payload, location in
                        receive(payload, minuteOffset: location.y / hourHeight * 60)
                    }
                }.task { await Task.yield(); proxy.scrollTo(initialHour, anchor: .top) }
            }
        }.accessibilityIdentifier("planning-timeline")
    }
    private var rows: some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { hour in
                HStack(alignment: .top, spacing: 8) {
                    Text(String(format: "%02d:00", hour))
                        .font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                        .frame(width: 40, alignment: .trailing)
                    Rectangle().fill(Color.secondary.opacity(0.25)).frame(height: 0.5)
                        .frame(maxWidth: .infinity, alignment: .top)
                }.frame(height: hourHeight, alignment: .top)
                    .contentShape(Rectangle())
                    .background(hoveringHour == hour ? PlanningPalette.accent.opacity(0.08) : Color.clear)
                    .dropDestination(for: Entry.self) { payload, location in
                        receive(payload, minuteOffset: Double(hour) * 60 + location.y / hourHeight * 60)
                    } isTargeted: { hoveringHour = $0 ? hour : nil }
                    .id(hour)
            }
        }
    }
    private func receive(_ payload: [Entry], minuteOffset: Double) -> Bool {
        guard canEdit, let entry = payload.first,
              let start = CalendarTimelineLayout.start(on: date, minuteOffset: minuteOffset, calendar: calendar) else { return false }
        drop(entry, start)
        return true
    }
    private func blockView(_ block: CalendarBlock, width: CGFloat) -> some View {
        let height = max(20, CGFloat(block.endMinute - block.startMinute) / 60 * hourHeight)
        let entry = block.item.entry
        return Button { edit(entry) } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if entry.kind != .schedule {
                        Text("待办").font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(PlanningPalette.accent.opacity(0.25), in: Capsule())
                    }
                    Text(entry.title).font(.caption.weight(.semibold)).lineLimit(height < 40 ? 1 : 2)
                }
                if height >= 40 {
                    Text(clock(block.item.date)).font(.caption2).monospacedDigit()
                }
            }.foregroundStyle(Color.primary).padding(.horizontal, 7).padding(.vertical, 4)
                .frame(width: max(40, width - 56), height: height, alignment: .topLeading)
                .background(PlanningPalette.accent.opacity(0.17), in: RoundedRectangle(cornerRadius: 6))
                .overlay(alignment: .leading) {
                    UnevenRoundedRectangle(topLeadingRadius: 3, bottomLeadingRadius: 3)
                        .fill(PlanningPalette.accent).frame(width: 3)
                }
                .clipped()
        }.buttonStyle(.plain)
            .offset(x: 48, y: CGFloat(block.startMinute) / 60 * hourHeight)
            .accessibilityLabel("\(entry.title)，\(clock(block.item.date))")
            .accessibilityIdentifier("planning-block-\(entry.id)")
    }
    @ViewBuilder private var nowLine: some View {
        if day.start <= now && now < day.end {
            HStack(spacing: 0) {
                Circle().fill(.red).frame(width: 6, height: 6)
                Rectangle().fill(.red).frame(height: 1)
            }.frame(maxWidth: .infinity, alignment: .leading)
                .offset(y: CGFloat(now.timeIntervalSince(day.start) / 3600) * hourHeight)
                .allowsHitTesting(false)
                .accessibilityLabel("当前时间")
        }
    }
    private var initialHour: Int {
        let target = blocks.first?.startMinute ?? (calendar.isDate(date, inSameDayAs: now) ? now.timeIntervalSince(day.start) / 60 : 540)
        return max(0, Int(target / 60) - 1)
    }
    private func clock(_ time: Date) -> String {
        String(format: "%02d:%02d", calendar.component(.hour, from: time), calendar.component(.minute, from: time))
    }
}

/// Mac 的小时规划：不做拖拽，用时间字段快速编辑当天的安排。
private struct MacHourFields: View {
    let targets: [Entry]
    let now: Date
    let setPlannedTime: (UUID, Date, Date) -> Void
    private var defaultStart: Date {
        Date(timeIntervalSince1970: (now.addingTimeInterval(900).timeIntervalSince1970 / 900).rounded(.down) * 900)
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Mac 暂不支持拖拽规划：用下面的时间字段快速安排；在 iPhone 上可把待办拖入时间轴。")
                    .font(.caption).foregroundStyle(.secondary)
                if targets.isEmpty {
                    Text("今天没有待安排的事项。").font(.subheadline).foregroundStyle(.secondary)
                }
                ForEach(targets) { entry in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(entry.title).font(.subheadline.weight(.semibold))
                            if entry.plannedAllDay { Text("全天安排").font(.caption).foregroundStyle(.secondary) }
                            if let due = entry.dueDate {
                                Label("DDL " + due.formatted(date: .abbreviated, time: .shortened), systemImage: "flag")
                                    .font(.caption).foregroundStyle(PlanningPalette.warm)
                            }
                        }
                        Spacer()
                        DatePicker("开始", selection: Binding(
                            get: { entry.plannedStart ?? defaultStart },
                            set: { setPlannedTime(entry.id, $0, $0.addingTimeInterval(duration(of: entry))) }
                        ), displayedComponents: [.hourAndMinute]).labelsHidden()
                            .accessibilityLabel("开始时间：\(entry.title)")
                        Picker("时长", selection: Binding(
                            get: { Int(duration(of: entry) / 60) },
                            set: { minutes in
                                let start = entry.plannedStart ?? defaultStart
                                setPlannedTime(entry.id, start, start.addingTimeInterval(Double(minutes) * 60))
                            }
                        )) {
                            ForEach(Array(Set([15, 30, 45, 60, 90, 120, Int(duration(of: entry) / 60)])).sorted(), id: \.self) {
                                Text("\($0) 分钟").tag($0)
                            }
                        }.frame(width: 130).accessibilityLabel("时长：\(entry.title)")
                    }.padding(12).background(PlanningPalette.card, in: RoundedRectangle(cornerRadius: 10))
                }
            }.padding(20)
        }
    }
    private func duration(of entry: Entry) -> TimeInterval {
        guard let start = entry.plannedStart, let end = entry.plannedEnd, end > start else { return 30 * 60 }
        return end.timeIntervalSince(start)
    }
}

/// 顶部分段：样式对齐 App/Theme.swift 的 ChoiceStrip（自绘、暗色可用）。
private struct PlanningSegment: View {
    @Binding var mode: PlanningView.Mode
    var body: some View {
        HStack(spacing: 4) {
            ForEach(PlanningView.Mode.allCases, id: \.self) { choice in
                Button { mode = choice } label: {
                    Text(choice.title).font(.subheadline.weight(.semibold))
                        .foregroundStyle(mode == choice ? PlanningPalette.onAccent : Color.primary)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(mode == choice ? PlanningPalette.accent : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 10))
                        .contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .accessibilityIdentifier("planning-mode-\(choice.rawValue)")
                    .accessibilityAddTraits(mode == choice ? .isSelected : [])
            }
        }.padding(4).background(PlanningPalette.track, in: RoundedRectangle(cornerRadius: 14))
            .accessibilityLabel("规划方式")
    }
}

/// 与 Theme.accent / Theme.card 同值的跨平台配色（Mac 目标不编译 Theme，就地定义）。
private enum PlanningPalette {
    #if canImport(UIKit)
    static let accent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.48, green: 0.85, blue: 0.70, alpha: 1)
            : UIColor(red: 0.12, green: 0.39, blue: 0.30, alpha: 1)
    })
    static let page = Color(uiColor: .systemGroupedBackground)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
    static let track = Color(uiColor: .tertiarySystemFill)
    static let onAccent = Color(uiColor: .systemBackground)
    #else
    static let accent = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.48, green: 0.85, blue: 0.70, alpha: 1)
            : NSColor(red: 0.12, green: 0.39, blue: 0.30, alpha: 1)
    })
    static let page = Color(nsColor: .windowBackgroundColor)
    static let card = Color(nsColor: .controlBackgroundColor)
    static let track = Color.primary.opacity(0.08)
    static let onAccent = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .black : .white
    })
    #endif
    static let warm = Color(red: 0.76, green: 0.43, blue: 0.18)
}

/// 泛化自 EntryEditor 的 RoutineDatePicker：点按切换，滑动（minimumDistance 0）连续涂抹；可跨月。
private struct PlanningMonthPicker: View {
    @Binding var dates: [Date]
    @State private var month = Date()
    @State private var painting: Painting?
    private let today: Date
    enum Painting { case add, remove }
    private let rowHeight: CGFloat = 40
    private let rowGap: CGFloat = 6
    private let columnGap: CGFloat = 2
    private var calendar: Calendar { var value = Calendar.current; value.firstWeekday = 2; return value }

    init(dates: Binding<[Date]>, initialDate: Date, today: Date) {
        _dates = dates
        _month = State(initialValue: initialDate)
        self.today = today
    }
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Button { move(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                    .accessibilityLabel("上个月")
                Spacer()
                Text(month, format: .dateTime.year().month()).font(.headline)
                Spacer()
                Button { move(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                    .accessibilityLabel("下个月")
            }
            HStack { ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) { Text($0).font(.caption).frame(maxWidth: .infinity) } }
            grid
            Text("今天标记为「今」；所选日期填充主题色。点按切换或滑动涂色，已选 \(dates.count) 天。")
                .font(.caption).foregroundStyle(.secondary)
        }.accessibilityIdentifier("planning-month-picker")
    }
    private var grid: some View {
        let days = CalendarDisplay.monthDays(containing: month, calendar: calendar)
        let rowCount = days.count / 7
        return GeometryReader { geo in
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: columnGap), count: 7), spacing: rowGap) {
                ForEach(days, id: \.self) { day in
                    cell(day, inMonth: calendar.isDate(day, equalTo: month, toGranularity: .month))
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { paint(at: $0.location, days: days, size: geo.size) }
                    .onEnded { _ in painting = nil }
            )
        }.frame(height: CGFloat(rowCount) * rowHeight + CGFloat(rowCount - 1) * rowGap)
    }
    private func cell(_ day: Date, inMonth: Bool) -> some View {
        let selected = dates.contains { calendar.isDate($0, inSameDayAs: day) }
        let isToday = calendar.isDate(day, inSameDayAs: today)
        let todayOutlineColor: Color = selected ? PlanningPalette.onAccent : Color.red
        return VStack(spacing: 0) {
            Text("\(calendar.component(.day, from: day))")
                .font(.subheadline.weight(selected || isToday ? .semibold : .regular))
            if isToday {
                Text("今").font(.system(size: 8, weight: .bold)).lineLimit(1)
            }
        }
            .frame(maxWidth: .infinity, minHeight: rowHeight)
            .foregroundStyle(selected ? PlanningPalette.onAccent : Color.primary)
            .background(selected ? PlanningPalette.accent : Color.clear, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isToday ? todayOutlineColor : Color.clear, lineWidth: isToday ? 1 : 0)
                    .padding(1)
            }
            .opacity(inMonth ? 1 : 0.4)
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(day.formatted(.dateTime.year().month().day()) + (isToday ? "，今天" : ""))
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityHint(isToday ? "今天；点按或滑动可切换规划选择。" : "点按或滑动可切换规划选择。")
            .accessibilityIdentifier("planning-day-\(Int(day.timeIntervalSince1970))")
    }
    /// 网格固定 7 列、行高 rowHeight，按落点换算行列即可命中；起手那天决定本次是涂还是擦。
    private func paint(at location: CGPoint, days: [Date], size: CGSize) {
        let rows = days.count / 7
        guard location.x >= 0, location.y >= 0, rows > 0 else { return }
        let cellWidth = (size.width - 6 * columnGap) / 7
        guard cellWidth > 0 else { return }
        let column = min(6, max(0, Int(location.x / (cellWidth + columnGap))))
        let row = min(rows - 1, max(0, Int(location.y / (rowHeight + rowGap))))
        let index = row * 7 + column
        guard days.indices.contains(index) else { return }
        let day = calendar.startOfDay(for: days[index])
        if painting == nil {
            painting = dates.contains { calendar.isDate($0, inSameDayAs: day) } ? .remove : .add
        }
        switch painting! {
        case .add:
            if !dates.contains(where: { calendar.isDate($0, inSameDayAs: day) }) {
                #if canImport(UIKit)
                UISelectionFeedbackGenerator().selectionChanged()
                #endif
                dates.append(day); dates.sort()
            }
        case .remove:
            if dates.contains(where: { calendar.isDate($0, inSameDayAs: day) }) {
                #if canImport(UIKit)
                UISelectionFeedbackGenerator().selectionChanged()
                #endif
                dates.removeAll { calendar.isDate($0, inSameDayAs: day) }
            }
        }
    }
    private func move(_ direction: Int) {
        if let next = calendar.date(byAdding: .month, value: direction, to: calendar.dateInterval(of: .month, for: month)!.start) { month = next }
    }
}
