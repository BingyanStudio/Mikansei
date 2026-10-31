import Foundation

public enum PomodoroMode: String, Codable, CaseIterable, Sendable {
    case countdown
    case countUp
}

public enum PomodoroURLAction: Equatable, Sendable {
    case open
    case pause(String)
    case resume(String)
    case finish(String)

    public init?(url: URL) {
        guard url.scheme?.lowercased() == "mikansei", url.host?.lowercased() == "pomodoro",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let rawAction = components.queryItems?.first(where: { $0.name == "action" })?.value else { return nil }
        switch rawAction.lowercased() {
        case "open": self = .open
        case "pause", "resume", "finish":
            guard let session = components.queryItems?.first(where: { $0.name == "session" })?.value,
                  let canonicalSession = UUID(uuidString: session)?.uuidString else { return nil }
            switch rawAction.lowercased() {
            case "pause": self = .pause(canonicalSession)
            case "resume": self = .resume(canonicalSession)
            default: self = .finish(canonicalSession)
            }
        default: return nil
        }
    }
}

/// An independent focus timer. All timestamps in this model are UNIX seconds.
public struct PomodoroRun: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var subject: String
    public var mode: PomodoroMode
    public var targetSeconds: Double
    public var accumulatedSeconds: Double
    public var runningSince: Double?
    public var createdAt: Double
    public var linkedEntryID: String?

    public var isRunning: Bool { runningSince != nil }

    public init(id: String = UUID().uuidString,
                subject: String,
                mode: PomodoroMode,
                targetSeconds: Double,
                accumulatedSeconds: Double = 0,
                runningSince: Double? = nil,
                createdAt: Double = Date().timeIntervalSince1970,
                linkedEntryID: String? = nil) {
        self.id = id
        self.subject = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        self.mode = mode
        self.targetSeconds = targetSeconds
        self.accumulatedSeconds = accumulatedSeconds
        self.runningSince = runningSince
        self.createdAt = createdAt
        self.linkedEntryID = linkedEntryID
    }

    /// Focused time at `now`, excluding pauses and clamping countdown sessions at their target.
    public func elapsedSeconds(at now: Date = Date()) -> Double {
        let since = runningSince.map { max(0, now.timeIntervalSince1970 - $0) } ?? 0
        let elapsed = max(0, accumulatedSeconds + since)
        return mode == .countdown ? min(max(0, targetSeconds), elapsed) : elapsed
    }

    public func remainingSeconds(at now: Date = Date()) -> Double? {
        guard mode == .countdown else { return nil }
        return max(0, targetSeconds - elapsedSeconds(at: now))
    }

    public func isDue(at now: Date = Date()) -> Bool {
        mode == .countdown && isRunning && elapsedSeconds(at: now) >= max(0, targetSeconds)
    }
}

public struct PomodoroRecord: Codable, Equatable, Identifiable, Sendable {
    public var run: PomodoroRun
    public var endedAt: Double
    public var durationSeconds: Double
    /// `completed` or `stopped`.
    public var outcome: String

    public var id: String { run.id }

    public init(run: PomodoroRun, endedAt: Double, durationSeconds: Double, outcome: String) {
        self.run = run
        self.endedAt = endedAt
        self.durationSeconds = max(0, durationSeconds)
        self.outcome = outcome
    }
}

public struct PomodoroArchive: Codable, Equatable, Sendable {
    public var version: Int
    public var active: PomodoroRun?
    public var history: [PomodoroRecord]

    public init(version: Int = 1, active: PomodoroRun? = nil, history: [PomodoroRecord] = []) {
        self.version = version
        self.active = active
        self.history = history
    }
}

/// Compact, private-details-free data for the iOS widget extension.
public struct PomodoroSnapshot: Codable, Equatable, Sendable {
    public var version: Int
    public var savedAt: Double
    public var active: PomodoroRun?
    public var todaySeconds: Double
    public var completedCount: Int

    public init(version: Int = 1, savedAt: Double = Date().timeIntervalSince1970,
                active: PomodoroRun?, todaySeconds: Double, completedCount: Int) {
        self.version = version
        self.savedAt = savedAt
        self.active = active
        self.todaySeconds = max(0, todaySeconds)
        self.completedCount = max(0, completedCount)
    }

