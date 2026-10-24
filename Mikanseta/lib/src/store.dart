import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'domain.dart';
import 'student_tools.dart' show Course;
import 'system_services.dart';
import 'windows_native.dart';

abstract class ArchiveStorage {
  Future<String?> read();
  Future<void> write(String content);
  Future<String?> pickBackup();
  Future<bool> exportBackup(String content);
}

class NativeStorage implements ArchiveStorage {
  static const channel = MethodChannel('mikanseta/native');
  static bool get supportsSystemServices =>
      kIsWeb || defaultTargetPlatform != TargetPlatform.windows;
  static Future<T?> invokeMethod<T>(String method, [Object? arguments]) async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      return await WindowsNative.instance.invoke(method, arguments) as T?;
    }
    return channel.invokeMethod<T>(method, arguments);
  }

  static Future<Map<K, V>?> invokeMapMethod<K, V>(
    String method, [
    Object? arguments,
  ]) async {
    final value = await invokeMethod<Map<Object?, Object?>>(method, arguments);
    return value?.cast<K, V>();
  }

  static Future<List<T>?> invokeListMethod<T>(
    String method, [
    Object? arguments,
  ]) async {
    final value = await invokeMethod<List<Object?>>(method, arguments);
    return value?.cast<T>();
  }

  Future<String?> appVersion() => invokeMethod<String>('appInfo');
  @override
  Future<String?> read() => invokeMethod<String>('readArchive');
  @override
  Future<void> write(String content) =>
      invokeMethod<void>('writeArchive', content);
  @override
  Future<String?> pickBackup() => invokeMethod<String>('importArchive');
  @override
  Future<bool> exportBackup(String content) async =>
      await invokeMethod<bool>('exportArchive', content) ?? false;
}

/// 首次安装时内置的使用说明正文（Markdown），原样进入笔记并可在编辑页预览。
const String guideMikanseta = '''
# 欢迎使用 Mikanseta

这是一个学生向的待办与日程工具，牛皮浅棕主题。

## 快速上手
- 点右上角 **＋** 新建事项：待办、作业、日程、笔记四种类型
- 点左侧圆圈完成事项；完成态会划线并进入「今日已完成」
- 点卡片上的 ▶ 开始专注计时，同一时间只计一件事

## 规划
- 「今日」页点 **规划**：
  - **日程规划**：在月历上涂色，决定"哪几天做"（常态 Routine 会自动规划）
  - **小时规划**：把左侧待办拖进时间轴，决定"今天哪个时段做"，类型仍是待办，可同步系统日历
- 列表里**长按拖动**卡片可调整顺序

## 同步与备份
- 设置 → 账户同步：登录同一账号，多设备实时同步
- 设置 → 本机同步：与原版 Mikansei 共享文件夹互通
- 设置 → 数据：导入 / 导出 JSON 备份

## 笔记
- 笔记是全页编辑，像备忘录一样；正文支持 **Markdown**，点右上角眼睛图标可切换预览
''';

class EntryStore extends ChangeNotifier {
  EntryStore(this.storage, {DateTime Function()? clock})
    : clock = clock ?? DateTime.now;
  final ArchiveStorage storage;
  final DateTime Function() clock;

  /// 内置的「使用说明」笔记：note 类型、分类「帮助」，正文即 guideMikanseta。
  static Entry builtInGuideNote(DateTime now) =>
      Entry.create(title: '使用说明', kind: EntryKind.note, now: now).change({
        'category': '帮助',
        'body': guideMikanseta,
      }, now: now);
  Archive _archive = Archive(entries: []);
  List<Course> get courses => (_archive.metadata['courses'] as List? ?? [])
      .map((c) => Course(Map<String, dynamic>.from(c as Map)))
      .toList();
  void saveCourse(Course course) {
    course.validate();
    _commit(
      Archive(
        entries: entries,
        metadata: {
          ..._archive.metadata,
          'courses': [
            ...courses.where((c) => c.id != course.id).map((c) => c.data),
            course.data,
          ],
        },
      ),
    );
  }

