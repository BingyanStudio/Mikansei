import SwiftUI

@main
struct MikanseiApp: App {
    @StateObject private var notifications: NotificationManager
    @StateObject private var store: EntryStore
    @StateObject private var calendarSync = CalendarSyncManager()

    init() {
        let notifications = NotificationManager()
        _notifications = StateObject(wrappedValue: notifications)
        _store = StateObject(wrappedValue: EntryStore(notifications: notifications))
    }
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(notifications)
                .environmentObject(calendarSync)
                .tint(Theme.accent)
        }
    }
}
