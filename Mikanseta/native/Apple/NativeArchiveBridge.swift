import Foundation
import UniformTypeIdentifiers
#if os(iOS)
import Flutter
import UIKit
import WidgetKit
#else
import FlutterMacOS
import AppKit
#endif

/// The Flutter domain owns merging. This adapter provides atomic local storage
/// and user-selected documents, without iCloud entitlements.
@MainActor
final class NativeArchiveBridge: NSObject {
    private let queue = DispatchQueue(label: "Mikanseta.archive", qos: .userInitiated)
    private let channel: FlutterMethodChannel
    private lazy var services = AppleSystemServices(channel:channel)
    private var pickerResult: FlutterResult?
    private var folderPickerResult: FlutterResult?
    private static let localSyncBookmarkKey = "Mikanseta.localSyncFolderBookmark.v1"
    private let archiveURL: URL
    private var pomodoroArchiveURL: URL {
        archiveURL.deletingLastPathComponent().appendingPathComponent("pomodoro.json")
    }
    init(messenger: FlutterBinaryMessenger) {
        channel = FlutterMethodChannel(name: "mikanseta/native", binaryMessenger: messenger)
        archiveURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Mikanseta", isDirectory: true).appendingPathComponent("entries.json")
        super.init()
        _ = services
        channel.setMethodCallHandler { [weak self] call, result in self?.handle(call, result: result) }
    }
    func acceptURL(_ url:URL) { services.acceptURL(url) }
    private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        if services.handle(call,result:result) { return }
        switch call.method {
        case "readArchive":
            perform(result) { [archiveURL] in
                guard FileManager.default.fileExists(atPath: archiveURL.path) else { return nil }
                let text = try String(contentsOf: archiveURL, encoding: .utf8)
                DispatchQueue.main.async { self.services.update(text) }
                return text
            }
        case "writeArchive":
            guard let text = call.arguments as? String else { result(FlutterError(code: "arguments", message: "缺少备份内容", details: nil)); return }
            perform(result) { [archiveURL] in
                try FileManager.default.createDirectory(at: archiveURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                #if os(iOS)
                try Data(text.utf8).write(to: archiveURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                #else
                try Data(text.utf8).write(to: archiveURL, options: .atomic)
                #endif
                DispatchQueue.main.async { self.services.update(text) }
                return nil
            }
        case "readPomodoroArchive":
            perform(result) { [pomodoroArchiveURL] in
                guard FileManager.default.fileExists(atPath: pomodoroArchiveURL.path) else { return nil }
                return try String(contentsOf: pomodoroArchiveURL, encoding: .utf8)
            }
        case "writePomodoroArchive":
            guard let text = call.arguments as? String else { result(FlutterError(code: "arguments", message: "缺少专注记录", details: nil)); return }
            perform(result) { [pomodoroArchiveURL] in
                try FileManager.default.createDirectory(at: pomodoroArchiveURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                #if os(iOS)
                try Data(text.utf8).write(to: pomodoroArchiveURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                #else
                try Data(text.utf8).write(to: pomodoroArchiveURL, options: .atomic)
                #endif
                return nil
            }
        case "writePomodoroSnapshot":
            #if os(iOS)
            guard let text = call.arguments as? String, let data = text.data(using: .utf8) else {
                result(FlutterError(code: "arguments", message: "缺少专注卡片状态", details: nil)); return
            }
            do {
                let snapshot = try JSONDecoder().decode(PomodoroSnapshot.self, from: data)
                perform(result) {
                    try PomodoroSnapshotStore.save(snapshot)
                    WidgetCenter.shared.reloadTimelines(ofKind: "Mikanseta.Pomodoro")
                    return nil
                }
            } catch {
                result(FlutterError(code: "snapshot", message: "专注卡片状态无效：\(error.localizedDescription)", details: nil))
            }
            #else
            result(nil)
            #endif
        case "importArchive", "importText": openDocument(result)
        case "exportArchive":
            guard let text = call.arguments as? String else { result(FlutterError(code: "arguments", message: "缺少备份内容", details: nil)); return }
            exportDocument(text, result: result)
        case "appInfo": result("\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"))")
        case "pickLocalSyncFolder": pickLocalSyncFolder(result)
        case "localSyncFolder": localSyncFolder(result)
        case "disconnectLocalSyncFolder": disconnectLocalSyncFolder(result)
        case "readLocalSyncFiles": readLocalSyncFiles(result)
        case "writeLocalSyncFile": writeLocalSyncFile(call, result)
        case "readLocalSyncState": readLocalSyncState(result)
        case "writeLocalSyncState": writeLocalSyncState(call, result)
        default: result(FlutterMethodNotImplemented)
        }
    }
    private func perform(_ result: @escaping FlutterResult, operation: @escaping () throws -> Any?) {
        #if os(iOS)
        var background: UIBackgroundTaskIdentifier = .invalid
        background = UIApplication.shared.beginBackgroundTask(withName: "Mikanseta 保存") {
            if background != .invalid { UIApplication.shared.endBackgroundTask(background); background = .invalid }
        }
        let finish: (Any?) -> Void = { value in
            if background != .invalid { UIApplication.shared.endBackgroundTask(background); background = .invalid }
            result(value)
        }
        #else
        let finish = result
        #endif
        queue.async {
            do { let value = try operation(); DispatchQueue.main.async { finish(value) } }
            catch { DispatchQueue.main.async { finish(FlutterError(code: "file", message: error.localizedDescription, details: nil)) } }
        }
    }
    private func readSelected(_ url: URL) throws -> String {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        var failure: NSError?
        var outcome: Result<String, Error>?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &failure) { coordinated in
            outcome = Result { try String(contentsOf: coordinated, encoding: .utf8) }
        }
        if let failure { throw failure }
        guard let outcome else { throw CocoaError(.fileReadUnknown) }
        return try outcome.get()
    }

    // MARK: - Shared folder sync (native Mikansei replica protocol)

    private func pickLocalSyncFolder(_ result: @escaping FlutterResult) {
        #if os(iOS)
        guard folderPickerResult == nil, pickerResult == nil, let presenter else {
            result(FlutterError(code: "unavailable", message: "无法打开文件夹选择窗口", details: nil))
            return
        }
        folderPickerResult = result
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
        picker.delegate = self
        picker.allowsMultipleSelection = false
        presenter.present(picker, animated: true)
        #else
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "选择同步文件夹"
        guard panel.runModal() == .OK, let url = panel.url else { result(nil); return }
        do {
            // The picked URL is security-scoped; bookmark creation needs access.
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let bookmark = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(bookmark, forKey: Self.localSyncBookmarkKey)
            result(["name": url.lastPathComponent, "path": url.path])
        } catch {
            result(FlutterError(code: "bookmark", message: error.localizedDescription, details: nil))
        }
        #endif
    }

    private func localSyncFolderURL() throws -> URL? {
        guard let data = UserDefaults.standard.data(forKey: Self.localSyncBookmarkKey) else { return nil }
        var stale = false
        #if os(iOS)
        let url = try URL(resolvingBookmarkData: data, options: [.withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
        #else
        let url = try URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
        #endif
        if stale { throw CocoaError(.fileReadNoPermission) }
        return url
    }

    private func localSyncFolder(_ result: @escaping FlutterResult) {
        do {
            guard let url = try localSyncFolderURL() else {
                result(["connected": false])
                return
            }
            result(["connected": true, "name": url.lastPathComponent, "path": url.path])
        } catch {
            result(["connected": false, "error": "文件夹授权已失效，请重新选择：\(error.localizedDescription)"])
        }
    }

    private func disconnectLocalSyncFolder(_ result: @escaping FlutterResult) {
        UserDefaults.standard.removeObject(forKey: Self.localSyncBookmarkKey)
        result(nil)
    }

    private func withSyncFolder<T>(_ operation: (URL) throws -> T) throws -> T {
        guard let url = try localSyncFolderURL() else { throw CocoaError(.fileNoSuchFile) }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        return try operation(url)
    }

    private func readLocalSyncFiles(_ result: @escaping FlutterResult) {
        perform(result) {
            try self.withSyncFolder { folder in
                let directory = folder.appendingPathComponent("Mikansei-sync", isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                var outcome: Result<[String: String], Error>?
                var coordinationError: NSError?
                NSFileCoordinator().coordinate(readingItemAt: directory, options: [], error: &coordinationError) { location in
                    outcome = Result {
                        var files: [String: String] = [:]
                        let entries = try FileManager.default.contentsOfDirectory(
                            at: location,
                            includingPropertiesForKeys: [.isRegularFileKey, .ubiquitousItemDownloadingStatusKey]
                        )
                        for file in entries {
                            let name = file.lastPathComponent
                            if name.hasPrefix(".replica-") && name.hasSuffix(".json.icloud") {
                                let original = location.appendingPathComponent(String(name.dropFirst().dropLast(7)))
                                try? FileManager.default.startDownloadingUbiquitousItem(at: original)
                                continue
                            }
                            guard name.hasPrefix("replica-"), file.pathExtension == "json" else { continue }
                            let values = try file.resourceValues(forKeys: [.isRegularFileKey, .ubiquitousItemDownloadingStatusKey])
                            guard values.isRegularFile == true else { continue }
                            if values.ubiquitousItemDownloadingStatus == .notDownloaded {
                                try? FileManager.default.startDownloadingUbiquitousItem(at: file)
                                continue
                            }
                            files[name] = try String(contentsOf: file, encoding: .utf8)
                        }
                        return files
                    }
                }
                if let coordinationError { throw coordinationError }
                guard let outcome else { throw CocoaError(.fileReadUnknown) }
                return try outcome.get()
            }
        }
    }

    private func writeLocalSyncFile(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        let pattern = #"^replica-[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\.json$"#
        guard let args = call.arguments as? [String: Any],
              let name = args["name"] as? String,
              let content = args["content"] as? String,
              name.range(of: pattern, options: .regularExpression) != nil else {
            result(FlutterError(code: "arguments", message: "同步文件名无效", details: nil))
            return
        }
        perform(result) {
            try self.withSyncFolder { folder in
                let directory = folder.appendingPathComponent("Mikansei-sync", isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let target = directory.appendingPathComponent(name)
                let data = Data(content.utf8)
                if (try? Data(contentsOf: target)) == data { return false }
                var coordinationError: NSError?
                var writeError: Error?
                NSFileCoordinator().coordinate(writingItemAt: target, options: .forMerging, error: &coordinationError) { location in
                    do { try data.write(to: location, options: .atomic) } catch { writeError = error }
                }
                if let coordinationError { throw coordinationError }
                if let writeError { throw writeError }
                return true
            }
        }
    }

    private var localSyncStateURL: URL {
        archiveURL.deletingLastPathComponent().appendingPathComponent("local-sync-state.json")
    }

    private func readLocalSyncState(_ result: @escaping FlutterResult) {
        perform(result) {
            guard FileManager.default.fileExists(atPath: self.localSyncStateURL.path) else { return nil }
            return try String(contentsOf: self.localSyncStateURL, encoding: .utf8)
        }
    }

    private func writeLocalSyncState(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        guard let content = call.arguments as? String else {
            result(FlutterError(code: "arguments", message: "缺少同步状态", details: nil))
            return
        }
        perform(result) {
            try FileManager.default.createDirectory(at: self.localSyncStateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            #if os(iOS)
            try Data(content.utf8).write(to: self.localSyncStateURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            #else
            try Data(content.utf8).write(to: self.localSyncStateURL, options: .atomic)
            #endif
            return nil
        }
    }

    #if os(iOS)
    private var presenter: UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive }
        var controller = scene?.windows.first { $0.isKeyWindow }?.rootViewController
        while let presented = controller?.presentedViewController { controller = presented }
        return controller
    }
    private func openDocument(_ result: @escaping FlutterResult) {
        guard pickerResult == nil, let presenter else { result(FlutterError(code: "busy", message: "请稍后再导入", details: nil)); return }
        pickerResult = result
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.json,.plainText,.commaSeparatedText,UTType(filenameExtension:"ics") ?? .data], asCopy: false)
        picker.delegate = self; picker.allowsMultipleSelection = false
        presenter.present(picker, animated: true)
    }
    private func exportDocument(_ text: String, result: @escaping FlutterResult) {
        guard let presenter else { result(FlutterError(code: "unavailable", message: "无法打开分享窗口", details: nil)); return }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent("Mikanseta-backup.json")
            try Data(text.utf8).write(to: url, options: .atomic)
            let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            activity.popoverPresentationController?.sourceView = presenter.view
            activity.popoverPresentationController?.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 1, height: 1)
            activity.completionWithItemsHandler = { _, completed, _, error in
                try? FileManager.default.removeItem(at: folder)
                if let error { result(FlutterError(code: "export", message: error.localizedDescription, details: nil)) }
                else { result(completed) }
            }
            presenter.present(activity, animated: true)
        } catch { result(FlutterError(code: "export", message: error.localizedDescription, details: nil)) }
    }
    #else
    private func openDocument(_ result: @escaping FlutterResult) {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json,.plainText,.commaSeparatedText,UTType(filenameExtension:"ics") ?? .data]
        panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { result(nil); return }
        perform(result) { try self.readSelected(url) }
    }
    private func exportDocument(_ text: String, result: @escaping FlutterResult) {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "Mikanseta-backup.json"
        guard panel.runModal() == .OK, let url = panel.url else { result(false); return }
        perform(result) {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            try Data(text.utf8).write(to: url, options: .atomic)
            return true
        }
    }
    #endif
}

#if os(iOS)
extension NativeArchiveBridge: UIDocumentPickerDelegate {
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        if let folderResult = folderPickerResult {
            folderPickerResult = nil
            folderResult(nil)
            return
        }
        pickerResult?(nil); pickerResult = nil
    }
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        if let folderResult = folderPickerResult {
            folderPickerResult = nil
            guard let url = urls.first else { folderResult(nil); return }
            do {
                // Mirrors FolderSyncManager.connect: create the bookmark while
                // the picked URL's security scope is active, or iCloud items
                // report "file doesn't exist".
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let bookmark = try url.bookmarkData(options: [.minimalBookmark], includingResourceValuesForKeys: nil, relativeTo: nil)
                UserDefaults.standard.set(bookmark, forKey: Self.localSyncBookmarkKey)
                folderResult(["name": url.lastPathComponent, "path": url.path])
            } catch {
                folderResult(FlutterError(code: "bookmark", message: error.localizedDescription, details: nil))
            }
            return
        }
        guard let result = pickerResult else { return }
        pickerResult = nil
        guard let url = urls.first else { result(nil); return }
        perform(result) { try self.readSelected(url) }
    }
}
#endif
