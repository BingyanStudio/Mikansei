import Foundation
import UniformTypeIdentifiers
#if os(iOS)
import Flutter
import UIKit
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
    private let archiveURL: URL
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
        case "importArchive", "importText": openDocument(result)
        case "exportArchive":
            guard let text = call.arguments as? String else { result(FlutterError(code: "arguments", message: "缺少备份内容", details: nil)); return }
            exportDocument(text, result: result)
        case "appInfo": result("\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"))")
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
        pickerResult?(nil); pickerResult = nil
    }
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let result = pickerResult else { return }
        pickerResult = nil
        guard let url = urls.first else { result(nil); return }
        perform(result) { try self.readSelected(url) }
    }
}
#endif
