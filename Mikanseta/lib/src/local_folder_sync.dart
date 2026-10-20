import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'domain.dart';
import 'store.dart';

/// Canonical JSON: map keys sorted recursively, null-valued keys dropped. Two
/// logically equal records therefore compare equal even when one side came
/// from Swift (which omits nil keys) and the other from Flutter (which may
/// write explicit nulls).
String canonicalJson(Object? value) {
  final buffer = StringBuffer();
  void write(Object? node) {
    if (node == null) {
      buffer.write('null');
    } else if (node is String || node is num || node is bool) {
      buffer.write(jsonEncode(node));
    } else if (node is List) {
      buffer.write('[');
      for (var i = 0; i < node.length; i++) {
        if (i > 0) buffer.write(',');
        write(node[i]);
      }
      buffer.write(']');
    } else if (node is Map) {
      final keys = node.keys.map((key) => key.toString()).toList()..sort();
      buffer.write('{');
      var first = true;
      for (final key in keys) {
        final item = node[key];
        if (item == null) continue;
        if (!first) buffer.write(',');
        first = false;
        buffer.write(jsonEncode(key));
        buffer.write(':');
        write(item);
      }
      buffer.write('}');
    } else {
      buffer.write(jsonEncode(node));
    }
  }

  write(value);
  return buffer.toString();
}

Map<String, dynamic> _jsonMap(Object? value) =>
    Map<String, dynamic>.from(value as Map);

/// A logical clock revision. Higher counter wins; equal counters are ordered
/// by device UUID so every device reaches the same winner.
class SyncRevision implements Comparable<SyncRevision> {
  const SyncRevision(this.counter, this.device);
  final int counter;
  final String device;

  factory SyncRevision.fromJson(Map<String, dynamic> json) {
    final counter = json['counter'];
    final device = json['device'];
    if (counter is! num ||
        counter < 1 ||
        counter >= 1000000000000 ||
        device is! String) {
      throw const FormatException('同步修订号无效。');
    }
    return SyncRevision(counter.toInt(), device.toUpperCase());
  }

  Map<String, dynamic> toJson() => {'counter': counter, 'device': device};

  @override
  int compareTo(SyncRevision other) {
    final byCounter = counter.compareTo(other.counter);
    return byCounter != 0 ? byCounter : device.compareTo(other.device);
  }
}

class SyncedRecord {
  SyncedRecord({required this.id, required this.revision, this.value});
  final String id;
  final SyncRevision revision;

  /// Null is a permanent deletion marker.
  final Map<String, dynamic>? value;

  factory SyncedRecord.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final revision = json['revision'];
    final value = json['value'];
    if (id is! String || revision is! Map || (value != null && value is! Map)) {
      throw const FormatException('同步记录无效。');
    }
    final map = value == null ? null : _jsonMap(value);
    if (map != null &&
        (map['id'] as String?)?.toUpperCase() != id.toUpperCase()) {
      throw const FormatException('同步记录编号不一致。');
    }
    return SyncedRecord(
      id: id.toUpperCase(),
      revision: SyncRevision.fromJson(_jsonMap(revision)),
      value: map,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'revision': revision.toJson(),
    if (value != null) 'value': value,
  };
}

/// The on-disk document shared with the native Mikansei folder sync:
/// `{version, entries, courses, deletedCalendarOccurrences}`.
class ReplicaDocument {
  ReplicaDocument({
    List<SyncedRecord>? entries,
    List<SyncedRecord>? courses,
    List<Map<String, dynamic>>? deletedCalendarOccurrences,
  }) : entries = entries ?? [],
       courses = courses ?? [],
       deletedCalendarOccurrences = deletedCalendarOccurrences ?? [];

  final List<SyncedRecord> entries;
  final List<SyncedRecord> courses;
  final List<Map<String, dynamic>> deletedCalendarOccurrences;

