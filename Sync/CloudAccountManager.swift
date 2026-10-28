import Combine
import Foundation

@MainActor
public final class CloudAccountManager: ObservableObject {
    @Published public private(set) var configured: Bool
    @Published public private(set) var initializing = false
    @Published public private(set) var busy = false
    @Published public private(set) var sendingCode = false
    @Published public private(set) var verifyingCode = false
    @Published public private(set) var email: String?
    @Published public private(set) var codeTarget: String?
    @Published public private(set) var loginError: String?
    @Published public private(set) var syncError: String?
    @Published public private(set) var lastSyncedAt: Date?
    @Published public private(set) var deletingAccount = false
    @Published public private(set) var sessionTransitionInProgress = false

    /// Set when a restored or newly verified account has no matching local
    /// account state. The UI should ask before the first cloud merge/upload.
    @Published public private(set) var needsInitialMergeConfirmation = false

    private weak var workspace: (any CloudSyncWorkspace)?
    private let client: SupabaseClient
    private var didStart = false
    private var foreground = true
    private var generation: UInt64 = 0
    private var activeAccountKey: String?
    private var syncTask: Task<Void, Never>?
    private var syncRunID: UInt64 = 0
    private var cancellingSync = false
    private var timerTask: Task<Void, Never>?
    private var pushTask: Task<Void, Never>?
    private var pullTask: Task<Void, Never>?
    private var realtimeTask: Task<Void, Never>?
    private var rerunRequested = false

    init(workspace: any CloudSyncWorkspace, client: SupabaseClient? = nil) {
        self.workspace = workspace
        let resolvedClient = client ?? SupabaseClient()
        self.client = resolvedClient
        configured = resolvedClient.configuration.isConfigured
        workspace.setCloudSyncCommitObserver { [weak self] in
            self?.schedulePush()
        }
    }

    deinit {
        pushTask?.cancel()
        pullTask?.cancel()
        timerTask?.cancel()
        realtimeTask?.cancel()
        syncTask?.cancel()
    }

    public func start() async {
        guard !didStart else { return }
        didStart = true
        initializing = true
        sessionTransitionInProgress = true
        defer {
            initializing = false
            sessionTransitionInProgress = false
        }
        guard configured else { return }

        let token = generation
        do {
            try await client.restoreSession()
            guard generation == token else { return }
            sessionTransitionInProgress = false
            guard activateCurrentSession() else { return }
            if !needsInitialMergeConfirmation {
                startForegroundServicesIfNeeded()
                await syncNow()
            }
        } catch {
            guard generation == token else { return }
            sessionTransitionInProgress = false
            if let supabaseError = error as? SupabaseClientError,
               case .sessionExpired = supabaseError {
                loginError = "登录已过期，请重新登录。"
                return
            }
            guard activateCurrentSession() else {
                loginError = "账户状态恢复失败：\(error.localizedDescription)"
                return
            }
            loginError = "云账号恢复时暂时无法连接，已保留登录状态并会在前台重试：\(error.localizedDescription)"
            if !needsInitialMergeConfirmation {
                startForegroundServicesIfNeeded()
            }
        }
    }

    public func setForeground(_ active: Bool) {
        guard foreground != active else { return }
        foreground = active
        if active {
            guard email != nil else { return }
            startForegroundServicesIfNeeded()
            if !needsInitialMergeConfirmation {
                Task { [weak self] in await self?.syncNow() }
            }
        } else {
            timerTask?.cancel()
            timerTask = nil
            pushTask?.cancel()
            pushTask = nil
            pullTask?.cancel()
            pullTask = nil
            realtimeTask?.cancel()
            realtimeTask = nil
            client.stopRealtime()
            syncTask?.cancel()
        }
    }

    public func sendCode(_ value: String) async {
        guard !sessionTransitionInProgress else { return }
        let address = value.trimmingCharacters(in: .whitespacesAndNewlines)
        loginError = nil
        guard configured else {
            loginError = "账户同步尚未配置。"
            return
        }
        guard !address.isEmpty else {
            loginError = "请输入邮箱地址。"
            return
        }
        sendingCode = true
        defer { sendingCode = false }
        do {
            try await client.sendCode(email: address)
            codeTarget = address
        } catch {
            loginError = "验证码发送失败：\(error.localizedDescription)"
        }
    }