  void deleteCourse(String id) {
    final remaining = courses
        .where((c) => c.id != id)
        .map((c) => c.data)
        .toList();
    final staged = Archive(
      entries: entries,
      metadata: {..._archive.metadata, 'courses': remaining},
    );
    _commit(staged.withTombstone('courseTombstones', id, now: clock()));
  }

  int importCourses(List<Course> added) {
    for (final c in added) {
      c.validate();
    }
    final next = courses.toList();
    var count = 0;
    for (final c in added) {
      if (!next.any(
        (old) =>
            old.name == c.name &&
            old.weekday == c.weekday &&
            old.begin == c.begin &&
            old.end == c.end &&
            old.first == c.first &&
            old.last == c.last &&
            old.data['location'] == c.data['location'],
      )) {
        next.add(c);
        count++;
      }
    }
    _commit(
      Archive(
        entries: entries,
        metadata: {
          ..._archive.metadata,
          'courses': next.map((c) => c.data).toList(),
        },
      ),
    );
    return count;
  }

  String get archiveText => _archive.encode();
  Map<String, dynamic> get preferences =>
      Map<String, dynamic>.from(_archive.metadata['preferences'] as Map? ?? {});
  void setPreferences(Map<String, dynamic> changes) => _commit(
    Archive(
      entries: entries,
      metadata: {
        ..._archive.metadata,
        'preferences': {...preferences, ...changes},
      },
    ),
  );
  List<Entry> get entries => List.unmodifiable(_archive.entries);
  bool loading = true;
  bool readOnly = false;
  bool saveFailed = false;
  bool saving = false;
  String displayVersion = '0.5.2 (15)';
  String? error;
  String? serviceError;

  /// Read-only view for local folder sync (capture compares against it).
  Archive get archive => _archive;

  /// Notified after the archive is durably written locally (and once after a
  /// successful load), so account sync can schedule an upload.
  void Function()? onLocalWrite;
  Future<void> refreshServices() async {
    if (storage is! NativeStorage ||
        readOnly ||
        !NativeStorage.supportsSystemServices) {
      return;
    }
    final revision = _revision;
    try {
      final payload = await compute(buildServicePayload, {
        'archive': _archive.encode(),
        'now': clock().millisecondsSinceEpoch,
      });
      if (revision != _revision || readOnly) return;
      await NativeStorage.invokeMethod('reconcileServices', payload);
      serviceError = null;
    } catch (e) {
      serviceError = '系统服务尚未更新：$e';
    }
    notifyListeners();
  }

  int _revision = 0;
  Future<void> _writes = Future.value();
  Future<void> get settled => _writes;
  TaskBoard get board => TaskBoard(entries, clock());
  Entry? find(String id) =>
      entries.where((e) => e.id.toUpperCase() == id.toUpperCase()).firstOrNull;
  Entry? get running =>
      entries.where((e) => !e.completed && e.startedAt != null).firstOrNull;

  Archive _withRoutineIdentityFields(Archive archive) {
    var changed = false;
    final next = archive.entries.map((entry) {
      final existingSeries = entry.data['routineSeriesID'];
      final existingOccurrence = entry.data['routineOccurrenceID'];
      final hasSeries =
          existingSeries is String && existingSeries.trim().isNotEmpty;
      final hasOccurrence =
          existingOccurrence is String &&
          existingOccurrence.trim().isNotEmpty &&
          existingOccurrence != 'single';
      if (hasSeries && hasOccurrence) {
        return entry;
      }
      final identity = androidRoutineIdentity(
        entry.data['androidCalendarLink'] as Map?,
      );
      if (identity == null) return entry;
      final fields = <String, dynamic>{};
      if (!hasSeries) fields['routineSeriesID'] = identity.seriesID;
      if (!hasOccurrence) {
        fields['routineOccurrenceID'] = identity.occurrenceID;
      }
      if (fields.isEmpty) return entry;
      changed = true;
      return Entry({...entry.data, ...fields});
    }).toList();
    return changed ? archive.withEntries(next) : archive;
  }

