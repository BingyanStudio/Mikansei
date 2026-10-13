import 'package:flutter/material.dart';

import 'src/app.dart';
import 'src/store.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final store = EntryStore(NativeStorage());
  runApp(MikansetaApp(store: store));
  store.load();
}
