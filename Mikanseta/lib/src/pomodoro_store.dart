import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'domain.dart' show newId;
import 'store.dart' show NativeStorage;

enum PomodoroMode { countdown, countUp }

class PomodoroRun {
  const PomodoroRun({
    required this.id,
    required this.subject,
    required this.mode,
    required this.targetSeconds,
    required this.accumulatedSeconds,
    required this.runningSince,
    required this.createdAt,
    required this.linkedEntryID,
  });

  final String id;
  final String subject;
  final PomodoroMode mode;
  final double targetSeconds;
  final double accumulatedSeconds;
  final double? runningSince;
  final double createdAt;
  final String? linkedEntryID;

  factory PomodoroRun.fromJson(Map<String, dynamic> json) {
    final mode = PomodoroMode.values.byName(json['mode'] as String);
    final id = json['id'];
    final subject = json['subject'];
    final target = _number(json['targetSeconds']);
    final accumulated = _number(json['accumulatedSeconds']);
    final createdAt = _number(json['createdAt']);
    final runningSince = json['runningSince'] == null
        ? null
        : _number(json['runningSince']);
    final linkedEntryID = json['linkedEntryID'];
    if (id is! String ||
        id.isEmpty ||
        subject is! String ||
        subject.trim().isEmpty) {
      throw const FormatException('专注记录缺少主题或编号');
    }
    if (target < 0 ||
        accumulated < 0 ||
        createdAt <= 0 ||
        (runningSince != null && runningSince <= 0) ||
        (mode == PomodoroMode.countdown && target <= 0) ||
        (mode == PomodoroMode.countUp && target != 0) ||
        (linkedEntryID != null && linkedEntryID is! String)) {
      throw const FormatException('专注记录中的时间或关联事项无效');
    }
    return PomodoroRun(
      id: id,
      subject: subject.trim(),
      mode: mode,
      targetSeconds: target,
      accumulatedSeconds: accumulated,
      runningSince: runningSince,
      createdAt: createdAt,
      linkedEntryID: linkedEntryID as String?,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'subject': subject,
    'mode': mode.name,
    'targetSeconds': targetSeconds,
    'accumulatedSeconds': accumulatedSeconds,
    if (runningSince != null) 'runningSince': runningSince,
    'createdAt': createdAt,
    if (linkedEntryID != null) 'linkedEntryID': linkedEntryID,
  };

  PomodoroRun copyWith({
    double? accumulatedSeconds,
    double? runningSince,
    bool clearRunningSince = false,
  }) => PomodoroRun(
    id: id,
    subject: subject,
    mode: mode,
    targetSeconds: targetSeconds,
    accumulatedSeconds: accumulatedSeconds ?? this.accumulatedSeconds,
    runningSince: clearRunningSince ? null : runningSince ?? this.runningSince,
    createdAt: createdAt,
    linkedEntryID: linkedEntryID,
  );
}

class PomodoroRecord {
  const PomodoroRecord({
    required this.run,
    required this.endedAt,
    required this.durationSeconds,
    required this.outcome,
  });

  final PomodoroRun run;
  final double endedAt;
  final double durationSeconds;
  final String outcome;

  factory PomodoroRecord.fromJson(Map<String, dynamic> json) {
    final runJson = json['run'];
    if (runJson is! Map) throw const FormatException('历史专注记录无效');
    final endedAt = _number(json['endedAt']);
    final duration = _number(json['durationSeconds']);
    final outcome = json['outcome'];
    final run = PomodoroRun.fromJson(Map<String, dynamic>.from(runJson));
    if (endedAt <= 0 ||
        duration < 0 ||
        (outcome != 'completed' && outcome != 'stopped') ||
        run.runningSince != null ||
        (outcome == 'completed' && duration <= 0) ||
        (run.mode == PomodoroMode.countdown && duration > run.targetSeconds)) {
      throw const FormatException('历史专注记录中的时间无效');
    }
    return PomodoroRecord(
      run: run,
      endedAt: endedAt,
      durationSeconds: duration,
      outcome: outcome as String,
    );
  }

