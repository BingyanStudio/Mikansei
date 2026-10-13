import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mikanseta/src/app.dart';
import 'package:mikanseta/src/domain.dart';
import 'package:mikanseta/src/store.dart';

import 'domain_test.dart' show MemoryStorage;

void main() {
  Future<EntryStore> loaded() async {
    final store = EntryStore(MemoryStorage());
    await store.load();
    return store;
  }

  testWidgets(
    'quick add, complete, crossed-out retention and history navigation',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = await loaded();
      await tester.pumpWidget(MikansetaApp(store: store));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('添加事项'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('entry-title')),
        '提交数学作业',
      );
      await tester.tap(find.byKey(const ValueKey('save-entry')));
      await tester.pumpAndSettle();
      expect(store.entries.single.title, '提交数学作业');
      await tester.tap(find.byTooltip('标记完成'));
      await tester.pumpAndSettle();
      expect(find.text('提交数学作业'), findsOneWidget);
      expect(find.text('今日已完成'), findsOneWidget);
      final text = tester.widget<Text>(find.text('提交数学作业'));
      final style = tester.widget<AnimatedDefaultTextStyle>(
        find
            .ancestor(
              of: find.byWidget(text),
              matching: find.byType(AnimatedDefaultTextStyle),
            )
            .first,
      );
      expect(style.style.decoration, TextDecoration.lineThrough);
      expect(tester.takeException(), null);
      await store.settled;
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('phone at 320 width and enlarged text has accessible controls', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    tester.view.physicalSize = const Size(320, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = await loaded();
    store.save(Entry.create(title: '一个很长的作业标题，检查小屏幕上是否仍然可以读取和勾选'));
    await tester.pumpWidget(MikansetaApp(store: store));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
    await tester.tap(find.byTooltip('添加事项'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('save-entry')), findsOneWidget);
    expect(tester.takeException(), null);
    await tester.pumpWidget(const SizedBox());
    await store.settled;
  });
  testWidgets('desktop rail and calendar long press create a schedule', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = await loaded();
    await tester.pumpWidget(MikansetaApp(store: store));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationRail), findsOneWidget);
    await tester.tap(find.text('日程'));
    await tester.pumpAndSettle();
    await tester.longPress(find.text('20'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('entry-title')), '社团会议');
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('save-entry')));
    await tester.pumpAndSettle();
    final entry = store.entries.single;
    expect(entry.kind, EntryKind.schedule);
    expect(entry.due, null);
    expect(entry.start!.day, 20);
    expect(entry.allDay, true);
    expect(entry.start!.hour, 0);
    expect(entry.end!.day, 21);
    expect(entry.end!.isAfter(entry.start!), true);
    expect(tester.takeException(), null);
    await tester.pumpWidget(const SizedBox());
    await store.settled;
  });
  testWidgets('editing Checklist keeps each remaining step identity and progress', (tester) async {
    final store = await loaded();
    final a = StepItem(title: 'A', done: true);
    final b = StepItem(title: 'B');
    final c = StepItem(title: 'C', done: true);
    store.save(Entry.create(title: '检查步骤').change({'checklist': [a.toJson(), b.toJson(), c.toJson()]}));
    await tester.pumpWidget(MikansetaApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('检查步骤'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();
    final field = find.byWidgetPredicate((widget) => widget is TextField && widget.controller?.text == 'A\nB\nC');
    await tester.enterText(field, 'B\nC');
    await tester.tap(find.byKey(const ValueKey('save-entry')));
    await tester.pumpAndSettle();
    expect(store.entries.single.steps.map((s) => s.id), [b.id, c.id]);
    expect(store.entries.single.steps.map((s) => s.done), [false, true]);
    expect(tester.takeException(), null);
    await tester.pumpWidget(const SizedBox()); await store.settled;
  });

  test('settings version follows pubspec', () {
    final yaml = File('pubspec.yaml').readAsStringSync();
    final version = RegExp(r'version:\s*(\S+)')
        .firstMatch(yaml)!
        .group(1)!
        .split('+');
    expect(appVersion, '${version[0]} (${version[1]})');
  });
}
