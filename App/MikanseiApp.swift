import SwiftUI

@main
struct MikanseiApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var notifications: NotificationManager
    @StateObject private var store: EntryStore
    @StateObject private var pomodoro: PomodoroCoordinator
    @StateObject private var cloud: CloudAccountManager
    @StateObject private var calendarSync = CalendarSyncManager()
    @StateObject private var deadlineActivity = DeadlineActivityManager()
    @StateObject private var folderSync = FolderSyncManager()
    @State private var didStartCloud = false

    init() {
        let notifications = NotificationManager()
        let store = EntryStore(notifications: notifications)
        _notifications = StateObject(wrappedValue: notifications)
        _store = StateObject(wrappedValue: store)
        _pomodoro = StateObject(wrappedValue: PomodoroCoordinator())
        _cloud = StateObject(wrappedValue: CloudAccountManager(workspace: store))
    }
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(pomodoro)
                .environmentObject(cloud)
                .environmentObject(notifications)
                .environmentObject(calendarSync)
                .environmentObject(deadlineActivity)
                .environmentObject(folderSync)
                .tint(Theme.accent)
                .task {
                    guard !ProcessInfo.processInfo.arguments.contains("--ui-testing"),
                          !didStartCloud else { return }
                    didStartCloud = true
                    await cloud.start()
                }
                .onChange(of: scenePhase) { _, phase in
                    guard !ProcessInfo.processInfo.arguments.contains("--ui-testing") else { return }
                    cloud.setForeground(phase == .active)
                }
        }
    }
}