  factory ReplicaDocument.decode(String text) {
    final json = jsonDecode(text);
    if (json is! Map<String, dynamic> || json['version'] != 1) {
      throw const FormatException('同步文件格式或版本不支持。');
    }
    List<SyncedRecord> read(String key) {
      final raw = json[key];
      if (raw != null && raw is! List) {
        throw const FormatException('同步文件记录列表无效。');
      }
      final records = [
        for (final item in raw as List? ?? [])
          SyncedRecord.fromJson(_jsonMap(item)),
      ];
      final ids = records.map((record) => record.id).toSet();
      if (ids.length != records.length) {
        throw const FormatException('同步文件包含重复编号。');
      }
      return records;
    }

    final deleted = json['deletedCalendarOccurrences'];
    if (deleted != null && deleted is! List) {
      throw const FormatException('同步文件日历记录无效。');
    }
    return ReplicaDocument(
      entries: read('entries'),
      courses: read('courses'),
      deletedCalendarOccurrences: [
        for (final item in deleted as List? ?? []) _jsonMap(item),
      ],
    );
  }

  String encode() => canonicalJson({
    'version': 1,
    'entries': (entries.toList()..sort((a, b) => a.id.compareTo(b.id)))
        .map((record) => record.toJson())
        .toList(),
    'courses': (courses.toList()..sort((a, b) => a.id.compareTo(b.id)))
        .map((record) => record.toJson())
        .toList(),
    if (deletedCalendarOccurrences.isNotEmpty)
      'deletedCalendarOccurrences': deletedCalendarOccurrences,
  });

  int get maxCounter => [
    ...entries.map((record) => record.revision.counter),
    ...courses.map((record) => record.revision.counter),
  ].fold(0, max);

  void merge(ReplicaDocument remote) {
    _mergeRecords(entries, remote.entries);
    _mergeRecords(courses, remote.courses);
    final seen = deletedCalendarOccurrences.map(canonicalJson).toSet();
    for (final identity in remote.deletedCalendarOccurrences) {
      if (seen.add(canonicalJson(identity))) {
        deletedCalendarOccurrences.add(identity);
      }
    }
    deletedCalendarOccurrences.sort(_identityOrder);
  }

  static void _mergeRecords(
    List<SyncedRecord> local,
    List<SyncedRecord> remote,
  ) {
    final indexed = {for (final record in local) record.id: record};
    for (final record in remote) {
      final existing = indexed[record.id];
      // Local keeps ties, matching WorkspaceSyncDocument.mergeRecords.
      if (existing == null ||
          record.revision.compareTo(existing.revision) > 0) {
        indexed[record.id] = record;
      }
    }
    local
      ..clear()
      ..addAll(indexed.values.toList()..sort((a, b) => a.id.compareTo(b.id)));
  }

  static int _identityOrder(Map<String, dynamic> a, Map<String, dynamic> b) {
    for (final key in [
      'eventID',
      'occurrence',
      'calendarID',
      'localEventID',
      'calendarTitle',
      'sourceTitle',
    ]) {
      final result = (a[key] ?? '').toString().compareTo(
        (b[key] ?? '').toString(),
      );
      if (result != 0) return result;
    }
    return 0;
  }

  /// Diff the local archive against the document and return the changed ids.
  /// Courses and entries are compared by canonical JSON so null-key and key
  /// order differences do not create phantom revisions.
  ({Set<String> entries, Set<String> courses}) changedFrom(Archive archive) {
    final currentEntries = {for (final record in entries) record.id: record};
    final currentCourses = {for (final record in courses) record.id: record};
    final nextEntries = <String, Map<String, dynamic>>{
      for (final entry in archive.entries)
        entry.id.toUpperCase(): _normalizedEntry(entry.data),
    };
    final nextCourses = <String, Map<String, dynamic>>{
      for (final course in archive.metadata['courses'] as List? ?? [])
        ((course['id'] as String).toUpperCase()): _jsonMap(course),
    };
    final changedEntries = <String>{};
    for (final id in {...currentEntries.keys, ...nextEntries.keys}) {
      if (canonicalJson(currentEntries[id]?.value) !=
          canonicalJson(nextEntries[id])) {
        changedEntries.add(id);
      }
    }
    final changedCourses = <String>{};
    for (final id in {...currentCourses.keys, ...nextCourses.keys}) {
      if (canonicalJson(currentCourses[id]?.value) !=
          canonicalJson(nextCourses[id])) {
        changedCourses.add(id);
      }
    }
    return (entries: changedEntries, courses: changedCourses);
  }

