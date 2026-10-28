import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'domain.dart';
import 'haptics.dart';
import 'segmented_strip.dart';
import 'store.dart';

class CalendarItem {
  const CalendarItem(
    this.owner,
    this.entry,
    this.start,
    this.end, {
    this.deadline = false,
  });
  final Entry owner, entry;
  final DateTime start;
  final DateTime? end;
  final bool deadline;
  bool get allDay => !deadline && entry.allDay;
  String get key =>
      '${owner.id}/${deadline ? 'ddl' : 'plan'}/${start.millisecondsSinceEpoch}';
}

/// Expand routines without saving copies or inventing completion records.
List<CalendarItem> calendarItems(
  List<Entry> entries,
  DateTime day, {
  bool showCompleted = true,
}) {
  final from = dayOf(day), to = DateTime(day.year, day.month, day.day + 1);
  final successors = <String, DateTime>{};
  for (final e in entries) {
    final previous = e.data['previousOccurrenceID'] as String?;
    final date = e.recurrenceDate;
    if (previous != null &&
        date != null &&
        (successors[previous] == null ||
            date.isBefore(successors[previous]!))) {
      successors[previous] = date;
    }
  }
  final items = <CalendarItem>[];
  for (final owner in entries.where(
    (e) => e.isTask && (showCompleted || !e.completed),
  )) {
    final instances = <Entry>[owner];
    if (owner.repeatRule != 'never' &&
        !owner.completed &&
        owner.recurrenceDate != null) {
      var lower = from.subtract(
        owner.end != null && owner.start != null
            ? owner.end!.difference(owner.start!)
            : const Duration(days: 1),
      );
      if (lower.isBefore(owner.recurrenceDate!)) lower = owner.recurrenceDate!;
      for (var count = 0; count < 64; count++) {
        final occurrence = owner.nextOccurrence(lower);
        final reference = occurrence?.recurrenceDate;
        if (occurrence == null ||
            reference == null ||
            !reference.isBefore(to) ||
            successors[owner.id] != null &&
                !reference.isBefore(successors[owner.id]!)) {
          break;
        }
        instances.add(occurrence);
        lower = reference;
      }
    }
    for (final e in instances) {
      if (e.start != null &&
          e.end != null &&
          e.start!.isBefore(to) &&
          e.end!.isAfter(from)) {
        items.add(CalendarItem(owner, e, e.start!, e.end));
      }
      if (e.due != null && !e.due!.isBefore(from) && e.due!.isBefore(to)) {
        items.add(CalendarItem(owner, e, e.due!, null, deadline: true));
      }
    }
  }
  items.sort(
    (a, b) => a.start == b.start
        ? a.key.compareTo(b.key)
        : a.start.compareTo(b.start),
  );
  return items;
}

class TimelineBlock {
  TimelineBlock(this.item, this.start, this.end);
  final CalendarItem item;
  final double start, end;
  int column = 0, columns = 1;
}

List<TimelineBlock> layoutTimeline(List<CalendarItem> items, DateTime day) {
  final from = dayOf(day), to = DateTime(day.year, day.month, day.day + 1);
  final minutes = to.difference(from).inMinutes.toDouble();
  final blocks =
      items
          .where((i) => !i.deadline && !i.allDay)
          .map(
            (i) => TimelineBlock(
              i,
              i.start.difference(from).inSeconds / 60.0 < 0
                  ? 0
                  : i.start.difference(from).inSeconds / 60.0,
              math.min(minutes, i.end!.difference(from).inSeconds / 60.0),
            ),
          )
          .toList()
        ..sort(
          (a, b) => a.start == b.start
              ? b.end.compareTo(a.end)
              : a.start.compareTo(b.start),
        );
  final active = <int, double>{};
  var group = <TimelineBlock>[], width = 1;
  void finish() {
    for (final b in group) {
      b.columns = width;
    }
  }

  for (final b in blocks) {
    active.removeWhere((_, end) => end <= b.start);
    if (active.isEmpty) {
      finish();
      group = [];
      width = 1;
    }
    var column = 0;
    while (active.containsKey(column)) {
      column++;
    }
    b.column = column;
    active[column] = math.max(b.end, b.start + 30);
    group.add(b);
    width = math.max(width, column + 1);
  }
  finish();
  return blocks;
}

