import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mikanseta/src/app.dart';
import 'package:mikanseta/src/cloud_sync.dart';
import 'package:mikanseta/src/domain.dart';
import 'package:mikanseta/src/local_folder_sync.dart';
import 'package:mikanseta/src/store.dart';
import 'package:mikanseta/src/theme.dart';

import 'cloud_sync_test.dart' show FakeCloudBackend;
import 'domain_test.dart' show MemoryStorage;
import 'local_folder_sync_test.dart' show FakeLocalSyncBackend;

void main() {
  Future<EntryStore> loaded() async {
    final store = EntryStore(MemoryStorage());
    await store.load();
    return store;
  }

  Future<void> pumpEntryList(
    WidgetTester tester,
    EntryStore store, {
    TargetPlatform? platform,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: platform == null
            ? null
            : KraftTheme.build(Brightness.light).copyWith(platform: platform),
        home: Scaffold(
          body: AnimatedBuilder(
            animation: store,
            builder: (context, _) => AnimatedEntryList(
              entries: store.entries,
              now: store.clock(),
              store: store,
              onDetails: (_) {},
              showGroups: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
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
  testWidgets('completion stays consistent through grouped list reordering', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = await loaded();
    final first = Entry.create(title: '事项甲');
    final second = Entry.create(title: '事项乙');
    final step = StepItem(title: '核对清单');
    final third = Entry.create(title: '事项丙').change({
      'checklist': [step.toJson()],
    });
    store
      ..save(first)
      ..save(second)
      ..save(third);
    await pumpEntryList(tester, store);

    void expectCardState(String title, {required bool completed}) {
      final card = find
          .ancestor(of: find.text(title), matching: find.byType(Card))
          .first;
      expect(
        tester
            .widget<IconButton>(
              find
                  .descendant(of: card, matching: find.byType(IconButton))
                  .first,
            )
            .tooltip,
        completed ? '恢复未完成' : '标记完成',
        reason: '$title 的完成按钮状态',
      );
      expect(
        find.descendant(
          of: card,
          matching: find.byIcon(
            completed ? Icons.check_circle : Icons.radio_button_unchecked,
          ),
        ),
        findsOneWidget,
        reason: '$title 的完成图标',
      );
      final rendered = DefaultTextStyle.of(tester.element(find.text(title)))
          .style;
      expect(
        rendered.decoration,
        completed
            ? TextDecoration.lineThrough
            : isNot(TextDecoration.lineThrough),
        reason: '$title 的实际渲染文字样式',
      );
    }

    expectCardState('事项甲', completed: false);
    final firstCard = find
        .ancestor(of: find.text('事项甲'), matching: find.byType(Card))
        .first;
    await tester.tap(
      find.descendant(of: firstCard, matching: find.byTooltip('标记完成')),
    );
    await tester.pump();
    expect(find.text('今日已完成'), findsOneWidget);
    expectCardState('事项甲', completed: true);
    expect(find.text('事项甲'), findsOneWidget);
    expect(find.text(step.title), findsOneWidget);
    await tester.pumpAndSettle();
    expectCardState('事项甲', completed: true);
    expect(find.text('事项甲'), findsOneWidget);

    final completedCard = find
        .ancestor(of: find.text('事项甲'), matching: find.byType(Card))
        .first;
    await tester.tap(
      find.descendant(of: completedCard, matching: find.byTooltip('恢复未完成')),
    );
    await tester.pump();
    expect(find.text('今日已完成'), findsNothing);
    expectCardState('事项甲', completed: false);
    expect(find.text('事项甲'), findsOneWidget);
    await tester.pumpAndSettle();
    expectCardState('事项甲', completed: false);
    expect(find.text('事项甲'), findsOneWidget);
    expect(tester.takeException(), null);
    await tester.pumpWidget(const SizedBox());
    await store.settled;
  });
  testWidgets(
    'rapid grouped completions stay consistent across Material platforms',
    (tester) async {
      tester.view.physicalSize = const Size(390, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const platforms = [
        TargetPlatform.android,
        TargetPlatform.iOS,
        TargetPlatform.macOS,
        TargetPlatform.windows,
      ];

      for (final platform in platforms) {
        final store = await loaded();
        final entries = List.generate(
          8,
          (index) => Entry.create(title: '快速${index + 1}'),
        );
        for (final entry in entries) {
          store.save(entry);
        }
        await pumpEntryList(tester, store, platform: platform);

        for (final entry in entries.take(7)) {
          store.toggle(entry.id);
          await tester.pump(const Duration(milliseconds: 60));
          final movingTiles = tester
              .widgetList<EntryTile>(find.byType(EntryTile))
              .where((tile) => tile.entry.title == entry.title);
          expect(movingTiles, isNotEmpty);
          for (final tile in movingTiles) {
            expect(
              tile.entry.completed,
              true,
              reason: '$platform ${entry.title} 的动画快照不应停留在未完成状态',
            );
            final tileFinder = find.byWidget(tile);
            expect(
              find.descendant(
                of: tileFinder,
                matching: find.byTooltip('恢复未完成'),
              ),
              findsOneWidget,
              reason: '$platform ${entry.title} 的动画图标应更新',
            );
          }
        }
        await tester.pumpAndSettle();

        for (final (index, entry) in entries.indexed) {
          final completed = index < 7;
          expect(
            store.find(entry.id)!.completed,
            completed,
            reason: '$platform ${entry.title} 的存储状态应一致',
          );
          expect(
            find.text(entry.title),
            findsOneWidget,
            reason: '$platform ${entry.title} 稳定后应只有一张卡片',
          );
          final card = find
              .ancestor(of: find.text(entry.title), matching: find.byType(Card))
              .first;
          expect(
            find.descendant(
              of: card,
              matching: find.byIcon(
                completed ? Icons.check_circle : Icons.radio_button_unchecked,
              ),
            ),
            findsOneWidget,
            reason: '$platform ${entry.title} 的完成图标应一致',
          );
          expect(
            DefaultTextStyle.of(tester.element(find.text(entry.title)))
                .style
                .decoration,
            completed
                ? TextDecoration.lineThrough
                : isNot(TextDecoration.lineThrough),
            reason: '$platform ${entry.title} 的删除线应一致',
          );
        }
        expect(tester.takeException(), null);
        await tester.pumpWidget(const SizedBox());
        await store.settled;
      }
    },
  );
  testWidgets(
    'checklist completion and same-id external replacement keep card state',
    (tester) async {
      tester.view.physicalSize = const Size(390, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = await loaded();
      final step = StepItem(title: '外部同步清单');
      final entry = Entry.create(title: '外部甲').change({
        'checklist': [step.toJson()],
      });
      store
        ..save(entry)
        ..save(Entry.create(title: '外部乙'));
      await pumpEntryList(tester, store);

      void expectState(String title, {required bool completed}) {
        expect(find.text(title), findsOneWidget);
        final card = find
            .ancestor(of: find.text(title), matching: find.byType(Card))
            .first;
        expect(
          find.descendant(
            of: card,
            matching: find.byIcon(
              completed ? Icons.check_circle : Icons.radio_button_unchecked,
            ),
          ),
          findsOneWidget,
        );
        expect(
          DefaultTextStyle.of(tester.element(find.text(title)))
              .style
              .decoration,
          completed
              ? TextDecoration.lineThrough
              : isNot(TextDecoration.lineThrough),
        );
      }

      store.toggle(entry.id);
      await tester.pump(const Duration(milliseconds: 60));
      expect(store.find(entry.id)!.completed, true);

      final replacement = store.find(entry.id)!.change({'title': '外部甲已替换'});
      expect(
        store.applyCloudArchive(Archive(entries: [replacement]).encode()),
        true,
      );
      await tester.pumpAndSettle();
      expect(find.text('外部甲'), findsNothing);
      expectState('外部甲已替换', completed: true);
      expect(
        tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        true,
      );
      expect(find.text('今日已完成'), findsOneWidget);

      store.toggle(entry.id);
      await tester.pumpAndSettle();
      expectState('外部甲已替换', completed: false);
      expect(find.text('今日已完成'), findsNothing);
      expect(tester.takeException(), null);
      await tester.pumpWidget(const SizedBox());
      await store.settled;
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

  testWidgets('settings shows the account section when unconfigured', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = await loaded();
    await tester.pumpWidget(MikansetaApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('账户同步'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('账户同步'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.textContaining('未配置 Supabase 账户服务'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('未配置 Supabase 账户服务'), findsOneWidget);
    expect(tester.takeException(), null);
    await tester.pumpWidget(const SizedBox());
    await store.settled;
  });

  testWidgets('account login sends a code and signs in from settings', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = await loaded();
    final backend = FakeCloudBackend();
    final cloud = CloudSync(
      store,
      backend,
      pushDelay: Duration.zero,
      pullDelay: Duration.zero,
    );
    store.onLocalWrite = cloud.schedulePush;
    await tester.pumpWidget(MikansetaApp(store: store, cloud: cloud));
    await tester.pumpAndSettle();
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    final emailField = find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.labelText == '邮箱',
    );
    await tester.scrollUntilVisible(
      emailField,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(emailField, 'me@example.com');
    await tester.ensureVisible(find.text('发送验证码'));
    await tester.tap(find.text('发送验证码'));
    await tester.pumpAndSettle();
    expect(find.textContaining('验证码（已发送至 me@example.com）'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byType(TextField).last,
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(find.byType(TextField).last, '123456');
    await tester.ensureVisible(find.text('登录'));
    await tester.tap(find.text('登录'));
    await tester.pumpAndSettle();
    expect(cloud.email, 'me@example.com');
    expect(find.text('me@example.com'), findsOneWidget);
    expect(find.text('退出登录'), findsOneWidget);
    expect(tester.takeException(), null);
    store.onLocalWrite = null;
    cloud.dispose();
    await tester.pumpWidget(const SizedBox());
    await store.settled;
  });

  testWidgets('notes open a full page editor with unsaved-change guard', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = await loaded();
    await tester.pumpWidget(MikansetaApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('笔记'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('添加事项'));
    await tester.pumpAndSettle();
    // 全页编辑器：不再是浮窗 Dialog。
    expect(find.byType(Dialog), findsNothing);
    expect(find.byKey(const ValueKey('note-title')), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('note-title')), '读书笔记');
    await tester.enterText(find.byKey(const ValueKey('note-body')), '先拆成小步骤');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('note-save')));
    await tester.pumpAndSettle();
    expect(find.text('读书笔记'), findsOneWidget);
    await store.settled;

    // 打开已有笔记：直接进入全页；未保存修改时退出会确认。
    await tester.tap(find.text('读书笔记'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(find.byKey(const ValueKey('note-body')), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('note-body')),
      '先拆成小步骤，再开始第一步',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    expect(find.text('放弃未保存的修改？'), findsOneWidget);
    await tester.tap(find.text('继续编辑'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('note-save')));
    await tester.pumpAndSettle();
    expect(find.text('读书笔记'), findsOneWidget);
    expect(store.entries.single.body, '先拆成小步骤，再开始第一步');
    expect(tester.takeException(), null);
    await store.settled;
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('settings connects a shared folder for local sync', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = await loaded();
    final backend = FakeLocalSyncBackend();
    final localSync = LocalFolderSync(
      store,
      backend,
      exchangeDelay: Duration.zero,
      period: null,
    );
    await localSync.whenReady;
    await tester.pumpWidget(MikansetaApp(store: store, localSync: localSync));
    await tester.pumpAndSettle();
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('本机同步（与 Mikansei）'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('共享文件夹自动同步'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('选择共享文件夹'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('选择共享文件夹'));
    await tester.pumpAndSettle();
    expect(find.text('Mikansei Cloud'), findsOneWidget);
    expect(find.text('立即同步'), findsOneWidget);
    expect(tester.takeException(), null);
    localSync.dispose();
    await tester.pumpWidget(const SizedBox());
    await store.settled;
  });
}
