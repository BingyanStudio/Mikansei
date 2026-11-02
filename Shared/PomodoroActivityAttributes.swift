import ActivityKit
import Foundation

struct PomodoroActivityAttributes: ActivityAttributes {
    enum Mode: String, Codable, Hashable {
        case countdown
        case countUp
    }

    let sessionID: String
    let subject: String
    let mode: Mode
    let targetSeconds: Double
    /// The time ActivityKit started this particular Live Activity, used for its eight-hour limit.
    let activityStartedAt: Date

    struct ContentState: Codable, Hashable {
        let isRunning: Bool
        let runningSince: Date?
        let accumulatedSeconds: Double
        let updatedAt: Date

        func elapsedSeconds(at now: Date) -> Double {
            max(0, accumulatedSeconds + (runningSince.map { max(0, now.timeIntervalSince($0)) } ?? 0))
        }

        func remainingSeconds(target: Double, at now: Date) -> Double {
            max(0, target - elapsedSeconds(at: now))
        }

        func countdownDeadline(target: Double) -> Date? {
            guard isRunning, let runningSince else { return nil }
            return runningSince.addingTimeInterval(max(0, target - accumulatedSeconds))
        }

        func countUpAnchor(at now: Date) -> Date {
            now.addingTimeInterval(-elapsedSeconds(at: now))
        }
    }

    init(run: PomodoroRun, activityStartedAt: Date) {
        sessionID = run.id
        subject = String(run.subject.prefix(160))
        mode = run.mode == .countdown ? .countdown : .countUp
        targetSeconds = run.targetSeconds
        self.activityStartedAt = activityStartedAt
    }

    func contentState(for run: PomodoroRun, at now: Date = Date()) -> ContentState {
        ContentState(
            isRunning: run.isRunning,
            runningSince: run.runningSince.map(Date.init(timeIntervalSince1970:)),
            accumulatedSeconds: run.accumulatedSeconds,
            updatedAt: now
        )
    }

    func staleDate(for state: ContentState) -> Date {
        let systemLimit = activityStartedAt.addingTimeInterval(8 * 60 * 60)
        guard mode == .countdown, let deadline = state.countdownDeadline(target: targetSeconds) else {
            return systemLimit
        }
        return min(deadline, systemLimit)
    }

    func countdownExpiresBeforeSystemLimit(for state: ContentState) -> Bool {
        guard mode == .countdown, let deadline = state.countdownDeadline(target: targetSeconds) else { return false }
        return deadline <= activityStartedAt.addingTimeInterval(8 * 60 * 60)
    }
}
