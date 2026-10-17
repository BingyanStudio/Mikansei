import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mikanseta/src/cloud_sync.dart';
import 'package:mikanseta/src/domain.dart';
import 'package:mikanseta/src/store.dart';

import 'domain_test.dart' show MemoryStorage;

class FakeCloudBackend implements CloudBackend {
  FakeCloudBackend({this.record});
  String? signedIn;
  String? pendingEmail;
  CloudRecord? record;
  int fetchCount = 0;
  int uploadCount = 0;
  final uploaded = <String>[];
  final revisions = StreamController<int>.broadcast();

  @override
  Future<void> initialize() async {}
  @override
  String? get userEmail => signedIn;
  @override
  Future<void> sendCode(String email) async {
    pendingEmail = email;
  }

  @override
  Future<String> verifyCode(String email, String code) async {
    if (code != '123456') {
      throw const FormatException('验证码不正确');
    }
    signedIn = email;
    return email;
  }

  @override
  Future<void> signOut() async {
    signedIn = null;
  }

  @override
  Future<CloudRecord?> fetch() async {
    fetchCount++;
    return record;
  }

  @override
  Future<int> upload(String content) async {
    uploadCount++;
    uploaded.add(content);
    final revision = DateTime.now().millisecondsSinceEpoch + uploadCount;
    record = CloudRecord(revision: revision, content: content);
    return revision;
  }

  @override
  Stream<int> changes() => revisions.stream;
  @override
  Future<void> dispose() async {
    await revisions.close();
  }
}

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 60));

