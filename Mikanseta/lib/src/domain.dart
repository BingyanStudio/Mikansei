import 'dart:convert';
import 'dart:math';

String newId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join()
      .toUpperCase();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

// Foundation's JSONDecoder.iso8601 accepts whole seconds across the native
// deployment targets. Keep the beta's export readable by the original app.
String isoDate(DateTime value) =>
    value.toUtc().toIso8601String().replaceFirst(RegExp(r'\.\d+Z$'), 'Z');
DateTime dayOf(DateTime value) {
  final local = value.toLocal();
  return DateTime(local.year, local.month, local.day);
}

bool sameDay(DateTime a, DateTime b) => dayOf(a) == dayOf(b);
String clockLabel(DateTime value) {
  final local = value.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}

String dateLabel(DateTime value, {bool time = true}) {
  final local = value.toLocal();
  return '${local.month}/${local.day}${time ? ' ${clockLabel(local)}' : ''}';
}

String durationLabel(double value) {
  final seconds = value.floor();
  final minute = (seconds ~/ 60 % 60).toString().padLeft(2, '0');
  final second = (seconds % 60).toString().padLeft(2, '0');
  return seconds >= 3600
      ? '${seconds ~/ 3600}:$minute:$second'
      : '${seconds ~/ 60}:$second';
}

enum EntryKind {
  task('待办'),
  schedule('日程'),
  homework('作业'),
  note('笔记');

  const EntryKind(this.label);
  final String label;
}

const priorities = ['普通', '重要', '紧急'];
const repeatLabels = <String, String>{
  'never': '不重复',
  'daily': '每天',
  'everyThreeDays': '每 3 天',
  'weekly': '每周',
  'biweekly': '每两周',
  'monthly': '每月',
  'custom': '自定义间隔',
  'dates': '日历选日',
};

class StepItem {
  StepItem({String? id, required this.title, this.done = false})
    : id = id ?? newId();
  factory StepItem.fromJson(Map<String, dynamic> json) => StepItem(
    id: json['id'] as String,
    title: json['title'] as String,
    done: json['isDone'] as bool,
  );
  final String id;
  final String title;
  final bool done;
  StepItem toggle() => StepItem(id: id, title: title, done: !done);
  Map<String, dynamic> toJson() => {'id': id, 'title': title, 'isDone': done};
}

