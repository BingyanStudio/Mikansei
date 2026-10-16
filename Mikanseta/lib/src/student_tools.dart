import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'domain.dart';
import 'store.dart';
import 'editor.dart';
import 'system_services.dart' show requestReminderAccess;

class Course {
  Course(this.data);
  factory Course.create() {
    final now = DateTime.now();
    return Course({
      'id': newId(),
      'name': '',
      'weekday': now.weekday,
      'startMinutes': 480,
      'endMinutes': 580,
      'location': '',
      'platform': '',
      'firstDate': isoDate(dayOf(now)),
      'lastDate': isoDate(DateTime(now.year, now.month, now.day + 112)),
      'reminderEnabled': true,
      'reminderDelivery': 'popup',
      'reminderSound': 'system',
      'snoozeMinutes': 5,
    });
  }
  final Map<String, dynamic> data;
  String get id => data['id'] as String;
  String get name => data['name'] as String;
  int get weekday => data['weekday'] as int;
  int get begin => data['startMinutes'] as int;
  int get end => data['endMinutes'] as int;
  DateTime get first => dayOf(DateTime.parse(data['firstDate'] as String));
  DateTime get last => dayOf(DateTime.parse(data['lastDate'] as String));
  bool occurs(DateTime d) =>
      d.weekday == weekday &&
      !dayOf(d).isBefore(first) &&
      !dayOf(d).isAfter(last);
  String get label =>
      '周${['一', '二', '三', '四', '五', '六', '日'][weekday - 1]} ${time(begin)}–${time(end)}';
  static String time(int m) =>
      '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
  Entry homework() => Entry.create(kind: EntryKind.homework).change({
    'category': name,
    'platform': data['platform'] ?? '',
    'source': '课后登记：$name · $label',
  });
  void validate() {
    if (name.trim().isEmpty ||
        weekday < 1 ||
        weekday > 7 ||
        begin < 0 ||
        end >= 1440 ||
        end <= begin ||
        last.isBefore(first) ||
        ![5, 10, 15].contains(data['snoozeMinutes'] ?? 5)) {
      throw const FormatException('课程名称、时间或日期范围无效。');
    }
  }
}

const courseHeader = '课程,星期,开始时间,结束时间,地点,提交平台,开始日期,结束日期';
List<List<String>> csvRows(String input) {
  final text = input
      .replaceFirst('\uFEFF', '')
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n');
  final rows = <List<String>>[];
  var row = <String>[], field = '', quoted = false, closed = false;
  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (quoted) {
      if (c == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          field += '"';
          i++;
        } else {
          quoted = false;
          closed = true;
        }
      } else {
        field += c;
      }
    } else if (c == ',' || c == '\n') {
      row.add(field);
      field = '';
      closed = false;
      if (c == '\n') {
        if (row.any((s) => s.isNotEmpty)) rows.add(row);
        row = [];
      }
    } else if (c == '"' && field.isEmpty && !closed) {
      quoted = true;
    } else if (closed || c == '"') {
      throw const FormatException('CSV 引号位置无效。');
    } else {
      field += c;
    }
  }
  if (quoted) throw const FormatException('CSV 引号未闭合。');
  row.add(field);
  if (row.any((s) => s.isNotEmpty)) rows.add(row);
  return rows;
}

DateTime strictDate(String input) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(input);
  if (m == null) throw const FormatException('日期使用 yyyy-MM-dd。');
  final d = DateTime(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
  if (d.year != int.parse(m[1]!) ||
      d.month != int.parse(m[2]!) ||
      d.day != int.parse(m[3]!)) {
    throw const FormatException('日期无效。');
  }
  return d;
}

