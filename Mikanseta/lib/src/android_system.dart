import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'domain.dart';
import 'store.dart';

class AndroidSystem {
  static bool get supported =>
      !kIsWeb &&
      [
        TargetPlatform.android,
        TargetPlatform.iOS,
        TargetPlatform.macOS,
      ].contains(defaultTargetPlatform);
  static Future<T?> call<T>(String method, [Object? args]) =>
      NativeStorage.invokeMethod<T>(method, args);
  static Future<int> sync(
    EntryStore store, {
    bool manual = false,
    bool Function()? canImport,
  }) async {
    final config = store.androidCalendarSettings;
    final selected = List<String>.from(config['selected'] as List? ?? []);
    if (!supported ||
        store.readOnly ||
        selected.isEmpty ||
        !manual && config['enabled'] != true) {
      return 0;
    }
    final deviceID = await call<String>('calendarDeviceID');
    if (deviceID == null || config['deviceID'] != deviceID) return 0;
    if (await call<bool>('calendarAccess') != true) {
      throw PlatformException(
        code: 'permission',
        message: '未获日历读取权限，请在系统设置允许后重试。',
      );
    }
    final now = store.clock();
    final start = DateTime(now.year, now.month, now.day);
    final end = DateTime(now.year, now.month, now.day + 30);
    final rows =
        await call<List<dynamic>>('calendarEvents', {
          'selected': selected,
          'start': start.millisecondsSinceEpoch,
          'end': end.millisecondsSinceEpoch,
        }) ??
        [];
    if (canImport != null && !canImport()) return 0;
    final current = store.androidCalendarSettings;
    if (current['deviceID'] != deviceID ||
        !listEquals(
          List<String>.from(current['selected'] as List? ?? []),
          selected,
        ) ||
        !manual && current['enabled'] != true) {
      return 0;
    }
    return store.importAndroidEvents(
      rows.map((r) => Map<String, dynamic>.from(r as Map)).where((event) {
        if (event['allDay'] != true) return true;
        DateTime day(String field) {
          final utc = DateTime.fromMillisecondsSinceEpoch(
            event[field] as int,
            isUtc: true,
          );
          return DateTime(utc.year, utc.month, utc.day);
        }

        // Provider all-day bounds use UTC dates, not local instants.
        return day('end').isAfter(start) && day('start').isBefore(end);
      }).toList(),
      deviceID,
    );
  }

  static String error(Object error) => error is PlatformException
      ? error.message ?? '系统操作未完成。'
      : '系统操作未完成：$error';
}

class AndroidCalendarPage extends StatefulWidget {
  const AndroidCalendarPage({super.key, required this.store});
  final EntryStore store;
  @override
  State<AndroidCalendarPage> createState() => _AndroidCalendarPageState();
}

