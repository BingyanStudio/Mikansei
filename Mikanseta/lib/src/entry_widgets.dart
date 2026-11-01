import 'dart:async';

import 'package:flutter/material.dart';

import 'android_system.dart';
import 'domain.dart';
import 'haptics.dart';
import 'store.dart';
import 'theme.dart';

/// 清单主体。分组标题行与条目行交错成一张行表：标题行没有拖拽监听，条目行
/// 长按拖动后按同组内的新次序调 store.reorder（sortOrder API）。
/// 之前这里用 AnimatedList 做插入/离场动画，但那些动画与拖动重排互斥，且
/// 离场快照会在完成动画期间展示过期内容（0.4.4 的问题）；改用
/// ReorderableListView 后条目始终直接渲染当前数据，快照问题随之消失。
class AnimatedEntryList extends StatefulWidget {
  const AnimatedEntryList({
    super.key,
    required this.entries,
    required this.now,
    required this.store,
    required this.onDetails,
    required this.showGroups,
    this.reorderable = false,
    this.onEdit,
    this.onOpen,
    this.header,
    this.focusTodayIDs = const <String>{},
    this.focusGroups = false,
    this.moveToPlanning = false,
  });
  final List<Entry> entries;
  final DateTime now;
  final EntryStore store;
  final ValueChanged<Entry> onDetails;
  final ValueChanged<Entry>? onEdit;
  final bool showGroups;
  final ValueChanged<Entry>? onOpen;
  final Widget? header;
  final Set<String> focusTodayIDs;
  final bool focusGroups;
  final bool moveToPlanning;

  /// 只在今日与我的清单开启长按拖动排序，其余页面保持纯列表。
  final bool reorderable;

  @override
  State<AnimatedEntryList> createState() => _AnimatedEntryListState();
}

