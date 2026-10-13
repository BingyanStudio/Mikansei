import SwiftUI

struct CalendarScheduleView: View {
    let entries: [Entry]
    let now: Date
    let edit: (Entry) -> Void
    let add: (Date, Bool) -> Void
    @AppStorage("calendarLayout") private var layout = 0
    @AppStorage("calendarShowCompleted") private var showCompleted = true
    @State private var selectedDate = Date()
    @State private var visibleMonth = Date()
    @State private var showInfo = false
    private var calendar: Calendar {
        var value = Calendar.current
        value.locale = Locale(identifier: "zh_CN")
        value.firstWeekday = 2
        return value
    }
    private var items: [CalendarDisplayItem] {
        CalendarDisplay.items(on: selectedDate, entries: entries, showCompleted: showCompleted, calendar: calendar)
    }
    var body: some View {
        VStack(spacing: 0) {
            navigation.padding(.horizontal, 20).padding(.bottom, 10)
            if layout == 0 {
                ScrollView {
                    VStack(spacing: 16) {
                        monthGrid
                        selectedHeading
                        if items.isEmpty {
                            Text("这一天没有已记录的日程或 DDL。")
                                .font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 24)
                        } else {
                            ForEach(items) { item in CalendarItemRow(item: item, edit: edit) }
                        }
                    }.padding(.horizontal, 20).padding(.bottom, 20)
                }.accessibilityIdentifier("calendar-month-view")
            } else {
                VStack(spacing: 10) {
                    selectedHeading.padding(.horizontal, 20)
                    let pinned = items.filter { $0.isAllDay || $0.kind == .deadline }
                    if !pinned.isEmpty {
                        ScrollView {
                            VStack(spacing: 6) { ForEach(pinned) { item in CalendarItemRow(item: item, edit: edit) } }
                                .padding(.horizontal, 20)
                        }.frame(maxHeight: pinned.count > 1 ? 156 : 86)
                    }
                    CalendarDayTimeline(date: selectedDate, items: items, now: now, calendar: calendar, edit: edit, add: { add($0, true) })
                        .id(calendar.startOfDay(for: selectedDate))
                }.accessibilityIdentifier("calendar-day-view")
            }
        }.environment(\.locale, Locale(identifier: "zh_CN"))
            .alert("日历视图", isPresented: $showInfo) { Button("知道了", role: .cancel) {} } message: {
                Text("绿色表示日程时段，旗标表示 DDL。长按月历日期或日视图空白处添加日程；常态的后续日期也会展示，点选可编辑规则。仅同步设置中勾选的日历来源。")
            }
    }
    private var navigation: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Button { move(-1) } label: { Image(systemName: "chevron.left").frame(width: 32, height: 40) }
                    .accessibilityLabel(layout == 0 ? "上个月" : "前一天").accessibilityIdentifier("calendar-previous")
                Text(layout == 0 ? visibleMonth.formatted(.dateTime.year().month()) : selectedDate.formatted(.dateTime.month().day().weekday()))
                    .font(.headline).frame(maxWidth: .infinity).accessibilityIdentifier("calendar-period-title")
                Button { move(1) } label: { Image(systemName: "chevron.right").frame(width: 32, height: 40) }
                    .accessibilityLabel(layout == 0 ? "下个月" : "后一天").accessibilityIdentifier("calendar-next")
                Button("今天") { select(now) }.font(.subheadline.weight(.semibold)).accessibilityIdentifier("calendar-today")
            }
            HStack(spacing: 12) {
                ChoiceStrip(label: "日历布局", choices: [0, 1], selection: $layout,
                    title: { $0 == 0 ? "月历" : "日视图" }, identifier: { "calendar-layout-\($0)" })
                Menu {
                    Toggle("显示已完成", isOn: $showCompleted)
                    Button("视图说明", systemImage: "info.circle") { showInfo = true }
                } label: { Image(systemName: "ellipsis.circle").font(.title3).frame(width: 40, height: 40) }
                    .accessibilityLabel("日历显示选项")
            }
        }
    }
    private var monthGrid: some View {
        VStack(spacing: 4) {
            HStack {
                ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) { day in
                    Text(day).font(.caption.weight(.medium)).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                }
            }.padding(.bottom, 4)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 4) {
                ForEach(CalendarDisplay.monthDays(containing: visibleMonth, calendar: calendar), id: \.self) { day in
                    monthCell(day)
                }
            }
        }.padding(12).background(Theme.card, in: RoundedRectangle(cornerRadius: 18))
    }
    private func monthCell(_ day: Date) -> some View {
        let selected = calendar.isDate(day, inSameDayAs: selectedDate)
        let today = calendar.isDate(day, inSameDayAs: now)
        let inMonth = calendar.isDate(day, equalTo: visibleMonth, toGranularity: .month)
        let dayItems = CalendarDisplay.items(on: day, entries: entries, showCompleted: showCompleted, calendar: calendar)
        return Button { select(day) } label: {
            VStack(spacing: 3) {
                Text("\(calendar.component(.day, from: day))").font(.body.weight(selected || today ? .semibold : .regular))
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .foregroundStyle(selected ? Color(uiColor: .systemBackground) : today ? Color.red : inMonth ? Color(uiColor: .label) : Color(uiColor: .secondaryLabel))
                    .frame(width: 34, height: 34).background(selected ? Theme.accent : .clear, in: Circle())
                HStack(spacing: 3) {
                    ForEach(Array(dayItems.prefix(3).enumerated()), id: \.offset) { _, item in
                        Circle().fill(item.entry.isCompleted ? Color.secondary.opacity(0.45) : item.kind == .deadline ? Theme.warm : Theme.accent)
                            .frame(width: 4, height: 4)
                    }
                }.frame(height: 5)
            }.frame(maxWidth: .infinity, minHeight: 46).contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityLabel("\(day.formatted(.dateTime.year().month().day().weekday()))，\(dayItems.count) 项")
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityIdentifier(today ? "calendar-date-today" : "calendar-date-\(Int(day.timeIntervalSince1970))")
            .highPriorityGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                select(day)
                UISelectionFeedbackGenerator().selectionChanged()
                add(suggestedStart(on: day), true)
            })
            .accessibilityHint("轻点选择日期，长按添加日程")
            .accessibilityAction(named: "添加日程") { select(day); add(suggestedStart(on: day), true) }
    }
    private var selectedHeading: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                if layout == 0 {
                    Text(selectedDate, format: .dateTime.month().day().weekday(.wide)).font(.headline)
                        .accessibilityIdentifier("calendar-selected-date")
                }
                HStack(spacing: 12) {
                    Label("执行", systemImage: "calendar").foregroundStyle(Theme.accent)
                    Label("DDL", systemImage: "flag").foregroundStyle(Theme.warm)
                }.font(.caption)
            }
            Spacer()
            Menu {
                Button("添加当天截止的待办", systemImage: "flag") { add(selectedDate, false) }
                Button("添加日程", systemImage: "calendar.badge.plus") { add(defaultStart, true) }
            } label: { Image(systemName: "plus.circle.fill").font(.title2) }
                .accessibilityLabel("为所选日期添加事项").accessibilityIdentifier("calendar-add")
        }.padding(.top, 4)
    }
    private var defaultStart: Date {
        suggestedStart(on: selectedDate)
    }
    private func suggestedStart(on date: Date) -> Date {
        if calendar.isDate(date, inSameDayAs: now), let day = calendar.dateInterval(of: .day, for: date) {
            let rounded = Date(timeIntervalSince1970: (now.addingTimeInterval(300).timeIntervalSince1970 / 900).rounded(.up) * 900)
            return min(rounded, day.end.addingTimeInterval(-900))
        }
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: date) ?? date
    }
    private func select(_ day: Date) { selectedDate = day; visibleMonth = day }
    private func move(_ direction: Int) {
        if layout == 0, let month = calendar.dateInterval(of: .month, for: visibleMonth),
           let next = calendar.date(byAdding: .month, value: direction, to: month.start),
           let range = calendar.range(of: .day, in: .month, for: next),
           let day = calendar.date(byAdding: .day, value: min(calendar.component(.day, from: selectedDate), range.count) - 1, to: next) {
            select(day)
        } else if let next = calendar.date(byAdding: .day, value: direction, to: selectedDate) { select(next) }
    }
}