  /// Apply a capture batch: changed/new records keep their value, removed
  /// records become tombstones, all with one fresh revision.
  void applyCapture(
    Archive archive,
    SyncRevision revision, {
    required Set<String> entryIds,
    required Set<String> courseIds,
  }) {
    if (entryIds.isEmpty && courseIds.isEmpty) return;
    final nextEntries = <String, Map<String, dynamic>>{
      for (final entry in archive.entries)
        entry.id.toUpperCase(): _normalizedEntry(entry.data),
    };
    final nextCourses = <String, Map<String, dynamic>>{
      for (final course in archive.metadata['courses'] as List? ?? [])
        ((course['id'] as String).toUpperCase()): _jsonMap(course),
    };
    final delta = ReplicaDocument(
      entries: [
        for (final id in entryIds)
          SyncedRecord(id: id, revision: revision, value: nextEntries[id]),
      ],
      courses: [
        for (final id in courseIds)
          SyncedRecord(id: id, revision: revision, value: nextCourses[id]),
      ],
    );
    merge(delta);
  }

  /// Project the merged document onto the local archive while preserving
  /// local-only metadata (preferences, calendar source, tombstones). Throws
  /// FormatException when the merged result is not a valid archive.
  Archive project(Archive local, DateTime now) {
    final entryValues = [
      for (final record in entries)
        if (record.value != null) Entry(_normalizedEntry(record.value!)),
    ];
    final courseValues = [
      for (final record in courses)
        if (record.value != null) _jsonMap(record.value),
    ];
    final liveEntries = {
      for (final record in entries)
        if (record.value != null) record.id,
    };
    final deadEntries = {
      for (final record in entries)
        if (record.value == null) record.id,
    };
    final liveCourses = {
      for (final record in courses)
        if (record.value != null) record.id,
    };
    final deadCourses = {
      for (final record in courses)
        if (record.value == null) record.id,
    };

    var metadata = <String, dynamic>{...local.metadata, 'courses': courseValues}
      ..remove('replica');
    metadata = _removeTombstones(metadata, 'tombstones', liveEntries);
    metadata = _removeTombstones(metadata, 'courseTombstones', liveCourses);

    var candidate = Archive(entries: entryValues, metadata: metadata);
    for (final id in deadEntries) {
      final previous = local.entries
          .where((entry) => entry.id.toUpperCase() == id)
          .firstOrNull
          ?.updatedAt;
      candidate = candidate.withTombstone(
        'tombstones',
        id,
        lastUpdate: previous,
        now: now,
      );
    }
    for (final id in deadCourses) {
      candidate = candidate.withTombstone('courseTombstones', id, now: now);
    }

    // Validate exactly like a backup import before handing it to the store.
    return Archive.decode(candidate.encode());
  }

  static Map<String, dynamic> _removeTombstones(
    Map<String, dynamic> metadata,
    String key,
    Set<String> liveIds,
  ) {
    final raw = metadata[key];
    if (raw is! Map) return metadata;
    final next = <String, dynamic>{};
    for (final entry in raw.entries) {
      if (!liveIds.contains(entry.key.toString().toUpperCase())) {
        next[entry.key.toString()] = entry.value;
      }
    }
    final result = {...metadata};
    if (next.isEmpty) {
      result.remove(key);
    } else {
      result[key] = next;
    }
    return result;
  }

  static Map<String, dynamic> _normalizedEntry(Map<String, dynamic> data) {
    final value = _jsonMap(data);
    value['id'] = (value['id'] as String).toUpperCase();
    return value;
  }
}

/// Persistent per-device replica state, mirroring `WorkspaceReplica`.
class ReplicaState {
  ReplicaState({
    required this.device,
    required this.counter,
    required this.document,
  });
  final String device;
  int counter;
  final ReplicaDocument document;

  String get fileName => 'replica-$device.json';

  factory ReplicaState.fresh() =>
      ReplicaState(device: newId(), counter: 0, document: ReplicaDocument());

