import AppKit
import UserNotifications

struct MacReminderRoute: Identifiable {
    let id = UUID()
    let entryID: UUID?
    let courseID: UUID?
}

final class MacNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    private let open: @MainActor (MacReminderRoute) -> Void
    init(open: @escaping @MainActor (MacReminderRoute) -> Void) { self.open = open }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completion: @escaping (UNNotificationPresentationOptions) -> Void) {
        completion([.banner, .sound])
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completion: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        let route = MacReminderRoute(entryID: (info["entryID"] as? String).flatMap(UUID.init(uuidString:)),
                                     courseID: (info["courseID"] as? String).flatMap(UUID.init(uuidString:)))
        Task { @MainActor in
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first(where: { $0.isVisible })?.makeKeyAndOrderFront(nil)
            open(route)
            completion()
        }
    }
}
