import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// App haptics stay within Flutter's platform APIs and the device's haptics
/// settings. Desktop and web builds intentionally remain silent.
class AppHaptics {
  AppHaptics._();

  static bool get mobileSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);

  static void _send(Future<void> Function() feedback) {
    if (mobileSupported) unawaited(_safeSend(feedback));
  }

  static Future<void> _safeSend(Future<void> Function() feedback) async {
    try {
      await feedback();
    } on MissingPluginException {
      // Some embedders do not register the platform haptics channel.
    } on PlatformException {
      // The system may refuse haptics; gesture handling should still proceed.
    }
  }

  /// A clear, heavy cue once a long press has become a real drag.
  static void pickup() => _send(HapticFeedback.heavyImpact);

  /// A strong pulse used sparingly while an item is held.
  static void holdPulse() => _send(HapticFeedback.heavyImpact);

  /// Confirm a successful drop, completion, or save.
  static void confirm() => _send(HapticFeedback.heavyImpact);

  /// Discrete state changes should feel firmer than a selection tick.
  static void change() => _send(HapticFeedback.mediumImpact);

  /// A light cue for a canceled drag.
  static void cancel() => _send(HapticFeedback.lightImpact);
}

/// Owns the bounded pulse timer for one active long-press gesture.
///
/// The first pulse arrives after 450 ms, then at 850 ms intervals, with at
/// most three pulses. Pointer-up can stop the timer before the owning gesture
/// reports its final accepted/canceled result.
class HoldHaptics {
  Timer? _timer;
  bool _active = false;
  int _pulseCount = 0;

  bool get isActive => _active;

  void start() {
    cancel();
    if (!AppHaptics.mobileSupported) return;
    _active = true;
    _pulseCount = 0;
    AppHaptics.pickup();
    _timer = Timer(const Duration(milliseconds: 450), _pulse);
  }

  void _pulse() {
    if (!_active) return;
    AppHaptics.holdPulse();
    _pulseCount++;
    if (_pulseCount < 3) {
      _timer = Timer(const Duration(milliseconds: 850), _pulse);
    } else {
      _timer = null;
    }
  }

  /// Stops only the repeating pulses while retaining the gesture result.
  void stopPulses() {
    _timer?.cancel();
    _timer = null;
  }

  void finish({required bool dropped, bool feedback = true}) {
    if (!_active) return;
    stopPulses();
    _active = false;
    if (!feedback) return;
    if (dropped) {
      AppHaptics.confirm();
    } else {
      AppHaptics.cancel();
    }
  }

  /// Immediately abandons the gesture, for pointer cancellation, route
  /// changes, backgrounding, or disposal.
  void cancel({bool feedback = false}) =>
      finish(dropped: false, feedback: feedback);
}

/// Shared route observer so transient hold pulses stop when a page is covered.
final RouteObserver<ModalRoute<dynamic>> appRouteObserver =
    RouteObserver<ModalRoute<dynamic>>();
