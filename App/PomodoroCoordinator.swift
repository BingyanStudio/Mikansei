import Foundation
import SwiftUI
import WidgetKit

@MainActor
final class PomodoroCoordinator: ObservableObject {
    @Published private(set) var archive = PomodoroArchive()
    @Published private(set) var readOnly = false
    @Published private(set) var saveFailed = false
    @Published var error: String?

    private let localStore: PomodoroLocalStore
    private let shouldPublishWidgetSnapshot: Bool

    init(fileURL: URL? = nil) {
        let testing = ProcessInfo.processInfo.arguments.contains("--ui-testing")
        shouldPublishWidgetSnapshot = !testing
        let base = testing
            ? FileManager.default.temporaryDirectory.appendingPathComponent("Mikansei-UITests/Pomodoro", isDirectory: true)
            : FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("QingdanJi", isDirectory: true)
        localStore = PomodoroLocalStore(fileURL: fileURL ?? base.appendingPathComponent("pomodoro.json"))
        do {
            archive = try localStore.load()
            if shouldPublishWidgetSnapshot { publishSnapshot(for: archive) }
            refresh(at: Date())
        } catch {
            readOnly = true
            self.error = error.localizedDescription
        }
    }

    var active: PomodoroRun? { archive.active }
    var history: [PomodoroRecord] { archive.history.sorted { $0.endedAt > $1.endedAt } }
    var completedCount: Int {
        archive.history.filter { $0.outcome == "completed" && $0.durationSeconds > 0 }.count
    }

    @discardableResult
    func start(subject: String, mode: PomodoroMode, targetSeconds: Double, linkedEntryID: String?, at now: Date = Date()) -> Bool {
        let title = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { error = "请先填写本次专注主题。"; return false }
        guard mode == .countUp || (targetSeconds.isFinite && targetSeconds > 0) else { error = "倒计时需要大于零的时长。"; return false }
        guard !readOnly else { return false }
        do {
            let start = PomodoroRun(subject: title, mode: mode,
                                    targetSeconds: mode == .countUp ? 0 : targetSeconds,
                                    runningSince: now.timeIntervalSince1970,
                                    createdAt: now.timeIntervalSince1970,
                                    linkedEntryID: linkedEntryID)
            try commit { archive in
                guard archive.active == nil else { throw PomodoroCoordinatorError.alreadyRunning }
                archive.active = start
            }
            return true
        } catch { report(error); return false }
    }

    @discardableResult
    func pause(sessionID: String, at now: Date = Date()) -> Bool {
        let wasDue = archive.active?.id == sessionID && (archive.active?.isDue(at: now) ?? false)
        refresh(at: now)
        if wasDue && archive.active?.id != sessionID { return archive.history.contains { $0.run.id == sessionID && $0.outcome == "completed" } }
        guard let current = archive.active, current.id == sessionID else { error = "这个专注计时已结束或已被替换。"; return false }
        guard !current.isDue(at: now) else { return false }
        guard current.isRunning else { return true }
        let elapsed = current.elapsedSeconds(at: now)
        do {
            try commit { archive in
                guard var active = archive.active, active.id == sessionID else { throw PomodoroCoordinatorError.staleSession }
                active.accumulatedSeconds = elapsed
                active.runningSince = nil
                archive.active = active
            }
            return true
        } catch { report(error); return false }
    }

    @discardableResult
    func resume(sessionID: String, at now: Date = Date()) -> Bool {
        let wasDue = archive.active?.id == sessionID && (archive.active?.isDue(at: now) ?? false)
        refresh(at: now)
        if wasDue && archive.active?.id != sessionID { return archive.history.contains { $0.run.id == sessionID && $0.outcome == "completed" } }
        guard let current = archive.active, current.id == sessionID else { error = "这个专注计时已结束或已被替换。"; return false }
        guard !current.isRunning else { return true }
        do {
            try commit { archive in
                guard var active = archive.active, active.id == sessionID else { throw PomodoroCoordinatorError.staleSession }
                active.runningSince = now.timeIntervalSince1970
                archive.active = active
            }
            return true
        } catch { report(error); return false }
    }