/// Retain native fields, including ones the beta does not yet edit.
class Entry {
  Entry(Map<String, dynamic> json) : data = Map.unmodifiable(json);
  factory Entry.create({
    String title = '',
    EntryKind kind = EntryKind.task,
    DateTime? now,
  }) {
    now ??= DateTime.now();
    final start = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour + 1,
      now.minute,
    );
    return Entry({
      'id': newId(),
      'title': title,
      'body': '',
      'kind': kind.name,
      'category': '',
      'priority': 0,
      'checklist': <Map<String, dynamic>>[],
      'isCompleted': false,
      'createdAt': isoDate(now),
      'updatedAt': isoDate(now),
      'platform': '',
      'location': '',
      'source': '',
      'repeatRule': 'never',
      'repeatIntervalDays': 1,
      'repeatIntervalMonths': 1,
      'repeatWeekdays': <int>[],
      'repeatDates': <String>[],
      'reminderPattern': 'single',
      'elapsedSeconds': 0,
      'plannedAllDay': false,
      'reminderDelivery': 'popup',
      'reminderAnchor': kind == EntryKind.schedule ? 'execution' : 'deadline',
      'reminderSound': 'system',
      'snoozeMinutes': 5,
      if (kind == EntryKind.schedule) 'plannedStart': isoDate(start),
      if (kind == EntryKind.schedule)
        'plannedEnd': isoDate(start.add(const Duration(minutes: 30))),
    });
  }
  final Map<String, dynamic> data;
  String get id => data['id'] as String;
  String get title => data['title'] as String;
  String get body => data['body'] as String;
  String get category => data['category'] as String;
  String get platform => data['platform'] as String? ?? '';
  String get location => data['location'] as String? ?? '';
  String get source => data['source'] as String? ?? '';
  EntryKind get kind => EntryKind.values.byName(data['kind'] as String);
  int get priority => data['priority'] as int;
  bool get completed => data['isCompleted'] as bool;
  bool get isTask => kind != EntryKind.note;
  bool get allDay => data['plannedAllDay'] as bool? ?? false;
  int? get estimate => data['estimatedMinutes'] as int?;
  String get repeatRule => data['repeatRule'] as String? ?? 'never';
  DateTime? date(String key) =>
      data[key] == null ? null : DateTime.parse(data[key] as String).toLocal();
  DateTime get createdAt => date('createdAt')!;
  DateTime get updatedAt => date('updatedAt')!;
  DateTime? get completedAt => date('completedAt');
  DateTime? get due => date('dueDate');
  DateTime? get start => date('plannedStart');
  DateTime? get end => date('plannedEnd');
  DateTime? get startedAt => date('startedAt');
  DateTime? get attention => kind == EntryKind.schedule
      ? start
      : due == null
      ? start
      : start == null
      ? due
      : due!.isBefore(start!)
      ? due
      : start;
  DateTime? get recurrenceDate =>
      kind == EntryKind.schedule ? start : due ?? start;
  List<StepItem> get steps => (data['checklist'] as List)
      .map((v) => StepItem.fromJson(Map<String, dynamic>.from(v as Map)))
      .toList();
  bool overdue(DateTime now) =>
      isTask &&
      kind != EntryKind.schedule &&
      !completed &&
      due != null &&
      due!.isBefore(now);
  bool onDay(DateTime day) {
    final nextDay = DateTime(day.year, day.month, day.day + 1);
    return due != null && sameDay(due!, day) ||
        start != null &&
            end != null &&
            start!.isBefore(nextDay) &&
            (end!.isAfter(dayOf(day)) || sameDay(start!, day));
  }

  bool matches(String query) => [
    title,
    body,
    category,
    platform,
    location,
    source,
    ...steps.map((e) => e.title),
  ].any((s) => s.toLowerCase().contains(query.trim().toLowerCase()));
  double focusSeconds(DateTime now) =>
      ((data['elapsedSeconds'] as num?)?.toDouble() ?? 0) +
      (startedAt == null
          ? 0
          : max(0, now.difference(startedAt!).inMilliseconds / 1000));
  Entry change(Map<String, dynamic> fields, {DateTime? now}) {
    var modified = DateTime.parse(isoDate(now ?? DateTime.now()));
    // Native backups use whole seconds. Distinct edits within one second must
    // still win a later backup merge instead of disappearing as timestamp ties.
    if (!modified.isAfter(updatedAt)) {
      modified = updatedAt.add(const Duration(seconds: 1));
    }
    return Entry({...data, ...fields, 'updatedAt': isoDate(modified)});
  }

  Entry pause(DateTime now) => startedAt == null
      ? this
      : change({
          'elapsedSeconds': focusSeconds(now),
          'startedAt': null,
        }, now: now);
  Entry setCompleted(bool done, DateTime now) {
    final entry = done ? pause(now) : this;
    return entry.change({
      'isCompleted': done,
      'completedAt': done ? isoDate(now) : null,
      if (done)
        'checklist': steps
            .map((s) => StepItem(id: s.id, title: s.title, done: true).toJson())
            .toList(),
    }, now: now);
  }

  Entry toggleStep(String stepId, DateTime now) {
    final next = steps.map((s) => s.id == stepId ? s.toggle() : s).toList();
    final reopened = completed && next.any((s) => !s.done);
    return change({
      'checklist': next.map((s) => s.toJson()).toList(),
      if (reopened) 'isCompleted': false,
      if (reopened) 'completedAt': null,
    }, now: now);
  }

  Entry? nextOccurrence(DateTime now) {
    final base = recurrenceDate;
    if (!isTask || repeatRule == 'never' || base == null) return null;
    final anchor = date('repeatAnchorDate') ?? base;
    final lower = now.isAfter(base) ? now : base;
    final selected = (data['repeatDates'] as List? ?? [])
        .map((d) => dayOf(DateTime.parse(d as String)))
        .toSet();
    final weekdays = (data['repeatWeekdays'] as List? ?? []).cast<int>();
    var day = dayOf(lower);
    final lastSelected = selected.isEmpty
        ? null
        : selected.reduce((a, b) => a.isAfter(b) ? a : b);
    final limitDays = repeatRule == 'dates' && lastSelected != null
        ? max(
                0,
                DateTime.utc(
                  lastSelected.year,
                  lastSelected.month,
                  lastSelected.day,
                ).difference(DateTime.utc(day.year, day.month, day.day)).inDays,
              ) +
              1
        : 366 * 5;
    for (var i = 0; i <= limitDays; i++) {
      final candidate = DateTime(
        day.year,
        day.month,
        day.day,
        base.hour,
        base.minute,
        base.second,
      );
      final gap = DateTime.utc(
        day.year,
        day.month,
        day.day,
      ).difference(DateTime.utc(anchor.year, anchor.month, anchor.day)).inDays;
      final monthGap = (day.year - anchor.year) * 12 + day.month - anchor.month;
      final lastDay = DateTime(day.year, day.month + 1, 0).day;
      final interval = switch (repeatRule) {
        'everyThreeDays' => 3,
        'weekly' => 7,
        'biweekly' => 14,
        'custom' => data['repeatIntervalDays'] as int? ?? 1,
        _ => 1,
      };
      final matches = switch (repeatRule) {
        'dates' => selected.contains(day),
        'monthly' =>
          monthGap >= 0 &&
              monthGap % (data['repeatIntervalMonths'] as int? ?? 1) == 0 &&
              day.day == min(anchor.day, lastDay),
        'weekly' when weekdays.isNotEmpty =>
          gap >= 0 && weekdays.contains(day.weekday),
        _ => gap >= 0 && gap % interval == 0,
      };
      if (matches && candidate.isAfter(lower)) {
        final dayGap = DateTime.utc(
          candidate.year,
          candidate.month,
          candidate.day,
        ).difference(DateTime.utc(base.year, base.month, base.day)).inDays;
        DateTime shift(DateTime value) => DateTime(
          value.year,
          value.month,
          value.day + dayGap,
          value.hour,
          value.minute,
          value.second,
        );
        final nextStart = start == null ? null : shift(start!);
        final nextEnd = end == null
            ? null
            : allDay
            ? shift(end!)
            : nextStart!.add(end!.difference(start!));
        final copy = {
          ...data,
          'id': newId(),
          'previousOccurrenceID': id,
          'repeatAnchorDate': isoDate(anchor),
          'isCompleted': false,
          'completedAt': null,
          'startedAt': null,
          'elapsedSeconds': 0,
          'createdAt': isoDate(now),
          'updatedAt': isoDate(now),
          'calendarEvent': null,
          'checklist': steps
              .map((s) => StepItem(title: s.title).toJson())
              .toList(),
          if (due != null) 'dueDate': isoDate(shift(due!)),
          if (nextStart != null) 'plannedStart': isoDate(nextStart),
          if (nextEnd != null) 'plannedEnd': isoDate(nextEnd),
        };
        return Entry(copy);
      }
      day = DateTime(day.year, day.month, day.day + 1);
    }
    return null;
  }
}

