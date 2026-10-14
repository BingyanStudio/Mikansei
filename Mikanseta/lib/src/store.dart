import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'domain.dart';

abstract class ArchiveStorage {
  Future<String?> read();
  Future<void> write(String content);
  Future<String?> pickBackup();
  Future<bool> exportBackup(String content);
}

class NativeStorage implements ArchiveStorage {
  static const channel = MethodChannel('mikanseta/native');
  Future<String?> appVersion() => channel.invokeMethod<String>('appInfo');
  @override
  Future<String?> read() => channel.invokeMethod<String>('readArchive');
  @override
  Future<void> write(String content) =>
      channel.invokeMethod<void>('writeArchive', content);
  @override
  Future<String?> pickBackup() => channel.invokeMethod<String>('importArchive');
  @override
  Future<bool> exportBackup(String content) async =>
      await channel.invokeMethod<bool>('exportArchive', content) ?? false;
}

class EntryStore extends ChangeNotifier {
  EntryStore(this.storage, {DateTime Function()? clock})
    : clock = clock ?? DateTime.now;
  final ArchiveStorage storage;
  final DateTime Function() clock;
  Archive _archive = Archive(entries: []);
  List<Entry> get entries => List.unmodifiable(_archive.entries);
  bool loading = true;
  bool readOnly = false;
  bool saveFailed = false;
  bool saving = false;
  String displayVersion = '0.1.2 (3)';
  String? error;
  int _revision = 0;
  Future<void> _writes = Future.value();
  Future<void> get settled => _writes;
  TaskBoard get board => TaskBoard(entries, clock());
  Entry? find(String id) => entries.where((e) => e.id == id).firstOrNull;
  Entry? get running =>
      entries.where((e) => !e.completed && e.startedAt != null).firstOrNull;
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

  int importAndroidEvents(List<Map<String, dynamic>> events, String deviceID) {
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
      };
      final old = index >= 0
          ? next[index]
          : Entry.create(
              title: snapshot['title'] as String,
              kind: EntryKind.schedule,
              now: clock(),
            );
      final previous =
          (old.data['androidCalendarLink'] as Map?)?['snapshot'] as Map?;
      final fields = <String, dynamic>{};
      for (final field in snapshot.keys) {
        if (index < 0 ||
            previous != null && old.data[field] == previous[field] ||
            previous == null &&
                (field == 'plannedStart' ||
                    field == 'plannedEnd' ||
                    field == 'plannedAllDay')) {
          fields[field] = snapshot[field];
        }
      }
      if (index < 0) fields['category'] = event['calendarTitle'];
      fields['androidCalendarLink'] = {
        'deviceID': deviceID,
        'key': key,
        'eventID': event['eventID'],
        'calendarID': event['calendarID'],
        'snapshot': snapshot,
      };
      if (index < 0) fields['source'] = '系统日历 · ${event['calendarTitle']}';
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
    if (changed > 0) _commit(_archive.withEntries(next));
    return changed;
  }

  Future<void> load() async {
    if (storage case final NativeStorage native) {
      try {
        displayVersion = await native.appVersion() ?? displayVersion;
      } catch (_) {
        /* Version lookup must not block archive recovery. */
      }
    }
    try {
      final content = await storage.read();
      if (content != null) _archive = Archive.decode(content);
    } catch (exception) {
      readOnly = true;
      error = '本地数据无法读取，原文件已保留。请勿卸载测试版。\n$exception';
    }
    loading = false;
    notifyListeners();
  }

  void _commit(Archive archive) {
    if (readOnly) return;
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
        if (revision == _revision) {
          saving = false;
          saveFailed = false;
          error = null;
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
    if (entry.completed &&
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

  void delete(String id) {
    final link = find(id)?.data['androidCalendarLink'] as Map?;
    final settings = androidCalendarSettings;
    final metadata = {..._archive.metadata};
    if (link != null && settings['deviceID'] == link['deviceID']) {
      metadata['androidCalendarSync'] = {
        ...settings,
        'suppressed': {
          ...List<String>.from(settings['suppressed'] as List? ?? []),
          link['key'] as String,
        }.toList(),
      };
    }
    _commit(
      Archive(
        entries: entries.where((e) => e.id != id).toList(),
        metadata: metadata,
      ),
    );
  }

  void focus(String id) {
    if (readOnly) return;
    final target = find(id);
    if (target == null || target.completed || !target.isTask) return;
    final now = clock();
    final next = entries.map((e) {
      if (e.id == id) {
        return e.startedAt == null
            ? e.change({'startedAt': isoDate(now)}, now: now)
            : e.pause(now);
      }
      return e.pause(now);
    }).toList();
    _commit(_archive.withEntries(next));
  }

  Future<int?> importBackup() async {
    if (readOnly) return null;
    final content = await storage.pickBackup();
    if (content == null) return null;
    final imported = Archive.decode(content);
    final merged = _archive.merge(imported);
    // Ensure a backup with several active sessions does not run multiple timers.
    final sessions =
        merged.entries
            .where((e) => e.startedAt != null && !e.completed)
            .toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final winner = sessions.firstOrNull?.id;
    final now = clock();
    final next = merged.entries
        .map(
          (e) => e.startedAt != null && (e.completed || e.id != winner)
              ? e.pause(now)
              : e,
        )
        .toList();
    _commit(merged.withEntries(next));
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
