import EventKit
import SwiftUI

struct CalendarSyncView: View {
    @EnvironmentObject private var store: EntryStore
    @EnvironmentObject private var sync: CalendarSyncManager
    var body: some View {
        Form {
            Section {
                Toggle("打开 App 时自动同步", isOn: Binding(get: { store.calendarSync.enabled }, set: { value in
                    var settings = store.calendarSync; settings.enabled = value
                    if store.saveCalendarSyncSettings(settings), value { Task { await sync.sync(store: store, requestAccess: true) } }
                })).accessibilityIdentifier("calendar-auto-sync")
                LabeledContent("日历权限", value: sync.statusTitle)
                if sync.authorization == .notDetermined || sync.authorization == .writeOnly {
                    Button("允许读取日历", systemImage: "calendar.badge.plus") { Task { await sync.sync(store: store, requestAccess: true, manual: true) } }
                } else if sync.authorization == .denied || sync.authorization == .restricted {
                    Button("打开系统权限设置", systemImage: "gear") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                }
            } footer: { Text("读取今天及未来 30 天内（含今天）的事件；自动导入不改动系统日历；只有在事项中点击安排或编辑日历并保存，才写入日历。关闭同步会保留已导入的清单。") }
            Section("导入方式") {
                Picker("时间安排", selection: Binding(get: { store.calendarSync.timing }, set: { value in
                    var settings = store.calendarSync; settings.timing = value
                    if store.saveCalendarSyncSettings(settings) { Task { await sync.sync(store: store) } }
                })) { ForEach(CalendarImportTiming.allCases) { Text($0.title).tag($0) } }.clearOptionText()
                Text("默认保留日历执行时段，不把开始时间当作 DDL。可单独设置截止日期；选择按结束时间截止时会附加 DDL。全天事件保留全天安排；标题、地点、备注和链接一并导入。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if sync.authorization == .fullAccess {
                Section("选择日历") {
                    if sync.calendars.isEmpty { Text("系统日历中暂无可读取的日历。") }
                    ForEach(sync.calendars) { calendar in
                        Toggle(isOn: Binding(get: { store.calendarSync.selected.contains(where: { $0.id == calendar.id }) }, set: { selected in
                            var settings = store.calendarSync
                            settings.selected.removeAll { $0.id == calendar.id }
                            if selected { settings.selected.append(calendar.selection) }
                            if store.saveCalendarSyncSettings(settings) { Task { await sync.sync(store: store) } }
                        })) {
                            HStack(spacing: 10) {
                                Circle().fill(calendar.color).frame(width: 9, height: 9)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(calendar.selection.title).foregroundStyle(.primary)
                                    Text(calendar.selection.sourceTitle).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    let unavailable = store.calendarSync.selected.filter { selected in !sync.calendars.contains(where: { $0.id == selected.id }) }
                    ForEach(unavailable) { calendar in
                        HStack {
                            Text("暂未找到：\(calendar.title)").font(.subheadline)
                            Spacer()
                            Button("取消选择") { var settings = store.calendarSync; settings.selected.removeAll { $0.id == calendar.id }; _ = store.saveCalendarSyncSettings(settings) }
                        }
                    }
                }
            }
            Section {
                Button { Task { await sync.sync(store: store, requestAccess: true, manual: true) } } label: {
                    HStack { Label("立即同步", systemImage: "arrow.triangle.2.circlepath"); Spacer(); if sync.isSyncing { ProgressView() } }
                }.disabled(sync.isSyncing || store.readOnly).accessibilityIdentifier("calendar-sync-now")
                Text(sync.message).font(.subheadline).accessibilityIdentifier("calendar-sync-status")
                if let date = sync.lastSync { LabeledContent("上次同步", value: Theme.dateLabel(date)) }
                if let error = sync.error { Text(error).font(.caption).foregroundStyle(.red) }
            } footer: {
                Text("相同事件不重复添加。保留完成状态、Checklist、计时和手动修改的字段；删除已导入事项后，不会在下次打开时重新添加。原日历未找到或取消的事件会保留，并提示核对。")
            }
        }
        .navigationTitle("日历自动导入").navigationBarTitleDisplayMode(.inline)
        .disabled(store.readOnly)
        .task { sync.refreshChoices(store: store); await sync.sync(store: store) }
    }
}
