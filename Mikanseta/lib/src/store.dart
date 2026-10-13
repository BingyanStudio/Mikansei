import 'dart:async';

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
  String displayVersion = '0.1.1 (2)';
  String? error;
  int _revision = 0;
  Future<void> _writes = Future.value();
  Future<void> get settled => _writes;
  TaskBoard get board => TaskBoard(entries, clock());
  Entry? find(String id) => entries.where((e) => e.id == id).firstOrNull;
  Entry? get running =>
      entries.where((e) => !e.completed && e.startedAt != null).firstOrNull;

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

  void delete(String id) =>
      _commit(_archive.withEntries(entries.where((e) => e.id != id).toList()));
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