  Map<String, dynamic> get androidCalendarSettings => Map<String, dynamic>.from(
    _archive.metadata['androidCalendarSync'] as Map? ?? {},
  );
  void setAndroidCalendarSettings(Map<String, dynamic> settings) {
    _commit(
      Archive(
        entries: entries,
        metadata: {..._archive.metadata, 'androidCalendarSync': settings},
      ),
    );
  }

  int importAndroidEvents(
    List<Map<String, dynamic>> events,
    String deviceID, {
    bool confirmedEdit = false,
  }) {
    if (readOnly) return 0;
    final settings = androidCalendarSettings;
    final suppressed = settings['deviceID'] == deviceID
        ? Set<String>.from(settings['suppressed'] as List? ?? [])
        : <String>{};
    final next = entries.toList();
    var changed = 0;
    for (final event in events) {
      final key = event['key'] as String;
      if (suppressed.contains(key)) continue;
      final routineIdentity = androidRoutineIdentity({
        ...event,
        'deviceID': deviceID,
      });
      var index = next.indexWhere((entry) {
        final link = entry.data['androidCalendarLink'] as Map?;
        return link?['deviceID'] == deviceID && link?['key'] == key;
      });
      final rawBody = event['body'] as String;
      final markerMatch = RegExp(
        r'mikanseta://entry/([0-9a-fA-F-]{36})\?token=([0-9a-fA-F-]{36})',
      ).firstMatch(rawBody);
      final marker = markerMatch?.group(1);
      if (index < 0 && marker != null) {
        index = next.indexWhere(
          (e) =>
              e.id.toLowerCase() == marker.toLowerCase() &&
              e.data['androidCalendarLink'] == null &&
              e.data['androidCalendarExportToken'] == markerMatch?.group(2),
        );
      }
      var reattachedBySharedIdentity = false;
      if (index < 0 && routineIdentity != null) {
        final matches = <MapEntry<int, Entry>>[
          for (var i = 0; i < next.length; i++)
            if (next[i].data['routineSeriesID'] ==
                    routineIdentity.seriesID &&
                next[i].data['routineOccurrenceID'] ==
                    routineIdentity.occurrenceID)
              MapEntry(i, next[i]),
        ];
        matches.sort((a, b) {
          final completion = (b.value.completed ? 1 : 0).compareTo(
            a.value.completed ? 1 : 0,
          );
          if (completion != 0) return completion;
          final updated = b.value.updatedAt.compareTo(a.value.updatedAt);
          return updated == 0 ? a.value.id.compareTo(b.value.id) : updated;
        });
        if (matches.isNotEmpty) {
          index = matches.first.key;
          reattachedBySharedIdentity = true;
        }
      }
      DateTime date(String field) {
        final utc = DateTime.fromMillisecondsSinceEpoch(
          event[field] as int,
          isUtc: true,
        );
        return event['allDay'] == true
            ? DateTime(utc.year, utc.month, utc.day)
            : utc.toLocal();
      }

      final start = date('start');
      var end = date('end');
      if (!end.isAfter(start)) {
        end = event['allDay'] == true
            ? DateTime(start.year, start.month, start.day + 1)
            : start.add(const Duration(minutes: 30));
      }
      final snapshot = <String, dynamic>{
        'title': (event['title'] as String).trim().isEmpty
            ? '未命名日程'
            : event['title'],
        'body': rawBody
            .replaceAll(
              RegExp(
                r'\n?mikanseta://entry/[0-9a-fA-F-]{36}\?token=[0-9a-fA-F-]{36}',
              ),
              '',
            )
            .trim(),
        'location': event['location'],
        'plannedStart': isoDate(start),
        'plannedEnd': isoDate(end),
        'plannedAllDay': event['allDay'],
        'kind': settings['timing'] == 'end' ? 'task' : 'schedule',
        'dueDate': settings['timing'] == 'end'
            ? isoDate(
                event['allDay'] == true
                    ? end.subtract(const Duration(seconds: 1))
                    : end,
              )
            : null,
      };
      final old = index >= 0
          ? next[index]
          : Entry.create(
              title: snapshot['title'] as String,
              kind: settings['timing'] == 'end'
                  ? EntryKind.task
                  : EntryKind.schedule,
              now: clock(),
            );
      final previous =
          (old.data['androidCalendarLink'] as Map?)?['snapshot'] as Map?;
      final preserveReattachedFields =
          reattachedBySharedIdentity && previous == null && !confirmedEdit;
      final fields = <String, dynamic>{};
      for (final field in snapshot.keys) {
        if (preserveReattachedFields) continue;
        if (index < 0 ||
            confirmedEdit &&
                [
                  'plannedStart',
                  'plannedEnd',
                  'plannedAllDay',
                  'title',
                  'location',
                ].contains(field) ||
            previous != null &&
                (old.data[field] == previous[field] ||
                    field == 'kind' &&
                        old.kind.name == (previous['kind'] ?? 'schedule')) ||
            previous == null &&
                (field == 'plannedStart' ||
                    field == 'plannedEnd' ||
                    field == 'plannedAllDay')) {
          fields[field] = snapshot[field];
        }
      }
      if (index < 0) fields['category'] = event['calendarTitle'];
      final calendarLink = <String, dynamic>{
        'deviceID': deviceID,
        'key': key,
        'eventID': event['eventID'],
        'calendarID': event['calendarID'],
        'calendarTitle': event['calendarTitle'],
        'seriesID': event['seriesID'],
        'recurring': event['recurring'],
        'originalOccurrence': event['originalOccurrence'],
        'snapshot': snapshot,
      };
      fields['androidCalendarLink'] = calendarLink;
      fields['routineSeriesID'] = routineIdentity?.seriesID;
      fields['routineOccurrenceID'] = routineIdentity?.occurrenceID;
      if (index < 0 ||
          reattachedBySharedIdentity && old.source.isEmpty) {
        fields['source'] = '系统日历 · ${event['calendarTitle']}';
      }
      // Comparing the normalized data avoids a save on every app resume.
      if (fields.entries.every(
        (f) => jsonEncode(old.data[f.key]) == jsonEncode(f.value),
      )) {
        continue;
      }
      final updated = old.change(fields, now: clock());
      validateEntry(updated);
      if (index < 0) {
        next.add(updated);
      } else {
        next[index] = updated;
      }
      changed++;
    }
    if (changed > 0) {
      _commit(_withRoutineIdentityFields(_archive.withEntries(next)));
    }
    return changed;
  }