    /// Daily values intentionally count sessions archived today because the shared
    /// schema does not keep each resume interval. The live clock is shown separately.
    public static func make(archive: PomodoroArchive, now: Date = Date(), calendar: Calendar = .current) -> Self {
        let dayStart = calendar.startOfDay(for: now).timeIntervalSince1970
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))?.timeIntervalSince1970
            ?? dayStart + 86_400
        let endedToday = archive.history.filter { $0.endedAt >= dayStart && $0.endedAt < tomorrow }
        let seconds = endedToday.reduce(0) { $0 + $1.durationSeconds }
        let completed = archive.history.filter { $0.outcome == "completed" && $0.durationSeconds > 0 }.count
        return Self(savedAt: now.timeIntervalSince1970, active: archive.active,
                    todaySeconds: seconds, completedCount: completed)
    }
}

public enum PomodoroStoreError: LocalizedError {
    case unsupportedVersion(Int)
    case invalidArchive(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version): return "此专注历史版本（\(version)）暂不支持，原文件已保留。"
        case .invalidArchive(let detail): return "专注历史格式无效，原文件已保留。\(detail)"
        }
    }
}

/// Serialized, atomic persistence for local-only focus history.
/// The file is deliberately separate from the task archive.
public final class PomodoroLocalStore: @unchecked Sendable {
    public let fileURL: URL
    private static let lock = NSLock()

    public init(fileURL: URL) { self.fileURL = fileURL }

    public func load() throws -> PomodoroArchive {
        Self.lock.lock(); defer { Self.lock.unlock() }
        return try loadUnlocked()
    }

    /// Changes are read-modify-write serialized through one lock and an atomic file replacement.
    /// If the existing file is corrupt, this throws without replacing it.
    @discardableResult
    public func update(_ mutation: (inout PomodoroArchive) throws -> Void) throws -> PomodoroArchive {
        Self.lock.lock(); defer { Self.lock.unlock() }
        var archive = try loadUnlocked()
        try mutation(&archive)
        try validate(archive)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(archive)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        #if os(iOS)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: fileURL, options: .atomic)
        #endif
        return archive
    }

    private func loadUnlocked() throws -> PomodoroArchive {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return PomodoroArchive() }
        let archive: PomodoroArchive
        do { archive = try JSONDecoder().decode(PomodoroArchive.self, from: Data(contentsOf: fileURL)) }
        catch { throw PomodoroStoreError.invalidArchive(error.localizedDescription) }
        try validate(archive)
        return archive
    }

    private func validate(_ archive: PomodoroArchive) throws {
        guard archive.version == 1 else { throw PomodoroStoreError.unsupportedVersion(archive.version) }
        var sessionIDs = Set<String>()
        if let active = archive.active {
            try validate(active)
            sessionIDs.insert(active.id)
        }
        for record in archive.history {
            try validate(record.run)
            guard sessionIDs.insert(record.run.id).inserted else {
                throw PomodoroStoreError.invalidArchive("同一专注计时出现了重复记录。")
            }
            guard record.endedAt.isFinite, record.durationSeconds.isFinite, record.durationSeconds >= 0,
                  record.outcome == "completed" || record.outcome == "stopped" else {
                throw PomodoroStoreError.invalidArchive("记录包含无法使用的结束时间或结果。")
            }
        }
    }

    private func validate(_ run: PomodoroRun) throws {
        let subject = run.subject.trimmingCharacters(in: .whitespacesAndNewlines)
        guard UUID(uuidString: run.id) != nil, !subject.isEmpty,
              run.targetSeconds.isFinite, run.targetSeconds >= 0,
              run.accumulatedSeconds.isFinite, run.accumulatedSeconds >= 0,
              run.createdAt.isFinite,
              run.runningSince.map({ $0.isFinite }) ?? true else {
            throw PomodoroStoreError.invalidArchive("计时记录缺少有效标题或时间信息。")
        }
        if run.mode == .countdown && run.targetSeconds <= 0 {
            throw PomodoroStoreError.invalidArchive("倒计时目标必须大于零。")
        }
        if run.mode == .countUp && run.targetSeconds != 0 {
            throw PomodoroStoreError.invalidArchive("正计时的目标时间必须为零。")
        }
    }
}
