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
      await tester.tap(find.byTooltip('添加事项'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('entry-title')),
        '验证测试版作业',
      );
      await tester.tap(find.byKey(const ValueKey('save-entry')));
      await tester.pumpAndSettle();
      final id = store.entries.single.id;
      await tester.tap(find.byTooltip('开始计时'));
      await tester.pumpAndSettle();
      expect(store.running?.id, id);
      await tester.tap(find.byTooltip('标记完成'));
      await tester.pumpAndSettle();
      expect(find.text('今日已完成'), findsOneWidget);
      expect(store.find(id)!.startedAt, null);
      await store.settled;
      final restored = EntryStore(storage);
      await restored.load();
      expect(restored.find(id)!.completed, true);
      expect(restored.board.finishedToday.single.id, id);
      await tester.tap(find.text('我的清单'));
      await tester.pumpAndSettle();
      expect(find.text('验证测试版作业'), findsOneWidget);
      await tester.tap(find.text('设置'));
      await tester.pumpAndSettle();
      expect(find.text('Flutter 测试版 · 牛皮浅棕'), findsOneWidget);
      expect(tester.takeException(), null);
      await tester.pumpWidget(const SizedBox());
    } finally {
      // Restore any prior content even if a developer runs on their local beta.
      await storage.write(before ?? Archive(entries: []).encode());
    }
  });
}