  List<Entry> get cleanableCalendarEntries {
    final settings = androidCalendarSettings;
    final selected = Set<String>.from(settings['selected'] as List? ?? []);
    return entries.where((e) {
      final link = e.data['androidCalendarLink'] as Map?;
      if (link == null ||
          link['deviceID'] != settings['deviceID'] ||
          selected.contains(link['calendarID']) ||
          e.completed ||
          e.steps.isNotEmpty ||
          e.startedAt != null ||
          e.focusSeconds(clock()) > 0 ||
          e.estimate != null ||
          e.platform.isNotEmpty ||
          e.repeatRule != 'never' ||
          e.data['reminder'] != null) {
        return false;
      }
      final snapshot = link['snapshot'] as Map?;
      if (snapshot == null) return false;
      final plain = [
        'title',
        'body',
        'location',
        'plannedStart',
        'plannedEnd',
        'plannedAllDay',
        'dueDate',
      ];
      return plain.every((key) => e.data[key] == snapshot[key]) &&
          e.kind.name == (snapshot['kind'] ?? 'schedule') &&
          e.category == link['calendarTitle'];
    }).toList();
  }

  int cleanUnselectedCalendarEntries() {
    final removed = cleanableCalendarEntries;
    final ids = removed.map((e) => e.id).toSet();
    if (ids.isEmpty || readOnly) return 0;
    var staged = _archive.withEntries(
      entries.where((e) => !ids.contains(e.id)).toList(),
    );
    for (final entry in removed) {
      staged = staged.withTombstone(
        'tombstones',
        entry.id,
        lastUpdate: entry.updatedAt,
        now: clock(),
      );
    }
    _commit(staged);
    return ids.length;
  }