  factory ReplicaState.decode(String text) {
    final json = jsonDecode(text);
    final device = json is Map ? json['device'] : null;
    final counter = json is Map ? json['counter'] : null;
    final document = json is Map ? json['document'] : null;
    if (device is! String ||
        counter is! num ||
        counter < 0 ||
        counter >= 1000000000000 ||
        document is! Map) {
      throw const FormatException('本机同步状态文件无效。');
    }
    return ReplicaState(
      device: device.toUpperCase(),
      counter: counter.toInt(),
      document: ReplicaDocument.decode(canonicalJson(document)),
    );
  }

  String encode() => canonicalJson({
    'device': device,
    'counter': counter,
    'document': jsonDecode(document.encode()),
  });

  /// Make room for a new local batch and record it.
  void capture(Archive archive) {
    final changed = document.changedFrom(archive);
    if (changed.entries.isEmpty && changed.courses.isEmpty) return;
    counter += 1;
    document.applyCapture(
      archive,
      SyncRevision(counter, device),
      entryIds: changed.entries,
      courseIds: changed.courses,
    );
  }

  void receive(ReplicaDocument remote) {
    document.merge(remote);
    counter = max(counter, document.maxCounter);
  }
}

class LocalSyncFolderStatus {
  LocalSyncFolderStatus({
    required this.connected,
    this.name,
    this.path,
    this.error,
  });
  final bool connected;
  final String? name;
  final String? path;
  final String? error;
}

/// Platform primitives for the shared folder. Apple platforms persist a
/// security-scoped bookmark; Android uses a persisted SAF tree permission.
abstract class LocalSyncBackend {
  /// Returns null when the user cancels the picker.
  Future<LocalSyncFolderStatus?> pickFolder();
  Future<LocalSyncFolderStatus> folder();
  Future<void> disconnect();
  Future<Map<String, String>> readFiles();
  Future<bool> writeFile(String name, String content);
  Future<String?> readState();
  Future<void> writeState(String content);
}

class NativeLocalSyncBackend implements LocalSyncBackend {
  @override
  Future<LocalSyncFolderStatus?> pickFolder() async {
    final raw = await NativeStorage.invokeMapMethod<String, dynamic>(
      'pickLocalSyncFolder',
    );
    if (raw == null) return null;
    return LocalSyncFolderStatus(
      connected: true,
      name: raw['name'] as String?,
      path: raw['path'] as String?,
    );
  }

  @override
  Future<LocalSyncFolderStatus> folder() async {
    final raw =
        await NativeStorage.invokeMapMethod<String, dynamic>(
          'localSyncFolder',
        ) ??
        const {};
    return LocalSyncFolderStatus(
      connected: raw['connected'] == true,
      name: raw['name'] as String?,
      path: raw['path'] as String?,
      error: raw['error'] as String?,
    );
  }

  @override
  Future<void> disconnect() =>
      NativeStorage.invokeMethod<void>('disconnectLocalSyncFolder');

  @override
  Future<Map<String, String>> readFiles() async {
    final raw =
        await NativeStorage.invokeMapMethod<String, dynamic>(
          'readLocalSyncFiles',
        ) ??
        const {};
    return {for (final entry in raw.entries) entry.key: entry.value.toString()};
  }

  @override
  Future<bool> writeFile(String name, String content) async =>
      await NativeStorage.invokeMethod<bool>('writeLocalSyncFile', {
        'name': name,
        'content': content,
      }) ??
      false;

  @override
  Future<String?> readState() =>
      NativeStorage.invokeMethod<String>('readLocalSyncState');

  @override
  Future<void> writeState(String content) =>
      NativeStorage.invokeMethod<void>('writeLocalSyncState', content);
}

/// Automatically exchanges the archive with the folder used by the native
/// Mikansei app (and by other Mikanseta devices).
class LocalFolderSync extends ChangeNotifier {
  LocalFolderSync(
    this._store,
    this._backend, {
    this.exchangeDelay = const Duration(seconds: 2),
    this.period = const Duration(seconds: 30),
  }) {
    _boot();
  }

