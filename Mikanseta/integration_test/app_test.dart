import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mikanseta/src/app.dart';
import 'package:mikanseta/src/domain.dart';
import 'package:mikanseta/src/store.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native archive, quick add, completion and timer survive reload', (
    tester,
  ) async {
    final storage = NativeStorage();
    // Only the independent beta bundle is used; preserve its existing archive.
    final before = await storage.read();
    try {
      await storage.write(Archive(entries: []).encode());
      final store = EntryStore(storage);
      await store.load();
      expect(store.readOnly, false);
      await tester.pumpWidget(MikansetaApp(store: store));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('add-entry')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('entry-title')),
        '验证测试版作业',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('补充分类、备注、Checklist 与提醒'));
      await tester.pumpAndSettle();
      for (final title in ['完成练习', '上传作业']) {
        final stepField = find.byWidgetPredicate(
          (widget) =>
              widget is TextField && widget.decoration?.hintText == '添加清单项',
        );
        await tester.ensureVisible(stepField);
        await tester.enterText(stepField, title);
        await tester.tap(find.byTooltip('添加清单项'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byKey(const ValueKey('save-entry')));
      await tester.pumpAndSettle();
      final id = store.entries.single.id;
      final stepIDs = store.find(id)!.steps.map((step) => step.id).toList();
      expect(store.find(id)!.steps.map((step) => step.title), ['完成练习', '上传作业']);
      await tester.tap(find.text('完成练习'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(find.text('1/2 项'), findsOneWidget);
      await store.settled;
      final progress = EntryStore(storage);
      await progress.load();
      expect(progress.find(id)!.steps.map((step) => step.id), stepIDs);
      expect(progress.find(id)!.steps.map((step) => step.done), [true, false]);
      expect(progress.find(id)!.completed, false);
      await tester.ensureVisible(find.byTooltip('开始计时'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('开始计时'));
      await tester.pumpAndSettle();
      expect(store.running?.id, id);
      await tester.ensureVisible(find.byTooltip('标记完成'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('标记完成'));
      await tester.pumpAndSettle();
      expect(find.text('今日已完成'), findsOneWidget);
      expect(store.find(id)!.startedAt, null);
      await store.settled;
      final restored = EntryStore(storage);
      await restored.load();
      expect(restored.find(id)!.completed, true);
      expect(restored.find(id)!.steps.map((step) => step.id), stepIDs);
      expect(restored.find(id)!.steps.map((step) => step.done), [true, true]);
      expect(restored.board.finishedToday.single.id, id);
      expect(find.text('验证测试版作业'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('settings-entry')));
      await tester.pumpAndSettle();
      // The settings page removes the header action that opened it. Detect the
      // desktop navigation from the UI that remains visible on that page.
      final desktop = find.byType(NavigationRail).evaluate().isNotEmpty;
      if (desktop) {
        final railFinder = find.byType(NavigationRail);
        expect(railFinder, findsOneWidget);
        expect(tester.widget<NavigationRail>(railFinder).selectedIndex, 5);
        await tester.tap(find.byKey(const ValueKey('desktop-tab-0')));
      } else {
        final backButton = find.byKey(const ValueKey('back-to-main'));
        expect(backButton, findsOneWidget);
        await tester.tap(backButton);
      }
      await tester.pumpAndSettle();
      if (desktop) {
        expect(
          tester
              .widget<NavigationRail>(find.byType(NavigationRail))
              .selectedIndex,
          0,
        );
      } else {
        expect(
          tester
              .widget<NavigationBar>(
                find.byKey(const ValueKey('main-tab-navigation')),
              )
              .selectedIndex,
          0,
        );
      }
      await tester.tap(find.byKey(const ValueKey('settings-entry')));
      await tester.pumpAndSettle();
      final settingsScrollable = find
          .descendant(
            of: find.byType(ListView).last,
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.text('账户同步'),
        200,
        scrollable: settingsScrollable,
      );
      expect(find.text('账户同步'), findsOneWidget);
      expect(tester.takeException(), null);
      await tester.pumpWidget(const SizedBox());
    } finally {
      // Restore any prior content even if a developer runs on their local beta.
      await storage.write(before ?? Archive(entries: []).encode());
    }
  });
}
