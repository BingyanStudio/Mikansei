import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'store.dart';

/// Connection values are injected at build time with --dart-define and stay in
/// the untracked LocalInstall folder; see Documentation/SUPABASE_SETUP.md.
/// Empty values disable the account section instead of failing the build.
class SupabaseConfig {
  static const url = String.fromEnvironment('SUPABASE_URL');
  static const anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static bool get ready => url.isNotEmpty && anonKey.isNotEmpty;
}

/// One row per account: the newest full archive JSON plus a client change
/// token used to ignore our own realtime events.
class CloudRecord {
  CloudRecord({required this.revision, required this.content});
  final int revision;
  final String content;
}

/// Transport surface for account sync. SupabaseCloudBackend is the real
/// implementation; tests substitute a fake backend.
abstract class CloudBackend {
  Future<void> initialize();
  String? get userEmail;
  Future<void> sendCode(String email);
  Future<String> verifyCode(String email, String code);
  Future<void> signOut();
  Future<CloudRecord?> fetch();
  Future<int> upload(String content);
  Stream<int> changes();
  Future<void> dispose();
}

class SupabaseCloudBackend implements CloudBackend {
  SupabaseCloudBackend();
  static bool _initialized = false;
  final _revisions = StreamController<int>.broadcast();
  SupabaseClient? _client;
  RealtimeChannel? _channel;
  String? _channelUserId;

  @override
  Future<void> initialize() async {
    if (!SupabaseConfig.ready) return;
    if (!_initialized) {
      await Supabase.initialize(
        url: SupabaseConfig.url,
        publishableKey: SupabaseConfig.anonKey,
      );
      _initialized = true;
    }
    _client = Supabase.instance.client;
  }

  @override
  String? get userEmail => _client?.auth.currentSession?.user.email;

  SupabaseClient _requireClient() {
    final client = _client;
    if (client == null) {
      throw StateError('Supabase 账户服务尚未初始化。');
    }
    return client;
  }

  @override
  Future<void> sendCode(String email) async {
    await _requireClient().auth.signInWithOtp(email: email);
  }

  @override
  Future<String> verifyCode(String email, String code) async {
    await _requireClient().auth.verifyOTP(
      type: OtpType.email,
      email: email,
      token: code,
    );
    return email;
  }

  @override
  Future<void> signOut() async {
    final client = _client;
    if (client != null) {
      try {
        await client.auth.signOut();
      } catch (exception) {
        // A broken session still leaves the device; keep the local channel
        // teardown running so a later login starts clean.
        debugPrint('Supabase signOut: $exception');
      }
    }
    await _teardownChannel();
  }

  @override
  Future<CloudRecord?> fetch() async {
    final row = await _requireClient()
        .from('mikanseta_archives')
        .select('revision, content')
        .maybeSingle();
    if (row == null) return null;
    return CloudRecord(
      revision: (row['revision'] as num).toInt(),
      content: row['content'] as String,
    );
  }

  @override
  Future<int> upload(String content) async {
    final client = _requireClient();
    final revision = DateTime.now().millisecondsSinceEpoch;
    await client.from('mikanseta_archives').upsert({
      'user_id': client.auth.currentSession!.user.id,
      'revision': revision,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
      'content': content,
    }, onConflict: 'user_id');
    return revision;
  }

  @override
  Stream<int> changes() {
    final client = _requireClient();
    final userId = client.auth.currentSession!.user.id;
    if (_channel == null || _channelUserId != userId) {
      _channelUserId = userId;
      _channel = client
          .channel('mikanseta-archive-$userId')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'mikanseta_archives',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'user_id',
              value: userId,
            ),
            callback: (payload) {
              final revision = payload.newRecord['revision'];
              if (revision is int) {
                _revisions.add(revision);
              } else if (revision is String && int.tryParse(revision) != null) {
                _revisions.add(int.parse(revision));
              }
            },
          )
          .subscribe();
    }
    return _revisions.stream;
  }

  Future<void> _teardownChannel() async {
    final channel = _channel;
    final client = _client;
    _channel = null;
    _channelUserId = null;
    if (channel != null && client != null) {
      try {
        await client.removeChannel(channel);
      } catch (exception) {
        debugPrint('Supabase channel teardown: $exception');
      }
    }
  }

  @override
  Future<void> dispose() async {
    await _teardownChannel();
    await _revisions.close();
  }
}

/// Keeps one account row in step with the local archive. Every cycle pulls the
/// account row, merges it into the local store (which schedules the upload of
/// the merged state), and uploads whenever the local content is newer than
/// what the account row last saw. Own realtime events are ignored by revision.
class CloudSync extends ChangeNotifier {
  CloudSync(
    this._store,
    this._backend, {
    this.pushDelay = const Duration(seconds: 2),
    this.pullDelay = const Duration(seconds: 1),
  }) {
    _boot();
  }