class _AnimatedEntryListState extends State<AnimatedEntryList>
    with WidgetsBindingObserver, RouteAware {
  final _holdHaptics = HoldHaptics();
  ModalRoute<dynamic>? _route;
  int? _dragStartIndex;
  bool _lastCanReorder = false;

  bool get _canReorder => widget.reorderable && !widget.store.readOnly;

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
  void didUpdateWidget(covariant AnimatedEntryList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) {
      oldWidget.store.removeListener(_onStoreChanged);
      widget.store.addListener(_onStoreChanged);
    }
    if (_lastCanReorder && !_canReorder) _abortDrag();
  }

  void _onStoreChanged() {
    if (widget.store.readOnly) _abortDrag();
  }

  void _abortDrag() {
    _holdHaptics.cancel();
    _dragStartIndex = null;
  }

  void _onReorderStart(int index) {
    if (!_canReorder) return;
    _dragStartIndex = index;
    _holdHaptics.start();
  }

  void _onReorderEnd(int _) {
    final start = _dragStartIndex;
    _dragStartIndex = null;
    if (start == null) return;
    if (!_canReorder) {
      _holdHaptics.cancel();
      return;
    }
    // onReorderEnd means the drag was released; unchanged positions still get
    // a drop confirmation, while pointer cancellation never reaches this path.
    _holdHaptics.finish(dropped: true);
  }

  void _onPointerCancel() => _abortDrag();

  @override
  void didPushNext() => _abortDrag();

  @override
  void didPop() => _abortDrag();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _abortDrag();
  }

  @override
  void dispose() {
    widget.store.removeListener(_onStoreChanged);
    WidgetsBinding.instance.removeObserver(this);
    appRouteObserver.unsubscribe(this);
    _holdHaptics.cancel();
    super.dispose();
  }

  String group(Entry e) {
    if (widget.focusGroups) {
      if (e.completed) return '今日已完成';
      if (e.overdue(widget.now)) return '已超时';
      return widget.focusTodayIDs.contains(e.id) ? '今天要做' : '随时可做';
    }
    if (e.completed) return '今日已完成';
    if (e.overdue(widget.now)) return '已超时';
    return e.startedAt == null ? '待完成' : '正在做';
  }

  @override
  Widget build(BuildContext context) {
    final entries = widget.entries;
    final now = widget.now;
    final store = widget.store;
    final onDetails = widget.onDetails;
    final showGroups = widget.showGroups;
    final canReorder = _canReorder;
    _lastCanReorder = canReorder;
    final scheme = Theme.of(context).colorScheme;
    final rows = <_ListRow>[
      if (widget.header != null) _ListRow.header(widget.header!),
      for (var index = 0; index < entries.length; index++) ...[
        if (showGroups &&
            (index == 0 || group(entries[index - 1]) != group(entries[index])))
          // boundary 记下标题前那条条目的 id：同一分组标签可能出现两次
          // （条目顺序不保证分组连续时），key 必须唯一。
          _ListRow.heading(
            group(entries[index]),
            index == 0 ? 'start' : entries[index - 1].id,
          ),
        _ListRow.entry(entries[index]),
      ],
    ];
    return Listener(
      onPointerUp: (_) => _holdHaptics.stopPulses(),
      onPointerCancel: (_) => _onPointerCancel(),
      child: ReorderableListView.builder(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        buildDefaultDragHandles: false,
        itemCount: rows.length,
        onReorderItem: (oldIndex, newIndex) =>
            _reorder(rows, oldIndex, newIndex),
        onReorderStart: canReorder ? _onReorderStart : null,
        onReorderEnd: canReorder ? _onReorderEnd : null,
        proxyDecorator: (child, index, animation) => Material(
          color: Colors.transparent,
          elevation: 4,
          borderRadius: BorderRadius.circular(18),
          child: child,
        ),
        itemBuilder: (context, index) {
          final row = rows[index];
          final entry = row.entry;
          if (entry != null) {
            final tile = Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: EntryTile(
                entry: entry,
                now: now,
                store: store,
                onDetails: () => onDetails(entry),
                onEdit: () => (widget.onEdit ?? widget.onDetails)(entry),
                onOpen: () =>
                    (widget.onOpen ?? widget.onEdit ?? widget.onDetails)(entry),
              ),
            );
            Widget child = tile;
            if (widget.moveToPlanning &&
                entry.isTask &&
                !entry.completed &&
                !entry.isInPlanning &&
                !store.readOnly) {
              child = Dismissible(
                key: ValueKey('planning-swipe-${entry.id}'),
                direction: DismissDirection.endToStart,
                background: const SizedBox.shrink(),
                secondaryBackground: Container(
                  alignment: Alignment.centerRight,
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Icon(Icons.calendar_month_outlined),
                      SizedBox(width: 8),
                      Text('移到规划'),
                    ],
                  ),
                ),
                confirmDismiss: (_) async =>
                    !store.readOnly && store.moveToPlanning(entry.id),
                child: child,
              );
            }
            return canReorder && !entry.completed
                ? ReorderableDelayedDragStartListener(
                    key: ValueKey(entry.id),
                    index: index,
                    child: child,
                  )
                : KeyedSubtree(key: ValueKey(entry.id), child: child);
          }
          if (row.header != null) {
            return KeyedSubtree(
              key: const ValueKey('entry-list-header'),
              child: row.header!,
            );
          }
          final heading = row.heading!;
          final palette = MikanseiPalette.of(context);
          final headingColor = switch (heading) {
            '已超时' => palette.error,
            '正在做' || '今天要做' => palette.accent,
            '今日已完成' => palette.completed,
            '随时可做' => palette.secondary,
            _ => scheme.primary,
          };
          return KeyedSubtree(
            key: ValueKey('heading-$heading-${row.boundary}'),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(3, 14, 0, 10),
              child: Row(
                children: [
                  Text(
                    heading,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontSize: 13,
                      letterSpacing: .3,
                      color: headingColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: headingColor.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${entries.where((e) => group(e) == heading).length}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: headingColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// onReorderItem 的落点按“先移除条目再插入”计。这里数出落点之前有几个
  /// 同组条目：标题行不计入，落点跨过分组标题时自然夹回本组开头或结尾，
  /// 条目始终留在自己的分组内，按组内新次序写入 sortOrder。
  void _reorder(List<_ListRow> rows, int oldIndex, int newIndex) {
    if (!_canReorder) return;
    final dragged = rows[oldIndex].entry;
    if (dragged == null || dragged.completed) return;
    final without = List.of(rows)..removeAt(oldIndex);
    var after = 0;
    for (var i = 0; i < newIndex && i < without.length; i++) {
      final row = without[i].entry;
      if (row != null && group(row) == group(dragged)) after++;
    }
    // after 统计的是“移除被拖条目后”落点之前的同组数量，构造新次序时
    // 也要先把被拖条目从成员里摘出来，避免同一个编号写两次 sortOrder。
    final others = [
      for (final e in widget.entries)
        if (group(e) == group(dragged) && e.id != dragged.id) e.id,
    ];
    widget.store.reorder([
      ...others.sublist(0, after),
      dragged.id,
      ...others.sublist(after),
    ]);
  }
}

class _ListRow {
  const _ListRow.heading(this.heading, this.boundary)
    : entry = null,
      header = null;
  const _ListRow.entry(this.entry)
    : heading = null,
      boundary = null,
      header = null;
  const _ListRow.header(this.header)
    : heading = null,
      boundary = null,
      entry = null;
  final String? heading;

  /// 标题行 key 的边界记号（前一条条目 id 或 'start'），保证唯一。
  final String? boundary;
  final Entry? entry;
  final Widget? header;
}

class EntryTile extends StatelessWidget {
  const EntryTile({
    super.key,
    required this.entry,
    required this.now,
    required this.store,
    required this.onDetails,
    this.onEdit,
    this.onOpen,
  });
  final Entry entry;
  final DateTime now;
  final EntryStore store;
  final VoidCallback onDetails;
  final VoidCallback? onEdit;
  final VoidCallback? onOpen;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final palette = MikanseiPalette.of(context);
    final overdue = entry.overdue(now);
    final running = entry.startedAt != null && !entry.completed;
    final textColor = entry.completed ? palette.completed : scheme.onSurface;
    final metaColor = entry.completed
        ? palette.completed
        : overdue
        ? palette.error
        : scheme.onSurfaceVariant;
    final tags = [
      if (entry.category.isNotEmpty) entry.category,
      if (entry.platform.isNotEmpty) entry.platform,
      if (entry.location.isNotEmpty) entry.location,
      if (entry.isRoutine) entry.routineLabel,
    ];
    Widget meta(IconData icon, String text, Color color) => Text.rich(
      TextSpan(
        style: TextStyle(fontSize: 12, color: color),
        children: [
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Icon(icon, size: 12.5, color: color),
          ),
          TextSpan(text: ' $text'),
        ],
      ),
      softWrap: true,
    );
    // 已超时的 DDL 段用 error 填充小胶囊，比裸文字更醒目。
    Widget ddlPill(String text) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: palette.error,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text.rich(
        TextSpan(
          style: TextStyle(fontSize: 12, color: scheme.onError),
          children: [
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Icon(Icons.schedule, size: 12.5, color: scheme.onError),
            ),
            TextSpan(text: ' $text'),
          ],
        ),
        softWrap: true,
      ),
    );
    return Card(
      color: running ? palette.entryBackground(entry) : null,
      shape: running
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(color: palette.entryBorder(entry), width: 1.5),
            )
          : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onOpen ?? onEdit ?? onDetails,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 6, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (entry.isTask)
                IconButton(
                  tooltip: entry.completed ? '恢复未完成' : '标记完成',
                  iconSize: 24,
                  style: IconButton.styleFrom(
                    fixedSize: const Size(44, 44),
                    padding: EdgeInsets.zero,
                  ),
                  onPressed: store.readOnly
                      ? null
                      : () {
                          if (entry.completed) {
                            AppHaptics.change();
                          } else {
                            AppHaptics.confirm();
                          }
                          store.toggle(entry.id);
                        },
                  icon: Icon(
                    entry.completed
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    color: scheme.primary,
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: palette.warm.withValues(alpha: .14),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.notes, size: 19, color: palette.warm),
                  ),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AnimatedDefaultTextStyle(
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 220),
                      style: Theme.of(context).textTheme.titleMedium!.copyWith(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        decoration: entry.completed
                            ? TextDecoration.lineThrough
                            : null,
                        color: textColor,
                      ),
                      child: Text(
                        entry.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 10,
                      runSpacing: 3,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        meta(
                          switch (entry.kind) {
                            EntryKind.task => Icons.check_circle_outline,
                            EntryKind.schedule => Icons.calendar_today_outlined,
                            EntryKind.homework => Icons.menu_book_outlined,
                            EntryKind.note => Icons.notes,
                          },
                          entry.kind.label,
                          palette.entryKind(entry.kind),
                        ),
                        if (entry.priority > 0)
                          meta(
                            Icons.flag_outlined,
                            priorities[entry.priority],
                            entry.priority == 2 ? palette.error : palette.warm,
                          ),
                        if (entry.start != null)
                          meta(
                            Icons.calendar_today_outlined,
                            '执行 ${dateLabel(entry.start!, time: !entry.allDay)}${entry.allDay
                                ? ' 全天'
                                : entry.end == null
                                ? ''
                                : '–${clockLabel(entry.end!)}'}',
                            palette.accent,
                          ),
                        if (entry.due != null)
                          overdue
                              ? ddlPill('DDL ${dateLabel(entry.due!)}')
                              : meta(
                                  Icons.flag_outlined,
                                  'DDL ${dateLabel(entry.due!)}',
                                  palette.warm,
                                ),
                        if (entry.start == null &&
                            entry.due == null &&
                            entry.isTask)
                          meta(Icons.schedule, '未设时间', metaColor),
                      ],
                    ),
                    if (tags.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          tags.join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: metaColor),
                        ),
                      ),
                    if (entry.body.trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          entry.body.trim(),
                          maxLines: entry.kind == EntryKind.note ? 3 : 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13, color: metaColor),
                        ),
                      ),
                    const SizedBox(height: 8),
                    _InlineChecklist(entry: entry, store: store),
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(
                        children: [
                          if (entry.isTask && !entry.completed)
                            IconButton(
                              tooltip: entry.startedAt == null
                                  ? '开始计时'
                                  : '暂停计时',
                              iconSize: 22,
                              style: IconButton.styleFrom(
                                fixedSize: const Size(40, 40),
                                padding: EdgeInsets.zero,
                              ),
                              onPressed: store.readOnly
                                  ? null
                                  : () {
                                      AppHaptics.change();
                                      store.focus(entry.id);
                                    },
                              icon: Icon(
                                entry.startedAt == null
                                    ? Icons.play_arrow_rounded
                                    : Icons.pause_rounded,
                                color: scheme.primary,
                              ),
                            ),
                          if (entry.isTask &&
                              (entry.startedAt != null ||
                                  entry.focusSeconds(now) > 0))
                            Expanded(
                              child: entry.startedAt == null
                                  ? meta(
                                      Icons.timer_outlined,
                                      '用时 ${durationLabel(entry.focusSeconds(now))}',
                                      palette.accent,
                                    )
                                  : Ticking(
                                      builder: (context) => meta(
                                        Icons.timer_outlined,
                                        '正在做 · ${durationLabel(entry.focusSeconds(store.clock()))}',
                                        palette.accent,
                                      ),
                                    ),
                            )
                          else
                            const Spacer(),
                          PopupMenuButton<String>(
                            tooltip: '更多操作',
                            onSelected: (value) {
                              if (value == 'details') onDetails();
                              if (value == 'edit') (onEdit ?? onDetails)();
                              if (value == 'planning' && !store.readOnly) {
                                store.moveToPlanning(entry.id);
                              }
                              if (value == 'delete' && !store.readOnly) {
                                showDialog<void>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text('删除这条事项？'),
                                    content: const Text('仅删除这条记录，其他循环事项会保留。'),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(context),
                                        child: const Text('取消'),
                                      ),
                                      TextButton(
                                        onPressed: () {
                                          store.delete(entry.id);
                                          Navigator.pop(context);
                                        },
                                        child: const Text('删除'),
                                      ),
                                    ],
                                  ),
                                );
                              }
                            },
                            itemBuilder: (context) => [
                              PopupMenuItem(
                                value: 'edit',
                                enabled:
                                    !store.readOnly ||
                                    entry.kind != EntryKind.note,
                                child: const Text('编辑'),
                              ),
                              const PopupMenuItem(
                                value: 'details',
                                child: Text('查看详情'),
                              ),
                              if (entry.isTask &&
                                  !entry.completed &&
                                  !entry.isInPlanning &&
                                  !store.readOnly)
                                const PopupMenuItem(
                                  value: 'planning',
                                  child: Text('移到规划'),
                                ),
                              if (!store.readOnly)
                                const PopupMenuItem(
                                  value: 'delete',
                                  child: Text('删除'),
                                ),
                            ],
                            icon: const Icon(Icons.more_horiz),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InlineChecklist extends StatefulWidget {
  const _InlineChecklist({required this.entry, required this.store});
  final Entry entry;
  final EntryStore store;

  @override
  State<_InlineChecklist> createState() => _InlineChecklistState();
}