  Map<String, Object?> toJson() => {
    'run': run.toJson(),
    'endedAt': endedAt,
    'durationSeconds': durationSeconds,
    'outcome': outcome,
  };
}

class PomodoroArchive {
  const PomodoroArchive({this.active, this.history = const []});

  final PomodoroRun? active;
  final List<PomodoroRecord> history;

  factory PomodoroArchive.decode(String text) {
    final root = jsonDecode(text);
    if (root is! Map || root['version'] != 1 || root['history'] is! List) {
      throw const FormatException('专注历史文件版本无效');
    }
    final active = root['active'];
    final history = (root['history'] as List)
        .map((row) {
          if (row is! Map) throw const FormatException('专注历史数据无效');
          return PomodoroRecord.fromJson(Map<String, dynamic>.from(row));
        })
        .toList(growable: false);
    final decodedActive = active == null
        ? null
        : active is Map
        ? PomodoroRun.fromJson(Map<String, dynamic>.from(active))
        : throw const FormatException('当前专注数据无效');
    final ids = <String>{};
    for (final record in history) {
      if (!_isUUID(record.run.id) || !ids.add(record.run.id)) {
        throw const FormatException('专注历史编号重复或无效');
      }
    }
    if (decodedActive != null &&
        (!_isUUID(decodedActive.id) || !ids.add(decodedActive.id))) {
      throw const FormatException('当前专注编号重复或无效');
    }
    return PomodoroArchive(active: decodedActive, history: history);
  }

  String encode() => jsonEncode({
    'version': 1,
    'active': active?.toJson(),
    'history': history.map((record) => record.toJson()).toList(),
  });
}

abstract interface class PomodoroStorage {
  Future<String?> read();
  Future<void> write(String content);
  Future<void> writeWidgetSnapshot(String content);
}

class MemoryPomodoroStorage implements PomodoroStorage {
  String? archive;

  @override
  Future<String?> read() async => archive;

  @override
  Future<void> write(String content) async {
    archive = content;
  }

  @override
  Future<void> writeWidgetSnapshot(String content) async {}
}

/// Stores the timer alongside, but independently from, Mikansei's entry archive.
class NativePomodoroStorage implements PomodoroStorage {
  @override
  Future<String?> read() =>
      NativeStorage.invokeMethod<String>('readPomodoroArchive');

  @override
  Future<void> write(String content) =>
      NativeStorage.invokeMethod<void>('writePomodoroArchive', content);

  @override
  Future<void> writeWidgetSnapshot(String content) async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      return;
    }
    await NativeStorage.invokeMethod<void>('writePomodoroSnapshot', content);
  }
}

class PomodoroStore extends ChangeNotifier {
  PomodoroStore(this.storage, {DateTime Function()? clock})
    : clock = clock ?? DateTime.now;

  final PomodoroStorage storage;
  final DateTime Function() clock;
  PomodoroArchive _archive = const PomodoroArchive();
  Timer? _ticker;
  Future<void> _writes = Future.value();
  bool loading = true;
  bool readOnly = false;
  bool _loadStarted = false;
  String? error;
  String? _archiveSaveError;
  String? _snapshotSaveError;
  int _archiveDurableRevision = 0;
  int _revision = 0;

  PomodoroRun? get active => _archive.active;
  List<PomodoroRecord> get history => List.unmodifiable(_archive.history);
  bool get hasActive => active != null;
  String? get saveError => _archiveSaveError ?? _snapshotSaveError;
  Map<String, Object?> get widgetSnapshot =>
      Map<String, Object?>.from(_snapshot());
  double get activeElapsedSeconds {
    final run = active;
    if (run == null) return 0;
    final now = _epoch(clock());
    return run.accumulatedSeconds +
        (run.runningSince == null
            ? 0
            : (now - run.runningSince!).clamp(0, double.infinity));
  }

  double get activeRemainingSeconds {
    final run = active;
    if (run == null || run.mode != PomodoroMode.countdown) return 0;
    return (run.targetSeconds - activeElapsedSeconds).clamp(
      0,
      run.targetSeconds,
    );
  }

