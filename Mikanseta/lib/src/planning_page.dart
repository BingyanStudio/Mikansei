import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'calendar_view.dart';
import 'domain.dart';
import 'haptics.dart';
import 'segmented_strip.dart';
import 'store.dart';

/// 全屏规划页。日程规划把未完成待办涂到月历日期上（plannedDays）；小时规划把
/// 当天待办拖进 24 小时时间轴（plannedStart/plannedEnd，条目保持待办类型）。
/// 循环条目的日期由重复规则生成，这里只提示并跳去现有编辑器。
class PlanningPage extends StatefulWidget {
  const PlanningPage({
    super.key,
    required this.store,
    required this.onDetails,
    required this.onEdit,
  });

  final EntryStore store;
  final ValueChanged<Entry> onDetails;
  final ValueChanged<Entry> onEdit;

  /// 小时规划时间轴每小时的高度；测试用同一常量换算落点时刻。
  static const hourHeight = 64.0;

  /// 时间轴初始停在这一小时，与日历时间轴一致。
  static const timelineStartHour = 7;

  @override
  State<PlanningPage> createState() => _PlanningPageState();
}

class _PlanningPageState extends State<PlanningPage>
    with WidgetsBindingObserver, RouteAware {
  static const cellExtent = 54.0;
  static const gridRows = 6;

  String mode = 'days';

  // 日程规划：选中的待办与已涂日期草稿（dayKey 集合），保存时一次写入。
  String? selectedTaskId;
  final draft = <String>{};
  bool? paintMode;
  late DateTime month = _currentMonth();

  // 小时规划。
  late DateTime day = dayOf(widget.store.clock());
  final gridKey = GlobalKey();
  final scroll = ScrollController(
    initialScrollOffset:
        PlanningPage.timelineStartHour * PlanningPage.hourHeight,
  );
  final _dragHaptics = HoldHaptics();
  ModalRoute<dynamic>? _route;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.store.addListener(_onStoreChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != _route) {
      if (_route != null) appRouteObserver.unsubscribe(this);
      _route = route;
      if (route != null) appRouteObserver.subscribe(this, route);
    }
  }

  @override
  void didUpdateWidget(covariant PlanningPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) {
      oldWidget.store.removeListener(_onStoreChanged);
      widget.store.addListener(_onStoreChanged);
    }
  }

  void _onStoreChanged() {
    if (widget.store.readOnly) _dragHaptics.cancel();
  }

  void _onTaskDragStarted() {
    if (!widget.store.readOnly) _dragHaptics.start();
  }

  void _onTaskDragEnded(DraggableDetails details) {
    if (widget.store.readOnly) {
      _dragHaptics.cancel();
      return;
    }
    _dragHaptics.finish(dropped: details.wasAccepted);
  }

  @override
  void didPushNext() => _dragHaptics.cancel();

  @override
  void didPop() => _dragHaptics.cancel();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _dragHaptics.cancel();
  }

  DateTime _currentMonth() {
    final now = widget.store.clock();
    return DateTime(now.year, now.month);
  }

  @override
  void dispose() {
    widget.store.removeListener(_onStoreChanged);
    WidgetsBinding.instance.removeObserver(this);
    appRouteObserver.unsubscribe(this);
    _dragHaptics.cancel();
    scroll.dispose();
    super.dispose();
  }

  Entry? get selected =>
      selectedTaskId == null ? null : widget.store.find(selectedTaskId!);

  void pick(Entry task) {
    setState(() {
      selectedTaskId = task.id;
      paintMode = null;
      draft
        ..clear()
        ..addAll(task.plannedDays.map(dayKey));
    });
    AppHaptics.change();
  }

  void savePlan() {
    final entry = selected;
    if (entry == null) return;
    widget.store.setPlannedDays(
      entry.id,
      [for (final key in draft) DateTime.parse(key)],
    );
    AppHaptics.confirm();
  }

  DateTime? _dateAt(Offset local, double cellWidth) {
    if (local.dx < 0 || local.dy < 0) return null;
    final column = (local.dx / cellWidth).floor();
    final row = (local.dy / cellExtent).floor();
    if (column >= 7 || row >= gridRows) return null;
    return DateTime(
      month.year,
      month.month,
      1 - (month.weekday - 1) + row * 7 + column,
    );
  }

  // onPanDown 在手指落下的瞬间就会触发，因此点按与起笔都走这里：先按命中
  // 的格子切换一次，之后 onPanUpdate 沿同一方向连续涂抹。
  void paintCell(Offset local, double cellWidth, {required bool start}) {
    final date = _dateAt(local, cellWidth);
    if (date == null) return;
    final key = dayKey(date);
    // 按下时记录本次涂抹是补涂还是擦除，滑动途中保持同一方向。
    if (start) paintMode = !draft.contains(key);
    if (paintMode == null) return;
    // 滑动途中同一格会收到多次回调，只有格子状态真的翻转时才刷新并给一次触觉。
    if (paintMode! ? draft.add(key) : draft.remove(key)) {
      setState(() {});
      AppHaptics.change();
    }
  }

  void acceptDrop(DragTargetDetails<Entry> details) {
    if (widget.store.readOnly) return;
    final box = gridKey.currentContext!.findRenderObject() as RenderBox;
    final local = box.globalToLocal(details.offset);
    final minute =
        ((local.dy / PlanningPage.hourHeight * 60 / 15).floor() * 15)
            .clamp(0, 24 * 60 - 30)
            .toInt();
    final start = DateTime(day.year, day.month, day.day, 0, minute);
    widget.store.setPlannedTime(
      details.data.id,
      start,
      start.add(const Duration(minutes: 30)),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('规划'),
      leading: IconButton(
        tooltip: '关闭',
        onPressed: () => Navigator.pop(context),
        icon: const Icon(Icons.close),
      ),
    ),
    body: ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) => SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
              child: SegmentedStrip<String>(
                label: '规划方式',
                choices: const ['days', 'hours'],
                selection: mode,
                identifier: (value) => 'plan-mode-$value',
                title: (value) => switch (value) {
                  'days' => '日程规划',
                  _ => '小时规划',
                },
                onChanged: (value) {
                  _dragHaptics.cancel();
                  setState(() => mode = value);
                },
              ),
            ),
            Expanded(child: mode == 'days' ? daysMode() : hoursMode()),
          ],
        ),
      ),
    ),
  );

  Widget daysMode() {
    final candidates = TaskBoard(
      widget.store.entries,
      widget.store.clock(),
    ).open;
    final selectedEntry = selected;
    final routine = selectedEntry != null && selectedEntry.repeatRule != 'never';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 4),
          child: Text(
            '选择待办，然后在月历上涂出要做的日期',
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        SizedBox(
          height: 52,
          child: candidates.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('没有未完成的待办。'),
                  ),
                )
              : ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  children: [
                    for (final task in candidates)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _TaskChip(
                          key: ValueKey('plan-task-${task.id}'),
                          label: task.title,
                          selected: task.id == selectedTaskId,
                          onTap: () => pick(task),
                        ),
                      ),
                  ],
                ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: '上个月',
                    onPressed: () => setState(() {
                      month = DateTime(month.year, month.month - 1);
                    }),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Expanded(
                    child: Text(
                      '${month.year} 年 ${month.month} 月',
                      textAlign: TextAlign.center,
                    ),
                  ),
                  IconButton(
                    tooltip: '下个月',
                    onPressed: () => setState(() {
                      month = DateTime(month.year, month.month + 1);
                    }),
                    icon: const Icon(Icons.chevron_right),
                  ),
                  TextButton(
                    onPressed: () {
                      final now = widget.store.clock();
                      setState(() => month = DateTime(now.year, now.month));
                    },
                    child: const Text('本月'),
                  ),
                ],
              ),
              Row(
                children: ['一', '二', '三', '四', '五', '六', '日']
                    .map(
                      (label) => Expanded(
                        child: Center(
                          child: Text(
                            label,
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
              LayoutBuilder(
                builder: (context, limits) {
                  final cellWidth = limits.maxWidth / 7;
                  final interactive =
                      selectedEntry != null &&
                      !routine &&
                      !widget.store.readOnly;
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanDown: interactive
                        ? (details) =>
                              paintCell(details.localPosition, cellWidth, start: true)
                        : null,
                    onPanUpdate: interactive
                        ? (details) =>
                              paintCell(details.localPosition, cellWidth, start: false)
                        : null,
                    child: paintCalendar(),
                  );
                },
              ),
              if (selectedEntry == null)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text('先在上方选择一个待办，再涂选日期。'),
                )
              else if (routine) ...[
                const SizedBox(height: 12),
                Card(
                  margin: EdgeInsets.zero,
                  child: ListTile(
                    leading: const Icon(Icons.autorenew_outlined),
                    title: Text('按重复规则自动规划：${selectedEntry.routineLabel}'),
                    subtitle: const Text('日期随循环规则出现，无需手工涂色。'),
                    trailing: TextButton(
                      onPressed: () => widget.onEdit(selectedEntry),
                      child: const Text('编辑重复'),
                    ),
                  ),
                ),
              ] else ...[
                const SizedBox(height: 16),
                Center(
                  child: FilledButton.icon(
                    key: const ValueKey('plan-save'),
                    onPressed: widget.store.readOnly ? null : savePlan,
                    icon: const Icon(Icons.event_available_outlined),
                    label: const Text('保存规划'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget paintCalendar() => Column(
    children: [
      for (var row = 0; row < gridRows; row++)
        Row(
          children: [
            for (var column = 0; column < 7; column++)
              Expanded(
                child: dayCell(
                  DateTime(
                    month.year,
                    month.month,
                    1 - (month.weekday - 1) + row * 7 + column,
                  ),
                ),
              ),
          ],
        ),
    ],
  );

  Widget dayCell(DateTime date) {
    final scheme = Theme.of(context).colorScheme;
    final key = dayKey(date);
    final painted = draft.contains(key);
    final outside = date.month != month.month;
    final today = sameDay(date, dayOf(widget.store.clock()));
    return SizedBox(
      height: cellExtent,
      child: Container(
        key: ValueKey('plan-day-$key'),
        margin: const EdgeInsets.all(3),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: painted ? scheme.primary : null,
          borderRadius: BorderRadius.circular(12),
          border: today && !painted ? Border.all(color: scheme.primary) : null,
        ),
        child: Text(
          '${date.day}',
          style: TextStyle(
            fontSize: 13,
            fontWeight: painted || today ? FontWeight.w600 : null,
            color: painted
                ? scheme.onPrimary
                : outside
                ? scheme.onSurfaceVariant
                : scheme.onSurface,
          ),
        ),
      ),
    );
  }

  Widget hoursMode() {
    final now = widget.store.clock();
    final scheme = Theme.of(context).colorScheme;
    final hourHeight = PlanningPage.hourHeight;
    final board = TaskBoard(widget.store.entries, day);
    final todos = board.focus
        .where((e) => !e.completed && e.start == null)
        .toList();
    final items = calendarItems(widget.store.entries, day);
    final blocks = layoutTimeline(items, day);
    final floating = items
        .where((item) => item.deadline || item.allDay)
        .toList();
    final lanes = blocks.isEmpty
        ? 1
        : blocks.map((block) => block.columns).reduce(math.max);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 148,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
                child: Text(
                  sameDay(day, now)
                      ? '今日待办'
                      : '${dateLabel(day, time: false)} 待办',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              Expanded(
                child: todos.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          '这一天没有需要安排时间的待办。',
                          style: TextStyle(fontSize: 12),
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                        children: [
                          for (final todo in todos)
                            _TodoCard(
                              entry: todo,
                              readOnly: widget.store.readOnly,
                              onDetails: () => widget.onDetails(todo),
                              onDragStarted: _onTaskDragStarted,
                              onDragEnd: _onTaskDragEnded,
                            ),
                        ],
                      ),
              ),
            ],
          ),
        ),
        Container(width: 1, color: scheme.outline.withValues(alpha: .15)),
        Expanded(
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: '前一天',
                    onPressed: () {
                      _dragHaptics.cancel();
                      setState(() {
                        day = DateTime(day.year, day.month, day.day - 1);
                      });
                    },
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Expanded(
                    child: Text(
                      '${dateLabel(day, time: false)} '
                      '${['周一', '周二', '周三', '周四', '周五', '周六', '周日'][day.weekday - 1]}',
                      textAlign: TextAlign.center,
                    ),
                  ),
                  IconButton(
                    tooltip: '后一天',
                    onPressed: () {
                      _dragHaptics.cancel();
                      setState(() {
                        day = DateTime(day.year, day.month, day.day + 1);
                      });
                    },
                    icon: const Icon(Icons.chevron_right),
                  ),
                  TextButton(
                    onPressed: sameDay(day, now)
                        ? null
                        : () {
                            _dragHaptics.cancel();
                            setState(() => day = dayOf(now));
                          },
                    child: const Text('今天'),
                  ),
                ],
              ),
              if (floating.isNotEmpty)
                SizedBox(
                  height: 30,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    children: [
                      for (final item in floating)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainer,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${item.deadline ? 'DDL ${clockLabel(item.start)}' : '全天'} '
                              '${item.entry.title}',
                              style: const TextStyle(fontSize: 11),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              Expanded(
                child: DragTarget<Entry>(
                  key: const ValueKey('plan-drop'),
                  onWillAcceptWithDetails: (details) =>
                      details.data.isTask && !widget.store.readOnly,
                  onAcceptWithDetails: acceptDrop,
                  builder: (_, _, _) => LayoutBuilder(
                    builder: (context, limits) {
                      final laneWidth = (limits.maxWidth - 52) / lanes;
                      return SingleChildScrollView(
                        controller: scroll,
                        child: SizedBox(
                          key: gridKey,
                          height: 24 * hourHeight,
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: CustomPaint(
                                  painter: _HourGridPainter(
                                    44,
                                    scheme.outline.withValues(alpha: .25),
                                  ),
                                ),
                              ),
                              for (var hour = 0; hour < 24; hour++)
                                Positioned(
                                  top: hour * hourHeight,
                                  left: 4,
                                  child: IgnorePointer(
                                    child: Text(
                                      '${hour.toString().padLeft(2, '0')}:00',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: scheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                ),
                              if (sameDay(day, now))
                                Positioned(
                                  top:
                                      now.difference(dayOf(now)).inSeconds /
                                      3600 *
                                      hourHeight,
                                  left: 44,
                                  right: 4,
                                  child: IgnorePointer(
                                    child: Container(
                                      height: 2,
                                      color: scheme.error,
                                    ),
                                  ),
                                ),
                              for (final block in blocks)
                                _planBlock(block, laneWidth, scheme),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(6),
                child: Text(
                  '长按左侧待办，拖到时间轴上放下 · 15 分钟对齐',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _planBlock(TimelineBlock block, double laneWidth, ColorScheme scheme) {
    final item = block.item;
    final isSchedule = item.entry.kind == EntryKind.schedule;
    final hourHeight = PlanningPage.hourHeight;
    return Positioned(
      top: block.start / 60 * hourHeight,
      left: 46 + block.column * laneWidth + 2,
      width: math.max(8, laneWidth - 4),
      height: math.max(30, (block.end - block.start) / 60 * hourHeight - 2),
      child: Material(
        color: isSchedule ? scheme.primaryContainer : scheme.secondaryContainer,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: isSchedule
              ? BorderSide.none
              : BorderSide(color: scheme.secondary),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => widget.onDetails(item.owner),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
            child: Row(
              children: [
                if (!isSchedule) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: scheme.secondary,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '待办',
                      style: TextStyle(
                        fontSize: 9,
                        height: 1.5,
                        color: scheme.onSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
                Expanded(
                  child: Text(
                    '${clockLabel(item.start)} ${item.entry.title}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: isSchedule
                          ? scheme.onPrimaryContainer
                          : scheme.onSecondaryContainer,
                      decoration: item.owner.completed
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 日程规划候选条里的待办胶囊。
class _TaskChip extends StatelessWidget {
  const _TaskChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? scheme.primary : scheme.surfaceContainer,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Text(
            label,
            maxLines: 1,
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected ? scheme.onPrimary : scheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

/// 小时规划左栏的待办卡片，长按拖入右侧时间轴。
class _TodoCard extends StatelessWidget {
  const _TodoCard({
    required this.entry,
    required this.readOnly,
    required this.onDetails,
    required this.onDragStarted,
    required this.onDragEnd,
  });

  final Entry entry;
  final bool readOnly;
  final VoidCallback onDetails;
  final VoidCallback onDragStarted;
  final ValueChanged<DraggableDetails> onDragEnd;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final card = Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onDetails,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(entry.title, maxLines: 2, overflow: TextOverflow.ellipsis),
              if (entry.due != null)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    'DDL ${dateLabel(entry.due!)}',
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    // 只读档案不能拖拽规划，直接给出普通卡片。
    if (readOnly) return card;
    return LongPressDraggable<Entry>(
      data: entry,
      hapticFeedbackOnStart: false,
      onDragStarted: onDragStarted,
      onDragEnd: onDragEnd,
      // 让落点偏移等于手指位置，时间轴才能按指尖换算时刻。
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(12),
        color: scheme.primaryContainer,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            entry.title,
            maxLines: 1,
            style: TextStyle(color: scheme.onPrimaryContainer),
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: .4, child: card),
      child: card,
    );
  }
}

class _HourGridPainter extends CustomPainter {
  _HourGridPainter(this.labelWidth, this.color);

  final double labelWidth;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = .6;
    for (var hour = 0; hour <= 24; hour++) {
      final y = hour * PlanningPage.hourHeight;
      canvas.drawLine(Offset(labelWidth, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _HourGridPainter old) =>
      old.color != color || old.labelWidth != labelWidth;
}