int entryOrder(Entry a, Entry b) {
  var result = b.priority.compareTo(a.priority);
  if (result != 0) return result;
  result = (a.attention ?? DateTime(9999)).compareTo(
    b.attention ?? DateTime(9999),
  );
  if (result != 0) return result;
  result = a.createdAt.compareTo(b.createdAt);
  return result == 0 ? a.id.compareTo(b.id) : result;
}

class TaskBoard {
  TaskBoard(this.entries, this.now);
  final List<Entry> entries;
  final DateTime now;
  List<Entry> get open =>
      entries.where((e) => e.isTask && !e.completed).toList()..sort(entryOrder);
  List<Entry> get overdue => open.where((e) => e.overdue(now)).toList();
  List<Entry> get finishedToday =>
      entries
          .where(
            (e) =>
                e.isTask &&
                e.completed &&
                e.completedAt != null &&
                sameDay(e.completedAt!, now),
          )
          .toList()
        ..sort((a, b) => a.completedAt!.compareTo(b.completedAt!));
  List<Entry> get history =>
      entries
          .where(
            (e) =>
                e.isTask &&
                e.completed &&
                (e.completedAt == null || !sameDay(e.completedAt!, now)),
          )
          .toList()
        ..sort(
          (a, b) => (b.completedAt ?? DateTime(1900)).compareTo(
            a.completedAt ?? DateTime(1900),
          ),
        );
  List<Entry> get visible => [
    ...overdue,
    ...open.where((e) => !e.overdue(now)),
    ...finishedToday,
  ];
  List<Entry> get focus => [
    ...overdue,
    ...open.where(
      (e) =>
          !e.overdue(now) &&
          (e.onDay(now) ||
              e.attention == null ||
              e.attention!.isBefore(dayOf(now))),
    ),
    ...finishedToday,
  ];
}