List<Course> parseCourseCSV(String text) {
  final rows = csvRows(text);
  if (rows.isEmpty || rows.first.join(',') != courseHeader) {
    throw const FormatException('请使用课表 CSV 的 8 列模板。');
  }
  int minute(String s) {
    final m = RegExp(r'^([01]?\d|2[0-3]):([0-5]\d)$').firstMatch(s);
    if (m == null) throw const FormatException('时间使用 HH:mm。');
    return int.parse(m[1]!) * 60 + int.parse(m[2]!);
  }

  return rows.skip(1).map((r) {
    if (r.length != 8) throw const FormatException('课表每行需要 8 列。');
    final c = Course({
      ...Course.create().data,
      'name': r[0].trim(),
      'weekday': int.parse(r[1]),
      'startMinutes': minute(r[2]),
      'endMinutes': minute(r[3]),
      'location': r[4],
      'platform': r[5],
      'firstDate': isoDate(strictDate(r[6])),
      'lastDate': isoDate(strictDate(r[7])),
    });
    c.validate();
    return c;
  }).toList();
}

class _Property {
  _Property(this.name, this.params, this.value);
  final String name, value;
  final Map<String, String> params;
}

bool _zonesReady = false;
List<Course> parseCourseICS(String text) {
  if (!_zonesReady) {
    tzdata.initializeTimeZones();
    _zonesReady = true;
  }
  final lines = <String>[];
  for (final line
      in text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n')) {
    if ((line.startsWith(' ') || line.startsWith('\t')) && lines.isNotEmpty) {
      lines[lines.length - 1] += line.substring(1);
    } else {
      lines.add(line);
    }
  }
  if (!lines.contains('BEGIN:VCALENDAR') || !lines.contains('END:VCALENDAR')) {
    throw const FormatException('不是有效的 ICS 文件。');
  }
  final events = <List<_Property>>[];
  List<_Property>? current;
  var depth = 0;
  for (final line in lines) {
    if (line == 'BEGIN:VEVENT') {
      if (current != null) throw const FormatException('事件嵌套无效。');
      current = [];
      depth = 0;
    } else if (line == 'END:VEVENT') {
      if (current == null || depth != 0) throw const FormatException('事件结束无效。');
      events.add(current);
      current = null;
    } else if (current != null) {
      if (line.startsWith('BEGIN:')) {
        depth++;
        continue;
      }
      if (line.startsWith('END:')) {
        depth--;
        continue;
      }
      if (depth > 0 || line.isEmpty) continue;
      final colon = line.indexOf(':');
      if (colon < 0) throw const FormatException('ICS 属性无效。');
      final head = line.substring(0, colon).split(';');
      final params = <String, String>{};
      for (final v in head.skip(1)) {
        final pair = v.split('=');
        if (pair.length != 2) throw const FormatException('ICS 参数无效。');
        params[pair[0].toUpperCase()] = pair[1].replaceAll('"', '');
      }
      current.add(
        _Property(head.first.toUpperCase(), params, line.substring(colon + 1)),
      );
    }
  }
  if (current != null) throw const FormatException('ICS 事件未结束。');
  DateTime date(_Property p) {
    final m = RegExp(r'^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})(Z?)$')
        .firstMatch(p.value);
    if (m == null ||
        p.params['VALUE'] != null && p.params['VALUE'] != 'DATE-TIME') {
      throw const FormatException('课程必须有具体时刻，不支持全天课程。');
    }
    final v = List.generate(6, (i) => int.parse(m[i + 1]!));
    final zone = p.value.endsWith('Z')
        ? tz.UTC
        : p.params['TZID'] == null
        ? null
        : tz.getLocation(p.params['TZID']!);
    final d = zone == null
        ? DateTime(v[0], v[1], v[2], v[3], v[4], v[5])
        : tz.TZDateTime(zone, v[0], v[1], v[2], v[3], v[4], v[5]);
    if (d.year != v[0] ||
        d.month != v[1] ||
        d.day != v[2] ||
        d.hour != v[3] ||
        d.minute != v[4] ||
        d.second != v[5]) {
      throw const FormatException('ICS 日期无效。');
    }
    return d;
  }

  DateTime offsetDay(DateTime base, int days) => base is tz.TZDateTime
      ? tz.TZDateTime(
          base.location,
          base.year,
          base.month,
          base.day + days,
          base.hour,
          base.minute,
          base.second,
        )
      : DateTime(
          base.year,
          base.month,
          base.day + days,
          base.hour,
          base.minute,
          base.second,
        );
  String unescape(String s) => s
      .replaceAll(RegExp(r'\\[nN]'), '\n')
      .replaceAll(r'\,', ',')
      .replaceAll(r'\;', ';')
      .replaceAll(r'\\', r'\');
  final result = <Course>[];
  for (final event in events) {
    _Property? get(String key) => event.where((p) => p.name == key).firstOrNull;
    if (get('RECURRENCE-ID') != null) {
      throw const FormatException('调课覆盖请先展开为逐次事件再导入。');
    }
    if (get('STATUS')?.value == 'CANCELLED') continue;
    final startProp = get('DTSTART'), summary = get('SUMMARY');
    if (startProp == null || summary == null) {
      throw const FormatException('课程缺少名称或开始时间。');
    }
    final start = date(startProp);
    DateTime end;
    if (get('DTEND') != null) {
      end = date(get('DTEND')!);
    } else {
      final m = RegExp(r'^PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?$')
          .firstMatch(get('DURATION')?.value ?? '');
      if (m == null) throw const FormatException('课程缺少结束时间。');
      end = start.add(
        Duration(
          seconds:
              int.parse(m[1] ?? '0') * 3600 +
              int.parse(m[2] ?? '0') * 60 +
              int.parse(m[3] ?? '0'),
        ),
      );
    }
    if (!end.isAfter(start) ||
        end.difference(start) >= const Duration(days: 1) ||
        start.second != 0 ||
        end.second != 0) {
      throw const FormatException('课程应在同一天结束，并精确到分钟。');
    }
    final dates = <DateTime>[start];
    final rules = event.where((p) => p.name == 'RRULE').toList();
    if (rules.length > 1) throw const FormatException('不支持多条循环规则。');
    if (rules.isNotEmpty) {
      final rule = <String, String>{};
      for (final part in rules.single.value.split(';')) {
        final pair = part.split('=');
        if (pair.length != 2 || rule.containsKey(pair[0])) {
          throw const FormatException('RRULE 无效。');
        }
        rule[pair[0]] = pair[1];
      }
      if (!rule.keys.every(
            ['FREQ', 'INTERVAL', 'BYDAY', 'UNTIL', 'COUNT', 'WKST'].contains,
          ) ||
          !['DAILY', 'WEEKLY'].contains(rule['FREQ']) ||
          rule['WKST'] != null && rule['WKST'] != 'MO') {
        throw const FormatException('仅支持有学期范围的 DAILY/WEEKLY 循环。');
      }
      final interval = int.tryParse(rule['INTERVAL'] ?? '1') ?? 0,
          count = rule['COUNT'] == null ? null : int.tryParse(rule['COUNT']!);
      final until = rule['UNTIL'] == null
          ? null
          : date(_Property('UNTIL', startProp.params, rule['UNTIL']!));
      if (interval < 1 ||
          interval > 52 ||
          (rule['COUNT'] == null) == (until == null) ||
          rule['COUNT'] != null &&
              (count == null || count < 1 || count > 2048) ||
          until != null && until.isAfter(offsetDay(start, 732))) {
        throw const FormatException('循环需限定 COUNT 或 UNTIL（最多两年、2048 次）。');
      }
      final codes = {
        'MO': 1,
        'TU': 2,
        'WE': 3,
        'TH': 4,
        'FR': 5,
        'SA': 6,
        'SU': 7,
      };
      final weekdays =
          rule['BYDAY']?.split(',').map((v) => codes[v] ?? 0).toSet() ??
          {start.weekday};
      if (weekdays.contains(0) ||
          rule['FREQ'] == 'DAILY' && rule.containsKey('BYDAY') ||
          rule['FREQ'] == 'WEEKLY' && !weekdays.contains(start.weekday)) {
        throw const FormatException('BYDAY 与开始日期不匹配或暂不支持。');
      }
      dates.clear();
      for (var i = 0; i <= 732; i++) {
        final d = offsetDay(start, i);
        if (until != null && d.isAfter(until)) break;
        final hit = rule['FREQ'] == 'DAILY'
            ? i % interval == 0
            : ((i + start.weekday - 1) ~/ 7) % interval == 0 &&
                  weekdays.contains(d.weekday);
        if (hit) {
          dates.add(d);
          if (count != null && dates.length >= count) break;
        }
      }
      if (count != null && dates.length != count) {
        throw const FormatException('无法在两年内展开所有课程。');
      }
    }
    for (final p in event.where((p) => p.name == 'RDATE')) {
      for (final v in p.value.split(',')) {
        dates.add(date(_Property(p.name, p.params, v)));
      }
    }
    final excluded = <int>{};
    for (final p in event.where((p) => p.name == 'EXDATE')) {
      for (final v in p.value.split(',')) {
        excluded.add(
          date(_Property(p.name, p.params, v)).millisecondsSinceEpoch,
        );
      }
    }
    final unique = <int>{};
    for (final occurrence in dates) {
      if (excluded.contains(occurrence.millisecondsSinceEpoch) ||
          !unique.add(occurrence.millisecondsSinceEpoch)) {
        continue;
      }
      final a = DateTime.fromMillisecondsSinceEpoch(
            occurrence.millisecondsSinceEpoch,
          ),
          b = DateTime.fromMillisecondsSinceEpoch(
            occurrence.add(end.difference(start)).millisecondsSinceEpoch,
          );
      if (!sameDay(a, b)) throw const FormatException('换算到本机时区后课程跨天，请手动录入。');
      final c = Course({
        ...Course.create().data,
        'name': unescape(summary.value),
        'weekday': a.weekday,
        'startMinutes': a.hour * 60 + a.minute,
        'endMinutes': b.hour * 60 + b.minute,
        'firstDate': isoDate(dayOf(a)),
        'lastDate': isoDate(dayOf(a)),
        'location': unescape(get('LOCATION')?.value ?? ''),
      });
      c.validate();
      result.add(c);
      if (result.length > 2048) {
        throw const FormatException('请按学期拆分，最多导入 2048 次课程。');
      }
    }
  }
  if (result.isEmpty) throw const FormatException('没有可导入的课程。');
  return result;
}

(Entry, List<String>) parseMessage(String text, DateTime now) {
  final raw = text.trim(), assumptions = <String>[];
  var e = Entry.create(
    title: raw
        .split('\n')
        .first
        .trim()
        .substring(0, math.min(80, raw.split('\n').first.trim().length)),
    kind: raw.contains('作业') ? EntryKind.homework : EntryKind.task,
  );
  String? capture(String pattern, int group) =>
      RegExp(pattern, caseSensitive: false).firstMatch(raw)?.group(group);
  final platform =
      [
        '学习通',
        '雨课堂',
        '智慧树',
        'Moodle',
        'Canvas',
        'QQ群',
        '邮箱',
        '腾讯文档',
        '问卷星',
        '飞书',
        '钉钉',
      ].where((s) => raw.toLowerCase().contains(s.toLowerCase())).firstOrNull ??
      '';
  final fields = <String, dynamic>{
    'source': raw,
    'platform': platform,
    'category': capture(r'[【\[]([^】\]]{1,20})[】\]]', 1) ?? '',
  };
  final minutes = RegExp(r'(?:预计|大约|约|耗时)\s*(\d{1,3})\s*(分钟|小时)')
      .firstMatch(raw);
  if (minutes != null) {
    final m = int.parse(minutes[1]!) * (minutes[2] == '小时' ? 60 : 1);
    if (m > 0 && m <= 1440) fields['estimatedMinutes'] = m;
  }
  DateTime? day;
  final absolute = RegExp(r'(20\d{2})[-/年](\d{1,2})[-/月](\d{1,2})(?:日)?')
          .firstMatch(raw),
      short = RegExp(r'(\d{1,2})月(\d{1,2})日').firstMatch(raw);
  if (absolute != null) {
    day = DateTime(
      int.parse(absolute[1]!),
      int.parse(absolute[2]!),
      int.parse(absolute[3]!),
    );
    if (day.month != int.parse(absolute[2]!) ||
        day.day != int.parse(absolute[3]!)) {
      day = null;
      assumptions.add('日期无效，请手动补充。');
    }
  } else if (short != null) {
    day = DateTime(now.year, int.parse(short[1]!), int.parse(short[2]!));
    if (day.month != int.parse(short[1]!) || day.day != int.parse(short[2]!)) {
      day = null;
    }
    assumptions.add('未写年份，按当前年份建议。');
  } else {
    for (final pair in [('后天', 2), ('明天', 1), ('今天', 0)]) {
      if (raw.contains(pair.$1)) {
        day = DateTime(now.year, now.month, now.day + pair.$2);
        assumptions.add('相对日期按今天解析，旧消息请改日期。');
        break;
      }
    }
  }
  if (day != null) {
    final clock = RegExp(r'(?<!\d)([01]?\d|2[0-3])[:：]([0-5]\d)(?!\d)')
        .firstMatch(raw);
    if (clock == null) assumptions.add('未识别时刻，暂建议 23:59。');
    final due = DateTime(
      day.year,
      day.month,
      day.day,
      int.parse(clock?[1] ?? '23'),
      int.parse(clock?[2] ?? '59'),
    );
    fields['dueDate'] = isoDate(due);
    if (due.isBefore(now)) assumptions.add('建议日期已过去，请核对。');
  } else {
    assumptions.add('未可靠识别截止日期，星期需手动确认。');
  }
  final count = RegExp(
    r'20\d{2}[-/年]\d{1,2}[-/月]\d{1,2}(?:日)?|(?<![-/年])\b\d{1,2}月\d{1,2}日|今天|明天|后天',
  ).allMatches(raw).length;
  if (count > 1) {
    fields['dueDate'] = null;
    assumptions.add('含多个日期，未自动设置 DDL。');
  }
  if (fields['dueDate'] != null) fields['reminder'] = 0;
  e = e.change(fields);
  return (e, assumptions);
}

class CoursesPage extends StatefulWidget {
  const CoursesPage({super.key, required this.store});
  final EntryStore store;
  @override
  State<CoursesPage> createState() => _CoursesPageState();
}

class _CoursesPageState extends State<CoursesPage> {
  Future<void> edit(Course? value) async {
    await showDialog<void>(
      context: context,
      builder: (_) =>
          CourseEditor(store: widget.store, course: value ?? Course.create()),
    );
    if (mounted) setState(() {});
  }

  Future<void> import() async {
    await showDialog<void>(
      context: context,
      builder: (_) => _CourseImportDialog(store: widget.store),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('课表与下课登记'),
      actions: [
        IconButton(
          tooltip: '导入课表',
          onPressed: widget.store.readOnly ? null : import,
          icon: const Icon(Icons.file_open),
        ),
        IconButton(
          tooltip: '添加课程',
          onPressed: widget.store.readOnly ? null : () => edit(null),
          icon: const Icon(Icons.add),
        ),
      ],
    ),
    body: ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) => ListView(
        children: [
          const ListTile(
            title: Text('下课时提醒：有什么作业？DDL、平台、预计多久？'),
            subtitle: Text('点击提醒或课程的登记按钮，预填课程与提交平台。'),
          ),
          ...widget.store.courses.map(
            (c) => ListTile(
              title: Text(c.name),
              subtitle: Text(
                '${c.label}\n${dateLabel(c.first, time: false)}—${dateLabel(c.last, time: false)} · ${c.data['platform']}',
              ),
              onTap: () => edit(c),
              trailing: TextButton(
                onPressed: widget.store.readOnly
                    ? null
                    : () => showDialog<void>(
                        context: context,
                        builder: (_) => EntryEditor(
                          store: widget.store,
                          entry: c.homework(),
                          isNew: true,
                        ),
                      ),
                child: const Text('登记作业'),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _CourseImportDialog extends StatefulWidget {
  const _CourseImportDialog({required this.store});
  final EntryStore store;
  @override
  State<_CourseImportDialog> createState() => _CourseImportDialogState();
}

class _CourseImportDialogState extends State<_CourseImportDialog> {
  final controller = TextEditingController();
  List<Course>? preview;
  bool reminders = true, busy = false;
  String? error;
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> read() async {
    setState(() => busy = true);
    try {
      final text = await NativeStorage.channel.invokeMethod<String>(
        'importText',
      );
      if (mounted && text != null) {
        controller.text = text;
        setState(() => preview = null);
      }
    } catch (e) {
      if (mounted) setState(() => error = '读取文件失败：$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> submit() async {
    try {
      if (preview == null) {
        final parsed = controller.text.contains('BEGIN:VCALENDAR')
            ? parseCourseICS(controller.text)
            : parseCourseCSV(controller.text);
        if (parsed.isEmpty) throw const FormatException('文件里没有课程。');
        setState(() {
          preview = parsed;
          error = null;
        });
        return;
      }
      setState(() => busy = true);
      final count = widget.store.importCourses(
        preview!
            .map((c) => Course({...c.data, 'reminderEnabled': reminders}))
            .toList(),
      );
      await widget.store.settled;
      if (widget.store.saveFailed) throw StateError('尚未写入磁盘，请重试保存。');
      final allowed =
          !reminders ||
          widget.store.storage is! NativeStorage ||
          await requestReminderAccess('popup');
      await widget.store.refreshServices();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('新增 $count 条课程${allowed ? '' : '，通知权限尚未开启'}')),
      );
      Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AlertDialog(
      title: const Text('导入 CSV / ICS 课表'),
      content: SizedBox(
        width: 550,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                enabled: !busy,
                minLines: 5,
                maxLines: 10,
                decoration: const InputDecoration(labelText: '粘贴课表文件内容'),
                onChanged: (_) => setState(() => preview = null),
              ),
              TextButton(
                onPressed: busy ? null : read,
                child: const Text('从文件读取'),
              ),
              TextButton(
                onPressed: () => Clipboard.setData(
                  const ClipboardData(
                    text:
                        '$courseHeader\n高等数学,1,08:00,09:40,教室,学习通,2026-09-01,2027-01-15',
                  ),
                ),
                child: const Text('复制 CSV 模板'),
              ),
              if (error != null) Text(error!),
              if (preview != null) ...[
                Text('识别 ${preview!.length} 条课程，请核对'),
                SwitchListTile(
                  title: const Text('下课提醒登记作业'),
                  value: reminders,
                  onChanged: busy ? null : (v) => setState(() => reminders = v),
                ),
                ...preview!
                    .take(20)
                    .map(
                      (c) => Text(
                        '${c.name} · ${c.label} · ${dateLabel(c.first, time: false)}—${dateLabel(c.last, time: false)}',
                      ),
                    ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: busy ? null : submit,
          child: Text(preview == null ? '预览' : '确认导入'),
        ),
      ],
    ),
  );
}

class CourseEditor extends StatefulWidget {
  const CourseEditor({super.key, required this.store, required this.course});
  final EntryStore store;
  final Course course;
  @override
  State<CourseEditor> createState() => _CourseEditorState();
}

class _CourseEditorState extends State<CourseEditor> {
  late final data = {...widget.course.data};
  late final name = TextEditingController(text: data['name'] as String),
      location = TextEditingController(text: data['location'] as String),
      platform = TextEditingController(text: data['platform'] as String);
  String? error;
  @override
  void dispose() {
    name.dispose();
    location.dispose();
    platform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('课程设置'),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: '课程名称'),
            ),
            DropdownButtonFormField<int>(
              initialValue: data['weekday'] as int,
              items: List.generate(
                7,
                (i) => DropdownMenuItem(
                  value: i + 1,
                  child: Text('周${['一', '二', '三', '四', '五', '六', '日'][i]}'),
                ),
              ),
              onChanged: (v) => data['weekday'] = v,
            ),
            for (final pair in [('startMinutes', '上课'), ('endMinutes', '下课')])
              TextButton(
                onPressed: () async {
                  final old = data[pair.$1] as int;
                  final time = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay(hour: old ~/ 60, minute: old % 60),
                  );
                  if (time != null) {
                    setState(
                      () => data[pair.$1] = time.hour * 60 + time.minute,
                    );
                  }
                },
                child: Text('${pair.$2} ${Course.time(data[pair.$1] as int)}'),
              ),
            TextField(
              controller: location,
              decoration: const InputDecoration(labelText: '教室 / 地点'),
            ),
            TextField(
              controller: platform,
              decoration: const InputDecoration(labelText: '常用提交平台'),
            ),
            for (final pair in [('firstDate', '开始日期'), ('lastDate', '结束日期')])
              TextButton(
                onPressed: () async {
                  final date = DateTime.parse(data[pair.$1] as String)
                      .toLocal();
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: date,
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) {
                    setState(() => data[pair.$1] = isoDate(picked));
                  }
                },
                child: Text(
                  '${pair.$2} ${dateLabel(DateTime.parse(data[pair.$1] as String), time: false)}',
                ),
              ),
            SwitchListTile(
              title: const Text('下课时提醒登记作业'),
              value: data['reminderEnabled'] as bool,
              onChanged: (v) => setState(() => data['reminderEnabled'] = v),
            ),
            if (data['reminderEnabled'] == true)
              ReminderControls(
                data: data,
                onChanged: () => setState(() {}),
                course: true,
              ),
            if (error != null) Text(error!),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      if (widget.store.courses.any((c) => c.id == widget.course.id))
        TextButton(
          onPressed: widget.store.readOnly
              ? null
              : () {
                  widget.store.deleteCourse(widget.course.id);
                  Navigator.pop(context);
                },
          child: const Text('删除'),
        ),
      FilledButton(
        onPressed: widget.store.readOnly
            ? null
            : () async {
                try {
                  data.addAll({
                    'name': name.text.trim(),
                    'location': location.text.trim(),
                    'platform': platform.text.trim(),
                  });
                  final c = Course(data);
                  c.validate();
                  widget.store.saveCourse(c);
                  await widget.store.settled;
                  if (widget.store.saveFailed) throw StateError('课程暂未写入磁盘。');
                  final allowed =
                      data['reminderEnabled'] != true ||
                      widget.store.storage is! NativeStorage ||
                      await requestReminderAccess(
                        data['reminderDelivery'] as String? ?? 'popup',
                      );
                  await widget.store.refreshServices();
                  if (!context.mounted) return;
                  if (!allowed) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('课程已保存，提醒权限尚未开启。')),
                    );
                  }
                  Navigator.pop(context);
                } catch (e) {
                  if (mounted) setState(() => error = '$e');
                }
              },
        child: const Text('保存'),
      ),
    ],
  );
}