  Future<void> load() async {
    if (storage case final NativeStorage native) {
      try {
        displayVersion = await native.appVersion() ?? displayVersion;
      } catch (_) {
        /* Version lookup must not block archive recovery. */
      }
    }
    var backfilled = false;
    var seeded = false;
    try {
      final content = await storage.read();
      if (content != null) {
        _archive = Archive.decode(content);
        final normalized = _withRoutineIdentityFields(_archive);
        backfilled = normalized.encode() != _archive.encode();
        _archive = normalized;
      } else if (storage is NativeStorage) {
        // 只有真机首次安装（档案文件还不存在）才播种内置说明；MemoryStorage
        // （全部单测）与已有档案文件的设备都不播种。
        _archive = _archive.withEntries([builtInGuideNote(clock())]);
        seeded = true;
      }
    } catch (exception) {
      readOnly = true;
      error = '本地数据无法读取，原文件已保留。请勿卸载测试版。\n$exception';
    }
    if (!readOnly) await refreshServices();
    loading = false;
    notifyListeners();
    if (!readOnly) {
      if (seeded || backfilled) {
        _commit(_archive);
      } else {
        onLocalWrite?.call();
      }
    }
  }

  void _commit(Archive archive) {
    if (readOnly || loading) return;
    // Local edits must not carry the original device's sync replica back out.
    _archive = Archive(
      entries: archive.entries,
      metadata: {...archive.metadata}..remove('replica'),
    );
    final content = _archive.encode();
    final revision = ++_revision;
    saving = true;
    saveFailed = false;
    error = null;
    notifyListeners();
    _writes = _writes.then((_) async {
      try {
        await storage.write(content);
        if (revision == _revision) await refreshServices();
        if (revision == _revision) {
          saving = false;
          saveFailed = false;
          error = null;
          onLocalWrite?.call();
        }
      } catch (exception) {
        if (revision == _revision) {
          saving = false;
          saveFailed = true;
          error = '保存失败，修改暂存在内存中。请重试保存。\n$exception';
        }
      }
      notifyListeners();
    });
  }

  void retrySave() => _commit(_archive);
  void save(Entry entry) {
    if (readOnly) return;
    validateEntry(entry);
    final previous = find(entry.id);
    final next = entries.where((e) => e.id != entry.id).toList()..add(entry);
    if (!entry.calendarRoutine &&
        entry.completed &&
        previous?.completed != true &&
        !next.any((e) => e.data['previousOccurrenceID'] == entry.id)) {
      final successor = entry.nextOccurrence(clock());
      if (successor != null) next.add(successor);
    }
    _commit(_archive.withEntries(next));
  }

  void toggle(String id) {
    final entry = find(id);
    if (entry == null || !entry.isTask) return;
    save(entry.setCompleted(!entry.completed, clock()));
  }

  void toggleStep(String id, String step) {
    final entry = find(id);
    if (entry != null) save(entry.toggleStep(step, clock()));
  }

  /// Planning fields: plannedDays holds date-only keys ('yyyy-MM-dd'),
  /// deduplicated and ascending.
  void setPlannedDays(String id, List<DateTime> days) {
    final entry = find(id);
    if (entry == null) return;
    final keys = days.map((d) => dayKey(dayOf(d))).toSet().toList()..sort();
    save(entry.change({'plannedDays': keys}, now: clock()));
  }

