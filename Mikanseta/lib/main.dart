import 'package:flutter/material.dart';

import 'src/app.dart';
import 'src/cloud_sync.dart';
import 'src/store.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final store = EntryStore(NativeStorage());
  CloudSync? cloud;
  if (SupabaseConfig.ready) {
    cloud = CloudSync(store, SupabaseCloudBackend());
    store.onLocalWrite = cloud.schedulePush;
  }
  runApp(MikansetaApp(store: store, cloud: cloud));
  store.load();
}
