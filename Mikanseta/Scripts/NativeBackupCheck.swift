import Foundation

@main
struct NativeBackupCheck {
    static func main() throws {
        let args = CommandLine.arguments
        let url = URL(fileURLWithPath: args[2])
        if args[1] == "fixture" {
            let now = Date(timeIntervalSince1970: 1_791_878_400)
            var task = Entry(title: "提交实验报告", kind: .homework, category: "物理", priority: .urgent,
                checklist: [ChecklistItem(title: "整理数据"), ChecklistItem(title: "上传报告")],
                dueDate: now.addingTimeInterval(86400), reminder: .fiveMinutes, createdAt: now, updatedAt: now)
            task.platform = "学习通"; task.location = "图书馆"; task.estimatedMinutes = 40
            task.reminderDelivery = .alarm; task.reminderSound = .chime; task.reminderPattern = .stepped
            var routine = Entry(title: "洗衣服", dueDate: now.addingTimeInterval(3600), createdAt: now, updatedAt: now)
            routine.repeatRule = .everyThreeDays; routine.repeatAnchorDate = routine.dueDate
            let event = CalendarEventRecord(identity: CalendarEventIdentity(calendarID: "school", calendarTitle: "课程", sourceTitle: "iCloud", eventID: "event-1"),
                title: "社团会议", start: now.addingTimeInterval(7200), end: now.addingTimeInterval(10800))
            var schedule = event.draft(timing: .start, now: now)
            schedule.calendarEvent = CalendarEventLink(event: event, timing: .start)
            let note = Entry(title: "一个灵感", body: "先记下来", kind: .note, createdAt: now, updatedAt: now)
            var course = Course(); course.name = "物理"; course.firstDate = now; course.lastDate = now.addingTimeInterval(86400 * 28)
            var sync = CalendarSyncSettings(); sync.selected = [CalendarSelection(id: "school", title: "课程", sourceTitle: "iCloud")]
            let archive = EntryArchive(entries: [task, routine, schedule, note], courses: [course], calendarSync: sync)
            try archive.encoded().write(to: url)
            print("Native v1 fixture encoded")
        } else {
            let archive = try EntryArchive.decode(Data(contentsOf: url))
            guard archive.entries.count == 5, archive.courses.count == 1,
                  archive.calendarSync.selected.first?.title == "课程",
                  archive.entries.contains(where: { $0.title == "提交实验报告（Flutter 编辑）" && $0.reminderDelivery == .alarm && $0.reminderSound == .chime }),
                  archive.entries.contains(where: { $0.kind == .schedule && $0.calendarEvent != nil }),
                  archive.entries.contains(where: { $0.kind == .task && $0.title == "Flutter 新增" }) else {
                throw ArchiveError.invalidEntries
            }
            print("Swift → Dart → Swift backup roundtrip verified")
        }
    }
}
