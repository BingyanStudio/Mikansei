import Foundation

public enum FocusSession {
    /// A single active timer. Explicit start/pause commands are safe to repeat from a stale widget.
    public static func updating(_ entries: [Entry], id: UUID, isRunning: Bool, at now: Date = Date()) -> [Entry]? {
        guard let index = entries.firstIndex(where: { $0.id == id }), entries[index].isTask,
              !entries[index].isCompleted else { return nil }
        var next = entries
        if isRunning {
            for other in next.indices where other != index { next[other].pauseFocus(at: now) }
            if next[index].startedAt == nil { next[index].startedAt = now; next[index].updatedAt = now }
        } else { next[index].pauseFocus(at: now) }
        return next
    }
}
