import 'package:flutter/services.dart';

class PingStabilizerFFI {
  static final PingStabilizerFFI _instance = PingStabilizerFFI._internal();
  factory PingStabilizerFFI() => _instance;
  PingStabilizerFFI._internal();

  static const MethodChannel _platform = MethodChannel('com.minizivpn.app/core');
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
  }

  Future<int> ping(String host, {int timeoutMs = 3000}) async {
    await initialize();
    try {
      final result = await _platform.invokeMethod<int>('nativePing', {
        'host': host,
        'timeoutMs': timeoutMs,
      });
      return result ?? -1;
    } catch (_) {
      return -1;
    }
  }
}