class _InlineChecklistState extends State<_InlineChecklist> {
  final _newStep = TextEditingController();
  bool _pendingStepsExpanded = true;
  bool _completedStepsExpanded = false;

  @override
  void dispose() {
    _newStep.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _InlineChecklist oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldPendingIDs = oldWidget.entry.steps
        .where((step) => !step.done)
        .map((step) => step.id)
        .join(',');
    final newPendingIDs = widget.entry.steps
        .where((step) => !step.done)
        .map((step) => step.id)
        .join(',');
    if (oldPendingIDs != newPendingIDs) _pendingStepsExpanded = true;
  }

  void _addStep() {
    final title = _newStep.text.trim();
    final current = widget.store.find(widget.entry.id);
    if (title.isEmpty || current == null || widget.store.readOnly) return;
    final steps = [...current.steps, StepItem(title: title)];
    final changes = <String, Object?>{
      'checklist': steps.map((step) => step.toJson()).toList(),
    };
    if (current.isTask && current.completed) {
      changes['isCompleted'] = false;
      changes['completedAt'] = null;
    }
    widget.store.save(current.change(changes, now: widget.store.clock()));
    _newStep.clear();
    if (mounted) setState(() => _pendingStepsExpanded = true);
    AppHaptics.change();
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final store = widget.store;
    final steps = entry.steps;
    final pendingSteps = steps.where((step) => !step.done).toList();
    final completedSteps = steps.where((step) => step.done).toList();
    final scheme = Theme.of(context).colorScheme;
    final palette = MikanseiPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (steps.isNotEmpty)
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 64,
                child: LinearProgressIndicator(
                  value: completedSteps.length / steps.length,
                  color: palette.entryKind(entry.kind),
                  minHeight: 3,
                  borderRadius: BorderRadius.circular(2),
                  semanticsLabel:
                      '${entry.title}的子事项进度，已完成 ${completedSteps.length} 项，共 ${steps.length} 项',
                ),
              ),
              Text(
                '${completedSteps.length}/${steps.length} 项',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        if (pendingSteps.isNotEmpty) ...[
          TextButton.icon(
            key: ValueKey('checklist-pending-toggle-${entry.id}'),
            onPressed: () =>
                setState(() => _pendingStepsExpanded = !_pendingStepsExpanded),
            icon: Icon(
              _pendingStepsExpanded ? Icons.expand_less : Icons.expand_more,
              size: 18,
            ),
            label: Text(
              '${_pendingStepsExpanded ? '收起待办' : '显示待办'} · ${pendingSteps.length} 项',
            ),
            style: TextButton.styleFrom(
              foregroundColor: scheme.onSurfaceVariant,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              minimumSize: const Size(0, 36),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          if (_pendingStepsExpanded)
            ...pendingSteps.map(
              (step) => _stepTile(entry, step, store, scheme),
            ),
        ],
        if (completedSteps.isNotEmpty) ...[
          TextButton.icon(
            key: ValueKey('checklist-completed-toggle-${entry.id}'),
            onPressed: () => setState(
              () => _completedStepsExpanded = !_completedStepsExpanded,
            ),
            icon: Icon(
              _completedStepsExpanded ? Icons.expand_less : Icons.expand_more,
              size: 18,
            ),
            label: Text(
              '${_completedStepsExpanded ? '收起已完成' : '显示已完成'} · ${completedSteps.length} 项',
            ),
            style: TextButton.styleFrom(
              foregroundColor: scheme.onSurfaceVariant,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              minimumSize: const Size(0, 36),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          if (_completedStepsExpanded)
            ...completedSteps.map(
              (step) => _stepTile(entry, step, store, scheme),
            ),
        ],
        TextField(
          key: ValueKey('inline-new-step-${entry.id}'),
          controller: _newStep,
          enabled: !store.readOnly,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _addStep(),
          decoration: InputDecoration(
            hintText: '添加子项',
            prefixIcon: const Icon(Icons.add, size: 18),
            suffixIcon: IconButton(
              tooltip: '添加子项',
              onPressed: store.readOnly ? null : _addStep,
              icon: const Icon(Icons.arrow_upward_rounded, size: 18),
            ),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 8,
            ),
          ),
        ),
      ],
    );
  }

  Widget _stepTile(
    Entry entry,
    StepItem step,
    EntryStore store,
    ColorScheme scheme,
  ) => CheckboxListTile(
    key: ValueKey('inline-step-${entry.id}-${step.id}'),
    contentPadding: EdgeInsets.zero,
    controlAffinity: ListTileControlAffinity.leading,
    dense: true,
    visualDensity: VisualDensity.compact,
    value: step.done,
    title: Text(
      step.title,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        decoration: step.done ? TextDecoration.lineThrough : null,
        color: step.done ? scheme.onSurfaceVariant : scheme.onSurface,
      ),
    ),
    onChanged: store.readOnly
        ? null
        : (_) {
            AppHaptics.change();
            store.toggleStep(entry.id, step.id);
          },
  );
}