private struct CalendarItemRow: View {
    let item: CalendarDisplayItem
    let edit: (Entry) -> Void
    private var color: Color { item.entry.isCompleted ? .secondary : item.kind == .deadline ? Theme.warm : Theme.accent }
    var body: some View {
        Button { edit(item.entry) } label: {
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 4)
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.entry.title).font(.subheadline.weight(.semibold)).foregroundStyle(Color(uiColor: .label))
                        .strikethrough(item.entry.isCompleted).multilineTextAlignment(.leading)
                    Label(timeLabel, systemImage: item.kind == .deadline ? "flag" : "calendar")
                        .font(.caption).foregroundStyle(color)
                    if !item.entry.location.isEmpty { Text(item.entry.location).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer(minLength: 0)
                if item.entry.isCompleted { Image(systemName: "checkmark.circle.fill").foregroundStyle(.secondary) }
                else { Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary) }
            }.fixedSize(horizontal: false, vertical: true).padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain).accessibilityIdentifier("calendar-item-\(item.id)")
    }
    private var timeLabel: String {
        if item.kind == .deadline { return "DDL · \(item.date.formatted(date: .omitted, time: .shortened))" }
        if item.isAllDay { return "全天" }
        guard let end = item.end else { return item.date.formatted(date: .omitted, time: .shortened) }
        return "\(Theme.dateLabel(item.date))–\(end.formatted(date: .omitted, time: .shortened))"
    }
}

