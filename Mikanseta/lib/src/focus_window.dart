import 'dart:async';

import 'package:flutter/services.dart';

/// Controls a native top-level focus window. The application store remains the
/// only writer; native controls send commands back over this channel.
class FocusWindowBridge {
  FocusWindowBridge._();

  static const _channel = MethodChannel('mikanseta/focus_window');
  static Future<void> Function(Map<String, dynamic> action)? _onAction;

  static void setActionHandler(
    Future<void> Function(Map<String, dynamic> action)? handler,
  ) {
    _onAction = handler;
    if (handler == null) {
      _channel.setMethodCallHandler(null);
      return;
    }
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'focusAction' || call.arguments is! Map) return;
      final callback = _onAction;
      if (callback == null) return;
      await callback(Map<String, dynamic>.from(call.arguments as Map));
    });
  }

  static Future<void> show(Map<String, Object?> snapshot) =>
      _channel.invokeMethod<void>('show', snapshot);

  static Future<void> update(Map<String, Object?> snapshot) =>
      _channel.invokeMethod<void>('updateSnapshot', snapshot);

  static Future<void> hide() => _channel.invokeMethod<void>('hide');

  static void updateQuietly(Map<String, Object?> snapshot) {
    unawaited(update(snapshot).catchError((Object _) {}));
  }
}
