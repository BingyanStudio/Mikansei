import 'package:flutter/material.dart';

import 'calendar_view.dart';
import 'domain.dart';
import 'entry_widgets.dart';
import 'segmented_strip.dart';
import 'store.dart';
import 'student_tools.dart';
import 'theme.dart';

enum _TaskFilter { all, task, schedule, homework, routine }

extension on _TaskFilter {
  String get label => switch (this) {
    _TaskFilter.all => '全部',
    _TaskFilter.task => '待办',
    _TaskFilter.schedule => '日程',
    _TaskFilter.homework => '作业',
    _TaskFilter.routine => '常态',
  };

  bool includes(Entry entry) => switch (this) {
    _TaskFilter.all => entry.isTask,
    _TaskFilter.task => entry.kind == EntryKind.task,
    _TaskFilter.schedule => entry.kind == EntryKind.schedule,
    _TaskFilter.homework => entry.kind == EntryKind.homework,
    _TaskFilter.routine => entry.isTask && entry.isRoutineSeriesMember,
  };

  EntryKind get entryKind => switch (this) {
    _TaskFilter.schedule => EntryKind.schedule,
    _TaskFilter.homework => EntryKind.homework,
    _ => EntryKind.task,
  };
}

class TaskWorkspacePage extends StatefulWidget {
  const TaskWorkspacePage({
    super.key,
    required this.store,
    required this.searchFocus,
    required this.onEdit,
    required this.onOpen,
    required this.onDetails,
    required this.onAdd,
    required this.onContextChanged,
  });

  final EntryStore store;
  final FocusNode searchFocus;
  final ValueChanged<Entry> onEdit;
  final ValueChanged<Entry> onOpen;
  final ValueChanged<Entry> onDetails;
  final ValueChanged<EntryKind> onAdd;
  final ValueChanged<EntryKind> onContextChanged;

  @override
  State<TaskWorkspacePage> createState() => _TaskWorkspacePageState();
}

class _TaskWorkspacePageState extends State<TaskWorkspacePage> {
  String query = '';
  String category = '';
  bool history = false;
  _TaskFilter filter = _TaskFilter.all;
  final searchController = TextEditingController();

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = widget.store.clock();
    final board = TaskBoard(widget.store.entries, now);
    final all = history ? board.history : board.visible;
    final entries = all
        .where(
          (entry) =>
              filter.includes(entry) &&
              entry.matches(query) &&
              (category.isEmpty || entry.category == category),
        )
        .toList();
    if (!history) {
      int groupOrder(Entry entry) {
        if (entry.completed) return 3;
        if (entry.overdue(now)) return 0;
        return entry.startedAt == null ? 2 : 1;
      }

      entries.sort((a, b) {
        final group = groupOrder(a).compareTo(groupOrder(b));
        return group == 0 ? entryOrder(a, b) : group;
      });
    }
    final categories =
        widget.store.entries
            .where((entry) => entry.isTask && entry.category.isNotEmpty)
            .map((entry) => entry.category)
            .toSet()
            .toList()
          ..sort();
    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: const ValueKey('todo-search'),
          focusNode: widget.searchFocus,
          controller: searchController,
          onChanged: (value) => setState(() => query = value),
          decoration: InputDecoration(
            hintText: '搜索事项、平台或地点',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: query.isEmpty
                ? null
                : IconButton(
                    tooltip: '清除搜索',
                    onPressed: () {
                      searchController.clear();
                      setState(() => query = '');
                    },
                    icon: const Icon(Icons.close),
                  ),
          ),
        ),
        const SizedBox(height: 12),
        SegmentedStrip<_TaskFilter>(
          label: '事项类型',
          choices: _TaskFilter.values,
          selection: filter,
          identifier: (value) => 'todo-filter-${value.name}',
          title: (value) => value.label,
          onChanged: (value) {
            setState(() => filter = value);
            widget.onContextChanged(value.entryKind);
          },
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: SegmentedStrip<bool>(
                label: '清单状态',
                choices: const [false, true],
                selection: history,
                identifier: (value) => value ? 'todo-history' : 'todo-current',
                title: (value) => value ? '历史' : '当前清单',
                onChanged: (value) => setState(() => history = value),
              ),
            ),
            const SizedBox(width: 10),
            PopupMenuButton<String>(
              key: const ValueKey('todo-category-filter'),
              constraints: const BoxConstraints(maxWidth: 180),
              tooltip: '按分类筛选',
              onSelected: (value) => setState(() => category = value),
              itemBuilder: (context) => [
                CheckedPopupMenuItem(
                  value: '',
                  checked: category.isEmpty,
                  child: const Text('全部分类'),
                ),
                for (final value in categories)
                  CheckedPopupMenuItem(
                    value: value,
                    checked: category == value,
                    child: Text(value),
                  ),
              ],
              child: Container(
                constraints: const BoxConstraints(maxWidth: 150),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.filter_list, size: 18),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        category.isEmpty ? '分类' : category,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        if (entries.isEmpty)
          EmptyState(
            icon: history ? Icons.history : Icons.checklist_rounded,
            title: query.isNotEmpty
                ? '没有找到相关事项'
                : history
                ? '历史记录会在次日出现'
                : '清单里还没有事项',
            message: history
                ? '今天完成的事项会留在当前清单，次日归入历史。'
                : '先记下标题即可；可以稍后补时间、分类和子项。',
          ),
      ],
    );
    return AnimatedEntryList(
      key: const ValueKey('todo-entry-list'),
      entries: entries,
      now: now,
      store: widget.store,
      onEdit: widget.onEdit,
      onOpen: widget.onOpen,
      onDetails: widget.onDetails,
      showGroups: !history,
      reorderable: !history && !widget.store.readOnly,
      header: header,
    );
  }
}

