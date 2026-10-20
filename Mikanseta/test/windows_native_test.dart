import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mikanseta/src/domain.dart';
import 'package:mikanseta/src/store.dart';
import 'package:mikanseta/src/system_services.dart';
import 'package:mikanseta/src/windows_native.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temporary;
  late Directory support;
  late Directory shared;
  WindowsNative backend({
    WindowsReplaceFile? replace,
    WindowsOpenFile? open,
    WindowsSaveFile? save,
    Future<bool> Function(Uri)? openUrl,
  }) => WindowsNative(
    supportDirectory: () async => support,
    pickFolder: () async => shared.path,
    replaceFile: replace,
    openFile: open ?? (_) async => null,
    saveFile: save ?? () async => null,
    openUrl: openUrl,
  );

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('mikanseta-windows-');
    support = await Directory('${temporary.path}/support').create();
    shared = await Directory('${temporary.path}/shared').create();
  });
  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    await temporary.delete(recursive: true);
  });

  test(
    'archive replacement preserves Unicode, Checklist and timer data',
    () async {
      final native = backend();
      expect(await native.invoke('readArchive'), isNull);
      final original = Archive(entries: []).encode();
      await native.invoke('writeArchive', original);
      final entry = Entry.create(title: '数学作业 · 检查并提交').change({
        'checklist': [StepItem(title: '完成练习', done: true).toJson()],
        'elapsedSeconds': 125,
      });
      final content = Archive(entries: [entry]).encode();
      await native.invoke('writeArchive', content);
      final reloaded = Archive.decode(
        await backend().invoke('readArchive') as String,
      );
      expect(reloaded.entries.single.title, entry.title);
      expect(reloaded.entries.single.steps.single.done, isTrue);
      expect(reloaded.entries.single.data['elapsedSeconds'], 125);
      expect(await support.list().length, 1);
    },
  );

  test(
    'failed replacement retains the original and cleans temporary files',
    () async {
      await backend().invoke('writeArchive', 'original archive');
      final native = backend(
        replace: (_, _) async => throw const FileSystemException('file locked'),
      );
      await expectLater(
        native.invoke('writeArchive', 'new archive'),
        throwsA(isA<FileSystemException>()),
      );
      expect(await backend().invoke('readArchive'), 'original archive');
      expect(await support.list().length, 1);
    },
  );

  test('cancelled import and export preserve the existing archive', () async {
    final native = backend();
    await native.invoke('writeArchive', 'keep me');
    expect(await native.invoke('importArchive'), isNull);
    expect(await native.invoke('importText'), isNull);
    expect(await native.invoke('exportArchive', 'backup'), isFalse);
    expect(await native.invoke('readArchive'), 'keep me');
  });

  test('selected UTF-8 text and backup export round trip', () async {
    final input = File('${temporary.path}/课程.csv');
    await input.writeAsString('\uFEFF课程,星期\n高数,1');
    final output = File('${temporary.path}/备份.json');
    final native = backend(
      open: (_) async => input.path,
      save: () async => output.path,
    );
    expect(await native.invoke('importText'), '课程,星期\n高数,1');
    expect(await native.invoke('exportArchive', '{"title":"作业"}'), isTrue);
    expect(await output.readAsString(), '{"title":"作业"}');
  });

  test(
    'shared folder and replica state survive restarting the adapter',
    () async {
      final native = backend();
      await native.invoke('pickLocalSyncFolder');
      await native.invoke('writeLocalSyncFile', {
        'name': 'replica-device-A.json',
        'content': '{"version":1}',
      });
      await native.invoke('writeLocalSyncState', '{"counter":8}');
      final restarted = backend();
      expect(
        (await restarted.invoke('localSyncFolder') as Map)['connected'],
        isTrue,
      );
      expect(await restarted.invoke('readLocalSyncFiles'), {
        'replica-device-A.json': '{"version":1}',
      });
      expect(await restarted.invoke('readLocalSyncState'), '{"counter":8}');
      await restarted.invoke('disconnectLocalSyncFolder');
      expect(await restarted.invoke('localSyncFolder'), {'connected': false});
      expect(
        await File('${shared.path}/Mikansei-sync/replica-device-A.json')
            .exists(),
        isTrue,
      );
      expect(await restarted.invoke('readLocalSyncState'), '{"counter":8}');
    },
  );

  test(
    'replica writes reject traversal and Windows alternate stream names',
    () async {
      final native = backend();
      await native.invoke('pickLocalSyncFolder');
      for (final name in [
        '../entries.json',
        r'..\entries.json',
        'replica-a.json:stream',
        'replica-a/else.json',
        'state.json',
      ]) {
        await expectLater(
          native.invoke('writeLocalSyncFile', {
            'name': name,
            'content': 'invalid',
          }),
          throwsA(isA<PlatformException>()),
        );
      }
      expect(await native.invoke('readLocalSyncFiles'), isEmpty);
    },
  );

  test(
    'a missing sync folder reports recovery without touching the archive',
    () async {
      final native = backend();
      await native.invoke('writeArchive', 'local archive');
      await native.invoke('pickLocalSyncFolder');
      await shared.delete();
      final status = await native.invoke('localSyncFolder') as Map;
      expect(status['connected'], isFalse);
      expect(status['error'], contains('重新选择'));
      expect(await native.invoke('readArchive'), 'local archive');
    },
  );

  test('external links accept only HTTP(S) URLs', () async {
    Uri? opened;
    final native = backend(
      openUrl: (uri) async {
        opened = uri;
        return true;
      },
    );
    await native.invoke('openExternalURL', 'https://example.com/submit');
    expect(opened?.host, 'example.com');
    for (final value in [
      'file:///C:/Windows/system.ini',
      'javascript:alert(1)',
      'https:',
    ]) {
      await expectLater(
        native.invoke('openExternalURL', value),
        throwsA(isA<PlatformException>()),
      );
    }
  });

  testWidgets('Windows system settings explain unsupported services', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      final store = EntryStore(_MemoryStorage());
      await store.load();
      await tester.pumpWidget(
        MaterialApp(home: ServicesSettings(store: store)),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('后台提醒'), findsOneWidget);
      expect(find.text('开启闹钟权限'), findsNothing);
      expect(store.readOnly, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

class _MemoryStorage implements ArchiveStorage {
  @override
  Future<String?> read() async => null;
  @override
  Future<void> write(String content) async {}
  @override
  Future<String?> pickBackup() async => null;
  @override
  Future<bool> exportBackup(String content) async => false;
}
