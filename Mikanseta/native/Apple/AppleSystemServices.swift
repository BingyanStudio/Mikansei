import Foundation
import EventKit
import UserNotifications
import SwiftUI
import Combine
#if os(iOS)
import Flutter
import UIKit
import EventKitUI
import WidgetKit
#else
import FlutterMacOS
import AppKit
#endif

enum Theme { static let accent = Color(red:0.50,green:0.34,blue:0.20) }

@MainActor
final class AppleSystemServices: NSObject, UNUserNotificationCenterDelegate {
    private let store = EKEventStore()
    private let channel: FlutterMethodChannel
    private var entries: [Entry] = [], courses: [Course] = []
    private var routes: [[String:String]] = []
    private var cancellables = Set<AnyCancellable>()
    private var widgetError: String?
    private var calendarEdits: [[String:Any]] = []
    private var calendarResult: FlutterResult?
    private var scheduling: Task<Void,Never>?
    private let installation: String
    #if os(iOS)
    private let notifications = NotificationManager()
    private var activityManager: Any?
    @available(iOS 17.0, *) private var activity: DeadlineActivityManager {
        if let existing = activityManager as? DeadlineActivityManager { return existing }
        let value = DeadlineActivityManager(); activityManager = value; return value
    }
    #endif
    init(channel: FlutterMethodChannel) {
        self.channel = channel
        let base = FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("Mikanseta",isDirectory:true)
        let file = base.appendingPathComponent("calendar-installation-id")
        if let existing = try? String(contentsOf:file,encoding:.utf8), !existing.isEmpty { installation = existing }
        else {
            installation = UUID().uuidString
            try? FileManager.default.createDirectory(at:base,withIntermediateDirectories:true)
            try? Data(installation.utf8).write(to:file,options:.atomic)
        }
        var local = file
        var excluded = URLResourceValues(); excluded.isExcludedFromBackup = true
        try? local.setResourceValues(excluded)
        super.init()
        #if os(iOS)
        notifications.$openedEntryID.compactMap{$0}.sink { [weak self] in self?.route(["entryID":$0.uuidString]) }.store(in:&cancellables)
        notifications.$completedEntryID.compactMap{$0}.sink { [weak self] in self?.route(["entryID":$0.uuidString,"action":"complete"]) }.store(in:&cancellables)
        notifications.$openedCourseID.compactMap{$0}.sink { [weak self] in self?.route(["courseID":$0.uuidString]) }.store(in:&cancellables)
        notifications.$foregroundReminders.sink { [weak self] reminders in
            guard let first = reminders.first else {return}
            self?.channel.invokeMethod("foregroundReminder",arguments:["id":first.id,"title":first.content.title,"body":first.content.body,"canComplete":first.entryID != nil])
        }.store(in:&cancellables)
        #else
        UNUserNotificationCenter.current().delegate = self
        #endif
    }
    func acceptURL(_ url:URL) { guard url.scheme?.lowercased()=="mikanseta" else{return};route(["url":url.absoluteString]) }
    private func route(_ route:[String:String]) { routes.append(route); channel.invokeMethod("routesAvailable",arguments:nil) }
    func update(_ text:String) {
        do {
            let archive = try EntryArchive.decode(Data(text.utf8))
            entries = archive.entries; courses = archive.courses
            #if os(iOS)
            notifications.update(entries:entries,courses:courses)
            do { try WidgetSnapshotStore.save(WidgetSnapshot(entries:entries)); widgetError=nil; WidgetCenter.shared.reloadAllTimelines() } catch { widgetError="小组件：\(error.localizedDescription)" }
            if #available(iOS 17.0, *) { activity.refresh(entries:entries) }
            #else
            scheduleMac()
            #endif
        } catch { channel.invokeMethod("serviceError",arguments:"系统服务更新未完成：\(error.localizedDescription)") }
    }
    private func calendarAllowed()->Bool {
        let status = EKEventStore.authorizationStatus(for:.event)
        if #available(iOS 17,macOS 14,*) {return status == .fullAccess}
        return status == .authorized
    }
    private func authorizeCalendar() async throws -> Bool {
        if calendarAllowed() { return true }
        if #available(iOS 17,macOS 14,*) { return try await store.requestFullAccessToEvents() }
        return try await store.requestAccess(to:.event)
    }
    func handle(_ call:FlutterMethodCall,result:@escaping FlutterResult)->Bool {
        let args = call.arguments as? [String:Any] ?? [:]
        func fail(_ error:Error) { result(FlutterError(code:"system",message:error.localizedDescription,details:nil)) }
        switch call.method {
        case "calendarDeviceID": result(installation)
        case "calendarAccess": result(calendarAllowed())
        case "requestCalendarAccess": Task { do {result(try await authorizeCalendar())} catch {fail(error)} }
        case "calendarSources":
            guard calendarAllowed() else {result(FlutterError(code:"permission",message:"请允许日历读取权限",details:nil));return true}
            store.reset()
            result(store.calendars(for:.event).map{["id":$0.calendarIdentifier,"title":$0.title,"account":$0.source.title]})
        case "calendarEvents":
            guard calendarAllowed(),let selected = args["selected"] as? [String],let first = args["start"] as? NSNumber,let last = args["end"] as? NSNumber else {result(FlutterError(code:"permission",message:"请核对日历权限与范围",details:nil));return true}
            let calendars = store.calendars(for:.event).filter{selected.contains($0.calendarIdentifier)}
            if calendars.isEmpty {result([]);return true}
            let predicate = store.predicateForEvents(withStart:Date(timeIntervalSince1970:first.doubleValue/1000),end:Date(timeIntervalSince1970:last.doubleValue/1000),calendars:calendars)
            let events = store.events(matching:predicate).filter{$0.status != .canceled}
            guard events.count <= 5000 else {result(FlutterError(code:"limit",message:"事件过多，请减少日历来源",details:nil));return true}
            result(events.map { event -> [String:Any] in
                let id = event.calendarItemExternalIdentifier ?? event.calendarItemIdentifier
                let occurrence = event.hasRecurrenceRules || event.isDetached ? String(Int((event.occurrenceDate ?? event.startDate).timeIntervalSince1970)) : "single"
                func epoch(_ date:Date)->Double {
                    if !event.isAllDay {return date.timeIntervalSince1970*1000}
                    var components = Calendar.current.dateComponents([.year,.month,.day],from:date)
                    components.timeZone = TimeZone(secondsFromGMT:0)
                    return Calendar(identifier:.gregorian).date(from:components)!.timeIntervalSince1970*1000
                }
                let recurring = event.hasRecurrenceRules || event.isDetached
                return ["key":"\(event.calendar.calendarIdentifier)/\(id)/\(occurrence)","eventID":event.calendarItemIdentifier,"calendarID":event.calendar.calendarIdentifier,"calendarTitle":event.calendar.title,"title":event.title ?? "未命名日程","body":[event.notes ?? "",event.url?.absoluteString ?? ""].filter{!$0.isEmpty}.joined(separator:"\n"),"location":event.location ?? "","start":Int64(epoch(event.startDate)),"end":Int64(epoch(event.endDate)),"allDay":event.isAllDay,"seriesID":id,"recurring":recurring,"originalOccurrence":occurrence]
            })
        case "takeCalendarEdits":let edits=calendarEdits;calendarEdits=[];result(edits)
        case "openExternalURL":
            guard let raw=call.arguments as? String, let url=URL(string:raw), ["https","http"].contains(url.scheme?.lowercased() ?? "") else {result(false);return true}
            #if os(iOS)
            UIApplication.shared.open(url,options:[:]) { result($0) }
            #else
            result(NSWorkspace.shared.open(url))
            #endif
        case "openCalendarEvent","addCalendarEvent","editCalendarEvent":
            Task {
                do {
                    guard try await authorizeCalendar() else {throw NSError(domain:"calendar",code:1,userInfo:[NSLocalizedDescriptionKey:"请在系统设置允许日历访问"])}
                    let event:EKEvent
                    if call.method == "openCalendarEvent" || call.method == "editCalendarEvent" {
                        guard let id=args["eventID"] as? String,let first=args["start"] as? NSNumber,let last=args["end"] as? NSNumber else {throw CocoaError(.coderInvalidValue)}
                        let start=Date(timeIntervalSince1970:first.doubleValue/1000),end=Date(timeIntervalSince1970:last.doubleValue/1000)
                        let matches=store.events(matching:store.predicateForEvents(withStart:start.addingTimeInterval(-86400),end:end.addingTimeInterval(86400),calendars:nil)).filter{$0.calendarItemIdentifier==id}
                        guard let match=matches.first(where:{abs($0.startDate.timeIntervalSince(start))<1}) ?? matches.first else {throw NSError(domain:"calendar",code:2,userInfo:[NSLocalizedDescriptionKey:"原事件未找到，请先同步日历"])}
                        event=match
                    } else {
                        guard let first=args["start"] as? NSNumber,let last=args["end"] as? NSNumber,let defaultCalendar=store.defaultCalendarForNewEvents,defaultCalendar.allowsContentModifications else {throw NSError(domain:"calendar",code:3,userInfo:[NSLocalizedDescriptionKey:"请先在系统日历配置可写日历"])}
                        event=EKEvent(eventStore:store);event.calendar=defaultCalendar
                        event.title=args["title"] as? String;event.notes=args["body"] as? String;event.location=args["location"] as? String
                        event.isAllDay=args["allDay"] as? Bool ?? false
                        func date(_ n:NSNumber)->Date {let date=Date(timeIntervalSince1970:n.doubleValue/1000);if !event.isAllDay{return date};var c=Calendar(identifier:.gregorian);c.timeZone=TimeZone(secondsFromGMT:0)!;return Calendar.current.date(from:c.dateComponents([.year,.month,.day],from:date))!}
                        event.startDate=date(first);event.endDate=date(last);event.alarms=[]
                    }
                    if call.method=="editCalendarEvent" {
                        guard event.calendar.allowsContentModifications else {throw NSError(domain:"calendar",code:4,userInfo:[NSLocalizedDescriptionKey:"这个日历只读，不能回写。"])}
                        event.title=args["title"] as? String;event.notes=args["body"] as? String;event.location=args["location"] as? String
                        if let first=args["start"] as? NSNumber,let last=args["end"] as? NSNumber {event.startDate=Date(timeIntervalSince1970:first.doubleValue/1000);event.endDate=Date(timeIntervalSince1970:last.doubleValue/1000)}
                        event.isAllDay=args["allDay"] as? Bool ?? false
                    }
                    #if os(iOS)
                    guard calendarResult==nil,let presenter else {throw CocoaError(.userCancelled)}
                    if event.calendar.allowsContentModifications {
                        calendarResult=result;let editor=EKEventEditViewController();editor.eventStore=store;editor.event=event;editor.editViewDelegate=self;presenter.present(editor,animated:true)
                    } else {let viewer=EKEventViewController();viewer.event=event;viewer.allowsEditing=false;viewer.delegate=self;presenter.present(UINavigationController(rootViewController:viewer),animated:true);result(true)}
                    #else
                    if call.method=="addCalendarEvent" || call.method=="editCalendarEvent" {
                        let alert=NSAlert();alert.messageText="添加到系统日历？";alert.informativeText="\(event.title ?? "")\n\(event.startDate.formatted()) — \(event.endDate.formatted())\n日历：\(event.calendar.title)";alert.addButton(withTitle:"添加");alert.addButton(withTitle:"取消")
                        guard alert.runModal() == .alertFirstButtonReturn else {result(false);return}
                        try store.save(event,span:.thisEvent,commit:true)
                    }
                    if let date=event.startDate,let url=URL(string:"calshow:\(date.timeIntervalSinceReferenceDate)"){NSWorkspace.shared.open(url)}
                    result(true)
                    #endif
                } catch {fail(error)}
            }
        case "requestReminderAccess":
            Task {
                #if os(iOS)
                let delivery=ReminderDelivery(rawValue:args["delivery"] as? String ?? "popup") ?? .popup
                result(await notifications.requestAccess(for:delivery))
                #else
                do {result(try await UNUserNotificationCenter.current().requestAuthorization(options:[.alert,.sound,.badge]))} catch {fail(error)}
                #endif
            }
        case "openSystemSettings":
            #if os(iOS)
            if let url=URL(string:UIApplication.openSettingsURLString) {UIApplication.shared.open(url);result(true)}else{result(false)}
            #else
            if let url=URL(string:"x-apple.systempreferences:com.apple.preference.notifications") {result(NSWorkspace.shared.open(url))}else{result(false)}
            #endif
        case "systemStatus":
            Task {
                #if os(iOS)
                await notifications.refresh();result(["notification":notifications.statusTitle,"alarm":notifications.alarmStatus,"scheduled":notifications.scheduledCount+notifications.alarmCount,"error":[notifications.error,widgetError].compactMap{$0}.joined(separator:"\n"),"live":{if #available(iOS 17.0,*) {return activity.status};return "需要 iOS 17"}()])
                #else
                let status=await UNUserNotificationCenter.current().notificationSettings();result(["notification":status.authorizationStatus == .authorized ? "已开启":"未开启","alarm":"macOS 使用系统通知","scheduled":(await UNUserNotificationCenter.current().pendingNotificationRequests()).count])
                #endif
            }
        case "setLiveEnabled":
            #if os(iOS)
            if #available(iOS 17.0,*) {activity.setEnabled(args["enabled"] as? Bool ?? false,entries:entries);result(true)}else {result(FlutterError(code:"unavailable",message:"实时活动需要 iOS 17",details:nil))}
            #else
            result(false)
            #endif
        case "foregroundAction":
            #if os(iOS)
            if let reminder=notifications.foregroundReminders.first(where:{$0.id==args["id"] as? String}) {
                switch args["action"] as? String {case "complete":notifications.completePopup(reminder);case "open":notifications.openPopup(reminder);case "snooze":Task{await notifications.snoozePopup(reminder)};default:notifications.dismissPopup(reminder)}
            }
            #endif
            result(true)
        case "takeRoutes":let pending=routes;routes=[];result(pending)
        case "reconcileServices":
            if let text=args["archive"] as? String {update(text)}
            #if os(iOS)
            if #available(iOS 17.0, *) {
                let enabled=args["liveEnabled"] as? Bool ?? false
                if activity.enabled != enabled {activity.setEnabled(enabled,entries:entries)}
            }
            #endif
            result(true)
        case "refreshServices":result(true)
        default:return false
        }
        return true
    }
    #if os(iOS)
    private var presenter:UIViewController? {var current=UIApplication.shared.connectedScenes.compactMap{$0 as? UIWindowScene}.first{$0.activationState == .foregroundActive}?.windows.first{$0.isKeyWindow}?.rootViewController;while let next=current?.presentedViewController {current=next};return current}
    #else
    private func scheduleMac(){scheduling?.cancel();let entries=entries,courses=courses;scheduling=Task{let center=UNUserNotificationCenter.current();guard await center.notificationSettings().authorizationStatus == .authorized else{return};let old=await center.pendingNotificationRequests();center.removePendingNotificationRequests(withIdentifiers:old.filter{$0.identifier.hasPrefix("mikanseta.")}.map(\.identifier));for item in NotificationPlan.pending(entries:entries,courses:courses){if Task.isCancelled{return};let c=UNMutableNotificationContent();c.title=item.title;c.body=item.body;c.sound=item.sound.fileName.map{UNNotificationSound(named:UNNotificationSoundName($0))} ?? .default;c.userInfo=["entryID":item.entryID?.uuidString ?? "","courseID":item.courseID?.uuidString ?? ""];let trigger=UNCalendarNotificationTrigger(dateMatching:Calendar.current.dateComponents([.year,.month,.day,.hour,.minute,.second],from:item.date),repeats:false);try? await center.add(UNNotificationRequest(identifier:"mikanseta."+item.id,content:c,trigger:trigger))}}}
    nonisolated func userNotificationCenter(_ center:UNUserNotificationCenter,willPresent notification:UNNotification,withCompletionHandler completion:@escaping(UNNotificationPresentationOptions)->Void){completion([.banner,.sound])}
    nonisolated func userNotificationCenter(_ center:UNUserNotificationCenter,didReceive response:UNNotificationResponse,withCompletionHandler completion:@escaping()->Void) {
        let info=response.notification.request.content.userInfo
        var payload:[String:String]=[:]
        if let id=info["entryID"] as? String, !id.isEmpty {payload["entryID"]=id}
        if let id=info["courseID"] as? String, !id.isEmpty {payload["courseID"]=id}
        Task { @MainActor [weak self] in
            self?.route(payload)
            NSApp.activate(ignoringOtherApps:true)
            completion()
        }
    }

    #endif
}
#if os(iOS)
extension AppleSystemServices:EKEventEditViewDelegate,EKEventViewDelegate {
    func eventEditViewController(_ controller:EKEventEditViewController,didCompleteWith action:EKEventEditViewAction){if action == .saved,let event=controller.event,let calendar=event.calendar {
            func epoch(_ date:Date)->Int64 {if !event.isAllDay{return Int64(date.timeIntervalSince1970*1000)};var parts=Calendar.current.dateComponents([.year,.month,.day],from:date);parts.timeZone=TimeZone(secondsFromGMT:0);return Int64(Calendar(identifier:.gregorian).date(from:parts)!.timeIntervalSince1970*1000)}
            let external=event.calendarItemExternalIdentifier ?? event.calendarItemIdentifier
            let occurrence=event.hasRecurrenceRules || event.isDetached ? String(Int((event.occurrenceDate ?? event.startDate).timeIntervalSince1970)) : "single"
            let recurring = event.hasRecurrenceRules || event.isDetached
            calendarEdits.append(["key":"\(calendar.calendarIdentifier)/\(external)/\(occurrence)","eventID":event.calendarItemIdentifier,"calendarID":calendar.calendarIdentifier,"calendarTitle":calendar.title,"title":event.title ?? "","body":event.notes ?? "","location":event.location ?? "","start":epoch(event.startDate),"end":epoch(event.endDate),"allDay":event.isAllDay,"seriesID":external,"recurring":recurring,"originalOccurrence":occurrence])
        }
        controller.dismiss(animated:true);calendarResult?(action == .saved);calendarResult=nil}
    func eventViewController(_ controller:EKEventViewController,didCompleteWith action:EKEventViewAction){controller.dismiss(animated:true)}
}
#endif