class ScheduleCalendar extends StatefulWidget {
  const ScheduleCalendar({
    super.key,
    required this.store,
    required this.onOpen,
    required this.onCreate,
  });
  final EntryStore store;
  final void Function(Entry) onOpen;
  final void Function(DateTime start, DateTime end) onCreate;
  @override
  State<ScheduleCalendar> createState() => _ScheduleCalendarState();
}

class _ScheduleCalendarState extends State<ScheduleCalendar> {
  late DateTime selected = dayOf(widget.store.clock());
  late DateTime month = DateTime(selected.year, selected.month);
  late String mode =
      widget.store.preferences['calendarView'] as String? ?? 'month';
  late bool completed = widget.store.preferences['calendarCompleted'] != false;
  void selectMode(String next) {
    setState(() => mode = next);
    widget.store.setPreferences({'calendarView': next});
  }

  void move(int direction) => setState(() {
    if (mode == 'month') {
      month = DateTime(month.year, month.month + direction);
      selected = month;
    } else {
      selected = DateTime(
        selected.year,
        selected.month,
        selected.day + direction * (mode == 'week' ? 7 : 1),
      );
      month = DateTime(selected.year, selected.month);
    }
  });
  @override
  Widget build(BuildContext context) {
    final weekStart = DateTime(
      selected.year,
      selected.month,
      selected.day - selected.weekday + 1,
    );
    final items = calendarItems(
      widget.store.entries,
      selected,
      showCompleted: completed,
    );
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
          child: Row(
            children: [
              Expanded(
                child: SegmentedStrip<String>(
                  label: '日历视图',
                  choices: const ['month', 'day', 'week', 'list'],
                  selection: mode,
                  identifier: (value) => 'calendar-$value',
                  title: (value) => switch (value) {
                    'month' => '月视图',
                    'day' => '日视图',
                    'week' => '周视图',
                    _ => '列表',
                  },
                  onChanged: selectMode,
                ),
              ),
              PopupMenuButton<bool>(
                tooltip: '日历显示选项',
                onSelected: (value) {
                  setState(() => completed = value);
                  widget.store.setPreferences({'calendarCompleted': value});
                },
                itemBuilder: (_) => [
                  CheckedPopupMenuItem(
                    value: !completed,
                    checked: completed,
                    child: const Text('显示已完成'),
                  ),
                ],
              ),
            ],
          ),
        ),
        Row(
          children: [
            IconButton(
              tooltip: mode == 'month' ? '上个月' : '上一段日期',
              onPressed: () => move(-1),
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Text(
                mode == 'month'
                    ? '${month.year} 年 ${month.month} 月'
                    : mode == 'week'
                    ? '${dateLabel(weekStart, time: false)} — ${dateLabel(DateTime(weekStart.year, weekStart.month, weekStart.day + 6), time: false)}'
                    : '${selected.year}/${selected.month}/${selected.day}',
                textAlign: TextAlign.center,
              ),
            ),
            IconButton(
              tooltip: mode == 'month' ? '下个月' : '下一段日期',
              onPressed: () => move(1),
              icon: const Icon(Icons.chevron_right),
            ),
            TextButton(
              onPressed: () => setState(() {
                selected = dayOf(widget.store.clock());
                month = DateTime(selected.year, selected.month);
              }),
              child: const Text('今天'),
            ),
          ],
        ),
        Expanded(
          child: mode == 'list'
              ? ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                  children: [
                    for (var offset = 0; offset < 30; offset++) ...[
                      if (calendarItems(
                        widget.store.entries,
                        DateTime(
                          selected.year,
                          selected.month,
                          selected.day + offset,
                        ),
                        showCompleted: completed,
                      ).isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 14),
                          child: Text(
                            dateLabel(
                              DateTime(
                                selected.year,
                                selected.month,
                                selected.day + offset,
                              ),
                              time: false,
                            ),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                      ...calendarItems(
                        widget.store.entries,
                        DateTime(
                          selected.year,
                          selected.month,
                          selected.day + offset,
                        ),
                        showCompleted: completed,
                      ).map(
                        (i) => ListTile(
                          title: Text(
                            i.entry.title,
                            style: TextStyle(
                              decoration: i.owner.completed
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          ),
                          subtitle: Text(
                            i.deadline
                                ? 'DDL ${clockLabel(i.start)}'
                                : i.allDay
                                ? '全天'
                                : '${clockLabel(i.start)}–${clockLabel(i.end!)}',
                          ),
                          onTap: () => widget.onOpen(i.owner),
                        ),
                      ),
                    ],
                    if (!List.generate(
                      30,
                      (i) => DateTime(
                        selected.year,
                        selected.month,
                        selected.day + i,
                      ),
                    ).any(
                      (d) => calendarItems(
                        widget.store.entries,
                        d,
                        showCompleted: completed,
                      ).isNotEmpty,
                    ))
                      const Padding(
                        padding: EdgeInsets.all(30),
                        child: Text('未来 30 天没有安排；无日期待办在「我的清单」中。'),
                      ),
                  ],
                )
              : mode == 'month'
              ? SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                  child: Column(
                    children: [
                      Row(
                        children: ['一', '二', '三', '四', '五', '六', '日']
                            .map((d) => Expanded(child: Center(child: Text(d))))
                            .toList(),
                      ),
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 7,
                              mainAxisExtent: 54,
                            ),
                        itemCount: 42,
                        itemBuilder: (context, index) {
                          final date = DateTime(
                            month.year,
                            month.month,
                            1 - (month.weekday - 1) + index,
                          );
                          final has = calendarItems(
                            widget.store.entries,
                            date,
                            showCompleted: false,
                          ).isNotEmpty;
                          final active = sameDay(date, selected),
                              scheme = Theme.of(context).colorScheme;
                          return Semantics(
                            label:
                                '${date.month} 月 ${date.day} 日${has ? '，有未完成事项' : ''}',
                            button: true,
                            selected: active,
                            child: InkWell(
                              onTap: () => setState(() => selected = date),
                              onDoubleTap: () {
                                setState(() => selected = date);
                                selectMode('day');
                              },
                              onLongPress: widget.store.readOnly
                                  ? null
                                  : () => widget.onCreate(
                                      DateTime(
                                        date.year,
                                        date.month,
                                        date.day,
                                        9,
                                      ),
                                      DateTime(
                                        date.year,
                                        date.month,
                                        date.day,
                                        9,
                                        30,
                                      ),
                                    ),
                              child: Container(
                                margin: const EdgeInsets.all(3),
                                decoration: BoxDecoration(
                                  color: active ? scheme.primary : null,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      '${date.day}',
                                      style: TextStyle(
                                        color: active
                                            ? scheme.onPrimary
                                            : date.month == month.month
                                            ? scheme.onSurface
                                            : scheme.onSurfaceVariant,
                                      ),
                                    ),
                                    Text(
                                      has ? '•' : '',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: active
                                            ? scheme.onPrimary
                                            : scheme.primary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${dateLabel(selected, time: false)} 的安排',
                            ),
                          ),
                          TextButton(
                            onPressed: () => selectMode('day'),
                            child: const Text('打开日视图'),
                          ),
                        ],
                      ),
                      const Text('长按日期添加；日视图空白处长按并拖动选择时段。'),
                      if (items.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(30),
                          child: Text('这一天没有安排'),
                        ),
                      ...items.map(
                        (i) => ListTile(
                          title: Text(i.entry.title),
                          subtitle: Text(
                            i.deadline
                                ? 'DDL ${clockLabel(i.start)}'
                                : i.allDay
                                ? '全天'
                                : '${clockLabel(i.start)}–${clockLabel(i.end!)}',
                          ),
                          onTap: () => widget.onOpen(i.owner),
                        ),
                      ),
                    ],
                  ),
                )
              : TimelineCalendar(
                  key: ValueKey('$mode/$selected'),
                  days: List.generate(
                    mode == 'week' ? 7 : 1,
                    (i) => DateTime(
                      mode == 'week' ? weekStart.year : selected.year,
                      mode == 'week' ? weekStart.month : selected.month,
                      (mode == 'week' ? weekStart.day : selected.day) + i,
                    ),
                  ),
                  store: widget.store,
                  showCompleted: completed,
                  onCreate: widget.onCreate,
                  onOpen: widget.onOpen,
                  onDay: (d) {
                    setState(() => selected = d);
                    selectMode('day');
                  },
                ),
        ),
      ],
    );
  }
}