    public func verifyCode(_ value: String) async -> Bool {
        guard !sessionTransitionInProgress, let address = codeTarget else { return false }
        loginError = nil
        verifyingCode = true
        sessionTransitionInProgress = true
        defer {
            verifyingCode = false
            sessionTransitionInProgress = false
        }

        // Stop work under the prior auth session before verifyCode can replace it.
        generation &+= 1
        tearDownScheduledWork()
        await cancelSyncAndWait()
        let token = generation
        do {
            try await client.verifyCode(email: address, code: value.trimmingCharacters(in: .whitespacesAndNewlines))
            guard generation == token, activateCurrentSession() else { return false }
            codeTarget = nil
            // The sign-in UI only calls verifyCode after the user confirms the
            // target email and initial merge checkbox.
            needsInitialMergeConfirmation = false
            sessionTransitionInProgress = false
            if !needsInitialMergeConfirmation {
                startForegroundServicesIfNeeded()
                await syncNow()
            }
            return true
        } catch {
            guard generation == token else { return false }
            loginError = "登录未完成：\(error.localizedDescription)"
            let hasSession = activateCurrentSession()
            sessionTransitionInProgress = false
            if hasSession {
                if !needsInitialMergeConfirmation { startForegroundServicesIfNeeded() }
            }
            return false
        }
    }

    /// Call after the UI confirms the initial merge for this account.
    public func confirmInitialMerge() async {
        guard needsInitialMergeConfirmation, email != nil,
              !sessionTransitionInProgress else { return }
        needsInitialMergeConfirmation = false
        startForegroundServicesIfNeeded()
        await syncNow()
    }

    public func syncNow() async {
        guard configured, foreground, email != nil, !needsInitialMergeConfirmation,
              workspace?.cloudSyncReady == true, !cancellingSync,
              !sessionTransitionInProgress else { return }
        if let current = syncTask {
            rerunRequested = true
            await current.value
            return
        }
        let token = generation
        syncRunID &+= 1
        let runID = syncRunID
        let task = Task<Void, Never> { [weak self] in
            guard let self else { return }
            await self.runSyncLoop(generation: token, runID: runID)
        }
        syncTask = task
        await task.value
    }

    public func signOut() async {
        guard !sessionTransitionInProgress else { return }
        sessionTransitionInProgress = true
        generation &+= 1
        let token = generation
        tearDownScheduledWork()
        await cancelSyncAndWait()
        guard generation == token else {
            sessionTransitionInProgress = false
            return
        }
        do {
            try await client.signOut()
            guard generation == token else {
                sessionTransitionInProgress = false
                return
            }
            clearSessionState()
        } catch {
            guard generation == token else {
                sessionTransitionInProgress = false
                return
            }
            if client.session == nil {
                clearSessionState()
                loginError = "已在本机退出登录，但服务器未能确认退出：\(error.localizedDescription)"
            } else {
                loginError = "退出登录失败：\(error.localizedDescription)"
            }
        }
        sessionTransitionInProgress = false
        if client.session != nil, foreground, !needsInitialMergeConfirmation {
            startForegroundServicesIfNeeded()
        }
    }

    public func deleteAccount() async -> Bool {
        guard configured, !deletingAccount, !sessionTransitionInProgress else { return false }
        deletingAccount = true
        sessionTransitionInProgress = true
        defer {
            deletingAccount = false
            sessionTransitionInProgress = false
        }
        generation &+= 1
        let token = generation
        tearDownScheduledWork()
        await cancelSyncAndWait()
        guard generation == token else { return false }
        do {
            try await client.deleteAccount()
            guard generation == token else { return false }
            clearSessionState()
            return true
        } catch {
            guard generation == token else { return false }
            loginError = "删除账户失败：\(error.localizedDescription)"
            sessionTransitionInProgress = false
            if client.session != nil, foreground, !needsInitialMergeConfirmation {
                startForegroundServicesIfNeeded()
            }
            return false
        }
    }

    private func activateCurrentSession() -> Bool {
        guard let session = client.session else { return false }
        let project = client.configuration.url.map {
            $0.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        } ?? "unconfigured"
        let accountKey = "\(project)|\(session.userID.lowercased())"
        if activeAccountKey != accountKey {
            activeAccountKey = accountKey
            lastSyncedAt = nil
            syncError = nil
        }
        email = session.email
        let savedKey = workspace?.cloudSyncArchive.cloudArchiveState?.accountKey
        needsInitialMergeConfirmation = savedKey != accountKey
        return true
    }