enum _ScheduleSection { focus, list, calendar }

class ScheduleWorkspacePage extends StatefulWidget {
  const ScheduleWorkspacePage({
    super.key,
    required this.store,
    required this.onEdit,
    required this.onOpen,
    required this.onDetails,
    required this.onAdd,
    required this.onCreateOnDate,
    required this.onContextChanged,
    required this.onPlanning,
    this.focusRouteRevision = 0,
  });

  final EntryStore store;
  final ValueChanged<Entry> onEdit;
  final ValueChanged<Entry> onOpen;
  final ValueChanged<Entry> onDetails;
  final ValueChanged<EntryKind> onAdd;
  final void Function(DateTime start, DateTime end) onCreateOnDate;
  final ValueChanged<EntryKind> onContextChanged;
  final VoidCallback onPlanning;
  final int focusRouteRevision;

  @override
  State<ScheduleWorkspacePage> createState() => _ScheduleWorkspacePageState();
}

class _ScheduleWorkspacePageState extends State<ScheduleWorkspacePage> {
  _ScheduleSection section = _ScheduleSection.focus;

  @override
  void didUpdateWidget(covariant ScheduleWorkspacePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusRouteRevision != widget.focusRouteRevision) {
      section = _ScheduleSection.focus;
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = widget.store.clock();
    final board = TaskBoard(widget.store.entries, now);
    final focusTodayIDs = board.focusTodayIDs;
    final focusEntries = [...board.focus]
      ..sort((a, b) {
        int rank(Entry entry) {
          if (entry.completed) return 3;
          if (entry.overdue(now)) return 0;
          return focusTodayIDs.contains(entry.id) ? 1 : 2;
        }

        final result = rank(a).compareTo(rank(b));
        return result == 0 ? entryOrder(a, b) : result;
      });
    final pageHeader = Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                dateLabel(now, time: false),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            TextButton.icon(
              key: const ValueKey('planning-open'),
              onPressed: widget.store.readOnly ? null : widget.onPlanning,
              icon: const Icon(Icons.event_note_outlined),
              label: const Text('规划'),
            ),
            const SizedBox(width: 4),
            PopupMenuButton<String>(
              key: const ValueKey('schedule-more'),
              tooltip: '更多日程工具',
              onSelected: (value) {
                if (value == 'courses') {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => CoursesPage(store: widget.store),
                    ),
                  );
                }
                if (value == 'add-schedule' && !widget.store.readOnly) {
                  widget.onAdd(EntryKind.schedule);
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'courses', child: Text('课表与下课登记')),
                PopupMenuItem(value: 'add-schedule', child: Text('新建日程')),
              ],
              icon: const Icon(Icons.more_vert),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SegmentedStrip<_ScheduleSection>(
          label: '日程视图',
          choices: _ScheduleSection.values,
          selection: section,
          identifier: (value) =>
              'schedule-view-${_ScheduleSection.values.indexOf(value)}',
          title: (value) => switch (value) {
            _ScheduleSection.focus => '今日聚焦',
            _ScheduleSection.list => '列表',
            _ScheduleSection.calendar => '日历',
          },
          onChanged: (value) {
            setState(() => section = value);
            widget.onContextChanged(EntryKind.schedule);
          },
        ),
      ],
    );

    final focusPage = AnimatedEntryList(
      key: const ValueKey('schedule-focus-list'),
      entries: focusEntries,
      now: now,
      store: widget.store,
      onEdit: widget.onEdit,
      onOpen: widget.onOpen,
      onDetails: widget.onDetails,
      showGroups: true,
      reorderable: !widget.store.readOnly,
      focusGroups: true,
      focusTodayIDs: focusTodayIDs,
      moveToPlanning: true,
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.store.running case final Entry running)
            _RunningFocusCard(
              entry: running,
              now: now,
              store: widget.store,
              onOpen: () => widget.onOpen(running),
            ),
          if (focusEntries.isEmpty)
            _EmptyAction(
              icon: Icons.wb_sunny_outlined,
              title: '今天可以从容一点',
              message: '安排一件小事，或继续你的无日期待办。',
              action: '添加待办',
              onPressed: widget.store.readOnly
                  ? null
                  : () => widget.onAdd(EntryKind.task),
            ),
        ],
      ),
    );

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
          child: pageHeader,
        ),
        Expanded(
          child: IndexedStack(
            index: section.index,
            children: [
              TickerMode(
                enabled: section == _ScheduleSection.focus,
                child: focusPage,
              ),
              TickerMode(
                enabled: section == _ScheduleSection.list,
                child: _AgendaList(
                  store: widget.store,
                  now: now,
                  onOpen: widget.onOpen,
                  onAdd: () => widget.onAdd(EntryKind.schedule),
                ),
              ),
              TickerMode(
                enabled: section == _ScheduleSection.calendar,
                child: ScheduleCalendar(
                  store: widget.store,
                  onOpen: widget.onOpen,
                  onCreate: widget.onCreateOnDate,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RunningFocusCard extends StatelessWidget {
  const _RunningFocusCard({
    required this.entry,
    required this.now,
    required this.store,
    required this.onOpen,
  });

  final Entry entry;
  final DateTime now;
  final EntryStore store;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final palette = MikanseiPalette.of(context);
    return Card(
      color: palette.entryBackground(entry),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: palette.entryBorder(entry), width: 1.5),
      ),
      margin: const EdgeInsets.only(top: 12),
      child: ListTile(
        onTap: onOpen,
        leading: Icon(Icons.timelapse, color: palette.accent),
        title: Text(
          '正在做 · ${entry.title}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Ticking(
          builder: (context) =>
              Text(durationLabel(entry.focusSeconds(store.clock()))),
        ),
        trailing: IconButton(
          tooltip: '暂停计时',
          onPressed: store.readOnly ? null : () => store.focus(entry.id),
          icon: const Icon(Icons.pause_rounded),
        ),
      ),
    );
  }
}

class _AgendaList extends StatelessWidget {
  const _AgendaList({
    required this.store,
    required this.now,
    required this.onOpen,
    required this.onAdd,
  });

  final EntryStore store;
  final DateTime now;
  final ValueChanged<Entry> onOpen;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final itemsByKey = <String, CalendarItem>{};
    final open = TaskBoard(store.entries, now).open;
    for (final entry in open) {
      if (entry.start case final start?) {
        itemsByKey['${entry.id}/plan/${start.millisecondsSinceEpoch}'] =
            CalendarItem(entry, entry, start, entry.end);
      }
      if (entry.due case final due?) {
        itemsByKey['${entry.id}/ddl/${due.millisecondsSinceEpoch}'] =
            CalendarItem(entry, entry, due, null, deadline: true);
      }
    }
    final grouped = <DateTime, List<CalendarItem>>{};
    for (final item in itemsByKey.values) {
      (grouped[dayOf(item.start)] ??= []).add(item);
    }
    for (final items in grouped.values) {
      items.sort((a, b) => a.start.compareTo(b.start));
    }
    final dates = grouped.keys.toList()..sort();
    return ListView(
      key: const ValueKey('schedule-agenda-list'),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      children: [
        if (dates.isEmpty)
          _EmptyAction(
            icon: Icons.calendar_month_outlined,
            title: '日程还是空白的',
            message: '已安排的时段和截止时间会显示在这里。',
            action: '添加日程',
            onPressed: store.readOnly ? null : onAdd,
          )
        else
          for (final date in dates) ...[
            Padding(
              padding: const EdgeInsets.only(top: 20, bottom: 8),
              child: Text(
                '${dateLabel(date, time: false)}${sameDay(date, now) ? ' · 今天' : ''}',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            for (final item in grouped[date]!)
              _AgendaItem(item: item, onTap: () => onOpen(item.owner)),
          ],
      ],
    );
  }
}

class _AgendaItem extends StatelessWidget {
  const _AgendaItem({required this.item, required this.onTap});
  final CalendarItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = MikanseiPalette.of(context);
    final color = item.deadline ? palette.warm : palette.accent;
    final label = item.deadline
        ? '截止 · ${dateLabel(item.start)}'
        : '执行 · ${item.allDay ? '全天' : '${clockLabel(item.start)}${item.end == null ? '' : '–${clockLabel(item.end!)}'}'}';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        key: ValueKey('agenda-${item.key}'),
        leading: Icon(
          item.deadline ? Icons.flag_outlined : Icons.event_outlined,
          color: color,
        ),
        title: Text(item.entry.title),
        subtitle: Text(label, style: TextStyle(color: color)),
        onTap: onTap,
      ),
    );
  }
}

