import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mikanseta/src/domain.dart';
import 'package:mikanseta/src/store.dart';

class MemoryStorage implements ArchiveStorage {
  String? content;
  String? selected;
  String? exported;
  bool fail = false;
  final writes = <String>[];
  @override
  Future<String?> read() async => content;
  @override
  Future<void> write(String value) async {
    if (fail) throw StateError('磁盘写入失败');
    await Future<void>.delayed(const Duration(milliseconds: 1));
    content = value;
    writes.add(value);
  }

  @override
  Future<String?> pickBackup() async => selected;
  @override
  Future<bool> exportBackup(String value) async {
    exported = value;
    return true;
  }
}

void main() {
  test(
    'backup merge retains imported calendar selections and opaque settings',
    () {
      final source = Archive(
        entries: [Entry.create(title: '备份事项')],
        metadata: {
          'version': 1,
          'courses': [],
          'calendarSync': {
            'enabled': true,
            'selected': [
              {'id': 'school', 'title': '课程', 'sourceTitle': 'iCloud'},
            ],
            'suppressed': [],
            'futureCalendarSetting': '保留',
          },
        },
      );
      final merged = Archive(entries: [])
          .merge(Archive.decode(source.encode()));
      expect(merged.metadata['calendarSync'], source.metadata['calendarSync']);
    },
  );
  test(
    'selected dates beyond five years still generate the next occurrence',
    () {
      final start = DateTime(2026, 10, 13, 9);
      final entry = Entry.create(title: '特定日期', now: start).change({
        'dueDate': isoDate(start),
        'repeatRule': 'dates',
        'repeatDates': [isoDate(DateTime(2034, 1, 1))],
      }, now: start);
      expect(entry.nextOccurrence(start)!.due, DateTime(2034, 1, 1, 9));
    },
  );
  test(
    'edits within one second remain newer after native date serialization',
    () {
      final now = DateTime(2026, 10, 13, 9, 0, 0, 500);
      final original = Entry.create(title: '原始', now: now);
      final changed = original.change({'title': '新版'}, now: now);
      final copy = Archive.decode(Archive(entries: [changed]).encode())
          .entries
          .single;
      expect(copy.updatedAt.isAfter(original.updatedAt), true);
      expect(copy.data['updatedAt'] as String, isNot(contains('.')));
    },
  );
  test(
    'read-only recovery export preserves the original damaged file',
    () async {
      final storage = MemoryStorage()..content = 'damaged original data';
      final store = EntryStore(storage);
      await store.load();
      expect(await store.exportBackup(), true);
      expect(storage.exported, 'damaged original data');
      expect(storage.writes, isEmpty);
    },
  );
  final now = DateTime(2026, 10, 13, 12);
  Entry task(String title, int priority, DateTime? due) =>
      Entry.create(title: title, now: now).change({
        'priority': priority,
        'dueDate': due == null ? null : isoDate(due),
      }, now: now);
  test('overdue first, then importance, deadline and stable ID ordering', () {
    final overdue = task('超时普通', 0, now.subtract(const Duration(hours: 1)));
    final urgent = task('明日紧急', 2, now.add(const Duration(days: 1)));
    final earlier = task('今日重要', 1, now.add(const Duration(hours: 1)));
    final later = task('后天重要', 1, now.add(const Duration(days: 2)));
    final unscheduled = task('没有 DDL', 0, null);
    final board = TaskBoard([
      later,
      urgent,
      unscheduled,
      earlier,
      overdue,
    ], now);
    expect(board.visible.map((e) => e.title), [
      '超时普通',
      '明日紧急',
      '今日重要',
      '后天重要',
      '没有 DDL',
    ]);
    expect(board.focus.map((e) => e.title), ['超时普通', '今日重要', '没有 DDL']);
  });
  test('completed stays at bottom until local midnight, no data deletion', () {
    final completed = task('已完成', 2, now).setCompleted(true, now);
    final open = task('未完成', 0, null);
    expect(TaskBoard([completed, open], now).visible.map((e) => e.id), [
      open.id,
      completed.id,
    ]);
    final tomorrow = DateTime(2026, 10, 14);
    expect(TaskBoard([completed, open], tomorrow).visible.map((e) => e.id), [
      open.id,
    ]);
    expect(
      TaskBoard([completed, open], tomorrow).history.single.id,
      completed.id,
    );
  });
  test(
    'completion stops timer and checks every step; reopen preserves progress',
    () {
      final step = StepItem(title: '上传文件');
      var entry = task('作业', 1, now).change({
        'checklist': [step.toJson()],
        'startedAt': isoDate(now.subtract(const Duration(minutes: 2))),
        'elapsedSeconds': 15,
      }, now: now);
      entry = entry.setCompleted(true, now);
      expect(entry.startedAt, null);
      expect(entry.focusSeconds(now), 135);
      expect(entry.steps.single.done, true);
      entry = entry.toggleStep(step.id, now);
      expect(entry.completed, false);
      expect(entry.completedAt, null);
    },
  );
  test('schedules have start/end but no deadline or overdue section', () {
    final entry = Entry.create(
      title: '开会',
      kind: EntryKind.schedule,
      now: now.subtract(const Duration(days: 1)),
    );
    expect(entry.due, null);
    expect(entry.overdue(now), false);
    expect(entry.end!.difference(entry.start!), const Duration(minutes: 30));
  });
  test('monthly recurrence returns to original month-end', () {
    final jan = DateTime(2027, 1, 31, 9);
    final entry = task('每月归档', 0, jan).change({
      'repeatRule': 'monthly',
      'repeatAnchorDate': isoDate(jan),
    }, now: jan);
    final feb = entry.nextOccurrence(jan)!;
    expect(feb.due, DateTime(2027, 2, 28, 9));
    expect(feb.nextOccurrence(feb.due!)!.due, DateTime(2027, 3, 31, 9));
    expect(feb.id, isNot(entry.id));
    expect(feb.data['previousOccurrenceID'], entry.id);
  });
  test('weekly selected days and finite date repeats', () {
    final mon = DateTime(2026, 10, 12, 9);
    final weekly = task('课后整理', 0, mon).change({
      'repeatRule': 'weekly',
      'repeatWeekdays': [1, 3, 5],
    }, now: mon);
    expect(weekly.nextOccurrence(mon)!.due, DateTime(2026, 10, 14, 9));
    final finite = weekly.change({
      'repeatRule': 'dates',
      'repeatDates': [
        isoDate(DateTime(2026, 10, 14)),
        isoDate(DateTime(2026, 10, 18)),
      ],
    }, now: mon);
    final last = finite.nextOccurrence(DateTime(2026, 10, 15))!;
    expect(last.due, DateTime(2026, 10, 18, 9));
    expect(last.nextOccurrence(last.due!), null);
  });
  test('daily recurrence preserves local time across DST', () {
    // Run this test suite with TZ=America/Los_Angeles too.
    final start = DateTime(2026, 3, 7, 9);
    final entry = task(
      '晨间整理',
      0,
      start,
    ).change({'repeatRule': 'daily'}, now: start);
    final next = entry.nextOccurrence(start)!;
    expect(next.due, DateTime(2026, 3, 8, 9));
    expect(next.due!.hour, 9);
  });
  test('native JSON and unknown extension fields survive roundtrip', () {
    final original = task('原版备份', 1, now).change({
      'reminderDelivery': 'alarm',
      'reminder': 300,
      'futureField': {'x': 42},
    }, now: now);
    final archive = Archive(
      entries: [original],
      metadata: {
        'version': 1,
        'courses': [],
        'calendarSync': {'enabled': true, 'selected': [], 'suppressed': []},
        'futureArchiveField': '保留',
      },
    );
    final copy = Archive.decode(archive.encode());
    expect(copy.entries.single.data, original.data);
    expect(copy.metadata['futureArchiveField'], '保留');
    expect(copy.entries.single.data['reminderDelivery'], 'alarm');
  });
  test('bad version, duplicate ID and malformed schedule are rejected', () {
    expect(
      () => Archive.decode('{"version":2,"entries":[]}'),
      throwsFormatException,
    );
    final entry = task('测试', 0, null);
    expect(
      () => Archive.decode(Archive(entries: [entry, entry]).encode()),
      throwsFormatException,
    );
    final schedule = Entry.create(
      title: '无效日程',
      kind: EntryKind.schedule,
      now: now,
    ).change({'plannedEnd': null});
    expect(
      () => Archive.decode(Archive(entries: [schedule]).encode()),
      throwsFormatException,
    );
  });
  test('merge keeps newer records and removes source-device replica', () {
    final old = task('旧标题', 0, null);
    final newer = old.change({
      'title': '新标题',
    }, now: now.add(const Duration(minutes: 1)));
    final a = Archive(entries: [old]);
    final b = Archive(
      entries: [newer],
      metadata: {
        'version': 1,
        'replica': {'counter': 99},
        'courses': [],
      },
    );
    final merged = a.merge(b);
    expect(merged.entries.single.title, '新标题');
    expect(merged.metadata.containsKey('replica'), false);
  });
  test(
    'writes serialize and latest snapshot wins; failing save is retryable',
    () async {
      final storage = MemoryStorage();
      final store = EntryStore(storage, clock: () => now);
      await store.load();
      final entry = task('第一条', 0, null);
      store.save(entry);
      store.save(entry.change({'title': '第二个标题'}, now: now));
      await store.settled;
      expect(Archive.decode(storage.content!).entries.single.title, '第二个标题');
      storage.fail = true;
      store.toggle(entry.id);
      await store.settled;
      expect(store.saveFailed, true);
      expect(store.entries.single.completed, true);
      storage.fail = false;
      store.retrySave();
      await store.settled;
      expect(store.saveFailed, false);
      expect(Archive.decode(storage.content!).entries.single.completed, true);
    },
  );
  test(
    'focus exclusivity, pause and restart restore elapsed wall time',
    () async {
      final storage = MemoryStorage();
      var time = now;
      final store = EntryStore(storage, clock: () => time);
      await store.load();
      final a = task('A', 0, null), b = task('B', 0, null);
      store.save(a);
      store.save(b);
      store.focus(a.id);
      time = time.add(const Duration(seconds: 40));
      store.focus(b.id);
      expect(store.find(a.id)!.focusSeconds(time), 40);
      expect(store.running!.id, b.id);
      await store.settled;
      time = time.add(const Duration(seconds: 20));
      final restored = EntryStore(storage, clock: () => time);
      await restored.load();
      expect(restored.running!.focusSeconds(time), 20);
    },
  );
  test('re-completing a routine never creates a duplicate successor', () async {
    final storage = MemoryStorage();
    final store = EntryStore(storage, clock: () => now);
    await store.load();
    final entry = task('洗衣', 0, now).change({'repeatRule': 'daily'}, now: now);
    store.save(entry);
    store.toggle(entry.id);
    store.toggle(entry.id);
    store.toggle(entry.id);
    expect(store.entries.length, 2);
    expect(
      store.entries
          .where((e) => e.data['previousOccurrenceID'] == entry.id)
          .length,
      1,
    );
    await store.settled;
  });
  test(
    'corrupt local storage becomes read-only and never overwrites original',
    () async {
      final storage = MemoryStorage()..content = 'broken';
      final store = EntryStore(storage);
      await store.load();
      store.save(task('不可覆盖', 0, null));
      await store.settled;
      expect(store.readOnly, true);
      expect(storage.content, 'broken');
      expect(storage.writes, isEmpty);
    },
  );
  test('malformed import is atomic and keeps existing records', () async {
    final storage = MemoryStorage();
    final store = EntryStore(storage, clock: () => now);
    await store.load();
    store.save(task('保留我', 0, null));
    await store.settled;
    storage.selected = jsonEncode({
      'version': 1,
      'entries': [
        {'title': '坏数据'},
      ],
    });
    await expectLater(store.importBackup(), throwsA(anything));
    expect(store.entries.single.title, '保留我');
    expect(Archive.decode(storage.content!).entries.single.title, '保留我');
  });
}