class _AndroidCalendarPageState extends State<AndroidCalendarPage> {
  List<Map<String, dynamic>> sources = [];
  Set<String> selected = {};
  String? deviceID;
  bool enabled = false;
  String timing = 'start';
  bool busy = false;
  String status = '选择要导入的日历；首次不默认勾选任何来源。';
  Future<void> load() async {
    setState(() => busy = true);
    try {
      if (await AndroidSystem.call<bool>('requestCalendarAccess') != true) {
        throw PlatformException(
          code: 'permission',
          message: '日历权限未授予，可在系统设置中允许后重试。',
        );
      }
      final id = await AndroidSystem.call<String>('calendarDeviceID');
      final rows =
          await AndroidSystem.call<List<dynamic>>('calendarSources') ?? [];
      if (!mounted) return;
      final config = widget.store.androidCalendarSettings;
      setState(() {
        deviceID = id;
        sources = rows.map((r) => Map<String, dynamic>.from(r as Map)).toList();
        selected = config['deviceID'] == id
            ? Set<String>.from(config['selected'] as List? ?? [])
            : {};
        enabled = config['deviceID'] == id && config['enabled'] == true;
        timing = config['timing'] as String? ?? 'start';
        status = sources.isEmpty
            ? '系统中没有可读取的日历，请先在系统日历添加日历来源。'
            : '只导入勾选的来源，包含今天起 30 天的日程。';
      });
    } catch (error) {
      if (mounted) setState(() => status = AndroidSystem.error(error));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> save() async {
    setState(() => busy = true);
    try {
      final old = widget.store.androidCalendarSettings;
      widget.store.setAndroidCalendarSettings({
        'deviceID': deviceID,
        'selected': selected.toList(),
        'enabled': enabled,
        'timing': timing,
        'suppressed': old['deviceID'] == deviceID
            ? old['suppressed'] ?? []
            : [],
      });
      await widget.store.settled;
      if (widget.store.saveFailed) throw StateError('来源设置尚未保存，请重试保存。');
      final count = await AndroidSystem.sync(widget.store, manual: true);
      await widget.store.settled;
      if (widget.store.saveFailed) throw StateError('导入尚未写入磁盘，请重试保存。');
      if (mounted) setState(() => status = '已保存来源，本次新增或更新 $count 个事项。');
    } catch (error) {
      if (mounted) setState(() => status = AndroidSystem.error(error));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('系统日历来源')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(status),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: busy ? null : load,
          icon: const Icon(Icons.calendar_month),
          label: const Text('读取日历来源'),
        ),
        ...sources.map(
          (source) => CheckboxListTile(
            key: ValueKey('calendar-source-${source['id']}'),
            contentPadding: EdgeInsets.zero,
            title: Text(source['title'] as String? ?? '日历'),
            subtitle: Text(source['account'] as String? ?? ''),
            secondary: Icon(
              Icons.circle,
              size: 14,
              color: source['color'] is int
                  ? Color((source['color'] as int) | 0xff000000)
                  : Theme.of(context).colorScheme.primary,
            ),
            value: selected.contains(source['id']),
            onChanged: busy || widget.store.readOnly
                ? null
                : (value) => setState(() {
                    if (value == true) {
                      selected.add(source['id'] as String);
                    } else {
                      selected.remove(source['id']);
                    }
                  }),
          ),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('新增日程保存后安排到系统日历'),
          subtitle: const Text('先保存本地事项，再打开系统编辑页，由你确认日历与时段。'),
          value: widget.store.preferences['offerCalendar'] == true,
          onChanged: busy || widget.store.readOnly
              ? null
              : (v) {
                  widget.store.setPreferences({'offerCalendar': v});
                  setState(() {});
                },
        ),
        DropdownButtonFormField<String>(
          initialValue: timing,
          decoration: const InputDecoration(labelText: '导入时间安排'),
          items: const [
            DropdownMenuItem(value: 'start', child: Text('保留日程起止时间')),
            DropdownMenuItem(value: 'end', child: Text('按结束时间附加 DDL')),
          ],
          onChanged: busy || widget.store.readOnly
              ? null
              : (v) => setState(() => timing = v!),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('打开或返回 App 时自动导入'),
          value: enabled,
          onChanged: busy || widget.store.readOnly
              ? null
              : (value) => setState(() => enabled = value),
        ),
        const Text(
          '保留 Checklist、完成状态、计时和手动修改。删除导入事项后不再自动加回；取消勾选来源不删除已有事项。源事件删除后也会保留待办，请自行核对。',
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: busy || widget.store.readOnly || deviceID == null
              ? null
              : save,
          child: const Text('保存来源并导入'),
        ),
        if (widget.store.cleanableCalendarEntries.isNotEmpty)
          TextButton(
            onPressed: busy
                ? null
                : () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('清理未选来源的导入事项？'),
                        content: const Text(
                          '只清理未修改、未完成、没有 Checklist 或计时的导入事项。不会删除系统日历事件。',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('取消'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('清理'),
                          ),
                        ],
                      ),
                    );
                    if (ok == true) {
                      final count = widget.store
                          .cleanUnselectedCalendarEntries();
                      await widget.store.settled;
                      if (mounted) setState(() => status = '已清理 $count 件导入事项。');
                    }
                  },
            child: Text(
              '清理未选来源的导入事项（${widget.store.cleanableCalendarEntries.length} 件）',
            ),
          ),
        if (busy)
          const Padding(
            padding: EdgeInsets.all(16),
            child: LinearProgressIndicator(),
          ),
      ],
    ),
  );
}

