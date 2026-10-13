import EventKit
import SwiftUI

@MainActor
final class MacCalendarImport: ObservableObject {
    @Published var calendars: [EKCalendar] = []
    @Published var message = "允许日历权限后选择要导入的来源。"
    private let events = EKEventStore()
    func refresh(store: MacWorkspaceStore, request: Bool = false) async {
        guard !store.readOnly, !ProcessInfo.processInfo.arguments.contains("--ui-testing") else { return }
        do {
            if request { _ = try await events.requestFullAccessToEvents() }
            guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return }
            events.reset(); calendars = events.calendars(for: .event)
            let choices = calendars.map { CalendarSelection(id: $0.calendarIdentifier, title: $0.title, sourceTitle: $0.source.title) }
            store.calendarSettings = store.calendarSettings.refreshed(available: choices)
            store.persist()
            guard store.calendarSettings.enabled else { return }
            let selected = calendars.filter { c in store.calendarSettings.selected.contains { $0.id == c.calendarIdentifier } }
            guard !selected.isEmpty else { message = "请勾选要导入的来源，默认不导入节假日。"; return }
            let start = Calendar.current.startOfDay(for: Date()), end = Calendar.current.date(byAdding: .day, value: 30, to: start)!
            let records = events.events(matching: events.predicateForEvents(withStart: start, end: end, calendars: selected)).compactMap { event -> CalendarEventRecord? in
                guard let calendar = event.calendar, let first = event.startDate, let last = event.endDate else { return nil }
                var occurrence = ""
                if event.hasRecurrenceRules || event.isDetached {
                    let original = event.occurrenceDate ?? first
                    if event.isAllDay {
                        let formatter = DateFormatter(); formatter.calendar = Calendar(identifier: .gregorian); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
                        occurrence = "day:\(formatter.string(from: original))"
                    } else { occurrence = "time:\(Int64(original.timeIntervalSince1970.rounded()))" }
                }
                let identity = CalendarEventIdentity(calendarID: calendar.calendarIdentifier, calendarTitle: calendar.title, sourceTitle: calendar.source.title, eventID: event.calendarItemExternalIdentifier ?? event.calendarItemIdentifier, occurrence: occurrence, localEventID: event.calendarItemIdentifier)
                return CalendarEventRecord(identity: identity, title: event.title ?? "日程", start: Date(timeIntervalSince1970: first.timeIntervalSince1970.rounded(.down)), end: Date(timeIntervalSince1970: last.timeIntervalSince1970.rounded(.down)), isAllDay: event.isAllDay, notes: event.notes ?? "", location: event.location ?? "", url: event.url?.absoluteString ?? "", isCancelled: event.status == .canceled)
            }
            let result = CalendarImport.merge(events: records, into: store.entries, settings: store.calendarSettings, range: start..<end, availableCalendarIDs: Set(calendars.map(\.calendarIdentifier)), queriedCalendarIDs: Set(selected.map(\.calendarIdentifier)))
            for entry in result.entries where store.entries.first(where: { $0.id == entry.id }) != entry { store.save(entry) }
            message = "新增 \(result.added) 件，更新 \(result.updated) 件"
        } catch { message = error.localizedDescription }
    }
}

struct MacCalendarSettings: View {
    @EnvironmentObject private var store: MacWorkspaceStore
    @StateObject private var importer = MacCalendarImport()
    var body: some View {
        Section("苹果日历") {
            Toggle("打开时自动导入", isOn: $store.calendarSettings.enabled).onChange(of: store.calendarSettings.enabled) { _, _ in store.persist() }
            Button("允许日历并刷新来源") { Task { await importer.refresh(store: store, request: true) } }
            ForEach(importer.calendars, id: \.calendarIdentifier) { calendar in
                Toggle(calendar.title, isOn: Binding(get: { store.calendarSettings.selected.contains { $0.id == calendar.calendarIdentifier } }, set: { selected in
                    store.calendarSettings.selected.removeAll { $0.id == calendar.calendarIdentifier }
                    if selected { store.calendarSettings.selected.append(CalendarSelection(id: calendar.calendarIdentifier, title: calendar.title, sourceTitle: calendar.source.title)) }
                    store.persist()
                }))
            }
            Button("立即导入") { Task { await importer.refresh(store: store) } }
            Text(importer.message).font(.caption).foregroundStyle(.secondary)
        }.task { await importer.refresh(store: store) }
    }
}