  int get todayCompletedCount {
    final day = _localDay(clock());
    return history
        .where(
          (record) =>
              record.outcome == 'completed' &&
              _localDay(_date(record.endedAt)) == day,
        )
        .length;
  }

  int get completedCount => history
      .where(
        (record) => record.outcome == 'completed' && record.durationSeconds > 0,
      )
      .length;

  double get todayRecordedSeconds => history
      .where((record) => _localDay(_date(record.endedAt)) == _localDay(clock()))
      .fold<double>(0, (total, record) => total + record.durationSeconds);

  Future<void> load() async {
    if (_loadStarted) return;
    _loadStarted = true;
    try {
      final text = await storage.read();
      _archive = text == null
          ? const PomodoroArchive()
          : PomodoroArchive.decode(text);
      loading = false;
      _ticker?.cancel();
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
      await _settleExpiredRun(persist: text == null ? false : true);
      await _writeSnapshot();
    } catch (exception) {
      loading = false;
      readOnly = true;
      error = '专注历史无法读取，原文件已保留：$exception';
    }
    notifyListeners();
  }

  Future<bool> start({
    required String subject,
    required PomodoroMode mode,
    required int minutes,
    String? linkedEntryID,
  }) async {
    await _settleExpiredRun(persist: true);
    final trimmed = subject.trim();
    if (loading || readOnly || active != null || trimmed.isEmpty) return false;
    if (mode == PomodoroMode.countdown && (minutes < 1 || minutes > 180)) {
      return false;
    }
    final now = _epoch(clock());
    final run = PomodoroRun(
      id: _newID(),
      subject: trimmed,
      mode: mode,
      targetSeconds: mode == PomodoroMode.countdown ? minutes * 60.0 : 0,
      accumulatedSeconds: 0,
      runningSince: now,
      createdAt: now,
      linkedEntryID: linkedEntryID,
    );
    _archive = PomodoroArchive(active: run, history: _archive.history);
    _revision++;
    notifyListeners();
    await _persist();
    return true;
  }

  Future<void> pause() async {
    await _settleExpiredRun(persist: true);
    final run = active;
    if (run == null || run.runningSince == null || readOnly) return;
    final now = _epoch(clock());
    var elapsed =
        run.accumulatedSeconds +
        (now - run.runningSince!).clamp(0, double.infinity);
    if (run.mode == PomodoroMode.countdown) {
      elapsed = elapsed.clamp(0, run.targetSeconds);
    }
    _archive = PomodoroArchive(
      active: run.copyWith(
        accumulatedSeconds: elapsed,
        clearRunningSince: true,
      ),
      history: _archive.history,
    );
    _revision++;
    notifyListeners();
    await _persist();
  }

  Future<void> resume() async {
    await _settleExpiredRun(persist: true);
    final run = active;
    if (run == null || run.runningSince != null || readOnly) return;
    _archive = PomodoroArchive(
      active: run.copyWith(runningSince: _epoch(clock())),
      history: _archive.history,
    );
    _revision++;
    notifyListeners();
    await _settleExpiredRun(persist: false);
    await _persist();
  }

  Future<void> finish() async {
    await _settleExpiredRun(persist: true);
    final run = active;
    if (run == null || readOnly) return;
    final now = _epoch(clock());
    final elapsed = activeElapsedSeconds;
    final countdownCompleted =
        run.mode == PomodoroMode.countdown && elapsed >= run.targetSeconds;
    final duration = run.mode == PomodoroMode.countdown && countdownCompleted
        ? run.targetSeconds
        : elapsed;
    final endedAt = countdownCompleted ? _completionEpoch(run) : now;
    _archive = PomodoroArchive(
      history: [
        PomodoroRecord(
          run: run.copyWith(
            accumulatedSeconds: duration,
            clearRunningSince: true,
          ),
          endedAt: endedAt,
          durationSeconds: duration,
          outcome:
              duration > 0 &&
                  (run.mode == PomodoroMode.countUp || countdownCompleted)
              ? 'completed'
              : 'stopped',
        ),
        ..._archive.history,
      ],
    );
    _revision++;
    notifyListeners();
    await _persist();
  }

