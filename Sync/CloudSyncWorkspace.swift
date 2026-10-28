import Foundation

/// Store surface used by CloudAccountManager. Implementations report a commit
/// only after EntryArchiveWriter has completed the durable write.
@MainActor
public protocol CloudSyncWorkspace: AnyObject {
    var cloudSyncArchive: EntryArchive { get }
    var cloudSyncReady: Bool { get }
    var cloudSyncSaveFailed: Bool { get }

    @discardableResult
    func applyCloudArchive(_ merge: CloudArchiveMerge) -> Bool
    func waitForCloudSyncDurability() async -> Bool
    func setCloudSyncCommitObserver(_ observer: (@MainActor () -> Void)?)
}