  final EntryStore _store;
  final CloudBackend _backend;
  final Duration pushDelay;
  final Duration pullDelay;
  final Completer<void> _readyCompleter = Completer<void>();

  bool initialized = false;
  String? initError;
  String? email;
  bool busy = false;
  bool sendingCode = false;
  String? codeTarget;
  String? loginError;
  String? syncError;
  DateTime? lastSyncedAt;

  Timer? _pushTimer;
  Timer? _pullTimer;
  StreamSubscription<int>? _changes;
  int? _lastPushedRevision;
  String? _pushedContent;
  String? _pulledContent;
  bool _rerun = false;
  bool _disposed = false;

  Future<void> get whenReady => _readyCompleter.future;

  Future<void> _boot() async {
    try {
      await _backend.initialize();
      final restored = _backend.userEmail;
      if (restored != null && !_disposed) {
        email = restored;
        await _listen();
        await _run();
      }
    } catch (exception) {
      initError = '账户服务连接失败：$exception';
    } finally {
      initialized = true;
      _notify();
      _readyCompleter.complete();
    }
  }

  Future<void> sendCode(String value) async {
    final address = value.trim();
    loginError = null;
    sendingCode = true;
    _notify();
    try {
      await _backend.sendCode(address);
      codeTarget = address;
    } catch (exception) {
      loginError = '验证码发送失败：$exception';
    }
    sendingCode = false;
    _notify();
  }

  Future<bool> verifyCode(String value) async {
    final target = codeTarget;
    if (target == null) return false;
    loginError = null;
    _notify();
    try {
      final signedIn = await _backend.verifyCode(target, value.trim());
      email = signedIn;
      codeTarget = null;
      await _listen();
      await _run();
      _notify();
      return true;
    } catch (exception) {
      loginError = '登录未完成：$exception';
      _notify();
      return false;
    }
  }

  Future<void> _listen() async {
    await _changes?.cancel();
    _changes = _backend.changes().listen(
      (revision) {
        if (revision == _lastPushedRevision) return;
        _schedulePull();
      },
      onError: (Object exception) {
        syncError = '实时连接中断，恢复前台后重试：$exception';
        _notify();
      },
    );
  }

  Future<void> signOut() async {
    _pushTimer?.cancel();
    _pullTimer?.cancel();
    await _changes?.cancel();
    _changes = null;
    await _backend.signOut();
    email = null;
    codeTarget = null;
    loginError = null;
    syncError = null;
    lastSyncedAt = null;
    _pushedContent = null;
    _pulledContent = null;
    _lastPushedRevision = null;
    _notify();
  }

  /// Scheduled after every durable local write so rapid edits coalesce into
  /// one upload.
  void schedulePush() {
    if (_disposed || email == null) return;
    _pushTimer?.cancel();
    _pushTimer = Timer(pushDelay, _run);
  }

  void _schedulePull() {
    if (_disposed || email == null) return;
    _pullTimer?.cancel();
    _pullTimer = Timer(pullDelay, _run);
  }

  Future<void> syncNow() => _run();

  Future<void> _run() async {
    if (_disposed || email == null || _store.loading || _store.readOnly) {
      return;
    }
    if (busy) {
      _rerun = true;
      return;
    }
    busy = true;
    syncError = null;
    _notify();
    try {
      final record = await _backend.fetch();
      if (email == null) return;
      if (record != null &&
          record.content != _pulledContent &&
          record.content != _pushedContent) {
        final changed = _store.applyCloudArchive(record.content);
        _pulledContent = record.content;
        if (changed) {
          await _store.settled;
          if (email == null) return;
          if (_store.saveFailed) {
            throw StateError('本机尚未完成保存，暂缓上传合并结果。');
          }
        }
      } else if (record != null) {
        _pulledContent = record.content;
      }
      final content = _store.archiveText;
      if (content != _pushedContent && record?.content != content) {
        _lastPushedRevision = await _backend.upload(content);
        _pushedContent = content;
        if (email == null) return;
      }
      lastSyncedAt = DateTime.now();
      if (_store.archiveText == _pushedContent) {
        _pushTimer?.cancel();
      }
    } catch (exception) {
      syncError = '同步失败，本机修改已保留：$exception';
    } finally {
      busy = false;
      _notify();
      if (_rerun && !_disposed && email != null) {
        _rerun = false;
        schedulePush();
      } else {
        _rerun = false;
      }
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _pushTimer?.cancel();
    _pullTimer?.cancel();
    _changes?.cancel();
    unawaited(_backend.dispose());
    super.dispose();
  }
}