class TimelineCalendar extends StatefulWidget {
  const TimelineCalendar({
    super.key,
    required this.days,
    required this.store,
    required this.showCompleted,
    required this.onCreate,
    required this.onOpen,
    required this.onDay,
  });
  final List<DateTime> days;
  final EntryStore store;
  final bool showCompleted;
  final void Function(DateTime, DateTime) onCreate;
  final void Function(Entry) onOpen;
  final void Function(DateTime) onDay;
  @override
  State<TimelineCalendar> createState() => _TimelineCalendarState();
}

class _TimelineCalendarState extends State<TimelineCalendar>
    with WidgetsBindingObserver, RouteAware {
  final scroll = ScrollController(initialScrollOffset: 7 * 72);
  final gridKey = GlobalKey(), viewportKey = GlobalKey();
  final _rangeHaptics = HoldHaptics();
  Offset? pointer;
  int? selectedDay, anchorMinute, tipMinute;
  Timer? autoScroll;
  DateTime? _lastStepHaptic;
  ModalRoute<dynamic>? _route;
  static const hourHeight = 72.0;

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
  void didUpdateWidget(covariant TimelineCalendar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) {
      oldWidget.store.removeListener(_onStoreChanged);
      widget.store.addListener(_onStoreChanged);
    }
    var daysChanged = oldWidget.days.length != widget.days.length;
    if (!daysChanged) {
      for (var index = 0; index < widget.days.length; index++) {
        if (oldWidget.days[index] != widget.days[index]) {
          daysChanged = true;
          break;
        }
      }
    }
    if (daysChanged) _cancelRange();
  }

  void _onStoreChanged() {
    if (widget.store.readOnly) _cancelRange();
  }

  void _cancelRange({bool feedback = false}) {
    autoScroll?.cancel();
    autoScroll = null;
    _rangeHaptics.cancel(feedback: feedback);
    pointer = null;
    _lastStepHaptic = null;
    if (mounted && selectedDay != null) {
      setState(() {
        selectedDay = null;
        anchorMinute = null;
        tipMinute = null;
      });
    } else {
      selectedDay = null;
      anchorMinute = null;
      tipMinute = null;
    }
  }

  void _completeRange() {
    autoScroll?.cancel();
    autoScroll = null;
    pointer = null;
    _lastStepHaptic = null;
    _rangeHaptics.finish(dropped: true);
    setState(() {
      selectedDay = null;
      anchorMinute = null;
      tipMinute = null;
    });
  }

  @override
  void didPushNext() => _cancelRange();

  @override
  void didPop() => _cancelRange();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _cancelRange();
  }

  @override
  void dispose() {
    autoScroll?.cancel();
    widget.store.removeListener(_onStoreChanged);
    WidgetsBinding.instance.removeObserver(this);
    appRouteObserver.unsubscribe(this);
    _rangeHaptics.cancel();
    scroll.dispose();
    super.dispose();
  }

  int total(int i) => DateTime(
    widget.days[i].year,
    widget.days[i].month,
    widget.days[i].day + 1,
  ).difference(widget.days[i]).inMinutes;
  Offset position(Offset global) =>
      (gridKey.currentContext!.findRenderObject() as RenderBox).globalToLocal(
        global,
      );
  void update(Offset global, double columnWidth, {bool start = false}) {
    final local = position(global);
    final index = ((local.dx - 52) / columnWidth).floor().clamp(
      0,
      widget.days.length - 1,
    );
    if (start) {
      selectedDay = index;
      _rangeHaptics.start();
      _lastStepHaptic = DateTime.now();
    }
    // A store can become read-only between the long-press start and the
    // following move updates, or a move can arrive without a live anchor.
    // Without an anchored day there is no range to select, so drop the
    // update instead of asserting on a null day.
    if (selectedDay == null) return;
    final minute = (local.dy / hourHeight * 60 / 15).floor() * 15;
    final nextMinute = minute.clamp(0, total(selectedDay!) - 15);
    if (!start && nextMinute != tipMinute) {
      final now = DateTime.now();
      if (_lastStepHaptic == null ||
          now.difference(_lastStepHaptic!) >=
              const Duration(milliseconds: 100)) {
        AppHaptics.change();
        _lastStepHaptic = now;
      }
    }
    setState(() {
      if (start) anchorMinute = minute.clamp(0, total(selectedDay!) - 15);
      tipMinute = nextMinute;
      pointer = global;
    });
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, limits) {
      final width = math.max(limits.maxWidth, 52 + widget.days.length * 100.0),
          columnWidth = (width - 52) / widget.days.length;
      final height =
          widget.days
              .map(
                (d) => DateTime(
                  d.year,
                  d.month,
                  d.day + 1,
                ).difference(d).inMinutes,
              )
              .reduce(math.max) /
          60 *
          hourHeight;
      final scheme = Theme.of(context).colorScheme;
      final all = widget.days
          .map(
            (d) => calendarItems(
              widget.store.entries,
              d,
              showCompleted: widget.showCompleted,
            ),
          )
          .toList();
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: width,
          child: Column(
            children: [
              Row(
                children: [
                  const SizedBox(width: 52),
                  ...List.generate(
                    widget.days.length,
                    (i) => SizedBox(
                      width: columnWidth,
                      child: TextButton(
                        onPressed: () => widget.onDay(widget.days[i]),
                        child: Text(
                          '${['一', '二', '三', '四', '五', '六', '日'][widget.days[i].weekday - 1]} ${widget.days[i].day}',
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 120),
                child: SingleChildScrollView(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(width: 52),
                      ...List.generate(
                        widget.days.length,
                        (i) => SizedBox(
                          width: columnWidth,
                          child: Column(
                            children: all[i]
                                .where((item) => item.deadline || item.allDay)
                                .map(
                                  (item) => InkWell(
                                    onTap: () => widget.onOpen(item.owner),
                                    child: Container(
                                      width: columnWidth,
                                      margin: const EdgeInsets.all(2),
                                      padding: const EdgeInsets.all(5),
                                      color: scheme.secondaryContainer,
                                      child: Text(
                                        '${item.deadline ? 'DDL ${clockLabel(item.start)}' : '全天'} ${item.entry.title}',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 11,
                                          decoration: item.owner.completed
                                              ? TextDecoration.lineThrough
                                              : null,
                                        ),
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: ClipRect(
                  key: viewportKey,
                  child: SingleChildScrollView(
                    controller: scroll,
                    physics: selectedDay == null
                        ? null
                        : const NeverScrollableScrollPhysics(),
                    child: SizedBox(
                      key: gridKey,
                      height: height,
                      width: width,
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: GestureDetector(
                              key: const ValueKey('timeline-blank'),
                              behavior: HitTestBehavior.opaque,
                              onLongPressStart: widget.store.readOnly
                                  ? null
                                  : (d) {
                                      if (widget.store.readOnly) return;
                                      autoScroll?.cancel();
                                      update(
                                        d.globalPosition,
                                        columnWidth,
                                        start: true,
                                      );
                                      autoScroll = Timer.periodic(
                                        const Duration(milliseconds: 40),
                                        (_) {
                                          if (pointer == null ||
                                              !scroll.hasClients) {
                                            return;
                                          }
                                          final box =
                                              viewportKey.currentContext!
                                                      .findRenderObject()
                                                  as RenderBox;
                                          final y = box
                                              .globalToLocal(pointer!)
                                              .dy;
                                          final delta = y < 45
                                              ? -12.0
                                              : y > box.size.height - 45
                                              ? 12.0
                                              : 0.0;
                                          if (delta != 0) {
                                            scroll.jumpTo(
                                              (scroll.offset + delta).clamp(
                                                0,
                                                scroll.position.maxScrollExtent,
                                              ),
                                            );
                                            update(pointer!, columnWidth);
                                          }
                                        },
                                      );
                                    },
                              onLongPressMoveUpdate: widget.store.readOnly
                                  ? null
                                  : (d) {
                                      if (widget.store.readOnly) return;
                                      update(d.globalPosition, columnWidth);
                                    },
                              onLongPressCancel: () =>
                                  _cancelRange(feedback: true),
                              onLongPressEnd: widget.store.readOnly
                                  ? null
                                  : (_) {
                                      if (selectedDay == null) {
                                        _cancelRange(feedback: true);
                                        return;
                                      }
                                      // The store may turn read-only after the
                                      // drag started; drop the pending range
                                      // without creating anything.
                                      if (widget.store.readOnly) {
                                        _cancelRange();
                                        return;
                                      }
                                      final day = widget.days[selectedDay!];
                                      final first = math.min(
                                            anchorMinute!,
                                            tipMinute!,
                                          ),
                                          last =
                                              math.max(
                                                anchorMinute!,
                                                tipMinute!,
                                              ) +
                                              15;
                                      _completeRange();
                                      widget.onCreate(
                                        day.add(Duration(minutes: first)),
                                        day.add(Duration(minutes: last)),
                                      );
                                    },
                              child: CustomPaint(
                                painter: _GridPainter(
                                  widget.days,
                                  columnWidth,
                                  scheme.outline.withValues(alpha: .25),
                                ),
                              ),
                            ),
                          ),
                          ...List.generate(
                            (height / hourHeight).ceil(),
                            (hour) => Positioned(
                              top: hour * hourHeight,
                              left: 2,
                              child: IgnorePointer(
                                child: Text(
                                  clockLabel(
                                    widget.days.first.add(
                                      Duration(hours: hour),
                                    ),
                                  ),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          ...List.generate(
                            widget.days.length,
                            (i) => layoutTimeline(all[i], widget.days[i]).map((
                              b,
                            ) {
                              final lane = columnWidth / b.columns;
                              return Positioned(
                                top: b.start / 60 * hourHeight,
                                left:
                                    52 + i * columnWidth + b.column * lane + 2,
                                width: math.max(8, lane - 4),
                                height: math.max(
                                  30,
                                  (b.end - b.start) / 60 * hourHeight - 2,
                                ),
                                child: Material(
                                  color: scheme.primaryContainer,
                                  borderRadius: BorderRadius.circular(6),
                                  child: InkWell(
                                    onTap: () => widget.onOpen(b.item.owner),
                                    child: Padding(
                                      padding: const EdgeInsets.all(4),
                                      child: Text(
                                        '${clockLabel(b.item.start)} ${b.item.entry.title}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: scheme.onPrimaryContainer,
                                          decoration: b.item.owner.completed
                                              ? TextDecoration.lineThrough
                                              : null,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ).expand((v) => v),
                          for (var i = 0; i < widget.days.length; i++)
                            if (sameDay(widget.days[i], widget.store.clock()))
                              Positioned(
                                top:
                                    widget.store
                                        .clock()
                                        .difference(widget.days[i])
                                        .inSeconds /
                                    3600 *
                                    hourHeight,
                                left: 52 + i * columnWidth,
                                right: width - 52 - (i + 1) * columnWidth,
                                child: IgnorePointer(
                                  child: Container(
                                    height: 2,
                                    color: scheme.error,
                                  ),
                                ),
                              ),
                          if (selectedDay != null)
                            Positioned(
                              top:
                                  math.min(anchorMinute!, tipMinute!) /
                                  60 *
                                  hourHeight,
                              left: 52 + selectedDay! * columnWidth + 2,
                              width: columnWidth - 4,
                              height:
                                  (math.max(anchorMinute!, tipMinute!) -
                                      math.min(anchorMinute!, tipMinute!) +
                                      15) /
                                  60 *
                                  hourHeight,
                              child: IgnorePointer(
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: scheme.primary.withValues(alpha: .3),
                                    border: Border.all(
                                      color: scheme.primary,
                                      width: 2,
                                    ),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '${clockLabel(widget.days[selectedDay!].add(Duration(minutes: math.min(anchorMinute!, tipMinute!))))}–${clockLabel(widget.days[selectedDay!].add(Duration(minutes: math.max(anchorMinute!, tipMinute!) + 15)))}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: scheme.onSurface,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.all(6),
                child: Text(
                  '长按空白处，再拖动选择时段 · 15 分钟对齐',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _GridPainter extends CustomPainter {
  _GridPainter(this.days, this.columnWidth, this.color);
  final List<DateTime> days;
  final double columnWidth;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = .6;
    for (double y = 0; y <= size.height; y += 36) {
      canvas.drawLine(Offset(52, y), Offset(size.width, y), p);
    }
    for (var i = 0; i <= days.length; i++) {
      final x = 52 + i * columnWidth;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter old) =>
      old.color != color || old.columnWidth != columnWidth || old.days != days;
}