void main() {
  final now = DateTime(2026, 10, 17, 9);

  Future<(EntryStore, FakeCloudBackend, CloudSync)> connected({
    CloudRecord? record,
    List<Entry> local = const [],
  }) async {
    final store = EntryStore(MemoryStorage(), clock: () => now);
    await store.load();
    for (final entry in local) {
      store.save(entry);
    }
    await store.settled;
    final backend = FakeCloudBackend(record: record);
    final cloud = CloudSync(
      store,
      backend,
      pushDelay: Duration.zero,
      pullDelay: Duration.zero,
    );
    store.onLocalWrite = cloud.schedulePush;
    await cloud.whenReady;
    await cloud.sendCode('me@example.com');
    await cloud.verifyCode('123456');
    await settle();
    return (store, backend, cloud);
  }

  test('first login uploads the local archive to a fresh account', () async {
    final entry = Entry.create(title: '本地事项', now: now);
    final (store, backend, cloud) = await connected(local: [entry]);
    expect(cloud.email, 'me@example.com');
    expect(backend.uploadCount, 1);
    expect(backend.record!.content, contains('本地事项'));
    expect(cloud.syncError, isNull);
  });

  test('an existing account row merges into a new device both ways', () async {
    final remoteEntry = Entry.create(title: '云端事项', now: now);
    final localEntry = Entry.create(title: '本机事项', now: now);
    final (store, backend, cloud) = await connected(
      record: CloudRecord(
        revision: 500,
        content: Archive(entries: [remoteEntry]).encode(),
      ),
      local: [localEntry],
    );
    expect(store.find(remoteEntry.id), isNotNull);
    expect(backend.uploadCount, 1);
    expect(backend.record!.content, contains('云端事项'));
    expect(backend.record!.content, contains('本机事项'));
    expect(cloud.syncError, isNull);
  });

  test('local edits upload after the push debounce', () async {
    final (store, backend, _) = await connected(
      local: [Entry.create(title: '第一条', now: now)],
    );
    store.save(Entry.create(title: '第二条', now: now));
    await store.settled;
    await settle();
    expect(backend.uploadCount, 2);
    expect(backend.uploaded.last, contains('第二条'));
  });

  test('a realtime change from another device pulls and merges', () async {
    final localEntry = Entry.create(title: '本机已有', now: now);
    final (store, backend, cloud) = await connected(local: [localEntry]);
    final remoteEntry = Entry.create(title: '另一台设备', now: now);
    final mergedRemote = Archive(entries: [remoteEntry, localEntry]);
    backend.record = CloudRecord(revision: 777, content: mergedRemote.encode());
    backend.revisions.add(777);
    await settle();
    expect(store.find(remoteEntry.id), isNotNull);
    expect(cloud.syncError, isNull);
  });

  test('our own realtime upload is ignored by revision', () async {
    final (_, backend, _) = await connected(
      local: [Entry.create(title: '本地事项', now: now)],
    );
    final before = backend.fetchCount;
    backend.revisions.add(backend.record!.revision);
    await settle();
    expect(backend.fetchCount, before);
  });

  test('android calendar settings stay per-device on pull', () async {
    final (store, backend, _) = await connected();
    store.setAndroidCalendarSettings({
      'deviceID': 'device-A',
      'selected': ['calendar-1'],
    });
    await store.settled;
    await settle();
    final incoming = Archive(
      entries: const [],
      metadata: {
        'version': 1,
        'courses': <dynamic>[],
        'calendarSync': {
          'enabled': false,
          'selected': <dynamic>[],
          'suppressed': <dynamic>[],
        },
        'androidCalendarSync': {
          'deviceID': 'device-B',
          'selected': ['calendar-9'],
        },
      },
    ).encode();
    backend.record = CloudRecord(revision: 555, content: incoming);
    backend.revisions.add(555);
    await settle();
    expect(store.androidCalendarSettings['deviceID'], 'device-A');
  });

  test('simultaneous focus sessions collapse to the newest one', () async {
    final earlier = now.subtract(const Duration(minutes: 10));
    final localRunning = Entry.create(
      title: '本机计时',
      now: earlier,
    ).change({'startedAt': isoDate(earlier)}, now: earlier);
    final remoteStart = now.subtract(const Duration(minutes: 2));
    final remoteRunning = Entry.create(
      title: '云端计时',
      now: remoteStart,
    ).change({'startedAt': isoDate(remoteStart)}, now: remoteStart);
    final (store, backend, _) = await connected(local: [localRunning]);
    backend.record = CloudRecord(
      revision: 888,
      content: Archive(entries: [remoteRunning]).encode(),
    );
    backend.revisions.add(888);
    await settle();
    expect(store.running?.id, remoteRunning.id);
    final paused = store.find(localRunning.id)!;
    expect(paused.startedAt, isNull);
    expect(paused.data['elapsedSeconds'] as num, greaterThan(0));
  });

  test(
    'unreadable remote data reports an error and keeps local records',
    () async {
      final (store, backend, cloud) = await connected(
        local: [Entry.create(title: '本机保留', now: now)],
      );
      backend.record = CloudRecord(revision: 999, content: 'not json at all');
      backend.revisions.add(999);
      await settle();
      expect(cloud.syncError, isNotNull);
      expect(store.entries.single.title, '本机保留');
      expect(backend.uploaded.last, contains('本机保留'));
    },
  );

  test('signing out keeps local data and stops uploading', () async {
    final (store, backend, cloud) = await connected(
      local: [Entry.create(title: '离线保留', now: now)],
    );
    await cloud.signOut();
    expect(cloud.email, isNull);
    final uploads = backend.uploadCount;
    store.save(Entry.create(title: '退出后新增', now: now));
    await store.settled;
    await settle();
    expect(backend.uploadCount, uploads);
    expect(store.entries.map((e) => e.title), contains('退出后新增'));
  });

  test(
    'deletions carry tombstones and stale copies cannot resurrect',
    () async {
      final entry = Entry.create(title: '将被删除', now: now);
      final (store, backend, _) = await connected(local: [entry]);
      store.delete(entry.id);
      await store.settled;
      await settle();
      expect(store.find(entry.id), isNull);
      final pushed = Archive.decode(backend.uploaded.last);
      expect(pushed.entries.any((e) => e.id == entry.id), false);
      expect(pushed.tombstones('tombstones').containsKey(entry.id), true);
      // An offline device that still holds the entry must not bring it back.
      store.applyCloudArchive(Archive(entries: [entry]).encode());
      await store.settled;
      expect(store.find(entry.id), isNull);
    },
  );
}