  final EntryStore _store;
  final LocalSyncBackend _backend;
  final Duration exchangeDelay;

  /// Null disables the periodic exchange (used by tests).
  final Duration? period;

  bool initialized = false;
  bool connected = false;
  bool busy = false;
  String? folderName;
  String? folderPath;
  String? error;
  DateTime? lastSyncedAt;

  Timer? _debounce;
  Timer? _periodic;
  bool _rerun = false;
  bool _disposed = false;
  final Completer<void> _ready = Completer<void>();

  Future<void> get whenReady => _ready.future;

  String get folderLabel => folderName ?? folderPath ?? '共享文件夹';

  Future<void> _boot() async {
    try {
      _apply(await _backend.folder());
      if (connected) {
        _startPeriodic();
        await _exchange();
      }
    } catch (exception) {
      error = '读取本机同步设置失败：$exception';
    }
    initialized = true;
    _notify();
    if (!_ready.isCompleted) _ready.complete();
  }

  void _apply(LocalSyncFolderStatus status) {
    connected = status.connected;
    folderName = status.name;
    folderPath = status.path;
    if (!connected) {
      _periodic?.cancel();
      _periodic = null;
    }
    if (status.error != null) error = status.error;
  }

  Future<void> chooseFolder() async {
    if (busy) return;
    busy = true;
    error = null;
    _notify();
    try {
      final picked = await _backend.pickFolder();
      if (picked != null) {
        _apply(picked);
        _startPeriodic();
        await _exchange();
      }
    } catch (exception) {
      error = '选择文件夹失败：$exception';
    }
    busy = false;
    _notify();
  }

  Future<void> disconnect() async {
    _debounce?.cancel();
    _periodic?.cancel();
    _periodic = null;
    try {
      await _backend.disconnect();
      connected = false;
      folderName = null;
      folderPath = null;
      error = null;
    } catch (exception) {
      error = '停止同步失败：$exception';
    }
    _notify();
  }

  /// Called after every durable local write; rapid edits coalesce.
  void scheduleExchange() {
    if (_disposed || !connected) return;
    _debounce?.cancel();
    _debounce = Timer(exchangeDelay, _exchange);
  }

  Future<void> syncNow() => _exchange();

  void _startPeriodic() {
    final period = this.period;
    if (period == null || _periodic != null) return;
    _periodic = Timer.periodic(period, (_) => _exchange());
  }

  Future<void> _exchange() async {
    if (_disposed || !connected || _store.loading || _store.readOnly) return;
    if (busy) {
      _rerun = true;
      return;
    }
    busy = true;
    error = null;
    _notify();
    try {
      // Read every remote document first: unreadable data aborts the whole
      // exchange before the local archive or our file is touched.
      final files = await _backend.readFiles();
      final remote = [
        for (final content in files.values) ReplicaDocument.decode(content),
      ];

      var state = await _loadState();
      state ??= ReplicaState.fresh();
      // Capture local changes before merging so new local records are not
      // projected away, then fold every remote document in.
      state.capture(_store.archive);
      for (final document in remote) {
        state.receive(document);
      }

      final candidate = state.document.project(_store.archive, _store.clock());
      if (_store.applyLocalSyncArchive(candidate)) {
        await _store.settled;
        if (_store.saveFailed) {
          throw StateError('本机尚未完成保存，暂缓写出同步文件。');
        }
      }

      await _backend.writeFile(state.fileName, state.document.encode());
      await _backend.writeState(state.encode());
      lastSyncedAt = _store.clock();
    } catch (exception) {
      error = '本机同步失败，本机修改已保留：$exception';
    } finally {
      busy = false;
      _notify();
      if (_rerun && !_disposed && connected) {
        _rerun = false;
        scheduleExchange();
      } else {
        _rerun = false;
      }
    }
  }

  Future<ReplicaState?> _loadState() async {
    final text = await _backend.readState();
    if (text == null) return null;
    try {
      return ReplicaState.decode(text);
    } on FormatException {
      // A damaged state file must not block syncing; a fresh device identity
      // simply joins with counter zero, like a restored backup.
      return null;
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    _periodic?.cancel();
    super.dispose();
  }
}