  /// Planned time window for tasks. The entry kind stays untouched; the
  /// end-after-start check is delegated to validateEntry via save().
  void setPlannedTime(String id, DateTime start, DateTime end) {
    final entry = find(id);
    if (entry == null || !entry.isTask) return;
    save(entry.change({
      'plannedStart': isoDate(start),
      'plannedEnd': isoDate(end),
    }, now: clock()));
  }

  /// Drag ordering: assign 0..n sortOrder to the given entries in the given
  /// order with a single commit.
  void reorder(List<String> orderedIds) {
    final next = entries.toList();
    var order = 0;
    for (final id in orderedIds) {
      final index = next.indexWhere(
        (e) => e.id.toUpperCase() == id.toUpperCase(),
      );
      if (index < 0) continue;
      next[index] = next[index].change({'sortOrder': order++}, now: clock());
    }
    _commit(_archive.withEntries(next));
  }

  void delete(String id) {
    final target = find(id);
    final link = target?.data['androidCalendarLink'] as Map?;
    final settings = androidCalendarSettings;
    var metadata = {..._archive.metadata};
    if (link != null && settings['deviceID'] == link['deviceID']) {
      metadata['androidCalendarSync'] = {
        ...settings,
        'suppressed': {
          ...List<String>.from(settings['suppressed'] as List? ?? []),
          link['key'] as String,
        }.toList(),
      };
    }
    final staged = Archive(
      entries: entries.where((e) => e.id != id).toList(),
      metadata: metadata,
    );
    _commit(
      staged.withTombstone(
        'tombstones',
        id,
        lastUpdate: target?.updatedAt,
        now: clock(),
      ),
    );
  }

  void focus(String id) {
    if (readOnly) return;
    final target = find(id);
    if (target == null || target.completed || !target.isTask) return;
    final now = clock();
    final next = entries.map((e) {
      if (e.id == target.id) {
        return e.startedAt == null
            ? e.change({'startedAt': isoDate(now)}, now: now)
            : e.pause(now);
      }
      return e.pause(now);
    }).toList();
    _commit(_archive.withEntries(next));
  }

  /// Merge an incoming account copy from another device. Returns true when the
  /// local archive changed. Throws FormatException on unreadable remote data;
  /// in that case the local archive is untouched.
  bool applyCloudArchive(String content) {
    if (readOnly || loading) return false;
    final remote = Archive.decode(content);
    final merged = _archive.merge(remote);
    // The Android calendar source is a per-device setting; account data must
    // not swap this device's calendar identities or suppression list.
    final localCalendar = _archive.metadata['androidCalendarSync'];
    final metadata = {...merged.metadata};
    if (localCalendar != null) {
      metadata['androidCalendarSync'] = localCalendar;
    }
    final next = _withRoutineIdentityFields(collapseRunningSessions(
      Archive(entries: merged.entries, metadata: metadata),
      clock(),
    ));
    if (next.encode() == _archive.encode()) return false;
    _commit(next);
    return true;
  }

  /// Apply an archive projected from the shared-folder replica document.
  /// Returns true when the local archive changed.
  bool applyLocalSyncArchive(Archive archive) {
    if (readOnly || loading) return false;
    final next = _withRoutineIdentityFields(
      collapseRunningSessions(archive, clock()),
    );
    if (next.encode() == _archive.encode()) return false;
    _commit(next);
    return true;
  }

  Future<int?> importBackup() async {
    if (readOnly) return null;
    final content = await storage.pickBackup();
    if (content == null) return null;
    final imported = Archive.decode(content);
    final merged = _archive.merge(imported);
    // A merged copy may carry several running sessions; only one may run.
    _commit(
      _withRoutineIdentityFields(collapseRunningSessions(merged, clock())),
    );
    await settled;
    if (saveFailed) throw StateError('导入的事项尚未写入磁盘，请重试保存。');
    return imported.entries.length;
  }

  Future<bool> exportBackup() async {
    final content = readOnly ? await storage.read() : _archive.encode();
    if (content == null) throw StateError('没有可以导出的原始文件。');
    return storage.exportBackup(content);
  }
}
