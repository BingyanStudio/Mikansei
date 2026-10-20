import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'domain.dart';
import 'store.dart';
import 'calendar_view.dart';

List<Map<String, dynamic>> reminderPlan(
  Archive archive,
  DateTime now, {
  int limit = 60,
}) {
  final plan = <Map<String, dynamic>>[], seen = <String>{};
  final days = <DateTime, List<CalendarItem>>{};
  void add(
    Entry? entry,
    Map<String, dynamic>? course,
    DateTime at,
    String title,
    String body,
  ) {
    if (!at.isAfter(now)) return;
    final data = entry?.data ?? course!;
    final id =
        '${entry == null ? 'course' : 'entry'}.${data['id']}.${at.millisecondsSinceEpoch ~/ 1000}';
    if (!seen.add(id)) return;
    plan.add({
      'id': id,
      'at': at.millisecondsSinceEpoch,
      'title': title,
      'body': body,
      'entryID': entry?.id,
      'courseID': course?['id'],
      'delivery': data['reminderDelivery'] ?? 'popup',
      'sound': data['reminderSound'] ?? 'system',
      'snoozeMinutes': data['snoozeMinutes'] ?? 5,
    });
  }

  for (final e in archive.entries.where(
    (e) => e.isTask && !e.completed && e.data['reminder'] != null,
  )) {
    DateTime? anchor = e.data['reminderAnchor'] == 'execution'
        ? e.start
        : e.due ?? e.start;
    if (anchor == null) continue;
    final lead = e.data['reminder'] as int;
    final title = e.title,
        body = [
          e.category,
          e.platform,
          e.location,
          if (e.estimate != null) '约 ${e.estimate} 分钟',
        ].where((s) => s.isNotEmpty).join(' · ');
    if (e.repeatRule == 'never') {
      final pattern = e.data['reminderPattern'] as String? ?? 'single';
      final offsets = pattern == 'single'
          ? [-lead]
          : pattern == 'stepped'
          ? [-86400, -7200, 0, 7200]
          : [-86400, -7200, 0, ...List.generate(12, (i) => (i + 1) * 7200)];
      for (final offset in offsets) {
        add(
          e,
          null,
          anchor.add(Duration(seconds: offset)),
          offset > 0 ? '尚未完成：$title' : title,
          body,
        );
      }
    } else {
      for (var i = 0; i < 30; i++) {
        final d = DateTime(now.year, now.month, now.day + i);
        for (final item
            in days
                .putIfAbsent(
                  d,
                  () => calendarItems(archive.entries, d, showCompleted: false),
                )
                .where((i) => i.owner.id == e.id)) {
          final reference = e.data['reminderAnchor'] == 'execution'
              ? item.entry.start
              : item.entry.due ?? item.entry.start;
          final horizon = DateTime(
            now.year,
            now.month,
            now.day + 28,
            now.hour,
            now.minute,
            now.second,
          );
          if (reference != null &&
              !reference.subtract(Duration(seconds: lead)).isAfter(horizon)) {
            add(
              e,
              null,
              reference.subtract(Duration(seconds: lead)),
              title,
              '例行事项 · $body',
            );
          }
        }
      }
    }
  }
  for (final raw in archive.metadata['courses'] as List? ?? []) {
    final c = Map<String, dynamic>.from(raw as Map);
    if (c['reminderEnabled'] != true) continue;
    final first = dayOf(DateTime.parse(c['firstDate'] as String)),
        last = dayOf(DateTime.parse(c['lastDate'] as String));
    for (var i = 0; i < 28; i++) {
      final d = DateTime(now.year, now.month, now.day + i);
      if (d.weekday == c['weekday'] && !d.isBefore(first) && !d.isAfter(last)) {
        final m = c['endMinutes'] as int;
        add(
          null,
          c,
          DateTime(d.year, d.month, d.day, m ~/ 60, m % 60),
          '${c['name']}下课了，登记一下？',
          '有什么作业？DDL 是什么时候？在哪提交？预计需要多久？',
        );
      }
    }
  }
  plan.sort((a, b) {
    final date = (a['at'] as int).compareTo(b['at'] as int);
    return date == 0 ? (a['id'] as String).compareTo(b['id'] as String) : date;
  });
  return plan.take(limit).toList();
}

Map<String, dynamic> serviceSnapshot(Archive archive, DateTime now) {
  final board = TaskBoard(archive.entries, now);
  Map<String, dynamic> item(Entry e) => {
    'id': e.id,
    'title': e.title,
    'deadline': (e.kind == EntryKind.schedule ? e.start : e.due)
        ?.millisecondsSinceEpoch,
    'priority': e.priority,
  };
  final running = archive.entries
      .where((e) => e.isTask && !e.completed && e.startedAt != null)
      .firstOrNull;
  final live = board.focus.where((e) => !e.completed).toList()
    ..sort((a, b) {
      final priority = b.priority.compareTo(a.priority);
      if (priority != 0) return priority;
      final left =
              (a.kind == EntryKind.schedule ? a.start : a.due) ??
              DateTime(9999),
          right =
              (b.kind == EntryKind.schedule ? b.start : b.due) ??
              DateTime(9999);
      return left == right ? entryOrder(a, b) : left.compareTo(right);
    });
  return {
    'archive': archive.encode(),
    'plan': reminderPlan(archive, now),
    'summary': {
      'items': board.open.take(7).map(item).toList(),
      'remaining': board.open.length,
      'completed': board.finishedToday.length,
      'savedAt': now.millisecondsSinceEpoch,
      'dayEnd': DateTime(
        now.year,
        now.month,
        now.day + 1,
      ).millisecondsSinceEpoch,
      'liveItems': live.take(3).map(item).toList(),
      'liveCount': live.length,
      'focus': running == null
          ? null
          : {
              ...item(running),
              'elapsed': running.data['elapsedSeconds'] ?? 0,
              'startedAt': running.startedAt!.millisecondsSinceEpoch,
            },
    },
    'liveEnabled':
        (archive.metadata['preferences'] as Map?)?['liveEnabled'] == true,
  };
}