class Archive {
  Archive({required this.entries, Map<String, dynamic>? metadata})
    : metadata =
          metadata ??
          {
            'version': 1,
            'courses': <dynamic>[],
            'calendarSync': {
              'enabled': false,
              'timing': 'start',
              'selected': <dynamic>[],
              'suppressed': <dynamic>[],
            },
          };
  final List<Entry> entries;
  final Map<String, dynamic> metadata;
  factory Archive.decode(String text) {
    final json = jsonDecode(text);
    if (json is! Map<String, dynamic> || json['version'] != 1) {
      throw const FormatException('备份格式或版本不支持，原数据未修改。');
    }
    if (json['entries'] is! List) throw const FormatException('备份缺少事项列表。');
    final entries = (json['entries'] as List)
        .map((e) => Entry(Map<String, dynamic>.from(e as Map)))
        .toList();
    final ids = <String>{};
    for (final entry in entries) {
      validateEntry(entry);
      if (!ids.add(entry.id.toUpperCase())) {
        throw const FormatException('备份包含重复事项编号。');
      }
    }
    final courseIDs = <String>{};
    for (final course in json['courses'] as List? ?? []) {
      if (course is! Map ||
          course['id'] is! String ||
          course['name'] is! String ||
          (course['name'] as String).trim().isEmpty ||
          !courseIDs.add((course['id'] as String).toUpperCase())) {
        throw const FormatException('课表编号或名称无效。');
      }
      final weekday = course['weekday'] as int;
      final begin = course['startMinutes'] as int;
      final end = course['endMinutes'] as int;
      if (weekday < 1 ||
          weekday > 7 ||
          begin < 0 ||
          end >= 1440 ||
          end <= begin ||
          DateTime.parse(course['lastDate'] as String)
              .isBefore(DateTime.parse(course['firstDate'] as String))) {
        throw const FormatException('课表时间无效。');
      }
    }
    final calendar = json['calendarSync'] as Map?;
    final selectedIDs = <String>{};
    for (final selection in calendar?['selected'] as List? ?? []) {
      if (selection is! Map ||
          selection['id'] is! String ||
          !selectedIDs.add(selection['id'] as String)) {
        throw const FormatException('日历选择含重复或无效编号。');
      }
    }
    return Archive(entries: entries, metadata: {...json}..remove('entries'));
  }
  String encode() => const JsonEncoder.withIndent('  ').convert({
    ...metadata,
    'version': 1,
    'entries': entries.map((e) => e.data).toList(),
  });
  Archive withEntries(List<Entry> next) =>
      Archive(entries: next, metadata: metadata);
  Archive merge(Archive other) {
    final indexed = {for (final e in entries) e.id.toUpperCase(): e};
    for (final entry in other.entries) {
      final existing = indexed[entry.id.toUpperCase()];
      if (existing == null || entry.updatedAt.isAfter(existing.updatedAt)) {
        indexed[entry.id.toUpperCase()] = entry;
      }
    }
    final courses = <String, dynamic>{};
    for (final course in [
      ...(other.metadata['courses'] as List? ?? []),
      ...(metadata['courses'] as List? ?? []),
    ]) {
      courses[(course['id'] as String).toUpperCase()] = course;
    }
    // A backup is a copy. A native replica belongs to its source device and must
    // not be replayed after editing these records on an independent beta device.
    final mergedMetadata = {
      ...metadata,
      ...other.metadata,
      'courses': courses.values.toList(),
    }..remove('replica');
    return Archive(entries: indexed.values.toList(), metadata: mergedMetadata);
  }
}

