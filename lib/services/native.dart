import 'package:flutter/services.dart';

/// Small bridge to MainActivity.kt: shared/opened files and screen brightness.
class Native {
  static const _ch = MethodChannel('nflight/native');
  static void Function(String path)? onFile;

  static void init() {
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'file' && call.arguments is String) {
        onFile?.call(call.arguments as String);
      }
      return null;
    });
  }

  /// File the app was opened with (share sheet / open with), copied to cache.
  static Future<String?> initialFile() async {
    try {
      return await _ch.invokeMethod<String>('initialFile');
    } catch (_) {
      return null;
    }
  }

  /// 0..1, or null to give control back to the system.
  static Future<void> brightness(double? value) async {
    try {
      await _ch.invokeMethod('brightness', value ?? -1.0);
    } catch (_) {}
  }

  static Future<void> keepScreenOn(bool on) async {
    try {
      await _ch.invokeMethod('keepOn', on);
    } catch (_) {}
  }
}