class _EmptyAction extends StatelessWidget {
  const _EmptyAction({
    required this.icon,
    required this.title,
    required this.message,
    required this.action,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String message;
  final String action;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(top: 16, bottom: 12),
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Icon(icon, size: 36, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 12),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 14),
          FilledButton.tonal(onPressed: onPressed, child: Text(action)),
        ],
      ),
    ),
  );
}

class NotesWorkspacePage extends StatefulWidget {
  const NotesWorkspacePage({
    super.key,
    required this.store,
    required this.searchFocus,
    required this.onEdit,
    required this.onOpen,
    required this.onDetails,
    required this.onAdd,
  });

  final EntryStore store;
  final FocusNode searchFocus;
  final ValueChanged<Entry> onEdit;
  final ValueChanged<Entry> onOpen;
  final ValueChanged<Entry> onDetails;
  final ValueChanged<EntryKind> onAdd;

  @override
  State<NotesWorkspacePage> createState() => _NotesWorkspacePageState();
}

class _NotesWorkspacePageState extends State<NotesWorkspacePage> {
  String query = '';

  @override
  Widget build(BuildContext context) {
    final entries =
        widget.store.entries
            .where(
              (entry) => entry.kind == EntryKind.note && entry.matches(query),
            )
            .toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return AnimatedEntryList(
      key: const ValueKey('notes-entry-list'),
      entries: entries,
      now: widget.store.clock(),
      store: widget.store,
      onEdit: widget.onEdit,
      onOpen: widget.onOpen,
      onDetails: widget.onDetails,
      showGroups: false,
      header: Column(
        children: [
          TextField(
            key: const ValueKey('notes-search'),
            focusNode: widget.searchFocus,
            onChanged: (value) => setState(() => query = value),
            decoration: const InputDecoration(
              hintText: '搜索笔记与清单',
              prefixIcon: Icon(Icons.search),
            ),
          ),
          if (entries.isEmpty)
            _EmptyAction(
              icon: Icons.note_alt_outlined,
              title: query.isEmpty ? '给想法留一个位置' : '没有找到相关笔记',
              message: '随手记录灵感、课堂重点，或一份旅行清单。',
              action: '写一条笔记',
              onPressed: widget.store.readOnly
                  ? null
                  : () => widget.onAdd(EntryKind.note),
            ),
        ],
      ),
    );
  }
}