void validateEntry(Entry e) {
  final uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );
  if (!uuid.hasMatch(e.id) ||
      e.title.trim().isEmpty ||
      ![0, 1, 2].contains(e.priority)) {
    throw const FormatException('事项标题、编号或重要级无效。');
  }
  e.kind;
  e.body;
  e.category;
  e.completed;
  e.createdAt;
  e.updatedAt;
  for (final key in [
    'dueDate',
    'plannedStart',
    'plannedEnd',
    'completedAt',
    'startedAt',
    'repeatAnchorDate',
  ]) {
    e.date(key);
  }
  final steps = e.steps;
  if (steps.map((s) => s.id.toUpperCase()).toSet().length != steps.length ||
      steps.any((s) => !uuid.hasMatch(s.id))) {
    throw const FormatException('Checklist 编号无效。');
  }
  if (e.kind == EntryKind.schedule && (e.start == null || e.end == null) ||
      (e.start == null) != (e.end == null) ||
      e.start != null && e.end!.isBefore(e.start!)) {
    throw const FormatException('日程起止时间无效。');
  }
  final seconds = (e.data['elapsedSeconds'] as num?)?.toDouble() ?? 0;
  if (!seconds.isFinite ||
      seconds < 0 ||
      e.estimate != null && (e.estimate! < 1 || e.estimate! > 1440)) {
    throw const FormatException('计时或预计用时无效。');
  }
  if (!repeatLabels.containsKey(e.repeatRule) ||
      e.repeatRule != 'never' && (!e.isTask || e.recurrenceDate == null)) {
    throw const FormatException('循环规则无效。');
  }
  for (final pair in [
    ('repeatIntervalDays', 365),
    ('repeatIntervalMonths', 12),
  ]) {
    final value = e.data[pair.$1] as int? ?? 1;
    if (value < 1 || value > pair.$2) throw const FormatException('循环间隔无效。');
  }
  final weekdays = (e.data['repeatWeekdays'] as List? ?? []).cast<int>();
  if (weekdays.any((d) => d < 1 || d > 7)) {
    throw const FormatException('循环星期无效。');
  }
  final dates = e.data['repeatDates'] as List? ?? [];
  for (final date in dates) {
    DateTime.parse(date as String);
  }
  if (e.repeatRule == 'dates' && dates.isEmpty) {
    throw const FormatException('循环日期为空。');
  }
  if (![5, 10, 15].contains(e.data['snoozeMinutes'] ?? 5)) {
    throw const FormatException('稍后提醒间隔无效。');
  }
  if (e.data['reminder'] != null &&
      (!e.isTask ||
          e.attention == null ||
          ![0, 300, 900, 3600, 86400].contains(e.data['reminder']))) {
    throw const FormatException('提醒设置无效。');
  }
}
