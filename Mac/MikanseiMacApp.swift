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
    @StateObject private var cloud: CloudAccountManager
    @StateObject private var sync = FolderSyncManager()
    @State private var didStartCloud = false

    init() {
        let store = MacWorkspaceStore()
        _store = StateObject(wrappedValue: store)
        _cloud = StateObject(wrappedValue: CloudAccountManager(workspace: store))
    }

    var body: some Scene {
        WindowGroup("Mikansei", id: "workspace") {
            MacWorkspaceView().environmentObject(store).environmentObject(sync).environmentObject(cloud)
                .tint(MacTheme.accent)
                .frame(minWidth: 900, minHeight: 580)
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
        .commands { MacWorkspaceCommands() }
        Settings {
            MacSettingsView().environmentObject(store).environmentObject(sync).environmentObject(cloud).frame(width: 560, height: 530)
        }
    }
}

private struct NewEntryActionKey: FocusedValueKey { typealias Value = () -> Void }
extension FocusedValues {
    var newEntryAction: (() -> Void)? {
        get { self[NewEntryActionKey.self] }
        set { self[NewEntryActionKey.self] = newValue }
    }
}
struct MacWorkspaceCommands: Commands {
    @FocusedValue(\.newEntryAction) private var newEntry
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("新建事项") { newEntry?() }.keyboardShortcut("n").disabled(newEntry == nil)
        }
    }
}
