import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mikanseta/src/android_system.dart';
import 'package:mikanseta/src/domain.dart';
import 'package:mikanseta/src/store.dart';

import 'domain_test.dart' show MemoryStorage;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime(2026, 10, 14, 9);
  Map<String, dynamic> event({
    String key = '1/10/single',
    String title = '课堂作业',
    String body = '提交到平台',
  }) => {
    'key': key,
    'eventID': '10',
    'calendarID': '1',
    'calendarTitle': '课程',
    'title': title,
    'body': body,
    'location': '教室',
    'allDay': false,
    'start': now.add(const Duration(hours: 2)).millisecondsSinceEpoch,
    'end': now.add(const Duration(hours: 3)).millisecondsSinceEpoch,
  };
  Future<EntryStore> store() async {
    final s = EntryStore(MemoryStorage(), clock: () => now);
    await s.load();
    s.setAndroidCalendarSettings({
      'deviceID': 'phone',
      'selected': ['1'],
      'enabled': true,
    });
    await s.settled;
    return s;
  }

  test('calendar import is idempotent and keeps progress, manual changes and completion', () async {
    final s = await store();
    expect(s.importAndroidEvents([event()], 'phone'), 1);
    final original = s.entries.single;
    expect(original.kind, EntryKind.schedule);
    final step = StepItem(title: '检查提交', done: true);
    s.save(
      original.change({
        'title': '我的标题',
        'checklist': [step.toJson()],
        'elapsedSeconds': 120,
      }),
    );
    s.toggle(original.id);
    expect(
      s.importAndroidEvents([event(title: '来源新标题', body: '来源新备注')], 'phone'),
      1,
    );
    final merged = s.entries.single;
    expect(merged.id, original.id);
    expect(merged.title, '我的标题');
    expect(merged.body, '来源新备注');
    expect(merged.completed, true);
    expect(merged.steps.single.done, true);
    expect(merged.focusSeconds(now), 120);
    expect(
      s.importAndroidEvents([event(title: '来源新标题', body: '来源新备注')], 'phone'),
      0,
    );
    await s.settled;
    final reloaded = EntryStore(s.storage);
    await reloaded.load();
    expect(reloaded.entries.single.completed, true);
    expect(reloaded.androidCalendarSettings['selected'], ['1']);
  });
  test('moving a single event keeps its identity; deleted imports remain suppressed', () async {
    final s = await store();
    s.importAndroidEvents([event()], 'phone');
    final id = s.entries.single.id;
    s.importAndroidEvents([
      {
        ...event(),
        'start': now.add(const Duration(days: 2)).millisecondsSinceEpoch,
        'end': now
            .add(const Duration(days: 2, hours: 1))
            .millisecondsSinceEpoch,
      },
    ], 'phone');
    expect(s.entries.single.id, id);
    expect(s.entries.single.start!.day, 16);
    s.delete(id);
    expect(s.importAndroidEvents([event()], 'phone'), 0);
    expect(s.entries, isEmpty);
    await s.settled;
  });
  test('recurring instances stay distinct and all-day UTC dates keep their calendar day', () async {
    final s = await store();
    s.importAndroidEvents([
      event(key: '1/10/one'),
      event(key: '1/10/two'),
    ], 'phone');
    expect(s.entries.length, 2);
    s.importAndroidEvents([
      {
        ...event(key: '1/11/single'),
        'allDay': true,
        'start': DateTime.utc(2026, 11, 1).millisecondsSinceEpoch,
        'end': DateTime.utc(2026, 11, 2).millisecondsSinceEpoch,
      },
    ], 'phone');
    final allDay = s.entries.last;
    expect(allDay.start, DateTime(2026, 11, 1));
    expect(allDay.end, DateTime(2026, 11, 2));
    await s.settled;
  });
  test('only a matching local export token links back to the original task and keeps its DDL', () async {
    final s = await store();
    final task = Entry.create(title: '原待办', now: now).change({
      'dueDate': isoDate(now.add(const Duration(days: 4))),
      'androidCalendarExportToken': newId(),
    });
    s.save(task);
    s.importAndroidEvents([
      event(
        body:
            'mikanseta://entry/${task.id}?token=${task.data['androidCalendarExportToken']}',
      ),
    ], 'phone');
    expect(s.entries.length, 1);
    expect(s.entries.single.id, task.id);
    expect(s.entries.single.due, task.due);
    expect(s.entries.single.kind, EntryKind.task);
    expect(s.entries.single.start, isNotNull);
    await s.settled;
  });
  test(
    'resume sync ignores calendar IDs copied from another installation',
    () async {
      final s = await store();
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(NativeStorage.channel, (call) async {
            calls.add(call.method);
            return 'another-phone';
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(NativeStorage.channel, null),
      );
      expect(await AndroidSystem.sync(s), 0);
      expect(calls, ['calendarDeviceID']);
    },
  );
  test('a newly opened editor defers an in-flight calendar import', () async {
    final s = await store();
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(NativeStorage.channel, (call) async {
          return switch (call.method) {
            'calendarDeviceID' => 'phone',
            'calendarAccess' => true,
            'calendarEvents' => [
              event(),
              for (final day in [
                DateTime.utc(2026, 10, 13),
                DateTime.utc(2026, 10, 14),
                DateTime.utc(2026, 11, 13),
              ])
                {
                  ...event(key: 'all-day-${day.day}'),
                  'allDay': true,
                  'start': day.millisecondsSinceEpoch,
                  'end': day
                      .add(const Duration(days: 1))
                      .millisecondsSinceEpoch,
                },
            ],
            _ => null,
          };
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(NativeStorage.channel, null),
    );
    expect(await AndroidSystem.sync(s, canImport: () => false), 0);
    expect(s.entries, isEmpty);
    expect(await AndroidSystem.sync(s, canImport: () => true), 2);
    expect(
      s.entries.where((e) => e.allDay).single.start,
      DateTime(2026, 10, 14),
    );
    await s.settled;
  });
  testWidgets('calendar handoff keeps DDL separate and requires confirmation', (
    tester,
  ) async {
    final s = EntryStore(MemoryStorage());
    await s.load();
    final due = DateTime(2028, 12, 20, 18);
    final entry = Entry.create(title: '确认提交').change({'dueDate': isoDate(due)});
    s.save(entry);
    final requests = <Map<String, dynamic>>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(NativeStorage.channel, (call) async {
          if (call.method == 'calendarDeviceID') return 'phone';
          if (call.method == 'takeCalendarEdits') return [];
          if (call.method == 'addCalendarEvent') {
            requests.add(Map<String, dynamic>.from(call.arguments as Map));
          }
          return true;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(NativeStorage.channel, null),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AndroidEntryActions(entry: entry, store: s),
        ),
      ),
    );
    await tester.tap(find.text('添加到系统日历'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(requests, isEmpty);
    await tester.tap(find.text('添加到系统日历'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('打开系统日历'));
    await tester.pumpAndSettle();
    expect(requests, hasLength(1));
    expect(requests.single['title'], entry.title);
    expect(requests.single['start'], lessThan(due.millisecondsSinceEpoch));
    expect(
      requests.single['end'],
      greaterThan(requests.single['start'] as int),
    );
    expect(requests.single['body'], contains('DDL：'));
    expect(s.entries.single.due, due);
    expect(s.entries.single.data['androidCalendarExportToken'], isNotEmpty);
    await tester.pumpWidget(const SizedBox());
    await s.settled;
  });
  testWidgets(
    'sources start unchecked, clock duration validates and unavailable handlers report an error',
    (tester) async {
      final s = EntryStore(MemoryStorage());
      await s.load();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(NativeStorage.channel, (call) async {
            switch (call.method) {
              case 'requestCalendarAccess':
                return true;
              case 'calendarDeviceID':
                return 'phone';
              case 'calendarSources':
                return [
                  {'id': '1', 'title': '课程', 'account': '本地'},
                  {'id': '2', 'title': '节假日', 'account': '本地'},
                ];
              case 'createClockTimer':
                throw PlatformException(
                  code: 'unavailable',
                  message: '未找到系统时钟',
                );
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(NativeStorage.channel, null),
      );
      await tester.pumpWidget(MaterialApp(home: AndroidCalendarPage(store: s)));
      await tester.tap(find.text('读取日历来源'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CheckboxListTile>(
              find.byKey(const ValueKey('calendar-source-2')),
            )
            .value,
        false,
      );
      expect(
        tester
            .widget<CheckboxListTile>(
              find.byKey(const ValueKey('calendar-source-1')),
            )
            .value,
        false,
      );
      final e = Entry.create(title: '洗衣服');
      s.save(e);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AndroidEntryActions(entry: e, store: s),
          ),
        ),
      );
      await tester.tap(find.text('系统倒计时'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '0');
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '打开系统倒计时'))
            .onPressed,
        null,
      );
      await tester.enterText(find.byType(TextField), '5');
      await tester.pumpAndSettle();
      await tester.tap(find.text('打开系统倒计时'));
      await tester.pumpAndSettle();
      expect(find.text('未找到系统时钟'), findsOneWidget);
      expect(tester.takeException(), null);
      await tester.pumpWidget(const SizedBox());
      await s.settled;
    },
  );
}