  Future<void> handleRoute({
    required String action,
    required String? sessionID,
  }) async {
    if (action == 'open' && sessionID == null) return;
    final run = active;
    if (run == null || sessionID != run.id) return;
    switch (action) {
      case 'pause':
        await pause();
        break;
      case 'resume':
        await resume();
        break;
      case 'finish':
        await finish();
        break;
    }
  }

  Future<void> retrySave() async {
    if (readOnly) return;
    _revision++;
    notifyListeners();
    await _persist();
  }

  Future<void> refresh() async {
    if (loading || readOnly) return;
    await _settleExpiredRun(persist: true);
    await _writeSnapshot();
    notifyListeners();
  }

  void _tick() {
    if (loading) return;
    unawaited(_settleExpiredRun(persist: true));
    notifyListeners();
  }

  Future<void> _settleExpiredRun({required bool persist}) async {
    final run = active;
    if (run == null ||
        run.mode != PomodoroMode.countdown ||
        run.runningSince == null ||
        activeElapsedSeconds < run.targetSeconds) {
      return;
    }
    final duration = run.targetSeconds;
    final completion = _completionEpoch(run);
    _archive = PomodoroArchive(
      history: [
        PomodoroRecord(
          run: run.copyWith(
            accumulatedSeconds: duration,
            clearRunningSince: true,
          ),
          endedAt: completion,
          durationSeconds: duration,
          outcome: 'completed',
        ),
        ..._archive.history,
      ],
    );
    _revision++;
    notifyListeners();
    if (persist) await _persist();
  }

  Future<void> _persist() async {
    if (readOnly) return;
    final revision = _revision;
    final archiveText = _archive.encode();
    final snapshotText = jsonEncode(_snapshot());
    _writes = _writes.catchError((Object _) {}).then((_) async {
      try {
        await storage.write(archiveText);
        _archiveDurableRevision = revision;
        if (revision == _revision) _archiveSaveError = null;
      } catch (exception) {
        if (revision == _revision) {
          _archiveSaveError = '专注状态保存失败，请重试：$exception';
        }
        return;
      }
      try {
        await storage.writeWidgetSnapshot(snapshotText);
        if (revision == _revision) _snapshotSaveError = null;
      } catch (exception) {
        if (revision == _revision) {
          _snapshotSaveError = '专注卡片未更新：$exception';
        }
      }
    });
    await _writes;
    notifyListeners();
  }

  Future<void> _writeSnapshot() async {
    if (readOnly || loading || _archiveDurableRevision < _revision) return;
    final revision = _revision;
    final snapshotText = jsonEncode(_snapshot());
    _writes = _writes
        .catchError((Object _) {})
        .then((_) async {
          await storage.writeWidgetSnapshot(snapshotText);
          if (revision == _revision) _snapshotSaveError = null;
        })
        .catchError((Object exception) {
          if (revision == _revision) {
            _snapshotSaveError = '专注卡片未更新：$exception';
          }
        });
    await _writes;
    notifyListeners();
  }

  Map<String, Object?> _snapshot() => {
    'version': 1,
    'savedAt': _epoch(clock()),
    'active': active?.toJson(),
    'todaySeconds': todayRecordedSeconds,
    'completedCount': completedCount,
  };

  double _completionEpoch(PomodoroRun run) {
    final started = run.runningSince;
    if (started == null) return _epoch(clock());
    return started +
        (run.targetSeconds - run.accumulatedSeconds).clamp(0, double.infinity);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}

double _number(Object? value) {
  if (value is! num || !value.toDouble().isFinite) {
    throw const FormatException('专注记录包含无效数字');
  }
  return value.toDouble();
}

double _epoch(DateTime date) => date.millisecondsSinceEpoch / 1000.0;
DateTime _date(double epoch) =>
    DateTime.fromMillisecondsSinceEpoch((epoch * 1000).round());
DateTime _localDay(DateTime date) => DateTime(date.year, date.month, date.day);

String _newID() => newId();
bool _isUUID(String value) => RegExp(
  r'^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$',
).hasMatch(value);