private struct CalendarDayTimeline: View {
    let date: Date
    let items: [CalendarDisplayItem]
    let now: Date
    let calendar: Calendar
    let edit: (Entry) -> Void
    let add: (Date) -> Void
    private let hourHeight: CGFloat = 72
    private var day: DateInterval { calendar.dateInterval(of: .day, for: date)! }
    private var blocks: [CalendarBlock] { CalendarTimelineLayout.blocks(on: date, items: items, calendar: calendar) }
    var body: some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width, CGFloat(blocks.map(\.columnCount).max() ?? 1) * 90 + 58)
            ScrollViewReader { proxy in
                ScrollView([.vertical, .horizontal]) {
                    canvas(width: width)
                        .frame(width: width, height: CGFloat(day.duration / 3600) * hourHeight + 30, alignment: .topLeading)
                }.task { await Task.yield(); proxy.scrollTo(initialHour, anchor: .top) }
            }
        }.accessibilityIdentifier("calendar-hour-timeline")
    }
    private func canvas(width: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) { ForEach(0..<Int(day.duration / 3600), id: \.self) { hour in
                HStack(alignment: .top, spacing: 8) {
                    Text(hourLabel(hour))
                        .font(.caption2).monospacedDigit().foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8).frame(width: 48, alignment: .trailing)
                    Button { add(day.start.addingTimeInterval(Double(hour * 3600))) } label: {
                        VStack(spacing: 0) { Rectangle().fill(Color(uiColor: .separator)).frame(height: 0.5); Color.clear }
                            .frame(width: width - 64, height: hourHeight).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel("添加 \(hourLabel(hour)) 的日程")
                        .accessibilityIdentifier("calendar-hour-\(hour)")
                        .highPriorityGesture(LongPressGesture(minimumDuration: 0.5)
                            .sequenced(before: DragGesture(minimumDistance: 0))
                            .onEnded { value in
                                if case .second(true, let drag) = value {
                                    let fraction = Double((drag?.location.y ?? 0) / hourHeight)
                                    if let start = CalendarTimelineLayout.start(on: date, minuteOffset: Double(hour * 60) + fraction * 60, calendar: calendar) {
                                        UISelectionFeedbackGenerator().selectionChanged()
                                        add(start)
                                    }
                                }
                            })
                        .accessibilityHint("长按空白处，按所在位置添加日程")
                        .accessibilityAction(named: "添加日程") { add(day.start.addingTimeInterval(Double(hour * 3600))) }
                }.frame(height: hourHeight, alignment: .top).id(hour)
            } }.padding(.top, 12)
            ForEach(blocks) { block in
                blockView(block, width: width)
            }
            if day.start <= now && now < day.end {
                HStack(spacing: 0) {
                    Text(clockLabel(now))
                        .font(.caption2.weight(.semibold)).monospacedDigit().foregroundStyle(.red).frame(width: 52)
                    Circle().fill(.red).frame(width: 6, height: 6)
                    Rectangle().fill(.red).frame(height: 1)
                }.frame(width: width - 12).offset(y: CGFloat(now.timeIntervalSince(day.start) / 3600) * hourHeight + 6)
                    .allowsHitTesting(false).accessibilityLabel("当前时间")
            }
        }
    }
    private func blockView(_ block: CalendarBlock, width: CGFloat) -> some View {
        let columnWidth = (width - 68) / CGFloat(block.columnCount)
        let height = max(22, CGFloat(block.endMinute - block.startMinute) / 60 * hourHeight)
        let color: Color = block.item.entry.isCompleted ? .secondary : Theme.accent
        return Button { edit(block.item.entry) } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(block.item.entry.title).font(.caption.weight(.semibold)).strikethrough(block.item.entry.isCompleted).lineLimit(height < 42 ? 1 : 2)
                if height >= 42 {
                    Text(clockLabel(block.item.date)).font(.caption2).monospacedDigit()
                }
            }.foregroundStyle(Color(uiColor: .label)).padding(.horizontal, 7).padding(.vertical, 4)
                .frame(width: columnWidth - 4, height: height, alignment: .topLeading)
                .background(color.opacity(0.17), in: RoundedRectangle(cornerRadius: 6))
                .overlay(alignment: .leading) { UnevenRoundedRectangle(topLeadingRadius: 3, bottomLeadingRadius: 3).fill(color).frame(width: 3) }
                .clipped()
        }.buttonStyle(.plain).offset(x: 56 + CGFloat(block.column) * columnWidth, y: CGFloat(block.startMinute) / 60 * hourHeight + 12)
            .accessibilityLabel("\(block.item.entry.title)，\(Theme.dateLabel(block.item.date))")
            .accessibilityIdentifier("calendar-block-\(block.item.entry.id)")
    }
    private var initialHour: Int {
        let target = blocks.first?.startMinute ?? (calendar.isDate(date, inSameDayAs: now) ? now.timeIntervalSince(day.start) / 60 : 540)
        return max(0, Int(target / 60) - 1)
    }
    private func hourLabel(_ hour: Int) -> String {
        let time = day.start.addingTimeInterval(Double(hour * 3600))
        return clockLabel(time)
    }
    private func clockLabel(_ time: Date) -> String {
        return String(format: "%02d:%02d", calendar.component(.hour, from: time), calendar.component(.minute, from: time))
    }
}
