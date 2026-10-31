import SwiftUI
import AppKit

enum MacTheme {
    static let accent = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0.48, green: 0.85, blue: 0.70, alpha: 1)
            : NSColor(srgbRed: 0.12, green: 0.39, blue: 0.30, alpha: 1)
    })
}

@main
struct MikanseiMacApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store: MacWorkspaceStore
    @StateObject private var pomodoro: PomodoroCoordinator
    @StateObject private var pomodoroPanel: MacPomodoroPanelController
    @StateObject private var cloud: CloudAccountManager
    @StateObject private var sync = FolderSyncManager()
    @State private var didStartCloud = false
    @State private var didOpenPomodoroPreview = false

    init() {
        let store = MacWorkspaceStore()
        let pomodoro = PomodoroCoordinator()
        _store = StateObject(wrappedValue: store)
        _pomodoro = StateObject(wrappedValue: pomodoro)
        _pomodoroPanel = StateObject(wrappedValue: MacPomodoroPanelController(coordinator: pomodoro, workspace: store))
        _cloud = StateObject(wrappedValue: CloudAccountManager(workspace: store))
    }

    var body: some Scene {
        WindowGroup("Mikansei", id: "workspace") {
            MacWorkspaceView().environmentObject(store).environmentObject(sync).environmentObject(cloud)
                .environmentObject(pomodoro).environmentObject(pomodoroPanel)
                .tint(MacTheme.accent)
                .frame(minWidth: 900, minHeight: 580)
                .task {
                    if ProcessInfo.processInfo.arguments.contains("--pomodoro-preview"), !didOpenPomodoroPreview {
                        didOpenPomodoroPreview = true
                        pomodoroPanel.show()
                    }
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
        .commands { MacWorkspaceCommands() }
        Settings {
            MacSettingsView().environmentObject(store).environmentObject(sync).environmentObject(cloud).frame(width: 560, height: 530)
        }
    }
}

private struct NewEntryActionKey: FocusedValueKey { typealias Value = () -> Void }
private struct ShowPomodoroActionKey: FocusedValueKey { typealias Value = () -> Void }
extension FocusedValues {
    var newEntryAction: (() -> Void)? {
        get { self[NewEntryActionKey.self] }
        set { self[NewEntryActionKey.self] = newValue }
    }
    var showPomodoroAction: (() -> Void)? {
        get { self[ShowPomodoroActionKey.self] }
        set { self[ShowPomodoroActionKey.self] = newValue }
    }
}
struct MacWorkspaceCommands: Commands {
    @FocusedValue(\.newEntryAction) private var newEntry
    @FocusedValue(\.showPomodoroAction) private var showPomodoro
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("新建事项") { newEntry?() }.keyboardShortcut("n").disabled(newEntry == nil)
        }
        CommandGroup(after: .windowArrangement) {
            Button("显示专注浮窗") { showPomodoro?() }
                .keyboardShortcut("t", modifiers: [.command, .option])
                .disabled(showPomodoro == nil)
        }
    }
}
