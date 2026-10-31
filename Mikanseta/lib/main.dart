import 'package:flutter/material.dart';

import 'src/app.dart';
import 'src/cloud_sync.dart';
import 'src/local_folder_sync.dart';
import 'src/store.dart';
import 'src/pomodoro_store.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final store = EntryStore(NativeStorage());
  final focusStore = PomodoroStore(NativePomodoroStorage());
  final localSync = LocalFolderSync(store, NativeLocalSyncBackend());
  CloudSync? cloud;
  if (SupabaseConfig.ready) {
    cloud = CloudSync(store, SupabaseCloudBackend());
  }
  store.onLocalWrite = () {
    cloud?.schedulePush();
    localSync.scheduleExchange();
  };
  runApp(
    MikansetaApp(
      store: store,
      focusStore: focusStore,
      cloud: cloud,
      localSync: localSync,
    ),
  );
  store.load();
  focusStore.load();
}