class ReminderControls extends StatelessWidget {
  const ReminderControls({
    super.key,
    required this.data,
    required this.onChanged,
    this.course = false,
  });
  final Map<String, dynamic> data;
  final VoidCallback onChanged;
  final bool course;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      if (!course) ...[
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('开启提醒'),
          value: data['reminder'] != null,
          onChanged: (v) {
            data['reminder'] = v ? 0 : null;
            onChanged();
          },
        ),
        if (data['reminder'] != null)
          DropdownButtonFormField<int>(
            initialValue: data['reminder'] as int,
            decoration: const InputDecoration(labelText: '提前提醒'),
            items: const [
              DropdownMenuItem(value: 0, child: Text('准时')),
              DropdownMenuItem(value: 300, child: Text('提前 5 分钟')),
              DropdownMenuItem(value: 900, child: Text('提前 15 分钟')),
              DropdownMenuItem(value: 3600, child: Text('提前 1 小时')),
              DropdownMenuItem(value: 86400, child: Text('提前 1 天')),
            ],
            onChanged: (v) {
              data['reminder'] = v;
              onChanged();
            },
          ),
      ],
      if (!course &&
          data['plannedStart'] != null &&
          data['dueDate'] != null &&
          data['kind'] != 'schedule')
        DropdownButtonFormField<String>(
          initialValue: data['reminderAnchor'] as String? ?? 'deadline',
          decoration: const InputDecoration(labelText: '提醒依据'),
          items: const [
            DropdownMenuItem(value: 'deadline', child: Text('按截止时间')),
            DropdownMenuItem(value: 'execution', child: Text('按执行开始')),
          ],
          onChanged: (v) {
            data['reminderAnchor'] = v;
            onChanged();
          },
        ),
      if (course || data['reminder'] != null) ...[
        DropdownButtonFormField<String>(
          initialValue: data['reminderDelivery'] as String? ?? 'popup',
          decoration: const InputDecoration(labelText: '提醒方式'),
          items: const [
            DropdownMenuItem(value: 'popup', child: Text('弹窗提醒')),
            DropdownMenuItem(value: 'alarm', child: Text('闹钟提醒')),
          ],
          onChanged: (v) {
            data['reminderDelivery'] = v;
            onChanged();
          },
        ),
        DropdownButtonFormField<String>(
          initialValue: data['reminderSound'] as String? ?? 'system',
          decoration: const InputDecoration(labelText: '铃声'),
          items: const [
            DropdownMenuItem(value: 'system', child: Text('系统默认')),
            DropdownMenuItem(value: 'morning', child: Text('晨光')),
            DropdownMenuItem(value: 'chime', child: Text('清脆')),
            DropdownMenuItem(value: 'pulse', child: Text('节拍')),
          ],
          onChanged: (v) {
            data['reminderSound'] = v;
            onChanged();
          },
        ),
        DropdownButtonFormField<int>(
          initialValue: data['snoozeMinutes'] as int? ?? 5,
          decoration: const InputDecoration(labelText: '稍后提醒'),
          items: [5, 10, 15]
              .map((m) => DropdownMenuItem(value: m, child: Text('$m 分钟')))
              .toList(),
          onChanged: (v) {
            data['snoozeMinutes'] = v;
            onChanged();
          },
        ),
        if (!course)
          DropdownButtonFormField<String>(
            initialValue: data['reminderPattern'] as String? ?? 'single',
            decoration: const InputDecoration(labelText: '催办频率（非循环事项）'),
            items: const [
              DropdownMenuItem(value: 'single', child: Text('单次')),
              DropdownMenuItem(value: 'stepped', child: Text('分阶段')),
              DropdownMenuItem(
                value: 'persistent',
                child: Text('截止后每两小时，至 24 小时'),
              ),
            ],
            onChanged: (v) {
              data['reminderPattern'] = v;
              onChanged();
            },
          ),
      ],
    ],
  );
}

