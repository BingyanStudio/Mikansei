import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'domain.dart';
import 'store.dart';
import 'student_tools.dart' show ReminderControls;
import 'system_services.dart' show requestReminderAccess;
import 'android_system.dart' show AndroidSystem, addToSystemCalendar;
import 'segmented_strip.dart';
import 'theme.dart';

class EntryEditor extends StatefulWidget {
  const EntryEditor({
    super.key,
    required this.store,
    this.entry,
    this.kind,
    this.start,
    this.end,
    this.isNew = false,
  });
  final bool isNew;
  final EntryStore store;
  final Entry? entry;
  final EntryKind? kind;
  final DateTime? start;
  final DateTime? end;
  @override
  State<EntryEditor> createState() => _EntryEditorState();
}

class _EntryEditorState extends State<EntryEditor> {
  late Entry draft;
  late EntryKind kind;
  late final TextEditingController title;
  late final TextEditingController body;
  late final TextEditingController category;
  late final TextEditingController platform;
  late final TextEditingController location;
  late final TextEditingController estimate;
  late final TextEditingController newStep;
  List<StepItem> steps = [];
  int priority = 0;
  DateTime? due;
  late DateTime start;
  late DateTime end;
  bool allDay = false;
  bool advanced = false;
  String repeat = 'never';
  int intervalDays = 1;
  int intervalMonths = 1;
  List<int> weekdays = [];
  List<DateTime> repeatDates = [];
  String? error;
  bool saving = false;
  bool allowDismiss = false;
  bool confirmingDismiss = false;
  late String initialFingerprint;
  late final Map<String, dynamic> reminder;
  @override
  void initState() {
    super.initState();
    draft =
        widget.entry ??
        Entry.create(
          kind: widget.kind ?? EntryKind.task,
          now: widget.store.clock(),
        );
    reminder = {...draft.data};
    if (widget.entry == null && draft.kind == EntryKind.schedule) {
      reminder["reminder"] = 0;
    }
    kind = draft.kind;
    priority = draft.priority;
    due = draft.due;
    start =
        widget.start ??
        draft.start ??
        widget.store.clock().add(const Duration(hours: 1));
    start = DateTime(
      start.year,
      start.month,
      start.day,
      start.hour,
      start.minute,
    );
    end =
        widget.end ??
        (widget.start == null
            ? draft.end ?? start.add(const Duration(minutes: 30))
            : start.add(const Duration(minutes: 30)));
    allDay = draft.allDay;
    repeat = draft.repeatRule;
    intervalDays = draft.data['repeatIntervalDays'] as int? ?? 1;
    intervalMonths = draft.data['repeatIntervalMonths'] as int? ?? 1;
    weekdays = (draft.data['repeatWeekdays'] as List? ?? [])
        .cast<int>()
        .toList();
    repeatDates = (draft.data['repeatDates'] as List? ?? [])
        .map((v) => DateTime.parse(v as String).toLocal())
        .toList();
    title = TextEditingController(text: draft.title);
    body = TextEditingController(text: draft.body);
    category = TextEditingController(text: draft.category);
    platform = TextEditingController(text: draft.platform);
    location = TextEditingController(text: draft.location);
    estimate = TextEditingController(text: draft.estimate?.toString() ?? '');
    steps = List<StepItem>.of(draft.steps);
    newStep = TextEditingController();
    advanced = widget.entry != null || kind == EntryKind.schedule;
    initialFingerprint = _fingerprint();
    for (final controller in [
      title,
      body,
      category,
      platform,
      location,
      estimate,
      newStep,
    ]) {
      controller.addListener(_editorChanged);
    }
  }

