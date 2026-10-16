import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mikanseta/src/calendar_view.dart';
import 'package:mikanseta/src/domain.dart';
import 'package:mikanseta/src/store.dart';
import 'package:mikanseta/src/student_tools.dart';
import 'package:mikanseta/src/system_services.dart';

import 'domain_test.dart' show MemoryStorage;

void main() {
  final now = DateTime(2026, 10, 15, 8);
  Future<EntryStore> store() async {
    final s = EntryStore(MemoryStorage(), clock: () => now);
    await s.load();
    return s;
  }

  Entry schedule(String title, DateTime from, DateTime to) =>
      Entry.create(title: title, kind: EntryKind.schedule, now: now).change({
        'plannedStart': isoDate(from),
        'plannedEnd': isoDate(to),
      }, now: now);
  test('timeline separates deadlines and overlapping execution blocks', () {
    final a = schedule(
      'a',
      DateTime(2026, 10, 15, 9),
      DateTime(2026, 10, 15, 10),
    );
    final b = schedule(
      'b',
      DateTime(2026, 10, 15, 9, 30),
      DateTime(2026, 10, 15, 11),
    );
    final c = schedule(
      'c',
      DateTime(2026, 10, 15, 12),
      DateTime(2026, 10, 15, 13),
    );
    final ddl = Entry.create(
      title: 'ddl',
      now: now,
    ).change({'dueDate': isoDate(DateTime(2026, 10, 15, 9))});
    final items = calendarItems([a, b, c, ddl], now);
    final blocks = layoutTimeline(items, now);
    expect(items.where((i) => i.deadline), hasLength(1));
    expect(blocks, hasLength(3));
    expect(blocks.take(2).map((b) => b.columns), everyElement(2));
    expect(blocks.take(2).map((b) => b.column).toSet(), {0, 1});
    expect(blocks.last.columns, 1);
  });
  test(
    'cross-midnight and DST days clip execution at each actual boundary',
    () {
      final day = DateTime(2026, 11, 1);
      final end = DateTime(2026, 11, 2);
      final e = schedule(
        'overnight',
        DateTime(2026, 10, 31, 23),
        DateTime(2026, 11, 2, 1),
      );
      final blocks = layoutTimeline(calendarItems([e], day), day);
      expect(blocks.single.start, 0);
      expect(blocks.single.end, end.difference(day).inMinutes.toDouble());
    },
  );
  test(
    'routine projection keeps saved owners and stops at existing successors',
    () {
      final e = schedule(
        'routine',
        DateTime(2026, 10, 15, 9),
        DateTime(2026, 10, 15, 10),
      ).change({'repeatRule': 'daily'});
      final next = e.nextOccurrence(DateTime(2026, 10, 15, 10))!;
      final items = calendarItems([e, next], DateTime(2026, 10, 16));
      expect(items, hasLength(1));
      expect(items.single.owner.id, next.id);
      expect(calendarItems([e], DateTime(2026, 10, 17)).single.owner.id, e.id);
    },
  );
  testWidgets(
    'long press and drag in both directions creates the selected quarter-hour range',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final s = await store();
      final ranges = <(DateTime, DateTime)>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TimelineCalendar(
              days: [dayOf(now)],
              store: s,
              showCompleted: true,
              onCreate: (a, b) => ranges.add((a, b)),
              onOpen: (_) {},
              onDay: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> drag(double dy) async {
        final g = await tester.startGesture(const Offset(190, 290));
        await tester.pump(const Duration(milliseconds: 600));
        await g.moveBy(Offset(0, dy));
        await tester.pump(const Duration(milliseconds: 30));
        expect(ranges.length, dy > 0 ? 0 : 1);
        await g.up();
        await tester.pumpAndSettle();
      }

      await drag(108);
      await drag(-108);
      expect(ranges, hasLength(2));
      for (final (a, b) in ranges) {
        expect(a.minute % 15, 0);
        expect(b.minute % 15, 0);
        expect(b.isAfter(a), true);
        expect(b.difference(a).inMinutes, greaterThanOrEqualTo(90));
        expect(a.day, 15);
        expect(b.day, 15);
      }
      expect(tester.takeException(), null);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'read-only timeline cannot create schedules and day/week choices persist',
    (tester) async {
      final s = await store();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ScheduleCalendar(
              store: s,
              onOpen: (_) {},
              onCreate: (_, _) {
                fail('read only');
              },
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('calendar-week')));
      await tester.pumpAndSettle();
      expect(s.preferences['calendarView'], 'week');
      s.readOnly = true;
      final g = await tester.startGesture(const Offset(190, 290));
      await tester.pump(const Duration(milliseconds: 600));
      await g.moveBy(const Offset(0, 90));
      await g.up();
      await tester.pumpAndSettle();
      expect(tester.takeException(), null);
      await tester.pumpWidget(const SizedBox());
      await s.settled;
    },
  );
  test('CSV preserves quoted fields, rejects malformed input and deduplicates imports', () async {
    final text =
        '$courseHeader\n"数学,提高",1,08:00,09:40,"教室\n二楼",学习通,2026-09-01,2027-01-15';
    final courses = parseCourseCSV(text);
    expect(courses.single.name, '数学,提高');
    expect(courses.single.data['location'], '教室\n二楼');
    final s = await store();
    expect(s.importCourses(courses), 1);
    expect(s.importCourses(parseCourseCSV(text)), 0);
    expect(s.courses, hasLength(1));
    expect(
      () => parseCourseCSV(
        '$courseHeader\n数学,1,25:00,26:00,,,2026-09-01,2027-01-15',
      ),
      throwsFormatException,
    );
    await s.settled;
  });
  test(
    'ICS expands source timezone across DST and applies exclusion dates',
    () {
      final courses = parseCourseICS(
        'BEGIN:VCALENDAR\nBEGIN:VEVENT\nSUMMARY:数学\nDTSTART;TZID=America/New_York:20261025T090000\nDTEND;TZID=America/New_York:20261025T100000\nRRULE:FREQ=WEEKLY;COUNT=3\nEXDATE;TZID=America/New_York:20261108T090000\nEND:VEVENT\nEND:VCALENDAR',
      );
      expect(courses, hasLength(2));
      final a = DateTime.parse('2026-10-25T13:00:00Z').toLocal(),
          b = DateTime.parse('2026-11-01T14:00:00Z').toLocal();
      expect(courses[0].begin, a.hour * 60 + a.minute);
      expect(courses[1].begin, b.hour * 60 + b.minute);
      expect(courses[0].first, dayOf(a));
      expect(courses[1].first, dayOf(b));
      expect(
        () => parseCourseICS(
          'BEGIN:VCALENDAR\nBEGIN:VEVENT\nSUMMARY:x\nDTSTART:20261025T090000\nDTEND:20261025T100000\nRRULE:FREQ=WEEKLY\nEND:VEVENT\nEND:VCALENDAR',
        ),
        throwsFormatException,
      );
    },
  );
  test('message suggestions retain original text and never choose among multiple dates', () {
    final (e, warnings) = parseMessage('【物理】作业明天18:00交学习通，预计2小时', now);
    expect(e.kind, EntryKind.homework);
    expect(e.due, DateTime(2026, 10, 16, 18));
    expect(e.platform, '学习通');
    expect(e.estimate, 120);
    expect(e.source, contains('预计2小时'));
    expect(warnings, isNotEmpty);
    expect(parseMessage('今天布置作业，后天提交', now).$1.due, null);
    expect(parseMessage('2026年2月30日提交', now).$1.due, null);
  });
  test('managed reminders stop on completion and retain course routes, sounds and limits', () {
    final e = Entry.create(title: '任务', now: now).change({
      'dueDate': isoDate(now.add(const Duration(hours: 1))),
      'reminder': 0,
      'reminderDelivery': 'alarm',
      'reminderSound': 'pulse',
      'reminderPattern': 'persistent',
      'snoozeMinutes': 10,
    });
    final course = Course({
      ...Course.create().data,
      'name': '数学',
      'weekday': now.weekday,
      'firstDate': isoDate(dayOf(now)),
      'lastDate': isoDate(dayOf(now)),
      'endMinutes': 600,
    });
    final a = Archive(
      entries: [e],
      metadata: {
        'courses': [course.data],
      },
    );
    final plan = reminderPlan(a, now);
    expect(plan.any((r) => r['courseID'] == course.id), true);
    expect(
      plan
          .where((r) => r['entryID'] == e.id)
          .every((r) => r['sound'] == 'pulse' && r['snoozeMinutes'] == 10),
      true,
    );
    expect(plan.length, lessThanOrEqualTo(60));
    expect(
      reminderPlan(Archive(entries: [e.setCompleted(true, now)]), now),
      isEmpty,
    );
    final summary = serviceSnapshot(a, now)['summary'] as Map;
    final item = (summary['liveItems'] as List).first as Map;
    expect(item.containsKey('body'), false);
    expect(item.containsKey('source'), false);
  });
  test('calendar end timing and cleanup protect modified progress', () async {
    final s = await store();
    s.setAndroidCalendarSettings({
      'deviceID': 'phone',
      'selected': ['1'],
      'timing': 'end',
    });
    final row = {
      'key': '1/e/single',
      'eventID': 'e',
      'calendarID': '1',
      'calendarTitle': '课程',
      'title': '课',
      'body': '',
      'location': '',
      'start': now.add(const Duration(hours: 1)).millisecondsSinceEpoch,
      'end': now.add(const Duration(hours: 2)).millisecondsSinceEpoch,
      'allDay': false,
    };
    s.importAndroidEvents([row], 'phone');
    expect(s.entries.single.kind, EntryKind.task);
    expect(s.entries.single.due, now.add(const Duration(hours: 2)));
    s.setAndroidCalendarSettings({
      'deviceID': 'phone',
      'selected': [],
      'timing': 'end',
    });
    expect(s.cleanableCalendarEntries, hasLength(1));
    s.save(
      s.entries.single.change({
        'checklist': [StepItem(title: '完成步骤').toJson()],
      }),
    );
    expect(s.cleanableCalendarEntries, isEmpty);
    expect(s.cleanUnselectedCalendarEntries(), 0);
    await s.settled;
  });
}