class MessageImportPage extends StatefulWidget {
  const MessageImportPage({super.key, required this.store});
  final EntryStore store;
  @override
  State<MessageImportPage> createState() => _MessageImportPageState();
}

class _MessageImportPageState extends State<MessageImportPage> {
  final text = TextEditingController();
  (Entry, List<String>)? parsed;
  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('从群消息添加')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        TextField(
          controller: text,
          minLines: 6,
          maxLines: 15,
          decoration: const InputDecoration(labelText: '粘贴一件事相关的群消息'),
          onChanged: (_) => setState(() => parsed = null),
        ),
        const Text('仅在本机解析，不读取 QQ 账号，不上传消息。建议需核对后保存。'),
        FilledButton(
          onPressed: () {
            if (text.text.trim().isNotEmpty) {
              setState(
                () => parsed = parseMessage(text.text, widget.store.clock()),
              );
            }
          },
          child: const Text('提取建议'),
        ),
        if (parsed != null) ...[
          Text(parsed!.$1.title),
          ...parsed!.$2.map(Text.new),
          FilledButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => EntryEditor(
                store: widget.store,
                entry: parsed!.$1,
                isNew: true,
              ),
            ),
            child: const Text('核对并编辑事项'),
          ),
        ],
      ],
    ),
  );
}