Future<bool> requestReminderAccess(String delivery) async {
  if (!NativeStorage.supportsSystemServices) return false;
  try {
    return await NativeStorage.invokeMethod<bool>('requestReminderAccess', {
          'delivery': delivery,
        }) ??
        false;
  } catch (_) {
    return false;
  }
}

class ServicesSettings extends StatefulWidget {
  const ServicesSettings({super.key, required this.store});
  final EntryStore store;
  @override
  State<ServicesSettings> createState() => _ServicesSettingsState();
}

class _ServicesSettingsState extends State<ServicesSettings> {
  Map<String, dynamic> status = {};
  String? error;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    if (!NativeStorage.supportsSystemServices) return;
    try {
      final s = await NativeStorage.invokeMapMethod<String, dynamic>(
        'systemStatus',
      );
      if (mounted) setState(() => status = s ?? {});
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  Future<void> request(String delivery) async {
    setState(() => busy = true);
    final allowed = await requestReminderAccess(delivery);
    await widget.store.refreshServices();
    await load();
    if (mounted) {
      setState(() {
        busy = false;
        error = allowed ? null : '提醒权限尚未开启，请检查系统通知与精确闹钟设置。';
      });
    }
  }

  @override
  Widget build(BuildContext context) => !NativeStorage.supportsSystemServices
      ? Scaffold(
          appBar: AppBar(title: const Text('系统服务')),
          body: const Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Windows 版提供清单、Checklist、日历视图、循环、计时、备份和同步。系统日历、后台提醒、桌面小组件与实时活动尚未接入；保留的提醒配置可供支持这些能力的设备使用。',
            ),
          ),
        )
      : Scaffold(
          appBar: AppBar(title: const Text('提醒、小组件与实时活动')),
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text('通知：${status['notification'] ?? '读取中'}'),
              Text('闹钟：${status['alarm'] ?? '读取中'}'),
              Text('已安排 ${status['scheduled'] ?? 0} 个提醒'),
              if (status['error'] != null) Text('${status['error']}'),
              FilledButton(
                onPressed: busy ? null : () => request('popup'),
                child: const Text('开启弹窗通知'),
              ),
              OutlinedButton(
                onPressed: busy ? null : () => request('alarm'),
                child: const Text('开启闹钟权限'),
              ),
              TextButton(
                onPressed: () async {
                  try {
                    await NativeStorage.invokeMethod('openSystemSettings', {
                      'target': 'notifications',
                    });
                  } catch (e) {
                    if (mounted) setState(() => error = '$e');
                  }
                },
                child: const Text('打开系统通知设置'),
              ),
              if (defaultTargetPlatform == TargetPlatform.android)
                TextButton(
                  onPressed: () async {
                    try {
                      await NativeStorage.invokeMethod('openSystemSettings', {
                        'target': 'fullscreen',
                      });
                    } catch (e) {
                      if (mounted) setState(() => error = '$e');
                    }
                  },
                  child: const Text('全屏闹钟设置'),
                ),
              if (error != null) Text(error!),
              const Text(
                '事项和课表分别设置提醒方式、铃声、提前量及稍后提醒。完成、删除、改期后重新安排本 App 管理的提醒；手动创建到系统时钟的独立闹钟仍需手动管理。',
              ),
              const SizedBox(height: 20),
              const Text('主屏幕小组件：待办清单、快速添加、今日进度、正在做与计时。长按主屏幕添加 Mikanseta 小组件。'),
              SwitchListTile(
                title: Text(
                  defaultTargetPlatform == TargetPlatform.android
                      ? '显示今日 DDL 常驻通知'
                      : '自动显示今日 DDL 实时活动',
                ),
                subtitle: const Text('锁屏显示最重要的事项及倒计时；只包含标题，不显示备注和消息原文。'),
                value: widget.store.preferences['liveEnabled'] == true,
                onChanged: widget.store.readOnly
                    ? null
                    : (v) async {
                        widget.store.setPreferences({'liveEnabled': v});
                        await widget.store.settled;
                        try {
                          await NativeStorage.invokeMethod<bool>(
                            'setLiveEnabled',
                            {'enabled': v},
                          );
                          await widget.store.refreshServices();
                          await load();
                        } catch (e) {
                          if (mounted) setState(() => error = '$e');
                        }
                        if (mounted) setState(() {});
                      },
              ),
              if (status['live'] != null) Text('${status['live']}'),
              TextButton(
                onPressed: () async {
                  await widget.store.refreshServices();
                  await load();
                },
                child: const Text('更新系统服务状态'),
              ),
              const Text(
                'iPhone 使用 WidgetKit / ActivityKit；安卓使用桌面小组件和常驻通知。后台展示与提醒遵循系统权限及电池设置。',
              ),
            ],
          ),
        );
}

Map<String, dynamic> buildServicePayload(Map<String, Object> input) =>
    serviceSnapshot(
      Archive.decode(input['archive'] as String),
      DateTime.fromMillisecondsSinceEpoch(input['now'] as int),
    );
