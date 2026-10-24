import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mikanseta/src/domain.dart';
import 'package:mikanseta/src/note_editor_page.dart';
import 'package:mikanseta/src/store.dart';

import 'domain_test.dart' show MemoryStorage;

void main() {
  test('builtInGuideNote 生成笔记类型的内置使用说明', () {
    final now = DateTime(2026, 10, 24, 9);
    final note = EntryStore.builtInGuideNote(now);
    expect(note.kind, EntryKind.note);
    expect(note.title, '使用说明');
    expect(note.category, '帮助');
    expect(note.body, contains('# '));
    expect(note.body, contains('**'));
  });

  test('MemoryStorage 首载不播种，entries 保持为空', () async {
    final storage = MemoryStorage();
    final store = EntryStore(storage);
    await store.load();
    expect(store.entries, isEmpty);
    expect(storage.writes, isEmpty, reason: '未播种也不应写入档案文件');
  });

  testWidgets('笔记编辑页预览渲染 Markdown，切回编辑正文不丢', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = EntryStore(MemoryStorage());
    await store.load();
    final note = Entry.create(
      title: '读书笔记',
      kind: EntryKind.note,
      now: store.clock(),
    );
    await tester.pumpWidget(
      MaterialApp(home: NoteEditorPage(store: store, entry: note)),
    );
    await tester.enterText(
      find.byKey(const ValueKey('note-body')),
      '正文里有 **加粗文本** 一段',
    );
    await tester.pump();

    await tester.tap(find.byTooltip('预览'));
    await tester.pump();
    expect(find.byType(MarkdownBody), findsOneWidget);
    expect(find.byKey(const ValueKey('note-body')), findsNothing);
    // 加粗是 TextSpan，需要 findRichText 才能命中 Markdown 渲染结果。
    expect(find.textContaining('加粗文本', findRichText: true), findsOneWidget);

    await tester.tap(find.byTooltip('编辑'));
    await tester.pump();
    expect(find.byKey(const ValueKey('note-body')), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('note-body')))
          .controller!
          .text,
      '正文里有 **加粗文本** 一段',
      reason: '预览往返不应清空未保存的正文',
    );
    expect(tester.takeException(), null);
    await tester.pumpWidget(const SizedBox());
  });
}
