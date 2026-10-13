import Foundation

#if os(iOS) || os(macOS)
public enum FolderSyncTransport {
    /// Every device owns a separate snapshot file: concurrent uploads never overwrite another device.
    public static func exchange(snapshot: WorkspaceReplica, folder: URL) throws -> WorkspaceSyncDocument {
        let access = folder.startAccessingSecurityScopedResource()
        defer { if access { folder.stopAccessingSecurityScopedResource() } }
        let directory = folder.appendingPathComponent("Mikansei-sync", isDirectory: true)
        var coordinationError: NSError?
        var result: Result<WorkspaceSyncDocument, Error>?
        NSFileCoordinator().coordinate(writingItemAt: directory, options: .forMerging, error: &coordinationError) { location in
            result = Result {
                try FileManager.default.createDirectory(at: location, withIntermediateDirectories: true)
                var merged = snapshot.document
                let files = try FileManager.default.contentsOfDirectory(at: location, includingPropertiesForKeys: [.isRegularFileKey, .ubiquitousItemDownloadingStatusKey])
                for file in files {
                    let name = file.lastPathComponent
                    if name.hasPrefix(".replica-") && name.hasSuffix(".json.icloud") {
                        let original = location.appendingPathComponent(String(name.dropFirst().dropLast(7)))
                        try FileManager.default.startDownloadingUbiquitousItem(at: original)
                        throw CocoaError(.ubiquitousFileUnavailable)
                    }
                    guard name.hasPrefix("replica-") && file.pathExtension == "json" else { continue }
                    let values = try file.resourceValues(forKeys: [.isRegularFileKey, .ubiquitousItemDownloadingStatusKey])
                    guard values.isRegularFile == true else { continue }
                    if values.ubiquitousItemDownloadingStatus == .notDownloaded {
                        try FileManager.default.startDownloadingUbiquitousItem(at: file)
                        throw CocoaError(.ubiquitousFileUnavailable)
                    }
                    // Never publish over unreadable / newer-format remote data.
                    merged.merge(try WorkspaceSyncDocument.decode(Data(contentsOf: file)))
                }
                let own = location.appendingPathComponent("replica-\(snapshot.device.uuidString).json")
                let data = try merged.encoded()
                if (try? Data(contentsOf: own)) != data { try data.write(to: own, options: .atomic) }
                return merged
            }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw CocoaError(.fileWriteUnknown) }
        return try result.get()
    }
}
#endif

