import Foundation

public enum ReminderDelivery: String, Codable, CaseIterable, Identifiable {
    case popup, alarm
    public var id: Self { self }
    public var title: String { self == .popup ? "弹窗提醒" : "闹钟提醒" }
}

public enum ReminderAnchor: String, Codable, CaseIterable, Identifiable {
    case deadline, execution
    public var id: Self { self }
    public var title: String { self == .deadline ? "按截止时间" : "按执行开始" }
}

public enum ReminderSound: String, Codable, CaseIterable, Identifiable {
    case system, morning, chime, pulse
    public var id: Self { self }
    public var title: String {
        switch self { case .system: return "系统默认"; case .morning: return "晨光"; case .chime: return "清脆"; case .pulse: return "节拍" }
    }
    public var fileName: String? { self == .system ? nil : "mikansei-\(rawValue).wav" }
}

public struct AlarmRecord: Codable, Equatable {
    public let id: UUID
    public let event: PlannedNotification
    public init(id: UUID = UUID(), event: PlannedNotification) { self.id = id; self.event = event }
}

public enum AlarmReconciliation {
    /// Keep an already ringing or snoozed occurrence even after its original fire date.
    /// Its owner must still have exactly the same reminder configuration.
    public static func retained(_ records: [AlarmRecord], liveIDs: Set<UUID>, desired: [PlannedNotification],
                                entries: [Entry], courses: [Course], now: Date) -> [AlarmRecord] {
        records.filter { liveIDs.contains($0.id) &&
            (desired.contains($0.event) || ($0.event.date <= now && $0.event.isStillEnabled(entries: entries, courses: courses))) }
    }
}
