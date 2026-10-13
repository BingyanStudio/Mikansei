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
    @StateObject private var store = MacWorkspaceStore()
    @StateObject private var sync = FolderSyncManager()
    var body: some Scene {
        WindowGroup("Mikansei", id: "workspace") {
            MacWorkspaceView().environmentObject(store).environmentObject(sync)
                .tint(MacTheme.accent)
                .frame(minWidth: 900, minHeight: 580)
        }
        .commands { MacWorkspaceCommands() }
        Settings {
            MacSettingsView().environmentObject(store).environmentObject(sync).frame(width: 560, height: 530)
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