  void _editorChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final controller in [
      title,
      body,
      category,
      platform,
      location,
      estimate,
      newStep,
    ]) {
      controller.removeListener(_editorChanged);
      controller.dispose();
    }
    super.dispose();
  }

  String _fingerprint() => jsonEncode({
    'title': title.text,
    'body': body.text,
    'kind': kind.name,
    'priority': priority,
    'category': category.text,
    'platform': platform.text,
    'location': location.text,
    'estimate': estimate.text,
    'pendingStep': newStep.text,
    'steps': steps.map((step) => [step.id, step.title, step.done]).toList(),
    'due': due == null ? null : isoDate(due!),
    'start': isoDate(start),
    'end': isoDate(end),
    'allDay': allDay,
    'repeat': repeat,
    'intervalDays': intervalDays,
    'intervalMonths': intervalMonths,
    'weekdays': weekdays,
    'repeatDates': repeatDates.map(isoDate).toList(),
    'reminder': {
      for (final key in [
        'reminder',
        'reminderDelivery',
        'reminderSound',
        'snoozeMinutes',
        'reminderPattern',
        'reminderAnchor',
      ])
        key: reminder[key],
    },
  });

  bool get hasUnsavedChanges => _fingerprint() != initialFingerprint;

  Future<void> _requestDismiss() async {
    if (saving || confirmingDismiss) return;
    if (!hasUnsavedChanges) {
      Navigator.pop(context);
      return;
    }
    confirmingDismiss = true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('放弃未保存的更改？'),
        content: const Text('关闭后，这次编辑的内容将不会保存。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('继续编辑'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('放弃更改'),
          ),
        ],
      ),
    );
    confirmingDismiss = false;
    if (!mounted || discard != true) return;
    _popAfterAllowingDismiss();
  }

  void _popAfterAllowingDismiss({bool saved = false}) {
    if (!mounted) return;
    setState(() {
      if (saved) saving = false;
      allowDismiss = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context);
    });
  }

  void _addStep() {
    final value = newStep.text.trim();
    if (value.isEmpty) return;
    setState(() {
      steps = [...steps, StepItem(title: value)];
    });
    newStep.clear();
  }

  void _changeKind(EntryKind value) {
    if (value == kind) return;
    setState(() {
      kind = value;
      if (value == EntryKind.schedule) {
        final selectedStart = draft.start ?? start;
        start = selectedStart;
        if (!end.isAfter(start)) end = start.add(const Duration(minutes: 30));
        due = null;
        reminder['reminder'] = 0;
        reminder['reminderDelivery'] = 'alarm';
        reminder['reminderAnchor'] = 'execution';
        reminder['reminderPattern'] = 'single';
        advanced = true;
      } else {
        reminder['reminderAnchor'] = 'deadline';
        if (value == EntryKind.note) {
          reminder['reminder'] = null;
          repeat = 'never';
        }
      }
    });
  }

  Widget _priorityControls() => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: List.generate(3, (value) {
      final selected = priority == value;
      final palette = MikanseiPalette.of(context);
      final color = value == 2
          ? palette.error
          : value == 1
          ? palette.warm
          : palette.accent;
      return ChoiceChip(
        label: Text(
          priorities[value],
          style: TextStyle(
            color: selected
                ? value == 2
                      ? Theme.of(context).colorScheme.onError
                      : palette.onAccent
                : Theme.of(context).colorScheme.onSurface,
          ),
        ),
        selected: selected,
        showCheckmark: false,
        selectedColor: color,
        onSelected: (_) => setState(() => priority = value),
      );
    }),
  );

  Future<DateTime?> pick(DateTime initial, {bool includeTime = true}) async {
    final first = DateTime(initial.year < 2000 ? initial.year : 2000);
    final last = DateTime(initial.year > 2100 ? initial.year : 2100, 12, 31);
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
    );
    if (date == null || !mounted) return null;
    if (!includeTime) return dayOf(date);
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Future<void> save() async {
    if (saving || widget.store.readOnly) return;
    final cleanTitle = title.text.trim();
    final minutes = estimate.text.trim().isEmpty
        ? null
        : int.tryParse(estimate.text);
    if (cleanTitle.isEmpty) {
      setState(() => error = '先写一个事项标题。');
      return;
    }
    if (estimate.text.trim().isNotEmpty &&
        (minutes == null || minutes < 1 || minutes > 1440)) {
      setState(() => error = '预计用时应为 1–1440 分钟。');
      return;
    }
    if (kind == EntryKind.schedule && !end.isAfter(start)) {
      setState(() => error = '结束时间需要晚于开始时间。');
      return;
    }
    if (kind != EntryKind.note &&
        repeat != 'never' &&
        kind != EntryKind.schedule &&
        due == null &&
        draft.start == null) {
      setState(() => error = '循环事项需要一个 DDL。');
      return;
    }
    if (kind != EntryKind.note && repeat == 'dates' && repeatDates.isEmpty) {
      setState(() => error = '请至少选择一个循环日期。');
      return;
    }
    final pendingStep = newStep.text.trim();
    final nextSteps = [
      ...steps,
      if (pendingStep.isNotEmpty) StepItem(title: pendingStep),
    ].where((step) => step.title.trim().isNotEmpty).toList();
    final changedKind = kind != draft.kind;
    var next = draft.change({
      ...{
        for (final key in [
          'reminder',
          'reminderDelivery',
          'reminderSound',
          'snoozeMinutes',
          'reminderPattern',
          'reminderAnchor',
        ])
          key: reminder[key],
      },
      'title': cleanTitle,
      'body': body.text.trim(),
      'kind': kind.name,
      'priority': priority,
      'category': category.text.trim(),
      'platform': platform.text.trim(),
      'location': location.text.trim(),
      'estimatedMinutes': minutes,
      'checklist': nextSteps.map((step) => step.toJson()).toList(),
      'dueDate': kind == EntryKind.schedule || kind == EntryKind.note
          ? null
          : due == null
          ? null
          : isoDate(due!),
      if (kind == EntryKind.schedule || changedKind)
        'plannedStart': kind == EntryKind.schedule
            ? isoDate(allDay ? dayOf(start) : start)
            : null,
      if (kind == EntryKind.schedule || changedKind)
        'plannedEnd': kind == EntryKind.schedule
            ? isoDate(
                allDay
                    ? dayOf(end).isAfter(dayOf(start))
                          ? dayOf(end)
                          : DateTime(start.year, start.month, start.day + 1)
                    : end,
              )
            : null,
      if (kind == EntryKind.schedule || changedKind)
        'plannedAllDay': kind == EntryKind.schedule && allDay,
      'repeatRule': kind == EntryKind.note ? 'never' : repeat,
      'repeatIntervalDays': intervalDays,
      'repeatIntervalMonths': intervalMonths,
      'repeatWeekdays': weekdays,
      'repeatDates': repeatDates.map(isoDate).toList(),
      if (changedKind ||
          draft.repeatRule != repeat ||
          draft.recurrenceDate != (kind == EntryKind.schedule ? start : due))
        'repeatAnchorDate': null,
      if (kind == EntryKind.schedule) 'reminderAnchor': 'execution',
      if (kind == EntryKind.schedule) 'reminderPattern': 'single',
      if (kind == EntryKind.note) 'reminder': null,
      if (kind == EntryKind.note) 'isCompleted': false,
      if (kind == EntryKind.note) 'completedAt': null,
      if (kind == EntryKind.note) 'isInPlanning': false,
      if (kind == EntryKind.note) 'startedAt': null,
      if (kind == EntryKind.note) 'elapsedSeconds': 0,
    }, now: widget.store.clock());
    if (next.completed && next.steps.any((step) => !step.done)) {
      next = next.change({
        'isCompleted': false,
        'completedAt': null,
      }, now: widget.store.clock());
    }
    if (next.attention == null) {
      next = next.change({'reminder': null, 'repeatRule': 'never'});
    }
    if (next.repeatRule != 'never' && next.date('repeatAnchorDate') == null) {
      next = next.change({'repeatAnchorDate': isoDate(next.recurrenceDate!)});
    }
    try {
      setState(() => saving = true);
      widget.store.save(next);
      await widget.store.settled;
      if (widget.store.saveFailed) throw StateError('事项暂未写入磁盘，请重试保存。');
      bool allowed = true;
      if (NativeStorage.supportsSystemServices &&
          next.data['reminder'] != null &&
          widget.store.storage is NativeStorage) {
        allowed = await requestReminderAccess(
          next.data['reminderDelivery'] as String? ?? 'popup',
        );
        await widget.store.refreshServices();
      }
      if (!mounted) return;
      if (AndroidSystem.supported &&
          (widget.entry == null || widget.isNew) &&
          next.kind == EntryKind.schedule &&
          widget.store.preferences['offerCalendar'] == true) {
        try {
          await addToSystemCalendar(context, widget.store, next);
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text('事项已保存，日历尚未安排：$e')));
          }
        }
      }
      if (!mounted) return;
      if (!allowed) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('事项已保存，提醒权限尚未开启。请在设置中开启。')),
        );
      }
      _popAfterAllowingDismiss(saved: true);
    } catch (exception) {
      if (mounted) {
        setState(() {
          saving = false;
          error = '无法保存：$exception';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope<Object?>(
    canPop: !saving && (!hasUnsavedChanges || allowDismiss),
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) _requestDismiss();
    },
    child: Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 580,
          maxHeight:
              MediaQuery.sizeOf(context).height -
              MediaQuery.viewInsetsOf(context).bottom -
              48,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 12, 12, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.entry == null || widget.isNew ? '记下一件事' : '编辑事项',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: saving ? null : _requestDismiss,
                    icon: const Icon(Icons.close),
                  ),
                  FilledButton(
                    key: const ValueKey('save-entry'),
                    onPressed:
                        widget.store.readOnly ||
                            saving ||
                            title.text.trim().isEmpty
                        ? null
                        : save,
                    child: const Text('保存'),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 12, 22, 8),
                child: AbsorbPointer(
                  absorbing: widget.store.readOnly || saving,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (widget.store.readOnly) ...[
                        Text(
                          '此事项当前为只读，无法修改。',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: MikanseiPalette.of(context).secondary,
                              ),
                        ),
                        const SizedBox(height: 10),
                      ],
                      TextField(
                        key: const ValueKey('entry-title'),
                        controller: title,
                        autofocus: widget.entry == null || widget.isNew,
                        minLines: 1,
                        maxLines: 3,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => save(),
                        decoration: const InputDecoration(
                          labelText: '事项标题',
                          hintText: '比如：交物理作业、给家里打电话',
                        ),
                      ),
                      const SizedBox(height: 14),
                      SegmentedStrip<EntryKind>(
                        choices: EntryKind.values,
                        selection: kind,
                        title: (value) => value.label,
                        label: '事项类型',
                        identifier: (value) => 'entry-kind-${value.name}',
                        onChanged: _changeKind,
                      ),
                      const SizedBox(height: 14),
                      if (kind != EntryKind.note) ...[
                        if (kind != EntryKind.schedule)
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              for (final d in [(0, '今天'), (1, '明天')])
                                ActionChip(
                                  label: Text('${d.$2}截止'),
                                  onPressed: () {
                                    final now = widget.store.clock();
                                    setState(
                                      () => due = DateTime(
                                        now.year,
                                        now.month,
                                        now.day + d.$1,
                                        23,
                                        59,
                                      ),
                                    );
                                  },
                                ),
                              ActionChip(
                                label: const Text('无日期'),
                                onPressed: due == null
                                    ? null
                                    : () => setState(() => due = null),
                              ),
                            ],
                          ),
                        if (kind == EntryKind.schedule) ...[
                          Text(
                            '执行时段',
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(
                                  color: MikanseiPalette.of(context).accent,
                                ),
                          ),
                          const SizedBox(height: 6),
                          timeButton('开始', start, () async {
                            final date = await pick(
                              start,
                              includeTime: !allDay,
                            );
                            if (date != null) {
                              setState(() {
                                final duration = end.difference(start);
                                start = date;
                                end = date.add(duration);
                              });
                            }
                          }),
                          const SizedBox(height: 8),
                          timeButton(allDay ? '结束（不含当天）' : '结束', end, () async {
                            final date = await pick(end, includeTime: !allDay);
                            if (date != null) setState(() => end = date);
                          }),
                          TextFormField(
                            key: ValueKey('duration-$allDay'),
                            initialValue: allDay
                                ? '${DateTime.utc(end.year, end.month, end.day).difference(DateTime.utc(start.year, start.month, start.day)).inDays > 0 ? DateTime.utc(end.year, end.month, end.day).difference(DateTime.utc(start.year, start.month, start.day)).inDays : 1}'
                                : '${end.difference(start).inMinutes}',
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: allDay ? '持续天数' : '持续分钟',
                            ),
                            onChanged: (text) {
                              final value = int.tryParse(text);
                              if (value != null &&
                                  value > 0 &&
                                  value <= (allDay ? 365 : 1440)) {
                                setState(
                                  () => end = allDay
                                      ? DateTime(
                                          start.year,
                                          start.month,
                                          start.day + value,
                                        )
                                      : start.add(Duration(minutes: value)),
                                );
                              }
                            },
                          ),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('全天'),
                            value: allDay,
                            onChanged: (value) => setState(() {
                              allDay = value;
                              if (value) {
                                start = dayOf(start);
                                end = dayOf(end).isAfter(start)
                                    ? dayOf(end)
                                    : DateTime(
                                        start.year,
                                        start.month,
                                        start.day + 1,
                                      );
                              } else {
                                start = DateTime(
                                  start.year,
                                  start.month,
                                  start.day,
                                  9,
                                );
                                end = start.add(const Duration(minutes: 30));
                              }
                            }),
                          ),
                        ] else
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  icon: Icon(
                                    Icons.flag_outlined,
                                    color: MikanseiPalette.of(context).warm,
                                  ),
                                  label: Text(
                                    due == null
                                        ? '添加 DDL（可选）'
                                        : 'DDL ${dateLabel(due!)}',
                                    style: TextStyle(
                                      color: MikanseiPalette.of(context).warm,
                                    ),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    side: BorderSide(
                                      color: MikanseiPalette.of(context).warm
                                          .withValues(alpha: .45),
                                    ),
                                  ),
                                  onPressed: () async {
                                    final date = await pick(
                                      due ??
                                          widget.store.clock().add(
                                            const Duration(days: 1),
                                          ),
                                    );
                                    if (date != null) {
                                      setState(() => due = date);
                                    }
                                  },
                                ),
                              ),
                              if (due != null)
                                IconButton(
                                  tooltip: '移除 DDL',
                                  icon: const Icon(Icons.close),
                                  onPressed: () => setState(() => due = null),
                                ),
                            ],
                          ),
                      ],
                      TextButton.icon(
                        onPressed: () => setState(() => advanced = !advanced),
                        icon: Icon(
                          advanced ? Icons.expand_less : Icons.expand_more,
                        ),
                        label: Text(
                          advanced ? '收起补充详情' : '补充分类、备注、Checklist 与提醒',
                        ),
                      ),
                      if (advanced) ...[
                        Text(
                          '备注',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: body,
                          minLines: 2,
                          maxLines: 6,
                          decoration: const InputDecoration(labelText: '备注'),
                        ),
                        const SizedBox(height: 12),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Checklist',
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                                const SizedBox(height: 6),
                                for (final step in steps)
                                  Row(
                                    children: [
                                      Checkbox(
                                        value: step.done,
                                        onChanged: (value) => setState(() {
                                          steps = steps
                                              .map(
                                                (current) =>
                                                    current.id == step.id
                                                    ? StepItem(
                                                        id: current.id,
                                                        title: current.title,
                                                        done: value ?? false,
                                                      )
                                                    : current,
                                              )
                                              .toList();
                                        }),
                                      ),
                                      Expanded(
                                        child: TextFormField(
                                          key: ValueKey(
                                            'entry-step-${step.id}',
                                          ),
                                          initialValue: step.title,
                                          onChanged: (value) => setState(() {
                                            steps = steps
                                                .map(
                                                  (current) =>
                                                      current.id == step.id
                                                      ? StepItem(
                                                          id: current.id,
                                                          title: value,
                                                          done: current.done,
                                                        )
                                                      : current,
                                                )
                                                .toList();
                                          }),
                                          decoration: const InputDecoration(
                                            hintText: '步骤',
                                            border: InputBorder.none,
                                            enabledBorder: InputBorder.none,
                                            focusedBorder: InputBorder.none,
                                            contentPadding:
                                                EdgeInsets.symmetric(
                                                  vertical: 8,
                                                ),
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: '删除步骤',
                                        onPressed: () => setState(() {
                                          steps = steps
                                              .where(
                                                (item) => item.id != step.id,
                                              )
                                              .toList();
                                        }),
                                        icon: const Icon(
                                          Icons.remove_circle_outline,
                                        ),
                                      ),
                                    ],
                                  ),
                                Row(
                                  children: [
                                    const Icon(Icons.add_circle_outline),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: TextField(
                                        controller: newStep,
                                        onSubmitted: (_) => _addStep(),
                                        decoration: const InputDecoration(
                                          hintText: '添加清单项',
                                          border: InputBorder.none,
                                          enabledBorder: InputBorder.none,
                                          focusedBorder: InputBorder.none,
                                          contentPadding: EdgeInsets.symmetric(
                                            vertical: 8,
                                          ),
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: '添加清单项',
                                      onPressed: _addStep,
                                      icon: const Icon(Icons.add),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '分类与优先级',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 6),
                        if (kind != EntryKind.note) ...[
                          _priorityControls(),
                          const SizedBox(height: 10),
                        ],
                        TextField(
                          controller: category,
                          decoration: const InputDecoration(
                            labelText: '科目 / 分类',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: platform,
                          decoration: const InputDecoration(
                            labelText: '提交 / 处理平台',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: location,
                          decoration: const InputDecoration(labelText: '处理地点'),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: estimate,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: const InputDecoration(
                            labelText: '预计用时（分钟）',
                          ),
                        ),
                        if (kind != EntryKind.note) ...[
                          const SizedBox(height: 6),
                          Text(
                            '提醒与常态',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          ReminderControls(
                            data: reminder,
                            onChanged: () => setState(() {}),
                          ),
                          const SizedBox(height: 16),
                          DropdownButtonFormField<String>(
                            initialValue: repeat,
                            decoration: const InputDecoration(labelText: '循环'),
                            items: repeatLabels.entries
                                .map(
                                  (value) => DropdownMenuItem(
                                    value: value.key,
                                    child: Text(value.value),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) =>
                                setState(() => repeat = value!),
                          ),
                          if (repeat == 'custom' || repeat == 'monthly') ...[
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    repeat == 'custom'
                                        ? '每 $intervalDays 天'
                                        : '每 $intervalMonths 个月',
                                  ),
                                ),
                                IconButton(
                                  tooltip: '减少间隔',
                                  onPressed: () => setState(() {
                                    if (repeat == 'custom' &&
                                        intervalDays > 1) {
                                      intervalDays--;
                                    }
                                    if (repeat == 'monthly' &&
                                        intervalMonths > 1) {
                                      intervalMonths--;
                                    }
                                  }),
                                  icon: const Icon(Icons.remove),
                                ),
                                IconButton(
                                  tooltip: '增加间隔',
                                  onPressed: () => setState(() {
                                    if (repeat == 'custom' &&
                                        intervalDays < 365) {
                                      intervalDays++;
                                    }
                                    if (repeat == 'monthly' &&
                                        intervalMonths < 12) {
                                      intervalMonths++;
                                    }
                                  }),
                                  icon: const Icon(Icons.add),
                                ),
                              ],
                            ),
                          ],
                          if (repeat == 'weekly') ...[
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 5,
                              runSpacing: 5,
                              children: List.generate(
                                7,
                                (i) => FilterChip(
                                  label: Text(
                                    ['一', '二', '三', '四', '五', '六', '日'][i],
                                  ),
                                  selected: weekdays.contains(i + 1),
                                  onSelected: (selected) => setState(() {
                                    selected
                                        ? weekdays.add(i + 1)
                                        : weekdays.remove(i + 1);
                                    weekdays.sort();
                                  }),
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            const Text('不选择星期时，按原事项日期每周循环。'),
                          ],
                          if (repeat == 'dates') ...[
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                ...repeatDates.map(
                                  (date) => InputChip(
                                    label: Text(dateLabel(date, time: false)),
                                    onDeleted: () => setState(
                                      () => repeatDates.remove(date),
                                    ),
                                  ),
                                ),
                                ActionChip(
                                  label: const Text('选择日期'),
                                  avatar: const Icon(Icons.add, size: 18),
                                  onPressed: () async {
                                    final date = await pick(
                                      widget.store.clock(),
                                      includeTime: false,
                                    );
                                    if (date != null &&
                                        !repeatDates.any(
                                          (d) => sameDay(d, date),
                                        )) {
                                      setState(() {
                                        repeatDates.add(date);
                                        repeatDates.sort();
                                      });
                                    }
                                  },
                                ),
                              ],
                            ),
                          ],
                        ],
                      ],
                      if (error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                            error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      const SizedBox(height: 10),
                      Text(
                        '先记下来即可，细节可以以后补充。',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  Widget timeButton(String label, DateTime date, VoidCallback onTap) =>
      SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: onTap,
          icon: const Icon(Icons.schedule),
          label: Text('$label  ${dateLabel(date, time: !allDay)}'),
        ),
      );
}