    @discardableResult
    func finish(sessionID: String, at now: Date = Date()) -> Bool {
        refresh(at: now)
        guard let current = archive.active, current.id == sessionID else {
            // A widget finish action can race the deadline reconciliation. Make finishing
            // an already-archived session idempotent, without touching any newer run.
            if archive.history.contains(where: { $0.run.id == sessionID }) { return true }
            error = "这个专注计时已结束或已被替换。"
            return false
        }
        let elapsed = current.elapsedSeconds(at: now)
        let outcome: String = current.mode == .countdown && !current.isDue(at: now) ? "stopped" : (elapsed > 0 ? "completed" : "stopped")
        let endedAt = current.isDue(at: now)
            ? (current.runningSince ?? now.timeIntervalSince1970) + max(0, current.targetSeconds - current.accumulatedSeconds)
            : now.timeIntervalSince1970
        do {
            try recordEnd(sessionID: sessionID, duration: elapsed, endedAt: endedAt, outcome: outcome)
            return true
        } catch { report(error); return false }
    }

    /// Reconciles countdowns against timestamps. A missed deadline is recorded once at its exact time.
    func refresh(at now: Date = Date()) {
        guard !readOnly, let active = archive.active, active.isDue(at: now) else { return }
        let deadline = (active.runningSince ?? now.timeIntervalSince1970) + max(0, active.targetSeconds - active.accumulatedSeconds)
        do {
            try recordEnd(sessionID: active.id, duration: active.targetSeconds,
                          endedAt: deadline, outcome: "completed")
        } catch { report(error) }
    }

    @discardableResult
    func apply(_ action: PomodoroURLAction, at now: Date = Date()) -> Bool {
        switch action {
        case .open: return true
        case .pause(let id): return pause(sessionID: id, at: now)
        case .resume(let id): return resume(sessionID: id, at: now)
        case .finish(let id): return finish(sessionID: id, at: now)
        }
    }

    func clearError() { error = nil }

    private func recordEnd(sessionID: String, duration: Double, endedAt: Double, outcome: String) throws {
        try commit { archive in
            guard var run = archive.active, run.id == sessionID else { throw PomodoroCoordinatorError.staleSession }
            run.accumulatedSeconds = max(0, duration)
            run.runningSince = nil
            archive.history.append(PomodoroRecord(run: run, endedAt: endedAt,
                                                  durationSeconds: max(0, duration), outcome: outcome))
            archive.active = nil
        }
    }

    private func commit(_ mutation: (inout PomodoroArchive) throws -> Void) throws {
        guard !readOnly else { throw PomodoroCoordinatorError.readOnly }
        let saved = try localStore.update(mutation)
        archive = saved
        saveFailed = false
        error = nil
        publishSnapshot(for: saved)
    }

    private func publishSnapshot(for archive: PomodoroArchive) {
        guard shouldPublishWidgetSnapshot else { return }
        do {
            try PomodoroSnapshotStore.save(PomodoroSnapshot.make(archive: archive))
            WidgetCenter.shared.reloadTimelines(ofKind: "Mikansei.Pomodoro")
        } catch {
            saveFailed = true
            self.error = "专注历史已保存在本机，但桌面小组件未更新：\(error.localizedDescription)"
        }
    }

    private func report(_ error: Error) {
        saveFailed = true
        if let issue = error as? PomodoroCoordinatorError {
            switch issue {
            case .alreadyRunning: self.error = "已有一段专注正在进行，请先暂停或结束。"
            case .staleSession: self.error = "这个专注计时已结束或已被替换。"
            case .readOnly: self.error = "专注历史无法读取，已暂停修改以保护原文件。"
            }
        } else { self.error = "专注计时未能保存：\(error.localizedDescription)" }
    }
}

private enum PomodoroCoordinatorError: LocalizedError {
    case alreadyRunning, staleSession, readOnly
    var errorDescription: String? {
        switch self {
        case .alreadyRunning: return "已有活动计时。"
        case .staleSession: return "活动计时已变化。"
        case .readOnly: return "历史文件不可写。"
        }
    }
}