class AndroidEntryActions extends StatefulWidget {
  const AndroidEntryActions({
    super.key,
    required this.entry,
    required this.store,
  });
  final Entry entry;
  final EntryStore store;
  @override
  State<AndroidEntryActions> createState() => _AndroidEntryActionsState();
}

class _AndroidEntryActionsState extends State<AndroidEntryActions> {
  bool busy = false;
  Future<void> perform(Future<void> Function() action) async {
    setState(() => busy = true);
    try {
      await action();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(AndroidSystem.error(error))));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> calendar() =>
      addToSystemCalendar(context, widget.store, widget.entry);

  Future<void> editCalendar() async {
    final entry = widget.entry,
        link = widget.entry.data['androidCalendarLink'] as Map?;
    if (link == null || widget.store.readOnly) return;
    if (link['deviceID'] !=
        await AndroidSystem.call<String>('calendarDeviceID')) {
      throw StateError('请在此设备重新关联日历。');
    }
    final start =
        entry.start ??
        DateTime.parse((link['snapshot'] as Map)['plannedStart'] as String);
    final end = entry.end ?? start.add(const Duration(minutes: 30));
    final saved = await AndroidSystem.call<bool>('editCalendarEvent', {
      'eventID': link['eventID'],
      'title': entry.title,
      'body': entry.body,
      'location': entry.location,
      'start': start.millisecondsSinceEpoch,
      'end': end.millisecondsSinceEpoch,
      'allDay': entry.allDay,
    });
    if (saved == true) {
      final rows =
          await AndroidSystem.call<List<dynamic>>('takeCalendarEdits') ?? [];
      if (rows.isNotEmpty) {
        widget.store.importAndroidEvents(
          rows.map((r) => Map<String, dynamic>.from(r as Map)).toList(),
          link['deviceID'] as String,
          confirmedEdit: true,
        );
      } else {
        await AndroidSystem.sync(widget.store, manual: true);
      }
    }
  }

  Future<void> alarm() async {
    final entry = widget.entry;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(entry.attention ?? DateTime.now()),
      helpText: '系统闹钟时刻（不含日期）',
    );
    if (time == null || !mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('系统闹钟 ${time.format(context)}'),
        content: const Text(
          '系统闹钟按时、分设置，不包含事项的 DDL 日期。请在系统时钟确认生效日期、重复和铃声。完成事项不会自动取消闹钟。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('打开系统时钟'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await AndroidSystem.call<bool>('createClockAlarm', {
        'hour': time.hour,
        'minute': time.minute,
        'title': entry.title,
      });
    }
  }

  Future<void> timer() async {
    final minutes = await showDialog<int>(
      context: context,
      builder: (_) => _TimerDialog(initialMinutes: widget.entry.estimate ?? 25),
    );
    if (minutes != null) {
      await AndroidSystem.call<bool>('createClockTimer', {
        'seconds': minutes * 60,
        'title': widget.entry.title,
      });
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 18),
      const Text('系统日历与时钟', style: TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton.icon(
            onPressed: busy ? null : () => perform(calendar),
            icon: const Icon(Icons.event),
            label: Text(
              widget.entry.data['androidCalendarLink'] == null
                  ? '添加到系统日历'
                  : '查看系统日历',
            ),
          ),
          if (widget.entry.data['androidCalendarLink'] != null)
            OutlinedButton.icon(
              onPressed: busy || widget.store.readOnly
                  ? null
                  : () => perform(editCalendar),
              icon: const Icon(Icons.edit_calendar),
              label: const Text('编辑并保存到系统日历'),
            ),
          if (defaultTargetPlatform == TargetPlatform.android)
            OutlinedButton.icon(
              onPressed: busy ? null : () => perform(alarm),
              icon: const Icon(Icons.alarm),
              label: const Text('创建系统闹钟'),
            ),
          if (defaultTargetPlatform == TargetPlatform.android)
            OutlinedButton.icon(
              onPressed: busy ? null : () => perform(timer),
              icon: const Icon(Icons.timer_outlined),
              label: const Text('系统倒计时'),
            ),
        ],
      ),
      const Text('系统日历和时钟中的记录独立保留；修改、完成或删除事项不会自动取消闹钟或删除日历事件。'),
    ],
  );
}

