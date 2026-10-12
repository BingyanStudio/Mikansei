import Foundation

public enum FocusAction: String, Equatable { case start, pause }

public enum AppRoute: Equatable {
    case today, tasks
    case new(EntryKind)
    case entry(UUID)
    case focus(UUID, FocusAction)

    public init?(url: URL) {
        guard url.scheme?.lowercased() == "mikansei", let host = url.host?.lowercased(),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        switch host {
        case "today": self = .today
        case "tasks": self = .tasks
        case "new":
            let raw = components.queryItems?.first(where: { $0.name == "kind" })?.value ?? "task"
            guard let kind = EntryKind(rawValue: raw) else { return nil }
            self = .new(kind)
        case "entry":
            guard let id = UUID(uuidString: url.lastPathComponent) else { return nil }
            self = .entry(id)
        case "focus":
            guard let id = UUID(uuidString: url.lastPathComponent),
                  let raw = components.queryItems?.first(where: { $0.name == "action" })?.value,
                  let action = FocusAction(rawValue: raw) else { return nil }
            self = .focus(id, action)
        default: return nil
        }
    }

    public var url: URL {
        switch self {
        case .today: return URL(string: "mikansei://today")!
        case .tasks: return URL(string: "mikansei://tasks")!
        case .new(let kind): return URL(string: "mikansei://new?kind=\(kind.rawValue)")!
        case .entry(let id): return URL(string: "mikansei://entry/\(id.uuidString)")!
        case .focus(let id, let action): return URL(string: "mikansei://focus/\(id.uuidString)?action=\(action.rawValue)")!
        }
    }
}
