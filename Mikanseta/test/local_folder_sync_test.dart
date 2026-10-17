import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mikanseta/src/domain.dart';
import 'package:mikanseta/src/local_folder_sync.dart';
import 'package:mikanseta/src/store.dart';
import 'package:mikanseta/src/student_tools.dart' show Course;

import 'domain_test.dart' show MemoryStorage;

class FakeLocalSyncBackend implements LocalSyncBackend {
  bool connected = false;
  String? folderName = 'Mikansei Cloud';
  String? folderPath = '/tmp/Mikansei Cloud';
  final files = <String, String>{};
  String? state;
  int writes = 0;
  bool failRead = false;

  LocalSyncFolderStatus get status => LocalSyncFolderStatus(
    connected: connected,
    name: folderName,
    path: folderPath,
  );

  @override
  Future<LocalSyncFolderStatus?> pickFolder() async {
    connected = true;
    return status;
  }

  @override
  Future<LocalSyncFolderStatus> folder() async => status;

  @override
  Future<void> disconnect() async {
    connected = false;
  }

  @override
  Future<Map<String, String>> readFiles() async {
    if (failRead) throw StateError('同步文件夹不可读');
    return Map.of(files);
  }

  @override
  Future<bool> writeFile(String name, String content) async {
    if (files[name] == content) return false;
    files[name] = content;
    writes++;
    return true;
  }

  @override
  Future<String?> readState() async => state;

  @override
  Future<void> writeState(String content) async {
    state = content;
  }
}

const otherDevice = '11111111-2222-4333-8444-555555555555';