    private func startForegroundServicesIfNeeded() {
        guard foreground, email != nil, configured,
              !needsInitialMergeConfirmation, !sessionTransitionInProgress else { return }
        if timerTask == nil {
            timerTask = Task { [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(30)) } catch { return }
                    guard let self, self.foreground, self.email != nil else { return }
                    self.startForegroundServicesIfNeeded()
                    await self.syncNow()
                }
            }
        }
        guard realtimeTask == nil else { return }
        let token = generation
        realtimeTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.client.startRealtime { [weak self] in
                    guard let self, self.generation == token, self.foreground else { return }
                    self.schedulePull()
                }
            } catch {
                guard self.generation == token, self.foreground else { return }
                // Realtime is an optimization. The foreground timer continues
                // polling and will retry the websocket at its next interval.
                self.realtimeTask = nil
                return
            }
            guard !Task.isCancelled, self.generation == token, self.foreground else {
                self.client.stopRealtime()
                return
            }
        }
    }

    private func schedulePush() {
        guard foreground, email != nil, !needsInitialMergeConfirmation,
              !sessionTransitionInProgress else { return }
        pushTask?.cancel()
        pushTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            guard let self else { return }
            await self.syncNow()
        }
    }

    private func schedulePull() {
        pullTask?.cancel()
        pullTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
            guard let self else { return }
            await self.syncNow()
        }
    }

    private func runSyncLoop(generation token: UInt64, runID: UInt64) async {
        busy = true
        syncError = nil
        defer {
            busy = false
            if syncRunID == runID {
                syncTask = nil
                if generation == token && rerunRequested && foreground && email != nil && !needsInitialMergeConfirmation {
                    rerunRequested = false
                    Task { [weak self] in await self?.syncNow() }
                } else {
                    rerunRequested = false
                }
            }
        }

        repeat {
            rerunRequested = false
            do {
                try await performSyncCycle(generation: token)
            } catch {
                guard generation == token, !Task.isCancelled else { return }
                if let supabaseError = error as? SupabaseClientError,
                   case .sessionExpired = supabaseError {
                    client.stopRealtime()
                    email = nil
                    activeAccountKey = nil
                    needsInitialMergeConfirmation = false
                    syncError = "登录已过期，请重新登录。"
                    loginError = syncError
                    return
                }
                syncError = "同步失败，本机修改已保留：\(error.localizedDescription)"
                return
            }
        } while rerunRequested && generation == token && !Task.isCancelled
    }

    private func performSyncCycle(generation token: UInt64) async throws {
        guard let workspace, workspace.cloudSyncReady,
              let accountKey = activeAccountKey else { return }
        guard await workspace.waitForCloudSyncDurability() else {
            throw CloudArchiveError.invalidArchive
        }
        guard generation == token, !Task.isCancelled else { return }

        for _ in 0..<3 {
            let remote = try await client.fetchArchive()
            guard generation == token, !Task.isCancelled, email != nil else { return }

            let local = workspace.cloudSyncArchive
            let merge = try CloudArchiveCodec.merge(
                remoteContent: remote?.content,
                local: local,
                accountKey: accountKey
            )
            _ = workspace.applyCloudArchive(merge)
            guard await workspace.waitForCloudSyncDurability() else {
                throw CloudArchiveError.invalidArchive
            }
            guard generation == token, !Task.isCancelled, email != nil else { return }

            let content = try CloudArchiveCodec.encode(
                archive: workspace.cloudSyncArchive,
                accountKey: accountKey
            )
            if let remote, remote.content == content {
                lastSyncedAt = Date()
                loginError = nil
                return
            }
            do {
                try await client.uploadArchive(content, expectedRevision: remote?.revision)
                guard generation == token, !Task.isCancelled, email != nil else { return }
                lastSyncedAt = Date()
                syncError = nil
                loginError = nil
                return
            } catch {
                guard let supabaseError = error as? SupabaseClientError,
                      case .conflict = supabaseError else { throw error }
            }
        }
        throw SupabaseClientError.conflict
    }

    private func tearDownScheduledWork() {
        timerTask?.cancel(); timerTask = nil
        pushTask?.cancel(); pushTask = nil
        pullTask?.cancel(); pullTask = nil
        realtimeTask?.cancel(); realtimeTask = nil
        client.stopRealtime()
    }

    private func cancelSyncAndWait() async {
        cancellingSync = true
        defer { cancellingSync = false }
        rerunRequested = false
        let current = syncTask
        let runID = syncRunID
        current?.cancel()
        if let current { await current.value }
        if syncRunID == runID { syncTask = nil }
        busy = false
    }

    private func clearSessionState() {
        email = nil
        codeTarget = nil
        activeAccountKey = nil
        loginError = nil
        syncError = nil
        lastSyncedAt = nil
        needsInitialMergeConfirmation = false
        rerunRequested = false
    }
}