class _TimerDialog extends StatefulWidget {
  const _TimerDialog({required this.initialMinutes});
  final int initialMinutes;
  @override
  State<_TimerDialog> createState() => _TimerDialogState();
}

class _TimerDialogState extends State<_TimerDialog> {
  late final controller = TextEditingController(
    text: '${widget.initialMinutes}',
  );
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final minutes = int.tryParse(controller.text) ?? 0;
    return AlertDialog(
      title: const Text('开始系统倒计时'),
      content: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(labelText: '分钟（1–1440）'),
        onChanged: (_) => setState(() {}),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: minutes >= 1 && minutes <= 1440
              ? () => Navigator.pop(context, minutes)
              : null,
          child: const Text('打开系统倒计时'),
        ),
      ],
    );
  }
}

Future<void> addToSystemCalendar(
  BuildContext context,
  EntryStore store,
  Entry entry,
) async {
  final link = entry.data['androidCalendarLink'] as Map?;
  if (link != null &&
      link['deviceID'] ==
          await AndroidSystem.call<String>('calendarDeviceID')) {
    final snapshot = link['snapshot'] as Map;
    final start = DateTime.parse(snapshot['plannedStart'] as String);
    final end = DateTime.parse(snapshot['plannedEnd'] as String);
    await AndroidSystem.call<bool>('openCalendarEvent', {
      'eventID': link['eventID'],
      'start': start.millisecondsSinceEpoch,
      'end': end.millisecondsSinceEpoch,
    });
    return;
  }
  if (store.readOnly) {
    throw StateError('当前数据只读，请先恢复可写的数据后再添加到系统日历。');
  }
  if (!context.mounted) return;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('添加到系统日历'),
      content: Text(
        entry.start == null
            ? '请在系统日历确认执行时段。事项的 DDL 保持原样，不会被当作开始时间。'
            : '将预填日程时间、标题和地点，请在系统日历确认保存。',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('打开系统日历'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  final start = entry.start ?? DateTime.now().add(const Duration(hours: 1));
  final end = entry.end ?? start.add(Duration(minutes: entry.estimate ?? 30));
  int epoch(DateTime date) => entry.allDay
      ? DateTime.utc(date.year, date.month, date.day).millisecondsSinceEpoch
      : date.millisecondsSinceEpoch;
  final token = entry.data['androidCalendarExportToken'] as String? ?? newId();
  final current = store.find(entry.id);
  if (current == null) throw StateError('事项已删除。');
  store.save(current.change({'androidCalendarExportToken': token}));
  await store.settled;
  if (store.saveFailed) throw StateError('关联信息尚未保存，请先重试保存。');
  final saved = await AndroidSystem.call<bool>('addCalendarEvent', {
    'title': entry.title,
    'body': [
      entry.body,
      if (entry.platform.isNotEmpty) '处理平台：${entry.platform}',
      if (entry.due != null) 'DDL：${dateLabel(entry.due!)}',
      'mikanseta://entry/${entry.id}?token=$token',
    ].where((s) => s.isNotEmpty).join('\n'),
    'location': entry.location,
    'start': epoch(start),
    'end': epoch(
      end.isAfter(start) ? end : start.add(const Duration(minutes: 30)),
    ),
    'allDay': entry.allDay,
  });
  if (saved == true) {
    final rows =
        await AndroidSystem.call<List<dynamic>>('takeCalendarEdits') ?? [];
    if (rows.isNotEmpty) {
      final id = await AndroidSystem.call<String>('calendarDeviceID');
      if (id != null) {
        store.importAndroidEvents(
          rows.map((r) => Map<String, dynamic>.from(r as Map)).toList(),
          id,
          confirmedEdit: true,
        );
        await store.settled;
      }
    }
  }
}