class EntryDetails extends StatelessWidget {
  const EntryDetails({
    super.key,
    required this.store,
    required this.id,
    required this.onEdit,
  });
  final EntryStore store;
  final String id;
  final VoidCallback onEdit;
  @override
  Widget build(BuildContext context) => Ticking(
    builder: (context) => ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final entry = store.find(id);
        if (entry == null) return const AlertDialog(content: Text('事项已删除。'));
        return Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 580),
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            entry.title,
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                        ),
                        IconButton(
                          tooltip: '关闭',
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      [
                        entry.kind.label,
                        priorities[entry.priority],
                        entry.category,
                      ].where((s) => s.isNotEmpty).join(' · '),
                    ),
                    if (entry.due != null)
                      detail('截止时间', dateLabel(entry.due!)),
                    if ([
                      'https',
                      'http',
                    ].contains(Uri.tryParse(entry.platform)?.scheme))
                      TextButton.icon(
                        onPressed: () async {
                          try {
                            await NativeStorage.invokeMethod(
                              'openExternalURL',
                              entry.platform,
                            );
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('无法打开链接：$e')),
                              );
                            }
                          }
                        },
                        icon: const Icon(Icons.open_in_new),
                        label: const Text('打开提交平台'),
                      ),
                    if (entry.start != null)
                      detail(
                        '开始时间',
                        '${dateLabel(entry.start!)}${entry.allDay ? ' 全天' : ''}',
                      ),
                    if (entry.end != null)
                      detail('结束时间', dateLabel(entry.end!)),
                    if (entry.platform.isNotEmpty)
                      detail('处理平台', entry.platform),
                    if (entry.location.isNotEmpty)
                      detail('处理地点', entry.location),
                    if (entry.estimate != null)
                      detail('预计用时', '${entry.estimate} 分钟'),
                    if (entry.body.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      SelectableText(entry.body),
                    ],
                    if (entry.steps.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      const Text(
                        'Checklist',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      ...entry.steps.map(
                        (s) => CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          value: s.done,
                          title: Text(
                            s.title,
                            style: TextStyle(
                              decoration: s.done
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          ),
                          onChanged: store.readOnly
                              ? null
                              : (_) {
                                  AppHaptics.change();
                                  store.toggleStep(id, s.id);
                                },
                        ),
                      ),
                    ],
                    if (entry.source.isNotEmpty) detail('来源', entry.source),
                    if (entry.isRoutine) detail('循环', entry.routineLabel),
                    if (entry.isTask)
                      detail(
                        '累计专注',
                        durationLabel(entry.focusSeconds(store.clock())),
                      ),
                    if (AndroidSystem.supported && entry.isTask)
                      AndroidEntryActions(entry: entry, store: store),
                    const SizedBox(height: 20),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          onPressed: store.readOnly
                              ? null
                              : () {
                                  Navigator.pop(context);
                                  onEdit();
                                },
                          icon: const Icon(Icons.edit_outlined),
                          label: const Text('编辑'),
                        ),
                        if (entry.isTask)
                          OutlinedButton(
                            onPressed: store.readOnly
                                ? null
                                : () {
                                    if (entry.completed) {
                                      AppHaptics.change();
                                    } else {
                                      AppHaptics.confirm();
                                    }
                                    store.toggle(id);
                                  },
                            child: Text(entry.completed ? '恢复未完成' : '标记完成'),
                          ),
                        if (entry.isTask && !entry.completed)
                          OutlinedButton(
                            onPressed: store.readOnly
                                ? null
                                : () {
                                    AppHaptics.change();
                                    store.focus(id);
                                  },
                            child: Text(
                              entry.startedAt == null ? '开始计时' : '暂停计时',
                            ),
                          ),
                        TextButton(
                          onPressed: store.readOnly
                              ? null
                              : () async {
                                  final confirmed = await showDialog<bool>(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                      title: const Text('删除这条事项？'),
                                      content: const Text('仅删除这条记录，其他循环事项会保留。'),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(context, false),
                                          child: const Text('取消'),
                                        ),
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(context, true),
                                          child: const Text('删除'),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (confirmed == true && context.mounted) {
                                    store.delete(id);
                                    Navigator.pop(context);
                                  }
                                },
                          child: const Text('删除'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
  Widget detail(String label, String text) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Text('$label · $text'),
  );
}

