import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mikanseta/src/app.dart';
import 'package:mikanseta/src/domain.dart';
import 'package:mikanseta/src/planning_page.dart';
import 'package:mikanseta/src/store.dart';

import 'domain_test.dart' show MemoryStorage;

void main() {
  Future<EntryStore> loaded() async {
    final store = EntryStore(MemoryStorage());
    await store.load();
    return store;
  }

  // 从今日页 AppBar 进入全屏规划页。
  Future<void> pumpPlanning(WidgetTester tester, EntryStore store) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MikansetaApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('规划'));
    await tester.pumpAndSettle();
  }

  testWidgets('planning page opens day and hour modes', (tester) async {
    final store = await loaded();
    store.save(Entry.create(title: '背单词'));
    await pumpPlanning(tester, store);
    expect(find.text('日程规划'), findsOneWidget);
    expect(find.text('小时规划'), findsOneWidget);
    // 日程规划：候选条与月历。
    expect(find.text('背单词'), findsOneWidget);
    expect(find.byTooltip('上个月'), findsOneWidget);
    await tester.tap(find.text('小时规划'));
    await tester.pumpAndSettle();
    expect(find.text('今日待办'), findsOneWidget);
    expect(find.text('背单词'), findsOneWidget);
    expect(find.byTooltip('前一天'), findsOneWidget);
    await tester.tap(find.text('日程规划'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('上个月'), findsOneWidget);
    expect(tester.takeException(), null);
    await tester.pumpWidget(const SizedBox());
    await store.settled;
  });

  testWidgets('painting two days and saving writes plannedDays', (
    tester,
  ) async {
    final store = await loaded();
    final entry = Entry.create(title: '规划我');
    store.save(entry);
    await pumpPlanning(tester, store);
    await tester.tap(find.text('规划我'));
    await tester.pumpAndSettle();
    final now = DateTime.now();
    final dayA = DateTime(now.year, now.month, 5);
    final dayB = DateTime(now.year, now.month, 8);
    await tester.tap(find.byKey(ValueKey('plan-day-${dayKey(dayA)}')));
    await tester.pump();
    await tester.tap(find.byKey(ValueKey('plan-day-${dayKey(dayB)}')));
    await tester.pump();
    // 已涂日期用 primary 填充格。
    final paintedContext = tester.element(
      find.byKey(ValueKey('plan-day-${dayKey(dayA)}')),
    );
    final paintedDecoration =
        tester
            .widget<Container>(find.byKey(ValueKey('plan-day-${dayKey(dayA)}')))
            .decoration! as BoxDecoration;
    expect(
      paintedDecoration.color,
      Theme.of(paintedContext).colorScheme.primary,
    );
    await tester.tap(find.byKey(const ValueKey('plan-save')));
    await tester.pumpAndSettle();
    final saved = store.find(entry.id)!;
    expect(saved.kind, EntryKind.task);
    // setPlannedDays 去重并按日期升序保存。
    expect(saved.data['plannedDays'], [dayKey(dayA), dayKey(dayB)]);
    expect(tester.takeException(), null);
    await tester.pumpWidget(const SizedBox());
    await store.settled;
  });

  testWidgets('hour planning drags a todo onto the timeline', (tester) async {
    final store = await loaded();
    final entry = Entry.create(title: '拖我');
    store.save(entry);
    await pumpPlanning(tester, store);
    await tester.tap(find.text('小时规划'));
    await tester.pumpAndSettle();
    expect(find.text('今日待办'), findsOneWidget);
    // 长按左栏待办（超过 kLongPressTimeout）进入拖拽。
    final startCenter = tester.getCenter(find.text('拖我'));
    final gesture = await tester.startGesture(startCenter);
    await tester.pump(const Duration(milliseconds: 600));
    final dropRect = tester.getRect(find.byKey(const ValueKey('plan-drop')));
    await gesture.moveBy(dropRect.center - startCenter);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    // 落点换算：时间轴初始停在 7 点（timelineStartHour），落点在拖放区中心。
    const hourHeight = PlanningPage.hourHeight;
    final gridDy =
        dropRect.center.dy - dropRect.top +
        PlanningPage.timelineStartHour * hourHeight;
    final minute = ((gridDy / hourHeight * 60 / 15).floor() * 15)
        .clamp(0, 24 * 60 - 30)
        .toInt();
    final now = DateTime.now();
    final expectedStart = DateTime(
      now.year,
      now.month,
      now.day,
    ).add(Duration(minutes: minute));
    final saved = store.find(entry.id)!;
    expect(saved.kind, EntryKind.task);
    expect(saved.start, expectedStart);
    expect(saved.end, expectedStart.add(const Duration(minutes: 30)));
    // 左栏待办消失，时间轴出现块。
    expect(find.text('拖我'), findsNothing);
    expect(find.textContaining('拖我'), findsOneWidget);
    expect(tester.takeException(), null);
    await tester.pumpWidget(const SizedBox());
    await store.settled;
  });
}
