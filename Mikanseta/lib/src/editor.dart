import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'domain.dart';
import 'store.dart';

class EntryEditor extends StatefulWidget {
  const EntryEditor({
    super.key,
    required this.store,
    this.entry,
    this.kind,
    this.start,
  });
  final EntryStore store;
  final Entry? entry;
  final EntryKind? kind;
  final DateTime? start;
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
  late final TextEditingController checklist;
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
  @override
  void initState() {
    super.initState();
    draft =
        widget.entry ??
        Entry.create(
          kind: widget.kind ?? EntryKind.task,
          now: widget.store.clock(),
        );
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
    end = widget.start == null
        ? draft.end ?? start.add(const Duration(minutes: 30))
        : start.add(const Duration(minutes: 30));
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
    checklist = TextEditingController(
      text: draft.steps.map((s) => s.title).join('\n'),
    );
    advanced = widget.entry != null;
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
      checklist,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

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

  void save() {
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
    final oldSteps = draft.steps;
    final lines = checklist.text
        .split('\n')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    final unmatched = List<StepItem>.of(oldSteps);
    final steps = lines.map((line) {
      final index = unmatched.indexWhere((step) => step.title == line);
      if (index >= 0) return unmatched.removeAt(index);
      return StepItem(title: line, done: draft.completed);
    }).toList();
    final changedKind = kind != draft.kind;
    var next = draft.change({
      'title': cleanTitle,
      'body': body.text.trim(),
      'kind': kind.name,
      'priority': priority,
      'category': category.text.trim(),
      'platform': platform.text.trim(),
      'location': location.text.trim(),
      'estimatedMinutes': minutes,
      'checklist': steps.map((s) => s.toJson()).toList(),
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
      if (kind == EntryKind.note) 'startedAt': null,
      if (kind == EntryKind.note) 'elapsedSeconds': 0,
    }, now: widget.store.clock());
    if (next.attention == null) {
      next = next.change({'reminder': null, 'repeatRule': 'never'});
    }
    if (next.repeatRule != 'never' && next.date('repeatAnchorDate') == null) {
      next = next.change({'repeatAnchorDate': isoDate(next.recurrenceDate!)});
    }
    try {
      widget.store.save(next);
      Navigator.pop(context);
    } catch (exception) {
      setState(() => error = '无法保存：$exception');
    }
  }

  @override
  Widget build(BuildContext context) => Dialog(
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
                    widget.entry == null ? '记下一件事' : '编辑事项',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: '关闭',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 12, 22, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    key: const ValueKey('entry-title'),
                    controller: title,
                    autofocus: widget.entry == null,
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
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: EntryKind.values
                        .map(
                          (value) => ChoiceChip(
                            label: Text(value.label),
                            selected: kind == value,
                            onSelected: (_) => setState(() => kind = value),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 14),
                  if (kind != EntryKind.note) ...[
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: List.generate(
                        3,
                        (value) => ChoiceChip(
                          label: Text(priorities[value]),
                          selected: priority == value,
                          onSelected: (_) => setState(() => priority = value),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (kind == EntryKind.schedule) ...[
                      timeButton('开始', start, () async {
                        final date = await pick(start, includeTime: !allDay);
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
                              icon: const Icon(Icons.event_outlined),
                              label: Text(
                                due == null
                                    ? '添加 DDL（可选）'
                                    : 'DDL ${dateLabel(due!)}',
                              ),
                              onPressed: () async {
                                final date = await pick(
                                  due ??
                                      widget.store.clock().add(
                                        const Duration(days: 1),
                                      ),
                                );
                                if (date != null) setState(() => due = date);
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
                    label: const Text('备注、Checklist 与更多信息'),
                  ),
                  if (advanced) ...[
                    TextField(
                      controller: body,
                      minLines: 2,
                      maxLines: 6,
                      decoration: const InputDecoration(labelText: '备注'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: checklist,
                      minLines: 2,
                      maxLines: 8,
                      decoration: const InputDecoration(
                        labelText: 'Checklist',
                        hintText: '每行一个步骤',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: category,
                      decoration: const InputDecoration(labelText: '科目 / 分类'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: platform,
                      decoration: const InputDecoration(labelText: '提交 / 处理平台'),
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
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(labelText: '预计用时（分钟）'),
                    ),
                    if (kind != EntryKind.note) ...[
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
                        onChanged: (value) => setState(() => repeat = value!),
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
                                if (repeat == 'custom' && intervalDays > 1) {
                                  intervalDays--;
                                }
                                if (repeat == 'monthly' && intervalMonths > 1) {
                                  intervalMonths--;
                                }
                              }),
                              icon: const Icon(Icons.remove),
                            ),
                            IconButton(
                              tooltip: '增加间隔',
                              onPressed: () => setState(() {
                                if (repeat == 'custom' && intervalDays < 365) {
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
                                onDeleted: () =>
                                    setState(() => repeatDates.remove(date)),
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
                                    !repeatDates.any((d) => sameDay(d, date))) {
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
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 8, 22, 18),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    key: const ValueKey('save-entry'),
                    onPressed: widget.store.readOnly ? null : save,
                    icon: const Icon(Icons.check),
                    label: const Text('保存'),
                  ),
                ),
              ],
            ),
          ),
        ],
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