class EntryInspector extends StatelessWidget {
  const EntryInspector({
    super.key,
    required this.entry,
    required this.store,
    required this.onEdit,
    required this.onDetails,
  });

  final Entry entry;
  final EntryStore store;
  final VoidCallback onEdit;
  final VoidCallback onDetails;

  @override
  Widget build(BuildContext context) {
    final palette = MikanseiPalette.of(context);
    final focusSeconds = entry.focusSeconds(store.clock());
    return ListView(
      key: const ValueKey('entry-inspector'),
      padding: const EdgeInsets.all(28),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                entry.title,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            IconButton.filledTonal(
              tooltip: '编辑',
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: '查看详情与系统操作',
              onPressed: onDetails,
              icon: const Icon(Icons.open_in_full),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Chip(
              avatar: Icon(
                switch (entry.kind) {
                  EntryKind.task => Icons.check_circle_outline,
                  EntryKind.schedule => Icons.calendar_today_outlined,
                  EntryKind.homework => Icons.menu_book_outlined,
                  EntryKind.note => Icons.notes,
                },
                size: 18,
                color: palette.entryKind(entry.kind),
              ),
              label: Text(entry.kind.label),
            ),
            if (entry.category.isNotEmpty) Chip(label: Text(entry.category)),
            if (entry.priority > 0)
              Chip(label: Text(priorities[entry.priority])),
          ],
        ),
        const SizedBox(height: 14),
        if (entry.start != null)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.event_outlined, color: palette.accent),
            title: const Text('执行时间'),
            subtitle: Text(
              '${dateLabel(entry.start!, time: !entry.allDay)}${entry.allDay
                  ? ' · 全天'
                  : entry.end == null
                  ? ''
                  : ' – ${dateLabel(entry.end!)}'}',
            ),
          ),
        if (entry.due != null)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.flag_outlined, color: palette.warm),
            title: const Text('截止时间'),
            subtitle: Text(dateLabel(entry.due!)),
          ),
        if (entry.isTask && (entry.startedAt != null || focusSeconds > 0))
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.timer_outlined, color: palette.accent),
            title: const Text('专注用时'),
            subtitle: entry.startedAt == null
                ? Text('用时 ${durationLabel(focusSeconds)}')
                : Ticking(
                    builder: (context) => Text(
                      '正在做 · ${durationLabel(entry.focusSeconds(store.clock()))}',
                    ),
                  ),
          ),
        if (entry.location.isNotEmpty)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.place_outlined),
            title: const Text('地点'),
            subtitle: Text(entry.location),
          ),
        if (entry.platform.isNotEmpty)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.link),
            title: const Text('平台'),
            subtitle: Text(entry.platform),
          ),
        if (entry.body.isNotEmpty) ...[
          const SizedBox(height: 12),
          SelectableText(entry.body),
        ],
        if (entry.steps.isNotEmpty) ...[
          const SizedBox(height: 18),
          Text('子项', style: Theme.of(context).textTheme.titleMedium),
          for (final step in entry.steps)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: step.done,
              title: Text(
                step.title,
                style: TextStyle(
                  decoration: step.done ? TextDecoration.lineThrough : null,
                ),
              ),
              onChanged: store.readOnly
                  ? null
                  : (_) => store.toggleStep(entry.id, step.id),
            ),
        ],
        if (entry.isTask) ...[
          const SizedBox(height: 18),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: store.readOnly ? null : () => store.toggle(entry.id),
                icon: Icon(
                  entry.completed
                      ? Icons.undo_rounded
                      : Icons.check_circle_outline,
                ),
                label: Text(entry.completed ? '重新打开' : '标记完成'),
              ),
              if (!entry.completed)
                OutlinedButton.icon(
                  onPressed: store.readOnly
                      ? null
                      : () => store.focus(entry.id),
                  icon: Icon(
                    entry.startedAt == null
                        ? Icons.play_arrow_rounded
                        : Icons.pause_rounded,
                  ),
                  label: Text(entry.startedAt == null ? '开始计时' : '暂停计时'),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class Ticking extends StatefulWidget {
  const Ticking({super.key, required this.builder});
  final WidgetBuilder builder;
  @override
  State<Ticking> createState() => _TickingState();
}

class _TickingState extends State<Ticking> {
  Timer? timer;
  bool? tickingEnabled;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final enabled = TickerMode.valuesOf(context).enabled;
    if (tickingEnabled == enabled) return;
    tickingEnabled = enabled;
    timer?.cancel();
    timer = enabled
        ? Timer.periodic(const Duration(seconds: 1), (_) {
            if (mounted) setState(() {});
          })
        : null;
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
  });
  final IconData icon;
  final String title;
  final String message;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 34, horizontal: 18),
    child: Column(
      children: [
        Icon(icon, size: 38, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 14),
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    ),
  );
}
