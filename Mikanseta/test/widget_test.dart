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
    final step = StepItem(title: '一个很长的子事项标题，检查放大文字时能换行并直接勾选');
    final entry = Entry.create(title: '一个很长的作业标题，检查小屏幕上是否仍然可以读取和勾选').change({
      'checklist': [step.toJson()],
    });
    store.save(entry);
    await tester.pumpWidget(MikansetaApp(store: store));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
    await tester.ensureVisible(find.text(step.title));
    await tester.tap(find.text(step.title));
    await tester.pumpAndSettle();
    expect(store.find(entry.id)!.steps.single.done, true);
    expect(find.byType(Dialog), findsNothing);
    await tester.tap(find.byTooltip('添加事项'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('save-entry')), findsOneWidget);
    expect(tester.takeException(), null);
    await tester.pumpWidget(const SizedBox());
    await store.settled;
  });
  testWidgets(
    'inline checklist saves progress, opens remaining steps and reopens a completed task',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = await loaded();
      final steps = [
        '阅读课文',
        '写练习',
        '检查答案',
        '上传平台',
      ].map((title) => StepItem(title: title)).toList();
      final entry = Entry.create(title: '英语作业')
          .change({'checklist': steps.map((step) => step.toJson()).toList()});
      store.save(entry);
      await tester.pumpWidget(MikansetaApp(store: store));
      await tester.pumpAndSettle();
      expect(find.text('上传平台'), findsNothing);
      await tester.tap(find.text('阅读课文'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(find.text('1/4 项'), findsOneWidget);
      expect(store.find(entry.id)!.completed, false);
      expect(
        tester.widget<Text>(find.text('阅读课文')).style!.decoration,
        TextDecoration.lineThrough,
      );
      await store.settled;
      final restored = EntryStore(store.storage);
      await restored.load();
      expect(restored.find(entry.id)!.steps.first.done, true);
      await tester.tap(find.text('查看全部 4 个步骤'));
      await tester.pumpAndSettle();
      expect(find.text('上传平台'), findsOneWidget);
      await tester.tap(find.text('上传平台'));
      await tester.pumpAndSettle();
      expect(store.find(entry.id)!.steps.last.done, true);
      await tester.tap(find.byTooltip('关闭'));
      await tester.pumpAndSettle();
      expect(find.text('2/4 项'), findsOneWidget);
      await tester.tap(find.byTooltip('标记完成'));
      await tester.pumpAndSettle();
      expect(find.text('今日已完成'), findsOneWidget);
      expect(find.text('4/4 项'), findsOneWidget);
      await tester.tap(find.text('阅读课文'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(store.find(entry.id)!.completed, false);
      expect(store.find(entry.id)!.completedAt, null);
      expect(find.text('今日已完成'), findsNothing);
      expect(find.text('3/4 项'), findsOneWidget);
      await store.settled;
      await restored.load();
      expect(restored.find(entry.id)!.steps.map((step) => step.done), [
        false,
        true,
        true,
        true,
      ]);
      expect(restored.find(entry.id)!.completed, false);
      expect(tester.takeException(), null);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('inline checklist cannot change a read-only archive', (
    tester,
  ) async {
    final store = await loaded();
    final step = StepItem(title: '保留损坏原文件');
    final entry = Entry.create(title: '只读事项').change({
      'checklist': [step.toJson()],
    });
    store.save(entry);
    store.readOnly = true;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EntryTile(
            entry: entry,
            now: store.clock(),
            store: store,
            onDetails: () {},
          ),
        ),
      ),
    );
    expect(
      tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).onChanged,
      null,
    );
    await tester.tap(find.text(step.title));
    await tester.pumpAndSettle();
    expect(store.find(entry.id)!.steps.single.done, false);
    expect(tester.takeException(), null);
    await tester.pumpWidget(const SizedBox());
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
  testWidgets(
    'editing Checklist keeps each remaining step identity and progress',
    (tester) async {
      final store = await loaded();
      final a = StepItem(title: 'A', done: true);
      final b = StepItem(title: 'B');
      final c = StepItem(title: 'C', done: true);
      store.save(
        Entry.create(title: '检查步骤').change({
          'checklist': [a.toJson(), b.toJson(), c.toJson()],
        }),
      );
      await tester.pumpWidget(MikansetaApp(store: store));
      await tester.pumpAndSettle();
      await tester.tap(find.text('检查步骤'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('编辑'));
      await tester.pumpAndSettle();
      final field = find.byWidgetPredicate(
        (widget) => widget is TextField && widget.controller?.text == 'A\nB\nC',
      );
      await tester.enterText(field, 'B\nC');
      await tester.tap(find.byKey(const ValueKey('save-entry')));
      await tester.pumpAndSettle();
      expect(store.entries.single.steps.map((s) => s.id), [b.id, c.id]);
      expect(store.entries.single.steps.map((s) => s.done), [false, true]);
      expect(tester.takeException(), null);
      await tester.pumpWidget(const SizedBox());
      await store.settled;
    },
  );

  test('settings version follows pubspec', () {
    final yaml = File('pubspec.yaml').readAsStringSync();
    final version = RegExp(r'version:\s*(\S+)')
        .firstMatch(yaml)!
        .group(1)!
        .split('+');
    expect(appVersion, '${version[0]} (${version[1]})');
  });
}