void main() {
  final now = DateTime(2026, 10, 17, 10);

  Future<(EntryStore, FakeLocalSyncBackend, LocalFolderSync)> connected({
    List<Entry> local = const [],
    bool connect = true,
  }) async {
    final store = EntryStore(MemoryStorage(), clock: () => now);
    await store.load();
    for (final entry in local) {
      store.save(entry);
    }
    await store.settled;
    final backend = FakeLocalSyncBackend()..connected = connect;
    final sync = LocalFolderSync(
      store,
      backend,
      exchangeDelay: const Duration(hours: 1),
      period: null,
    );
    await sync.whenReady;
    return (store, backend, sync);
  }

  String ownName(FakeLocalSyncBackend backend) =>
      backend.files.keys.singleWhere((name) => !name.contains('BAD'));

  ReplicaDocument ownDocument(FakeLocalSyncBackend backend) =>
      ReplicaDocument.decode(backend.files[ownName(backend)]!);

  String remoteDocument({
    List<SyncedRecord> entries = const [],
    List<SyncedRecord> courses = const [],
  }) => ReplicaDocument(entries: entries, courses: courses).encode();

  SyncedRecord recordFor(Entry entry, {int counter = 5, String? title}) =>
      SyncedRecord(
        id: entry.id,
        revision: SyncRevision(counter, otherDevice),
        value: {...entry.data, 'title': ?title},
      );

  test('first exchange writes this device replica file', () async {
    final entry = Entry.create(title: '本机事项', now: now);
    final (store, backend, _) = await connected(local: [entry]);
    expect(store.find(entry.id), isNotNull);
    final document = ownDocument(backend);
    expect(document.entries.single.id, entry.id);
    expect(document.entries.single.value!['title'], '本机事项');
    expect(document.entries.single.revision.counter, 1);
    final state = ReplicaState.decode(backend.state!);
    expect(state.counter, 1);
    expect(ownName(backend), 'replica-${state.device}.json');
  });

  test('a remote document merges into the local archive', () async {
    final remote = Entry.create(title: '另一台设备', now: now);
    final store = EntryStore(MemoryStorage(), clock: () => now);
    await store.load();
    final backend = FakeLocalSyncBackend()..connected = true;
    backend.files['replica-$otherDevice.json'] = remoteDocument(
      entries: [recordFor(remote)],
    );
    final sync = LocalFolderSync(
      store,
      backend,
      exchangeDelay: const Duration(hours: 1),
      period: null,
    );
    await sync.whenReady;
    expect(store.find(remote.id)?.title, '另一台设备');
    expect(sync.error, isNull);
    expect(ReplicaState.decode(backend.state!).counter, 5);
  });

  test('local edits are captured with a higher revision', () async {
    final (store, backend, sync) = await connected();
    final before = ReplicaState.decode(backend.state!).counter;
    final entry = Entry.create(title: '新事项', now: now);
    store.save(entry);
    await store.settled;
    await sync.syncNow();
    final document = ownDocument(backend);
    final record = document.entries.singleWhere((e) => e.id == entry.id);
    expect(record.revision.counter, before + 1);
    expect(record.value!['title'], '新事项');
  });

  test(
    'local deletion writes a tombstone that stale copies cannot undo',
    () async {
      final entry = Entry.create(title: '待删除', now: now);
      final (store, backend, sync) = await connected(local: [entry]);
      store.delete(entry.id);
      await store.settled;
      await sync.syncNow();
      expect(
        ownDocument(backend).entries.singleWhere((e) => e.id == entry.id).value,
        isNull,
      );
      // An offline device still holding the entry must not resurrect it.
      backend.files['replica-99999999-2222-4333-8444-555555555555.json'] =
          remoteDocument(entries: [recordFor(entry, counter: 1)]);
      await sync.syncNow();
      expect(store.find(entry.id), isNull);
    },
  );

  test('a remote tombstone removes the entry and stamps the archive', () async {
    final entry = Entry.create(title: '远端删除', now: now);
    final (store, backend, sync) = await connected(local: [entry]);
    backend.files['replica-$otherDevice.json'] = remoteDocument(
      entries: [
        SyncedRecord(
          id: entry.id,
          revision: const SyncRevision(9, otherDevice),
        ),
      ],
    );
    await sync.syncNow();
    expect(store.find(entry.id), isNull);
    expect(store.archive.tombstones('tombstones').containsKey(entry.id), true);
  });

  test('a higher remote revision replaces the local value', () async {
    final entry = Entry.create(title: '本地标题', now: now);
    final (store, backend, sync) = await connected(local: [entry]);
    backend.files['replica-$otherDevice.json'] = remoteDocument(
      entries: [recordFor(entry, counter: 20, title: '远端标题')],
    );
    await sync.syncNow();
    expect(store.find(entry.id)!.title, '远端标题');
  });

  test('an unchanged exchange does not rewrite the replica file', () async {
    final (_, backend, sync) = await connected(
      local: [Entry.create(title: '稳定', now: now)],
    );
    final writes = backend.writes;
    await sync.syncNow();
    await sync.syncNow();
    expect(backend.writes, writes);
  });

  test('unreadable remote data aborts without touching local data', () async {
    final entry = Entry.create(title: '本机保留', now: now);
    final (store, backend, sync) = await connected(local: [entry]);
    final before = Map.of(backend.files);
    backend.files['replica-BAD.json'] = 'not json';
    await sync.syncNow();
    expect(sync.error, isNotNull);
    expect(store.find(entry.id)?.title, '本机保留');
    expect(backend.files['replica-BAD.json'], 'not json');
    final own = ownName(backend);
    expect(backend.files[own], before[own]);
    expect(sync.busy, false);
  });

  test('device identity and counter survive a restart', () async {
    final entry = Entry.create(title: '重启后可见', now: now);
    final storage = MemoryStorage();
    final store = EntryStore(storage, clock: () => now);
    await store.load();
    store.save(entry);
    await store.settled;
    final backend = FakeLocalSyncBackend()..connected = true;
    final sync = LocalFolderSync(
      store,
      backend,
      exchangeDelay: const Duration(hours: 1),
      period: null,
    );
    await sync.whenReady;
    final device = ReplicaState.decode(backend.state!).device;
    sync.dispose();

    // A real restart reuses the same container archive, so the replica state
    // and the projected entries stay consistent.
    final restarted = EntryStore(storage, clock: () => now);
    await restarted.load();
    final resumed = LocalFolderSync(
      restarted,
      backend,
      exchangeDelay: const Duration(hours: 1),
      period: null,
    );
    await resumed.whenReady;
    expect(ReplicaState.decode(backend.state!).device, device);
    expect(restarted.find(entry.id)?.title, '重启后可见');
    expect(backend.files.keys.where((n) => n.startsWith('replica-')).length, 1);
    resumed.dispose();
  });

  test('explicit nulls do not create phantom revisions', () async {
    final entry = Entry.create(title: '空字段', now: now).change({
      'dueDate': null,
      'completedAt': null,
      'startedAt': null,
    }, now: now);
    final (_, backend, sync) = await connected(local: [entry]);
    final before = ReplicaState.decode(backend.state!).counter;
    await sync.syncNow();
    expect(ReplicaState.decode(backend.state!).counter, before);
  });

  test('courses sync and tombstones prevent resurrection', () async {
    final store = EntryStore(MemoryStorage(), clock: () => now);
    await store.load();
    final course = Course({
      'id': newId(),
      'name': '数学',
      'weekday': 1,
      'startMinutes': 480,
      'endMinutes': 540,
      'firstDate': isoDate(DateTime(2026, 9, 1)),
      'lastDate': isoDate(DateTime(2027, 1, 31)),
      'location': '',
    });
    store.saveCourse(course);
    await store.settled;
    final backend = FakeLocalSyncBackend()..connected = true;
    final sync = LocalFolderSync(
      store,
      backend,
      exchangeDelay: const Duration(hours: 1),
      period: null,
    );
    await sync.whenReady;
    expect(ownDocument(backend).courses.single.value!['name'], '数学');

    store.deleteCourse(course.id);
    await store.settled;
    await sync.syncNow();
    expect(
      ownDocument(backend).courses.singleWhere((c) => c.id == course.id).value,
      isNull,
    );
    backend.files['replica-$otherDevice.json'] = remoteDocument(
      courses: [
        SyncedRecord(
          id: course.id,
          revision: const SyncRevision(1, otherDevice),
          value: {...course.data},
        ),
      ],
    );
    await sync.syncNow();
    expect(store.courses, isEmpty);
    expect(
      store.archive.tombstones('courseTombstones').containsKey(course.id),
      true,
    );
  });

  test('projection preserves per-device metadata', () async {
    final entry = Entry.create(title: '保留设置', now: now);
    final (store, backend, sync) = await connected(local: [entry]);
    store.setAndroidCalendarSettings({
      'deviceID': 'device-A',
      'selected': ['calendar-1'],
    });
    await store.settled;
    backend.files['replica-$otherDevice.json'] = remoteDocument(
      entries: [recordFor(Entry.create(title: '远端', now: now))],
    );
    await sync.syncNow();
    expect(store.androidCalendarSettings['deviceID'], 'device-A');
  });

  test('native replica JSON decodes and re-encodes compatibly', () {
    final entry = Entry.create(title: '原生格式', now: now);
    // Compact, sorted-key JSON exactly like WorkspaceSyncDocument.encoded().
    final native = jsonEncode({
      'version': 1,
      'entries': [
        {
          'id': entry.id,
          'revision': {'counter': 3, 'device': otherDevice},
          'value': entry.data,
        },
      ],
      'courses': <Object>[],
    });
    final document = ReplicaDocument.decode(native);
    expect(document.entries.single.value!['title'], '原生格式');
    final encoded = document.encode();
    expect(encoded, isNot(contains('\n')));
    expect(
      encoded.indexOf('"courses"'),
      lessThan(encoded.indexOf('"entries"')),
    );
    expect(
      encoded.indexOf('"entries"'),
      lessThan(encoded.indexOf('"version"')),
    );
    final again = ReplicaDocument.decode(encoded);
    expect(again.entries.single.revision.counter, 3);
    expect(canonicalJson(entry.data), isNot(contains(':null')));
  });
}
